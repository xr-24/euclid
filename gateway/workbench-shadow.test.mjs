import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { cp, lstat, mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createGateway } from './server.mjs';

const repoRoot = fileURLToPath(new URL('../', import.meta.url));

test('shadow gateway preview boots drafted gateway code, serves live probes, stops on revise/discard, and rejects broken syntax', async t => {
  const area = await mkdtemp(path.join(os.tmpdir(), 'euclid-shadow-test-'));
  const root = path.join(area, 'project');
  const dataDir = path.join(area, 'data');
  await mkdir(path.join(root, 'world/scripts'), { recursive: true });
  await cp(path.join(repoRoot, 'gateway'), path.join(root, 'gateway'), {
    recursive: true,
    filter: src => !path.relative(repoRoot, src).split(path.sep).some(part => ['.local', 'node_modules', '__pycache__'].includes(part)),
  });
  await cp(path.join(repoRoot, 'world/data'), path.join(root, 'world/data'), { recursive: true });
  await cp(path.join(repoRoot, 'package.json'), path.join(root, 'package.json'));
  await writeFile(path.join(root, 'world/scripts/example.gd'), 'extends Node\n');

  const git = (...args) => execFileSync('git', args, { cwd: root, windowsHide: true, encoding: 'utf8' }).trim();
  git('init', '-q');
  git('config', 'user.name', 'Euclid Test');
  git('config', 'user.email', 'test@example.invalid');
  git('config', 'core.autocrlf', 'false');
  git('add', '.');
  git('commit', '-qm', 'Fixture');

  const capability = 'd'.repeat(64);
  const { server } = await createGateway({
    dataDir,
    token: 'shadow-test-secret',
    developmentToken: capability,
    workbenchRoot: root,
    workbenchOptions: { runner: { playing: () => false, async stop() {} } },
  });
  t.after(async () => {
    server.closeAllConnections();
    if (server.listening) await new Promise(resolve => server.close(resolve));
    await rm(area, { recursive: true, force: true });
  });

  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const origin = `http://127.0.0.1:${server.address().port}`;
  const headers = { Authorization: 'Bearer shadow-test-secret', 'Content-Type': 'application/json' };
  const tool = async (name, args = {}, agent = 'claude') => {
    const response = await fetch(`${origin}/mcp/dev/${capability}/${agent}`, {
      method: 'POST',
      headers,
      body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name, arguments: args } }),
    });
    const answer = await response.json();
    assert.ok(answer.result, JSON.stringify(answer.error));
    return { ...JSON.parse(answer.result.content[0].text), isError: answer.result.isError };
  };

  await t.test('rejects drafts that do not touch gateway/', async () => {
    const drafted = await tool('patch_draft', {
      request: 'Edit world script only',
      edits: [{ path: 'world/scripts/example.gd', old_text: 'extends Node', new_text: 'extends Node3D' }],
    });
    assert.equal(drafted.isError, false, drafted.message);
    const started = await tool('preview_gateway', { version: drafted.draft.version, action: 'start' });
    assert.equal(started.isError, true);
    assert.match(started.message, /changes gateway\/ files/);
    assert.equal((await tool('discard_draft', { version: drafted.draft.version })).isError, false);
  });

  await t.test('starts shadow, serves /v1/shadow-ping and /mcp/dev, and stops on revise and discard', async () => {
    const anchor = "if (supplied.length !== expected.length || !timingSafeEqual(supplied, expected)) return reply(res, 401, { error: 'Unauthorized' });";
    const drafted = await tool('patch_draft', {
      request: 'Add shadow ping route',
      edits: [{
        path: 'gateway/server.mjs',
        old_text: anchor,
        new_text: `${anchor}\n      if (req.method === 'GET' && req.url === '/v1/shadow-ping') return reply(res, 200, { pong: true });`,
      }],
    });
    assert.equal(drafted.isError, false, drafted.message);
    const v1 = drafted.draft.version;

    const before = await tool('preview_gateway', { version: v1, action: 'status' });
    assert.deepEqual(before, { ok: true, running: false, isError: false });

    const started = await tool('preview_gateway', { version: v1, action: 'start' });
    assert.equal(started.isError, false, started.message);
    assert.equal(started.running, true);
    assert.equal(started.version, v1);
    assert.ok(Number.isInteger(started.port) && started.port > 0);
    const port1 = started.port;

    const status = await tool('preview_gateway', { version: v1, action: 'status' });
    assert.equal(status.running, true);
    assert.equal(status.stale, false);
    assert.equal(status.port, port1);

    const ping = await tool('preview_gateway', { version: v1, action: 'call', method: 'GET', path: '/v1/shadow-ping', auth: 'bearer' });
    assert.equal(ping.isError, false, ping.message);
    assert.equal(ping.status, 200);
    assert.deepEqual(ping.body, { pong: true });

    const unauth = await tool('preview_gateway', { version: v1, action: 'call', method: 'GET', path: '/v1/shadow-ping', auth: 'none' });
    assert.equal(unauth.status, 401);

    const mcp = await tool('preview_gateway', {
      version: v1,
      action: 'call',
      method: 'POST',
      path: '/mcp/dev',
      auth: 'bearer',
      body: { jsonrpc: '2.0', id: 7, method: 'tools/list' },
    });
    assert.equal(mcp.isError, false, mcp.message);
    assert.equal(mcp.status, 200);
    assert.ok(mcp.body.result.tools.some(item => item.name === 'preview_gateway'));

    const badPath = await tool('preview_gateway', { version: v1, action: 'call', method: 'GET', path: '/v1/../health' });
    assert.equal(badPath.isError, true);

    assert.equal(await lstat(path.join(root, '.local')).catch(error => error.code), 'ENOENT');

    // Revising the draft stops the running shadow process before publishing the new version.
    const revised = await tool('patch_draft', {
      version: v1,
      request: 'Update shadow ping payload',
      edits: [{
        path: 'gateway/server.mjs',
        old_text: "if (req.method === 'GET' && req.url === '/v1/shadow-ping') return reply(res, 200, { pong: true });",
        new_text: "if (req.method === 'GET' && req.url === '/v1/shadow-ping') return reply(res, 200, { pong: 2 });",
      }],
    });
    assert.equal(revised.isError, false, revised.message);
    const v2 = revised.draft.version;
    assert.notEqual(v2, v1);

    const afterRevise = await tool('preview_gateway', { version: v2, action: 'status' });
    assert.equal(afterRevise.running, false);
    await assert.rejects(fetch(`http://127.0.0.1:${port1}/health`));

    const restarted = await tool('preview_gateway', { version: v2, action: 'start' });
    assert.equal(restarted.isError, false, restarted.message);
    const ping2 = await tool('preview_gateway', { version: v2, action: 'call', method: 'GET', path: '/v1/shadow-ping' });
    assert.equal(ping2.status, 200);
    assert.deepEqual(ping2.body, { pong: 2 });

    assert.equal((await tool('discard_draft', { version: v2 })).isError, false);
    await assert.rejects(fetch(`http://127.0.0.1:${restarted.port}/health`));
  });

  await t.test('fails preflight cleanly on broken syntax in gateway/server.mjs', async () => {
    const broken = await tool('patch_draft', {
      request: 'Introduce syntax error in gateway/server.mjs',
      edits: [{
        path: 'gateway/server.mjs',
        old_text: "if (req.method === 'GET' && req.url === '/health')",
        new_text: 'if (req.method === {{{',
      }],
    });
    assert.equal(broken.isError, false, broken.message);
    const started = await tool('preview_gateway', { version: broken.draft.version, action: 'start' });
    assert.equal(started.isError, true);
    assert.match(started.message, /preflight failed/i);
    assert.equal((await tool('preview_gateway', { version: broken.draft.version, action: 'status' })).running, false);
    assert.equal((await tool('discard_draft', { version: broken.draft.version })).isError, false);
  });
});
