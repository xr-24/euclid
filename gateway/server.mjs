import http from 'node:http';
import { randomBytes, timingSafeEqual } from 'node:crypto';
import { readFile, writeFile, mkdir, appendFile, rename } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { createReadStream } from 'node:fs';
import { createAssetService, validAssetId } from './assets.mjs';
import { planWorld, validGridPlan } from './world-planner.mjs';
import { createWorldBridge, validContext, validWorldPlan } from './world-tools.mjs';
import { createWorkbench } from './workbench.mjs';

export const root = fileURLToPath(new URL('../', import.meta.url));
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
  workbenchRoot = root, workbenchOptions } = {}) {
  await mkdir(dataDir, { recursive: true });
  const world = JSON.parse(await readFile(worldPath, 'utf8'));
  let saved = { agents: {}, seen: [] };
  try { saved = JSON.parse(await readFile(path.join(dataDir, 'state.json'), 'utf8')); }
  catch (error) { if (error.code !== 'ENOENT') throw error; }
  const secret = token ?? randomBytes(32).toString('hex');
  const expected = Buffer.from(`Bearer ${secret}`);
  const workbenchToken = randomBytes(32).toString('hex');
  const workbenchExpected = Buffer.from(workbenchToken);
  const workbench = createWorkbench(workbenchRoot, path.join(dataDir, 'workbench'), workbenchOptions);
  let queue = Promise.resolve();
  let rateStart = Date.now();
  let rateCount = 0;
  let gridBusy = false;
  const assets = createAssetService(path.join(dataDir, 'runtime-assets'));
  const bridge = createWorldBridge(assets);
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
      if (req.method === 'GET' && req.url === '/health') return reply(res, 200, { service: 'construct-gateway', version: 23 });
      const supplied = Buffer.from(req.headers.authorization ?? '');
      if (supplied.length !== expected.length || !timingSafeEqual(supplied, expected)) return reply(res, 401, { error: 'Unauthorized' });
      if (Date.now() - rateStart > 60000) { rateStart = Date.now(); rateCount = 0; }
      if (++rateCount > 240) return reply(res, 429, { error: 'Rate limit exceeded' });
      const workbenchRoute = /^\/v1\/workbench\/([a-z]+)$/.exec(req.url);
      if (workbenchRoute) {
        const capability = Buffer.from(req.headers['x-euclid-workbench'] ?? '');
        if (capability.length !== workbenchExpected.length || !timingSafeEqual(capability, workbenchExpected)) return reply(res, 403, { error: 'Workbench access requires the local Euclid launcher.' });
        if (req.method !== 'POST') return reply(res, 405, { error: 'Use POST' });
        const body = await readJson(req, res, 512 * 1024);
        if (body === undefined) return;
        if (!body || typeof body !== 'object' || Array.isArray(body)) return reply(res, 400, { error: 'Expected an object' });
        const controller = new AbortController();
        res.once('close', () => controller.abort());
        try { return reply(res, 200, await workbench(workbenchRoute[1], body, controller.signal)); }
        catch (error) { if (!res.destroyed) return reply(res, 400, { error: error.message }); return; }
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
        return reply(res, 200, { ...world, agents });
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
  return { server, token: secret, workbenchToken };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const gateway = await createGateway();
  const port = Number(process.env.CONSTRUCT_PORT ?? 4317);
  gateway.server.on('error', error => { console.error(`Gateway: ${error.message}`); process.exitCode = 1; });
  gateway.server.listen(port, '127.0.0.1', async () => {
    await writeFile(path.join(root, '.local/gateway.json'), JSON.stringify({ url: `http://127.0.0.1:${port}`, token: gateway.token, workbench_token: gateway.workbenchToken }), { mode: 0o600 });
    console.log(`Euclid gateway ready on 127.0.0.1:${port}. Credentials saved locally; never commit .local/.`);
  });
  for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => gateway.server.close());
}
