import http from 'node:http';
import { randomBytes, timingSafeEqual } from 'node:crypto';
import { readFile, writeFile, mkdir, mkdtemp, appendFile, rename, rm } from 'node:fs/promises';
import os from 'node:os';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { createReadStream } from 'node:fs';
import { createAssetService, validAssetId } from './assets.mjs';
import { createMaterialService, createSkyService } from './materials.mjs';
import { planWorld, validGridPlan } from './world-planner.mjs';
import { createWorldBridge, validContext, validWorldPlan } from './world-tools.mjs';
import { createWorkbench } from './workbench.mjs';
import { createDevelopmentBridge } from './workbench-mcp.mjs';
import { createTaskBoard, taskTools } from './agent-tasks.mjs';
import { createTaskWorkers, isLocalWorker, listLocalWorkers } from './task-workers.mjs';
import { createAgentViews, viewTools } from './agent-views.mjs';
import { createAgentCredentials } from './agent-credentials.mjs';
import { createRemoteEndpoint, createRemoteServer } from './remote.mjs';
import { createRelayLink } from './relay-link.mjs';
import { createTerminalSessions } from './terminal/sessions.mjs';
import { createHandoff, inheritedHandoff, listen } from './handoff.mjs';

export const root = fileURLToPath(new URL('../', import.meta.url));
const youtubePage = new URL('./youtube-player.html', import.meta.url);
const states = { 'task.started': 'working', 'task.completed': 'completed', 'task.failed': 'failed', 'task.blocked': 'blocked', 'presence.online': 'idle' };
const validId = value => typeof value === 'string' && /^[a-zA-Z0-9._-]{1,100}$/.test(value);

export function validateEvent(event) {
  if (!event || Array.isArray(event) || typeof event !== 'object') return 'Expected an object';
  if (!validId(event.event_id) || !validId(event.agent_id)) return 'Invalid event_id or agent_id';
  if (!Object.hasOwn(states, event.event)) return 'Unsupported event';
  if (event.event.startsWith('task.') && !validId(event.task_id)) return 'task_id required';
  if (typeof event.summary !== 'string' || event.summary.length > 2000) return 'summary must be text of at most 2000 characters';
  return null;
}

