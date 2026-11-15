import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync, spawn } from 'node:child_process';
import { access, cp, mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import net from 'node:net';
import { setTimeout as sleep } from 'node:timers/promises';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { handoffVariable, inheritedHandoff } from './handoff.mjs';
import { createWorkbench } from './workbench.mjs';
import { isAgentSourcePath, isSourcePath, kernel } from './workbench-source.mjs';

const project = fileURLToPath(new URL('../', import.meta.url));

test('drafts reach the gateway and docs but never the kernel or launcher', async () => {
  for (const name of kernel) {
    await access(path.join(project, name));
    assert.equal(isAgentSourcePath(name), false, name);
  }
  for (const name of ['gateway/server.mjs', 'gateway/agents/claude.mjs', 'gateway/server.test.mjs', 'gateway/grid-plan.schema.json',
    'docs/architecture.md', 'README.md', 'world/scripts/world.gd', 'world/scripts/diagnostics/core_tests.gd', 'world/data/world.json']) {
    assert.equal(isAgentSourcePath(name), true, name);
  }
  for (const name of ['AGENTS.md', 'package.json', '.gitignore', 'Start Euclid.cmd', 'scripts/start.ps1', 'scripts/recovery.mjs',
    'scripts/check.ps1', 'scripts/stop-gateway.ps1', 'world/project.godot', 'gateway/../scripts/start.ps1', 'gateway/.env',
    'gateway/node_modules/x/index.js', 'docs/../package.json', 'docs/nested/guide.md', '.local/gateway.json', 'gateway/workbench-source.mjs ']) {
    assert.equal(isAgentSourcePath(name), false, name);
  }
  // The in-world editor keeps its Godot-only catalog.
  assert.equal(isSourcePath('gateway/server.mjs'), false);
});

test('committing or reverting gateway source asks the gateway to reload', async t => {
  const area = await mkdtemp(path.join(os.tmpdir(), 'euclid-scope-test-'));
  t.after(() => rm(area, { recursive: true, force: true }));
  const root = path.join(area, 'project');
  await mkdir(path.join(root, 'gateway'), { recursive: true });
  await mkdir(path.join(root, 'docs'));
  await mkdir(path.join(root, 'world/scripts'), { recursive: true });
  await writeFile(path.join(root, 'gateway/example.mjs'), 'export const ready = false;\n');
  await writeFile(path.join(root, 'docs/guide.md'), 'Guide.\n');
  await writeFile(path.join(root, 'world/scripts/example.gd'), 'extends Node\n');
  const git = (...args) => execFileSync('git', args, { cwd: root, windowsHide: true, encoding: 'utf8' }).trim();
  git('init', '-q');
  git('config', 'user.name', 'Euclid Test');
  git('config', 'user.email', 'test@example.invalid');
  git('config', 'core.autocrlf', 'false');
  git('add', '.');
  git('commit', '-qm', 'Fixture');
  let reloads = 0;
  const workbench = createWorkbench(root, path.join(area, 'workbench'), { onGatewayChange: () => { reloads++; },
    gatewayNotice: () => 'Fixture notice', runner: { async check() {}, playing: () => false, async stop() {} } });
  const call = (action, body = {}) => workbench(action, body, new AbortController().signal);
  async function until(status) {
    for (let attempt = 0; attempt < 100; attempt++) {
      const { draft } = await call('state');
      if (draft?.status === status) return draft;
      await sleep(20);
    }
    assert.fail('Draft did not reach ' + status);
  }
  async function commit(files, activation) {
    await call('submit', { owner: 'claude', prompt: 'Change the fixture', files });
    const staged = await until('staged');
    assert.equal(staged.activation, activation);
    await call('check', { id: staged.id, version: staged.version });
    await until('passed');
    return call('apply', { id: staged.id, version: staged.version, message: 'Fixture change' });
  }
  assert.equal((await call('state')).gateway_notice, 'Fixture notice');
  const docs = await commit([{ path: 'docs/guide.md', content: 'Guide, revised.\n' }], 'none');
  assert.deepEqual([docs.warning, reloads], ['', 0]);
  const world = await commit([{ path: 'world/scripts/example.gd', content: 'extends Node3D\n' }], 'hot');
  assert.deepEqual([world.warning, reloads, world.files], ['', 0, ['world/scripts/example.gd']]);
  const gateway = await commit([{ path: 'gateway/example.mjs', content: 'export const ready = true;\n' }], 'gateway_restart');
  assert.match(gateway.warning, /gateway is restarting/);
  assert.equal(reloads, 1);
  assert.match(await readFile(path.join(root, 'gateway/example.mjs'), 'utf8'), /ready = true/);
  const reverted = await call('restore', { revision: gateway.commit });
  assert.match(reverted.warning, /gateway is restarting/);
  assert.equal(reloads, 2);
  assert.match(await readFile(path.join(root, 'gateway/example.mjs'), 'utf8'), /ready = false/);
  const mixed = await commit([{ path: 'gateway/example.mjs', content: 'export const ready = 1;\n' },
    { path: 'world/scripts/example.gd', content: 'extends Node\n' }], 'hot');
  assert.match(mixed.warning, /gateway is restarting/);
  assert.equal(reloads, 3);

  const manual = createWorkbench(root, path.join(area, 'manual'), { runner: { async check() {}, playing: () => false, async stop() {} } });
  await manual('submit', { prompt: 'Change the fixture', files: [{ path: 'gateway/example.mjs', content: 'export const ready = 2;\n' }] }, new AbortController().signal);
  let staged;
  for (let attempt = 0; attempt < 100 && staged?.status !== 'staged'; attempt++) {
    ({ draft: staged } = await manual('state', {}, new AbortController().signal));
    await sleep(20);
  }
  await manual('check', { id: staged.id, version: staged.version }, new AbortController().signal);
  for (let attempt = 0; attempt < 100 && staged?.status !== 'passed'; attempt++) {
    ({ draft: staged } = await manual('state', {}, new AbortController().signal));
    await sleep(20);
  }
  const unmanaged = await manual('apply', { id: staged.id, version: staged.version, message: 'Fixture change' }, new AbortController().signal);
  assert.match(unmanaged.warning, /Restart the gateway to load/);
});

test('a handoff must carry three credentials and a port', () => {
  const valid = { token: 'a'.repeat(64), workbench_token: 'b'.repeat(64), development_token: 'c'.repeat(64), port: 4317 };
  const env = { [handoffVariable]: JSON.stringify(valid), OTHER: '1' };
  assert.deepEqual(inheritedHandoff(env), valid);
  assert.deepEqual(env, { OTHER: '1' });
  assert.equal(inheritedHandoff({}), null);
  for (const broken of ['{', '{}', JSON.stringify({ ...valid, port: 0 }), JSON.stringify({ ...valid, token: 'short' }),
    JSON.stringify({ ...valid, development_token: 'has spaces in the value' })]) {
    assert.throws(() => inheritedHandoff({ [handoffVariable]: broken }), /handoff is invalid/);
  }
});

// The remaining tests run real gateway processes from a copy of the gateway source.
async function gatewayCopy(t) {
  const area = await mkdtemp(path.join(os.tmpdir(), 'euclid-reload-test-'));
  const root = path.join(area, 'project');
  const dataDir = path.join(area, 'data');
  await cp(path.join(project, 'gateway'), path.join(root, 'gateway'), { recursive: true });
  await cp(path.join(project, 'world/data'), path.join(root, 'world/data'), { recursive: true });
  await mkdir(dataDir);
  const port = await new Promise(resolve => {
    const probe = net.createServer().listen(0, '127.0.0.1', () => { const { port } = probe.address(); probe.close(() => resolve(port)); });
  });
  const entry = path.join(root, 'gateway/server.mjs');
  const processes = new Set();
  const read = async name => readFile(path.join(dataDir, name), 'utf8').catch(error => { if (error.code !== 'ENOENT') throw error; return ''; });
  t.after(async () => {
    const replacement = Number(await read('gateway.pid'));
    for (const pid of [...processes].map(child => child.pid).concat(replacement || [])) {
      try { process.kill(pid); } catch {}
    }
    await sleep(200);
    await rm(area, { recursive: true, force: true, maxRetries: 10, retryDelay: 200 });
  });
  const origin = `http://127.0.0.1:${port}`;
  const world = token => fetch(origin + '/v1/world', { headers: { Authorization: `Bearer ${token}` } }).then(response => response.status, () => 0);
  async function eventually(probe, label) {
    for (let attempt = 0; attempt < 300; attempt++) {
      const value = await probe();
      if (value) return value;
      await sleep(100);
    }
    assert.fail('Timed out waiting for ' + label);
  }
  function start(extra = {}) {
    const env = { ...process.env, CONSTRUCT_PORT: String(port), EUCLID_DATA_DIR: dataDir, ...extra };
    delete env[handoffVariable];
    if (extra[handoffVariable]) env[handoffVariable] = extra[handoffVariable];
    const child = spawn(process.execPath, [entry], { cwd: root, env, stdio: 'ignore', windowsHide: true });
    processes.add(child);
    child.exited = new Promise(resolve => child.once('exit', resolve));
    return child;
  }
  const config = async () => { const text = await read('gateway.json'); return text ? JSON.parse(text) : null; };
  const workbench = (settings, action) => fetch(`${origin}/v1/workbench/${action}`, { method: 'POST', body: '{}',
    headers: { Authorization: `Bearer ${settings.token}`, 'X-Euclid-Workbench': settings.workbench_token, 'Content-Type': 'application/json' } })
    .then(response => response.json());
  return { entry, port, start, config, world, workbench, eventually, read };
}

test('a replacement gateway adopts the credentials and port it is handed', async t => {
  const { port, start, config, world, eventually, read } = await gatewayCopy(t);
  const handed = { token: 'a'.repeat(64), workbench_token: 'b'.repeat(64), development_token: 'c'.repeat(64), port };
  const child = start({ CONSTRUCT_PORT: '1', [handoffVariable]: JSON.stringify(handed) });
  await eventually(async () => await world(handed.token) === 200, 'the replacement gateway');
  assert.equal(await world('d'.repeat(64)), 401);
  const { url, ...saved } = await config();
  assert.deepEqual({ ...saved, port }, handed);
  assert.equal(url, `http://127.0.0.1:${port}`);
  assert.equal(Number(await read('gateway.pid')), child.pid);
});

test('reload replaces the gateway process and keeps its credentials', async t => {
  const { start, config, world, workbench, eventually, read } = await gatewayCopy(t);
  const first = start();
  const settings = await eventually(config, 'the first gateway');
  await eventually(async () => await world(settings.token) === 200, 'the first gateway to answer');
  assert.equal(await read('gateway.pid'), '');
  assert.deepEqual(await workbench(settings, 'reload'), { restarting: true });
  await first.exited;
  const replacement = Number(await eventually(() => read('gateway.pid'), 'the replacement to record itself'));
  assert.notEqual(replacement, first.pid);
  await eventually(async () => await world(settings.token) === 200, 'the replacement gateway to answer');
  assert.deepEqual(await config(), settings);
  assert.equal((await workbench(settings, 'state')).gateway_notice, '');
});

test('a gateway that cannot start is never swapped in', async t => {
  const { entry, start, config, world, workbench, eventually, read } = await gatewayCopy(t);
  const first = start();
  const settings = await eventually(config, 'the gateway');
  await eventually(async () => await world(settings.token) === 200, 'the gateway to answer');
  const source = await readFile(entry, 'utf8');

  // Broken code fails the startup check, and the running gateway never stops listening.
  await writeFile(entry, 'throw new Error("Fixture startup failure");\n' + source);
  await workbench(settings, 'reload');
  const kept = await eventually(async () => (await workbench(settings, 'state')).gateway_notice, 'the startup check to fail');
  assert.match(kept, /failed its startup check, so the running gateway was kept/);
  assert.match(kept, /Fixture startup failure/);

  // Code that passes the check but dies as a replacement makes the previous gateway resume.
  await writeFile(entry, `if (process.env.${handoffVariable}) process.exit(3);\n` + source);
  await workbench(settings, 'reload');
  const resumed = await eventually(async () => {
    const state = await workbench(settings, 'state').catch(() => null);
    return state?.gateway_notice && state.gateway_notice !== kept ? state.gateway_notice : '';
  }, 'the previous gateway to resume');
  assert.match(resumed, /did not start, so the previous gateway resumed/);
  assert.equal(await world(settings.token), 200);
  assert.equal(first.exitCode, null);
  assert.equal(await read('gateway.pid'), '');
});
