import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, rmdir } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { createGateway } from './server.mjs';
import { installedSnapshot } from './command-registry.mjs';

test('gateway authentication, lifecycle, duplicates, limits and restart', async t => {
  const dataDir = await mkdtemp(path.join(os.tmpdir(), 'construct-test-'));
  let server;
  t.after(async () => { if (server?.listening) await new Promise(resolve => server.close(resolve)); await rm(dataDir, { recursive: true, force: true }); });
  async function start() {
    ({ server } = await createGateway({ dataDir, token: 'test-only-secret' }));
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    return `http://127.0.0.1:${server.address().port}`;
  }
  let base = await start();
  const headers = { Authorization: 'Bearer test-only-secret', 'Content-Type': 'application/json' };
  const event = { agent_id: 'example-worker', event_id: 'start-1', task_id: 'task-1', event: 'task.started', summary: 'Running actual check' };
  const post = body => fetch(`${base}/v1/events`, { method: 'POST', headers, body: JSON.stringify(body) });
  assert.equal((await fetch(`${base}/v1/world`)).status, 401);
  assert.equal((await fetch(`${base}/v1/world`, { headers: { ...headers, Origin: 'https://example.com' } })).status, 403);
  assert.equal((await post({ ...event, event: 'shell.execute' })).status, 400);
  assert.equal((await post({ ...event, agent_id: 'unassigned' })).status, 403);
  assert.equal((await post({ ...event, event: 'task.completed' })).status, 409);
  const media = await fetch(base + '/media/youtube');
  assert.equal(media.status, 200);
  assert.ok(media.headers.get('content-security-policy').includes('frame-src https://www.youtube.com'));
  assert.match(await media.text(), /onYouTubeIframeAPIReady/);
  assert.equal((await fetch(base + '/media/youtube', { headers: { Origin: 'https://example.com' } })).status, 403);
  const concurrent = await Promise.all([post(event), post(event)]);
  const results = await Promise.all(concurrent.map(response => response.json()));
  assert.equal(results.filter(result => result.accepted).length, 1);
  assert.equal(results.filter(result => result.duplicate).length, 1);
  assert.equal((await post({ ...event, event_id: 'start-2', task_id: 'other-task' })).status, 409);
  assert.equal((await post({ ...event, event_id: 'done-1', event: 'task.completed', summary: 'Check passed' })).status, 200);
  assert.equal((await post({ ...event, event_id: 'bad-text', summary: 'x'.repeat(2001) })).status, 400);
  assert.equal((await post({ ...event, summary: 'x'.repeat(9000) })).status, 413);
  assert.equal((await fetch(`${base}/v1/events`, { method: 'POST', headers, body: '{' })).status, 400);
  await new Promise(resolve => server.close(resolve));
  base = await start();
  const snapshot = await (await fetch(`${base}/v1/world`, { headers })).json();
  assert.equal(snapshot.agents[0].status, 'completed');
  assert.equal(snapshot.agents[0].summary, 'Check passed');
  assert.equal((await (await post(event)).json()).duplicate, true);
});