export async function createGateway({ dataDir = path.join(root, '.local'), token,
  worldPath = path.join(root, 'world/data/world.json'), gridPlanner = planWorld,
  workbenchRoot = root, workbenchOptions, terminalOptions, relayOptions, developmentToken, workbenchToken: workbenchSecret,
  reloadGateway = null, gatewayNotice = () => '' } = {}) {
  await mkdir(dataDir, { recursive: true });
  const world = JSON.parse(await readFile(worldPath, 'utf8'));
  let saved = { agents: {}, seen: [] };
  try { saved = JSON.parse(await readFile(path.join(dataDir, 'state.json'), 'utf8')); }
  catch (error) { if (error.code !== 'ENOENT') throw error; }
  const secret = token ?? randomBytes(32).toString('hex');
  const expected = Buffer.from(`Bearer ${secret}`);
  const workbenchToken = workbenchSecret ?? randomBytes(32).toString('hex');
  const workbenchExpected = Buffer.from(workbenchToken);
  const workbench = createWorkbench(workbenchRoot, path.join(dataDir, 'workbench'), { onGatewayChange: reloadGateway, gatewayNotice, ...workbenchOptions });
  // A third capability, for agents: source reads, drafts and checks, without commit or preview.
  const developmentSecret = developmentToken ?? randomBytes(32).toString('hex');
  const developmentExpected = Buffer.from(developmentSecret);
  const tasks = await createTaskBoard(path.join(dataDir, 'tasks.json'));
  const views = createAgentViews();
  const development = createDevelopmentBridge(workbench, { tasks, extraTools: viewTools,
    callExtra: (agent, name, args, signal) => name === 'look_at_world'
      ? views.look(agent) : workbench('checkcapture', { owner: agent, view: args.view }, signal) });
  const agentCredentials = await createAgentCredentials(path.join(dataDir, 'agents.json'));
  // The person's shells. They outlive restarts of the world, not of the gateway.
  const terminals = createTerminalSessions({ root: workbenchRoot, ...terminalOptions });
  let terminalRateStart = Date.now();
  let terminalRateCount = 0;
  let developmentRateStart = Date.now();
  let developmentRateCount = 0;
  let queue = Promise.resolve();
  let rateStart = Date.now();
  let rateCount = 0;
  let gridBusy = false;
  const assets = createAssetService(path.join(dataDir, 'runtime-assets'));
  const materials = createMaterialService(path.join(dataDir, 'runtime-materials'));
  const skies = createSkyService(path.join(dataDir, 'runtime-skies'));
  const bridge = createWorldBridge(assets);
  const agentSeen = new Map();
  for (const { id } of tasks.working().filter(item => isLocalWorker(item.id))) {
    const { tasks: assigned } = await tasks.agent(id, 'inbox', {});
    const task = assigned.find(item => item.status === 'working');
    if (task) await tasks.agent(id, 'finish_task', { id: task.id, status: 'blocked',
      text: 'The gateway restarted during the task. Review any changes before assigning it again.' });
  }
  const workers = createTaskWorkers(tasks, () => server.address());
  function reply(res, code, value) {
    res.writeHead(code, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' });
    res.end(JSON.stringify(value));
  }
  async function readJson(req, res, limit = 8192) {
    if (!(req.headers['content-type'] ?? '').startsWith('application/json')) {
      reply(res, 415, { error: 'Use application/json' });
      return undefined;
    }
    const chunks = [];
    let size = 0;
    for await (const chunk of req) {
      size += chunk.length;
      if (size > limit) {
        reply(res, 413, { error: 'Payload too large' });
        req.resume();
        return undefined;
      }
      chunks.push(chunk);
    }
    try { return JSON.parse(Buffer.concat(chunks).toString('utf8')); }
    catch { reply(res, 400, { error: 'Invalid JSON' }); return undefined; }
  }
  const server = http.createServer(async (req, res) => {
    try {
      if (req.headers.origin) return reply(res, 403, { error: 'Browser origins are not supported' });
      if (req.method === 'GET' && req.url === '/media/youtube') {
        const host = server.address();
        if (!host || req.headers.host !== `127.0.0.1:${host.port}`) return reply(res, 403, { error: 'Use the local Euclid address' });
        const page = await readFile(youtubePage);
        res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store',
          'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'strict-origin-when-cross-origin',
          'X-Frame-Options': 'DENY', 'Content-Security-Policy': "default-src 'none'; script-src 'unsafe-inline' https://www.youtube.com https://s.ytimg.com; style-src 'unsafe-inline'; frame-src https://www.youtube.com; frame-ancestors 'none'; base-uri 'none'" });
        res.end(page);
        return;
      }
      if (req.method === 'GET' && req.url === '/health') return reply(res, 200, { service: 'construct-gateway', version: 32 });
      if (req.url === '/mcp/task') {
        const job = workers.identify(req.headers.authorization?.match(/^Bearer ([a-f0-9]{64})$/)?.[1]);
        if (!job) return reply(res, 401, { error: 'The local task credential expired.' });
        if (req.method !== 'POST') return reply(res, 405, { error: 'Use POST' });
        const body = await readJson(req, res, 512 * 1024);
        if (body === undefined) return;
        const controller = new AbortController();
        res.once('close', () => controller.abort());
        const signal = AbortSignal.any([controller.signal, job.controller.signal]);
        const policy = { tools: name => name !== 'claim_task' };
        let result = await development.rpc(job.actor, body, signal, policy);
        if (job.task.session && body?.method === 'tools/list' && result?.result) {
          const world = await bridge.rpc(job.task.session, body, signal);
          const names = new Set(result.result.tools.map(tool => tool.name));
          result.result.tools.push(...world.result.tools.filter(tool => !names.has(tool.name)));
        } else if (job.task.session && body?.method === 'tools/call' && result?.error?.message === 'Unknown workbench tool') {
          result = await bridge.rpc(job.task.session, body, signal, job.actor);
        }
        if (res.destroyed) return;
        return result === null ? res.writeHead(202).end() : reply(res, 200, result);
      }
      const supplied = Buffer.from(req.headers.authorization ?? '');
      if (supplied.length !== expected.length || !timingSafeEqual(supplied, expected)) return reply(res, 401, { error: 'Unauthorized' });
      async function serveDevelopment(agent, policy) {
        if (req.method !== 'POST') return reply(res, 405, { error: 'Use POST' });
        // Agents poll while checks run. Their budget is separate so they cannot starve the world.
        if (Date.now() - developmentRateStart > 60000) { developmentRateStart = Date.now(); developmentRateCount = 0; }
        if (++developmentRateCount > 240) return reply(res, 429, { error: 'Rate limit exceeded' });
        const body = await readJson(req, res, 512 * 1024);
        if (body === undefined) return;
        if (!policy) agentSeen.set(agent, Date.now());
        const controller = new AbortController();
        res.once('close', () => controller.abort());
        const result = await development.rpc(agent, body, controller.signal, policy);
        if (res.destroyed) return;
        if (result === null) return res.writeHead(202).end();
        return reply(res, 200, result);
      }
      // An agent with its own credential. The credential decides the name.
      if (req.url === '/mcp/agent') {
        const agent = agentCredentials.identify(req.headers['x-euclid-agent']);
        if (!agent || isLocalWorker(agent)) return reply(res, 403, { error: 'Connect with an agent credential issued in Euclid.' });
        return serveDevelopment(agent);
      }
      // The shared development capability. The name is a label, unless an agent credential reserves it.
      const developmentRoute = /^\/mcp\/dev\/([a-f0-9]{64})(?:\/([a-z0-9_-]{1,32}))?$/.exec(req.url);
      if (developmentRoute) {
        const capability = Buffer.from(developmentRoute[1]);
        if (capability.length !== developmentExpected.length || !timingSafeEqual(capability, developmentExpected)) return reply(res, 403, { error: 'Development tools require the current Euclid gateway capability.' });
        const agent = developmentRoute[2] ?? 'agent';
        if (isLocalWorker(agent)) return reply(res, 403, { error: 'This name is reserved for a Euclid task worker.' });
        if (agentCredentials.reserved(agent)) return reply(res, 403, { error: `${agent} has its own agent credential. Connect at /mcp/agent with it.` });
        return serveDevelopment(agent, { tools: name => ![...taskTools, ...viewTools].some(tool => tool.name === name) });
      }
      const terminalRoute = /^\/v1\/terminal\/(open|list|write|resize|read|close)$/.exec(req.url);
      if (terminalRoute) {
        const capability = Buffer.from(req.headers['x-euclid-workbench'] ?? '');
        if (capability.length !== workbenchExpected.length || !timingSafeEqual(capability, workbenchExpected)) return reply(res, 403, { error: 'The terminal requires the local Euclid launcher.' });
        if (req.method !== 'POST') return reply(res, 405, { error: 'Use POST' });
        // Keystrokes and screen reads are frequent. Their budget is separate so they cannot starve the world.
        if (Date.now() - terminalRateStart > 60000) { terminalRateStart = Date.now(); terminalRateCount = 0; }
        if (++terminalRateCount > 1800) return reply(res, 429, { error: 'Rate limit exceeded' });
        const body = await readJson(req, res, 96 * 1024);
        if (body === undefined) return;
        if (!body || typeof body !== 'object' || Array.isArray(body)) return reply(res, 400, { error: 'Expected an object' });
        const controller = new AbortController();
        res.once('close', () => controller.abort());
        try {
          switch (terminalRoute[1]) {
            case 'open': return reply(res, 200, terminals.open({ shell: body.shell, cols: body.cols, rows: body.rows }));
            case 'list': return reply(res, 200, { sessions: terminals.list() });
            case 'write': return reply(res, 200, terminals.write(body.id, body.data));
            case 'resize': return reply(res, 200, terminals.resize(body.id, body.cols, body.rows));
            case 'close': return reply(res, 200, terminals.close(body.id));
            default: {
              const result = await terminals.read(body.id, { since: body.since, wait: body.wait, offset: body.offset, signal: controller.signal });
              return res.destroyed ? undefined : reply(res, 200, result);
            }
          }
        } catch (error) { return res.destroyed ? undefined : reply(res, 400, { error: error.message }); }
      }
      if (Date.now() - rateStart > 60000) { rateStart = Date.now(); rateCount = 0; }
      if (++rateCount > 240) return reply(res, 429, { error: 'Rate limit exceeded' });
      const workbenchRoute = /^\/v1\/workbench\/([a-z]+)$/.exec(req.url);
      const agentsRoute = /^\/v1\/agents\/(issue|revoke|list|relay|activity)$/.exec(req.url);
      const tasksRoute = /^\/v1\/tasks\/(assign|cancel|inbox|send_message|task_log|share_view)$/.exec(req.url);
      if (workbenchRoute || agentsRoute || tasksRoute) {
        const capability = Buffer.from(req.headers['x-euclid-workbench'] ?? '');
        if (capability.length !== workbenchExpected.length || !timingSafeEqual(capability, workbenchExpected)) return reply(res, 403, { error: 'Workbench access requires the local Euclid launcher.' });
        if (req.method !== 'POST') return reply(res, 405, { error: 'Use POST' });
        const body = await readJson(req, res, tasksRoute && tasksRoute[1] !== 'share_view' ? 32 * 1024 : agentsRoute ? 1024 : 512 * 1024);
        if (body === undefined) return;
        if (!body || typeof body !== 'object' || Array.isArray(body)) return reply(res, 400, { error: 'Expected an object' });
        if (tasksRoute) {
          try { return reply(res, 200, tasksRoute[1] === 'share_view' ? views.share(body) : await tasks.player(tasksRoute[1], body)); }
          catch (error) { return reply(res, 400, { error: error.message }); }
        }
        // Only the person, through the Workbench capability, issues and revokes agent credentials.
        if (agentsRoute) {
          try {
            if (agentsRoute[1] === 'issue') {
              if (isLocalWorker(body.name?.toLowerCase?.())) return reply(res, 400, { error: 'This name is reserved for a Euclid task worker.' });
              return reply(res, 200, await agentCredentials.issue(body.name, { remote: body.remote === true, checks: body.checks === true }));
            }
            if (agentsRoute[1] === 'revoke') return reply(res, 200, { name: body.name, revoked: await agentCredentials.revoke(body.name) });
            if (agentsRoute[1] === 'relay') {
              if (body.action === 'configure') return reply(res, 200, await relay.configure({ url: body.url, key: body.key }));
              if (body.action === 'reconnect') return reply(res, 200, relay.reconnect());
              if (body.action === 'forget') return reply(res, 200, await relay.forget());
              return reply(res, 200, relay.status());
            }
            if (agentsRoute[1] === 'activity') {
              return reply(res, 200, { entries: await remote.recent(Number.isInteger(body.limit) ? body.limit : 30) });
            }
            const agents = agentCredentials.list();
            return reply(res, 200, { agents: agents.map(agent => ({ ...agent, last_seen: remote.lastSeen(agent.name) })),
              chat_agents: [...listLocalWorkers(), ...agents.map(({ name, remote }) => ({
                name, label: remote ? `Cloud · ${name}` : name, kind: 'inbox',
              }))],
              relay: relay.status() });
          } catch (error) { return reply(res, 400, { error: error.message }); }
        }
        if (workbenchRoute[1] === 'reload') {
          // Loads gateway code that changed on disk, such as after a merge made outside Euclid.
          if (!reloadGateway) return reply(res, 400, { error: 'This gateway cannot replace itself.' });
          reloadGateway();
          return reply(res, 200, { restarting: true });
        }
        const controller = new AbortController();
        res.once('close', () => controller.abort());
        try { return reply(res, 200, await workbench(workbenchRoute[1], body, controller.signal)); }
        catch (error) { if (!res.destroyed) return reply(res, 400, { error: error.message }); return; }
      }
      const materialMap = /^\/v1\/materials\/([a-z0-9_]{1,64})\/(albedo|normal|orm)\.jpg$/.exec(req.url);
      const skyMap = /^\/v1\/skies\/([a-z0-9_]{1,64})\/panorama\.hdr$/.exec(req.url);
      if (req.method === 'GET' && (materialMap || skyMap)) {
        const file = await (skyMap ? skies.map(skyMap[1], 'panorama') :
          materials.map(materialMap[1], materialMap[2])).catch(() => null);
        if (!file) return reply(res, 404, { error: 'Material map unavailable.' });
        const stream = createReadStream(file);
        stream.once('error', () => res.destroy());
        res.once('close', () => stream.destroy());
        res.writeHead(200, { 'Content-Type': skyMap ? 'application/octet-stream' : 'image/jpeg', 'X-Content-Type-Options': 'nosniff' });
        stream.pipe(res);
        return;
      }
      const importRoute = /^\/v1\/(materials|skies)\/(search|import)$/.exec(req.url);
      if (req.method === 'POST' && importRoute) {
        const sky = importRoute[1] === 'skies';
        const service = sky ? skies : materials;
        const body = await readJson(req, res, 1024);
        if (body === undefined) return;
        try {
          if (importRoute[2] === 'search') return reply(res, 200, { ok: true, [importRoute[1]]: await service.search(body?.query, body?.provider) });
          return reply(res, 200, { ok: true, [sky ? 'sky' : 'material']: await service.importMaterial(body?.id) });
        } catch (error) { return reply(res, 400, { error: error.message }); }
      }
      const assetRoute = /^\/v1\/assets\/([^/]+)(\/model\.glb)?$/.exec(req.url);
      if (req.method === 'GET' && req.url === '/v1/assets') return reply(res, 200, await assets.list());
      if (req.method === 'GET' && assetRoute && validAssetId(assetRoute[1])) {
        if (!assetRoute[2]) return reply(res, 200, await assets.status(assetRoute[1]));
        const item = await assets.model(assetRoute[1]);
        res.writeHead(200, { 'Content-Type': 'model/gltf-binary', 'Cache-Control': 'no-store' });
        const stream = createReadStream(item.file);
        res.once('close', () => stream.destroy());
        stream.on('error', () => res.destroy());
        stream.pipe(res);
        return;
      }
      if (req.method === 'POST' && ['/v1/assets/search', '/v1/assets/import', '/v1/assets/resolve'].includes(req.url)) {
        const body = await readJson(req, res);
        if (body === undefined) return;
        try {
          if (req.url === '/v1/assets/search') return reply(res, 200, await assets.search(body.query, body.provider));
          if (req.url === '/v1/assets/import') return reply(res, 200, await assets.importAsset(body.asset_id, body.preserve_rig));
          if (!validContext(body.context)) return reply(res, 400, { error: 'Invalid environment catalog.' });
          const found = await assets.search(body.query, body.preserve_rig ? 'sketchfab' : 'all');
          const candidates = body.preserve_rig ? found.assets.filter(item => item.triangles <= 100000) : found.assets;
          if (!candidates.length) return reply(res, 404, { error: found.notices.join(' ') || 'No downloadable model matched that search and import budget.' });
          const selection = await gridPlanner(`Choose one model for: ${body.query}`, AbortSignal.timeout(75000),
            { ...body.context, asset_catalog: candidates, rigged_import: body.preserve_rig === true });
          if (selection.tool !== 'spawn_asset' || !candidates.some(item => item.asset_id === selection.target)) {
            return reply(res, 422, { error: 'The agent could not select a matching model from the search results.' });
          }
          return reply(res, 200, await assets.importAsset(selection.target, body.preserve_rig));
        } catch (error) { return reply(res, 400, { error: error.message }); }
      }
      if (req.method === 'GET' && req.url === '/v1/world') {
        const agents = Object.values(saved.agents).map(agent => ({ ...agent, connected: Date.now() - Date.parse(agent.received_at) < 30000 }));
        const now = Date.now();
        for (const [id, at] of agentSeen) if (now - at > 30000) agentSeen.delete(id);
        const current = new Map(tasks.working().map(item => [item.id, item.task]));
        const online = new Set([...agentSeen.keys(), ...agentCredentials.list()
          .filter(agent => now - Date.parse(remote.lastSeen(agent.name)?.at) < 30000).map(agent => agent.name),
          ...[...current.keys()].filter(isLocalWorker)]);
        return reply(res, 200, { ...world, agents, task_agents: [...online].slice(0, 24)
          .map(id => ({ id, task: (current.get(id) ?? '').slice(0, 120) })) });
      }
      if (req.method === 'POST' && req.url === '/v1/companion/sync') {
        const body = await readJson(req, res, 128 * 1024);
        if (body === undefined) return;
        const response = bridge.sync(body);
        return response ? reply(res, 200, response) : reply(res, 400, { error: 'Invalid live world context' });
      }
      const mcp = /^\/mcp\/([a-f0-9]{32})$/.exec(req.url);
      if (mcp) {
        if (req.method !== 'POST') return reply(res, 405, { error: 'Use POST' });
        const body = await readJson(req, res, 65536);
        if (body === undefined) return;
        const controller = new AbortController();
        res.once('close', () => controller.abort());
        const result = await bridge.rpc(mcp[1], body, controller.signal);
        if (res.destroyed) return;
        if (result === null) return res.writeHead(202).end();
        return reply(res, 200, result);
      }
      const companion = req.url === '/v1/companion/plan';
      if (req.method === 'POST' && (companion || req.url === '/v1/grid/plan')) {
        const body = await readJson(req, res, companion ? 128 * 1024 : 8192);
        if (body === undefined) return;
        const prompt = typeof body?.prompt === 'string' ? body.prompt.trim() : '';
        const context = companion ? body?.context : null;
        if (!prompt || prompt.length > 240) return reply(res, 400, { error: 'Enter a request of 1 to 240 characters.' });
        if (companion && !validContext(context)) return reply(res, 400, { error: 'Invalid environment catalog.' });
        if (gridBusy) return reply(res, 409, { error: 'The agent is already working on a Grid request.' });
        gridBusy = true;
        const controller = new AbortController();
        res.once('close', () => controller.abort());
        try {
          const plan = await gridPlanner(prompt, controller.signal, context);
          if (res.destroyed) return;
          if (!(companion ? validWorldPlan(plan, context) : validGridPlan(plan))) return reply(res, 502, { error: 'The agent returned an invalid world plan.' });
          return reply(res, 200, { agent_id: 'local-codex', plan });
        } catch (error) {
          if (!res.destroyed) return reply(res, 503, { error: error.message });
        } finally {
          gridBusy = false;
        }
        return;
      }
      if (req.method !== 'POST' || req.url !== '/v1/events') return reply(res, 404, { error: 'Unknown route' });
      const event = await readJson(req, res);
      if (event === undefined) return;
      const error = validateEvent(event);
      if (error) return reply(res, 400, { error });
      if (!world.anchors.some(anchor => anchor.agent_id === event.agent_id)) return reply(res, 403, { error: 'Agent is not assigned to a world anchor' });
      // Serialize persistence and duplicate checks, including concurrent requests.
      const operation = queue.then(async () => {
        if (saved.seen.includes(event.event_id)) return { duplicate: true };
        const previous = saved.agents[event.agent_id];
        if (event.event !== 'presence.online') {
          if (event.event === 'task.started' && previous?.status === 'working' && previous.task_id !== event.task_id) throw new Error('Another task is active');
          if (event.event !== 'task.started' && (previous?.task_id !== event.task_id || previous?.status !== 'working')) throw new Error('Task must be started before reporting its outcome');
        }
        const received_at = new Date().toISOString();
        const agent = event.event === 'presence.online' && previous
          ? { ...previous, received_at }
          : { agent_id: event.agent_id, status: states[event.event], task_id: event.task_id ?? null, summary: event.summary, received_at };
        const next = { agents: { ...saved.agents, [event.agent_id]: agent }, seen: [...saved.seen, event.event_id].slice(-2000) };
        await writeFile(path.join(dataDir, 'state.tmp'), JSON.stringify(next, null, 2));
        await rename(path.join(dataDir, 'state.tmp'), path.join(dataDir, 'state.json'));
        saved = next;
        await appendFile(path.join(dataDir, 'events.jsonl'), JSON.stringify({ ...event, received_at }) + '\n');
        return { accepted: true };
      });
      queue = operation.catch(() => {});
      try { reply(res, 200, await operation); }
      catch (error) { if (error.message.startsWith('Task must') || error.message === 'Another task is active') reply(res, 409, { error: error.message }); else throw error; }
    } catch { if (!res.headersSent) reply(res, 500, { error: 'Gateway could not process the request' }); }
  });
  server.requestTimeout = 10000;
  server.headersTimeout = 10000;
  // Listened on only when EUCLID_REMOTE_PORT is set. See createRemoteServer.
  const remote = createRemoteEndpoint({ credentials: agentCredentials, development, auditFile: path.join(dataDir, 'remote-audit.jsonl') });
  const remoteServer = createRemoteServer(remote);
  await remote.prime();
  // Started only by the gateway process itself, never by tests or the reload preflight.
  const relay = createRelayLink({ endpoint: remote, file: path.join(dataDir, 'relay.json'), ...relayOptions });
  server.on('listening', () => workers.start());
  server.on('close', () => { workers.stop(); terminals.closeAll(); relay.stop(); });
  return { server, remoteServer, remoteAudited: remote.audited, terminals, relay, token: secret, workbenchToken, developmentToken: developmentSecret };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  if (process.argv.includes('--preflight')) {
    // Proves this code can build and serve a gateway, using throwaway data and a free port.
    const dataDir = await mkdtemp(path.join(os.tmpdir(), 'euclid-preflight-'));
    try {
      const { server } = await createGateway({ dataDir });
      await listen(server, 0);
      const health = await fetch(`http://127.0.0.1:${server.address().port}/health`);
      if (!health.ok || (await health.json()).service !== 'construct-gateway') throw new Error('The gateway did not report its identity.');
      server.closeAllConnections();
      await new Promise(resolve => server.close(resolve));
    } finally {
      await rm(dataDir, { recursive: true, force: true });
    }
    process.exit(0);
  }
  const handoff = inheritedHandoff(process.env);
  const dataDir = process.env.EUCLID_DATA_DIR || path.join(root, '.local');
  const port = handoff?.port ?? Number(process.env.CONSTRUCT_PORT ?? 4317);
  let reload;
  const gateway = await createGateway({ dataDir, token: handoff?.token, workbenchToken: handoff?.workbench_token,
    developmentToken: handoff?.development_token, reloadGateway: () => reload.start(), gatewayNotice: () => reload.notice() });
  const credentials = { token: gateway.token, workbench_token: gateway.workbenchToken, development_token: gateway.developmentToken };
  reload = createHandoff({ entry: fileURLToPath(import.meta.url), cwd: root, port, credentials, server: gateway.server, logDirectory: dataDir });
  // A replacement can start a moment before the gateway it replaces has released the port.
  try { await listen(gateway.server, port, handoff ? 40 : 1); }
  catch (error) { console.error(`Gateway: ${error.message}`); process.exit(1); }
  gateway.server.on('error', error => { console.error(`Gateway: ${error.message}`); process.exitCode = 1; });
  // A relay Euclid dials out to, when one is set in the Cloud Agents screen.
  await gateway.relay.start();
  // The outside endpoint for remote agents. A tunnel points here, never at the main port.
  const remotePort = Number(process.env.EUCLID_REMOTE_PORT ?? 0);
  if (Number.isInteger(remotePort) && remotePort > 0 && remotePort !== port) {
    try {
      await listen(gateway.remoteServer, remotePort, handoff ? 40 : 1);
      console.log(`Remote agent endpoint on 127.0.0.1:${remotePort}/mcp. Point a tunnel at this port only.`);
    } catch (error) { console.error(`Gateway: the remote endpoint could not start. ${error.message}`); }
  }
  await writeFile(path.join(dataDir, 'gateway.json'), JSON.stringify({ url: `http://127.0.0.1:${port}`, ...credentials }), { mode: 0o600 });
  // The launcher records the gateway it starts. A replacement records itself for stop-gateway.ps1.
  if (handoff) await writeFile(path.join(dataDir, 'gateway.pid'), String(process.pid));
  console.log(`Euclid gateway ready on 127.0.0.1:${port}. Credentials saved locally; never commit .local/.`);
  for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => { gateway.relay.stop(); gateway.server.close(); });
}
