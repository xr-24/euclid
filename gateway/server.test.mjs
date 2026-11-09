import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, rmdir } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { createGateway } from './server.mjs';

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
  const rpc = (method, params) => post('/mcp/' + session, { jsonrpc: '2.0', id: 1, method, params });
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
});