test('Grid plans require authentication, are bounded, and never overlap', async t => {
  const dataDir = await mkdtemp(path.join(os.tmpdir(), 'euclid-grid-test-'));
  const validPlan = { action: 'spawn_cone', color: 'ff681d', scale: 1 };
  let release;
  let started;
  const pending = new Promise(resolve => { release = resolve; });
  const entered = new Promise(resolve => { started = resolve; });
  const { server } = await createGateway({
    dataDir, token: 'grid-test-secret',
    gridPlanner: async prompt => {
      if (prompt === 'bad plan') return { ...validPlan, scale: 10 };
      if (prompt === 'provider failure') throw new Error('Sign-in required');
      started(prompt);
      return pending;
    },
  });
  t.after(async () => {
    release(validPlan);
    if (server.listening) await new Promise(resolve => server.close(resolve));
    await rmdir(dataDir);
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const endpoint = `http://127.0.0.1:${server.address().port}/v1/grid/plan`;
  const headers = { Authorization: 'Bearer grid-test-secret', 'Content-Type': 'application/json' };
  const post = (prompt, requestHeaders = headers) => fetch(endpoint, {
    method: 'POST', headers: requestHeaders, body: JSON.stringify({ prompt }),
  });
  assert.equal((await post('Make a cone', {})).status, 401);
  assert.equal((await post('x'.repeat(241))).status, 400);
  assert.equal((await post('bad plan')).status, 502);
  assert.equal((await post('provider failure')).status, 503);
  const first = post('  Make a cone  ');
  assert.equal(await entered, 'Make a cone');
  assert.equal((await post('Another cone')).status, 409);
  release(validPlan);
  const response = await first;
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { agent_id: 'local-codex', plan: validPlan });
});

test('MCP discovers a live world and waits for its tool result', async t => {
  const dataDir = await mkdtemp(path.join(os.tmpdir(), 'euclid-world-test-'));
  const { server } = await createGateway({ dataDir, token: 'world-test-secret' });
  t.after(async () => {
    server.closeAllConnections();
    if (server.listening) await new Promise(resolve => server.close(resolve));
    await rmdir(dataDir);
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const base = `http://127.0.0.1:${server.address().port}`;
  const session = 'a'.repeat(32);
  const headers = { Authorization: 'Bearer world-test-secret', 'Content-Type': 'application/json' };
  const post = (route, body) => fetch(base + route, { method: 'POST', headers, body: JSON.stringify(body) }).then(response => response.json());
  const rpc = (method, params, worldSession = session) => post('/mcp/' + worldSession, { jsonrpc: '2.0', id: 1, method, params });
  const context = { current: 'custom', environments: [{ id: 'custom', name: 'Signal Lab', description: 'A custom space' }] };
  const sync = result => post('/v1/companion/sync', { session, context, result });
  assert((await rpc('tools/list')).result.tools.some(tool => tool.name === 'preview_animation'));
  assert.equal((await rpc('tools/call', { name: 'list_environments' })).result.isError, true);
  await sync();
  const listed = await rpc('tools/call', { name: 'list_environments' });
  assert.deepEqual(JSON.parse(listed.result.content[0].text).environments, context.environments);
  const waiting = rpc('tools/call', { name: 'follow' });
  let command;
  for (let tries = 0; !command && tries < 10; tries++) {
    ({ command } = await sync());
  }
  assert.equal(command?.tool, 'follow');
  assert.equal((await sync()).command.id, command.id);
  await sync({ id: command.id, value: { ok: true, mode: 'follow' } });
  const answer = await waiting;
  assert.deepEqual(JSON.parse(answer.result.content[0].text), { ok: true, mode: 'follow' });
  assert.equal((await sync()).command, null);

  const key = time => ({ time, offset: [0, 0, 0], rotation: [0, 0, 0], pose: [0, 0] });
  const clip = { name: 'Head turn', duration: 4, interpolation: 'smooth', keyframes: [key(0), key(4)],
    joint_tracks: [{ joint: 'head', keyframes: [{ time: 0, rotation: [0, 0, 0] }, { time: 4, rotation: [0, 0, 0] }] }] };
  const rejected = await rpc('tools/call', { name: 'preview_animation', arguments: { target: '../companion', clip } });
  assert.equal(rejected.error.code, -32602);
  const preview = rpc('tools/call', { name: 'preview_animation', arguments: { target: 'companion', clip } });
  command = null;
  for (let tries = 0; !command && tries < 10; tries++) ({ command } = await sync());
  assert.equal(command?.tool, 'preview_animation');
  assert.deepEqual(command.clip, clip);
  await sync({ id: command.id, value: { ok: true, message: 'Preview applied' } });
  assert.equal((await preview).result.isError, false);

  const prefabTools = (await rpc('tools/list')).result.tools.filter(tool => tool.name.endsWith('_prefab') || tool.name === 'list_prefabs');
  assert.deepEqual(prefabTools.map(tool => tool.name), ['list_prefabs', 'save_prefab', 'spawn_prefab']);
  const entityId = 'b'.repeat(32);
  const invalidSceneEdit = await rpc('tools/call', { name: 'edit_entity',
    arguments: { target: entityId, changes: { name: 'Missing scene' } } });
  assert.equal(invalidSceneEdit.error.code, -32602);
  const invalidTransform = await rpc('tools/call', { name: 'edit_entity',
    arguments: { zone: context.current, target: entityId, changes: { position: [1, 2] } } });
  assert.equal(invalidTransform.error.code, -32602);
  const moving = rpc('tools/call', { name: 'edit_entity',
    arguments: { zone: context.current, target: entityId, changes: { position: [1, 0.15, -76], name: 'Library vase' } } });
  command = null;
  for (let tries = 0; !command && tries < 10; tries++) ({ command } = await sync());
  assert.equal(command?.tool, 'edit_entity');
  assert.equal(command.zone, context.current);
  assert.deepEqual(command.changes, { position: [1, 0.15, -76], name: 'Library vase' });
  await sync({ id: command.id, value: { ok: true, id: entityId } });
  assert.equal((await moving).result.isError, false);
  const invalidRestore = await rpc('tools/call', { name: 'restore_dressing',
    arguments: { target: entityId } });
  assert.equal(invalidRestore.error.code, -32602);
  const restoring = rpc('tools/call', { name: 'restore_dressing',
    arguments: { zone: context.current, target: entityId } });
  command = null;
  for (let tries = 0; !command && tries < 10; tries++) ({ command } = await sync());
  assert.equal(command?.tool, 'restore_dressing');
  assert.equal(command.zone, context.current);
  assert.equal(command.target, entityId);
  await sync({ id: command.id, value: { ok: true, id: entityId } });
  assert.equal((await restoring).result.isError, false);
  const invalid = await rpc('tools/call', { name: 'save_prefab', arguments: { target: entityId, name: 'Bad\nname' } });
  assert.equal(invalid.error.code, -32602);
  const saving = rpc('tools/call', { name: 'save_prefab', arguments: { target: entityId, name: 'Hover cone' } });
  command = null;
  for (let tries = 0; !command && tries < 10; tries++) ({ command } = await sync());
  assert.equal(command?.tool, 'save_prefab');
  assert.equal(command.target, entityId);
  assert.equal(command.name, 'Hover cone');
  const saved = { ok: true, prefab_id: 'c'.repeat(32) };
  await sync({ id: command.id, value: saved });
  assert.deepEqual(JSON.parse((await saving).result.content[0].text), saved);

  const behavior = { id: 'proximity_pulse', settings: [{ key: 'radius', value: 4 }] };
  const repeated = { ...behavior, settings: [...behavior.settings, ...behavior.settings] };
  assert.equal((await rpc('tools/call', { name: 'set_behavior', arguments: { target: entityId, behavior: repeated } })).error.code, -32602);
  const configuring = rpc('tools/call', { name: 'set_behavior', arguments: { target: entityId, behavior } });
  command = null;
  for (let tries = 0; !command && tries < 10; tries++) ({ command } = await sync());
  assert.equal(command?.tool, 'set_behavior');
  assert.deepEqual(command.behavior, behavior);
  await sync({ id: command.id, value: { ok: true } });
  assert.equal((await configuring).result.isError, false);
  context.behaviors = [{ id: 'proximity_pulse', name: 'Proximity pulse', settings: {
    radius: { minimum: 1, maximum: 12, default: 4 },
  } }];
  await sync();
  const attachmentName = 'attach_behavior_proximity_pulse';
  assert((await rpc('tools/list')).result.tools.some(tool => tool.name === attachmentName));
  assert.equal((await rpc('tools/call', { name: attachmentName,
    arguments: { target: entityId, settings: { radius: 13 } } })).error.code, -32602);
  const attachment = rpc('tools/call', { name: attachmentName,
    arguments: { target: entityId, settings: { radius: 6 } } });
  command = null;
  for (let tries = 0; !command && tries < 10; tries++) ({ command } = await sync());
  assert.equal(command?.tool, 'set_behavior');
  assert.equal(command.behavior.id, 'proximity_pulse');
  assert.deepEqual(command.behavior.settings, [{ key: 'radius', value: 6 }]);
  await sync({ id: command.id, value: { ok: true } });
  assert.equal((await attachment).result.isError, false);
  context.behaviors = [];
  await sync();
  assert(!(await rpc('tools/list')).result.tools.some(tool => tool.name === attachmentName));

  const reset = { name: 'grid_action_test_reset', label: 'Reset demo', description: 'Return the demo objects to their starting state.', revision: 'd'.repeat(64) };
  context.workshop_tools = [reset];
  await sync();
  assert((await rpc('tools/list')).result.tools.some(tool => tool.name === reset.name));
  const discovered = await rpc('tools/call', { name: 'list_workshop_tools' });
  assert.deepEqual(JSON.parse(discovered.result.content[0].text).tools, [reset]);
  assert.equal((await rpc('tools/call', { name: reset.name, arguments: { position: [1, 2, 3] } })).error.code, -32602);
  const running = rpc('tools/call', { name: 'run_workshop_tool', arguments: { name: reset.name } });
  command = null;
  for (let tries = 0; !command && tries < 10; tries++) ({ command } = await sync());
  assert.equal(command?.tool, 'run_workshop_tool');
  assert.equal(command?.target, reset.name);
  assert.equal(command?.revision, reset.revision);
  assert.equal(command?.zone, context.current);
  await sync({ id: command.id, value: { ok: true } });
  assert.equal((await running).result.isError, false);
  context.workshop_tools = [];
  await sync();
  assert(!(await rpc('tools/list')).result.tools.some(tool => tool.name === reset.name));
  assert.equal((await rpc('tools/call', { name: reset.name })).result.isError, true);
  const previewSession = 'c'.repeat(32);
  const registry = structuredClone(installedSnapshot);
  registry.commands.push({ ...registry.commands.find(tool => tool.name === 'follow'), name: 'fixture_follow' });
  const previewContext = { ...context, command_registry: registry };
  const previewSync = result => post('/v1/companion/sync', { session: previewSession, context: previewContext, result });
  await previewSync();
  assert((await rpc('tools/list', {}, previewSession)).result.tools.some(tool => tool.name === 'fixture_follow'));
  assert(!(await rpc('tools/list')).result.tools.some(tool => tool.name === 'fixture_follow'));
  const custom = rpc('tools/call', { name: 'fixture_follow' }, previewSession);
  command = null;
  for (let tries = 0; !command && tries < 10; tries++) ({ command } = await previewSync());
  assert.equal(command?.tool, 'fixture_follow');
  await previewSync({ id: command.id, value: { ok: true } });
  assert.equal((await custom).result.isError, false);
});

test('agent tool calls reach the activity feed the world long-polls', async t => {
  const dataDir = await mkdtemp(path.join(os.tmpdir(), 'euclid-activity-test-'));
  const developmentToken = 'd'.repeat(64);
  const { server } = await createGateway({ dataDir, token: 'test-only-secret', workbenchToken: 'bench', developmentToken });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(async () => { await new Promise(resolve => server.close(resolve)); await rm(dataDir, { recursive: true, force: true }); });
  const base = `http://127.0.0.1:${server.address().port}`;
  const headers = { Authorization: 'Bearer test-only-secret', 'Content-Type': 'application/json' };
  const feed = (body, extra = { 'X-Euclid-Workbench': 'bench' }) =>
    fetch(`${base}/v1/activity/feed`, { method: 'POST', headers: { ...headers, ...extra }, body: JSON.stringify(body) });
  assert.equal((await feed({}, {})).status, 403);
  assert.deepEqual(await (await feed({ since: 0 })).json(), { events: [], next: 0, reset: false });
  const waiting = feed({ since: 0, wait: 5 });
  const call = await fetch(`${base}/mcp/dev/${developmentToken}/scout`, { method: 'POST', headers,
    body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name: 'read_source', arguments: { path: 'README.md' } } }) });
  assert.equal(call.status, 200);
  const { events, next } = await (await waiting).json();
  assert.equal(events[0].actor, 'scout');
  assert.equal(events[0].kind, 'read');
  assert.equal(events[0].path, 'README.md');
  assert.ok(events[0].lines.length > 0);
  assert.equal(next, events.at(-1).seq);
});
