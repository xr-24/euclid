import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { setTimeout as sleep } from 'node:timers/promises';
import os from 'node:os';
import path from 'node:path';
import { createGateway } from './server.mjs';

test('workbench isolates drafts, gates apply on checks, and restores a reviewed source file', async t => {
  const folder = await mkdtemp(path.join(os.tmpdir(), 'euclid-workbench-test-'));
  const root = path.join(folder, 'project');
  const dataDir = path.join(folder, 'gateway');
  const name = 'world/scripts/example.gd';
  const file = path.join(root, name);
  const original = 'extends Node\r\nconst VALUE := 1\r\n';
  await mkdir(path.dirname(file), { recursive: true });
  await writeFile(file, original);
  let server;
  let fail = true;
  let playing = false;
  const runner = {
    async check(draft, output) {
      assert.equal(await readFile(file, 'utf8'), original);
      assert.match(draft.after, /VALUE := 2/);
      output('Checked a staged copy.');
      if (fail) throw new Error('Test failure');
    },
    playing: () => playing,
    play: async () => { playing = true; },
    stop: async () => { playing = false; },
  };
  t.after(async () => {
    server.closeAllConnections();
    if (server.listening) await new Promise(resolve => server.close(resolve));
    await rm(folder, { recursive: true, force: true });
  });
  async function start() {
    const gateway = await createGateway({ dataDir, workbenchRoot: root, workbenchOptions: {
      runner, propose: async () => ({ summary: 'Raise value.', original: 'VALUE := 1', replacement: 'VALUE := 2' }),
    } });
    server = gateway.server;
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    const base = `http://127.0.0.1:${server.address().port}/v1/workbench/`;
    return async (action, args = {}, trusted = true) => {
      const headers = { Authorization: `Bearer ${gateway.token}`, 'Content-Type': 'application/json' };
      if (trusted) headers['X-Euclid-Workbench'] = gateway.workbenchToken;
      const result = await fetch(base + action, { method: 'POST', headers, body: JSON.stringify(args) });
      return { code: result.status, body: await result.json() };
    };
  }
  let call = await start();
  assert.equal((await call('state', {}, false)).code, 403);
  assert.equal((await call('read', { name: '../secrets.txt' })).code, 400);
  assert.equal((await call('read', { name: 'world/project.godot' })).code, 400);
  const { text, hash } = (await call('read', { name })).body;
  const suggested = await call('propose', { name, text, hash, prompt: 'Raise the value' });
  assert.equal(suggested.body.text, original.replace(':= 1', ':= 2'));
  const staged = await call('stage', { name, hash, text: suggested.body.text });
  const id = staged.body.draft.id;
  assert.match(staged.body.draft.diff, /\+const VALUE := 2/);
  assert.equal(await readFile(file, 'utf8'), original);
  await new Promise(resolve => server.close(resolve));
  call = await start();
  const recovered = (await call('state')).body.draft;
  assert.equal(recovered.id, id);
  assert.equal(recovered.status, 'staged');
  assert.equal(recovered.diff, staged.body.draft.diff);
  assert.equal((await call('apply', { id })).code, 400);
  assert.equal((await call('play', { id })).code, 400);
  async function checks() {
    await call('check', { id });
    for (let tries = 0; tries < 30; tries++) {
      const { body } = await call('state');
      if (body.draft.status !== 'checking') return body.draft;
      await sleep(20);
    }
    throw new Error('Check did not finish');
  }
  assert.equal((await checks()).status, 'failed');
  assert.equal((await call('apply', { id })).code, 400);
  fail = false;
  assert.equal((await checks()).status, 'passed');
  assert.equal((await call('play', { id })).body.playing, true);
  await writeFile(file, original.replace(':= 1', ':= 3'));
  assert.equal((await call('apply', { id })).code, 400);
  await writeFile(file, original);
  const applied = await call('apply', { id });
  assert.equal(applied.body.draft, null);
  assert.equal(applied.body.playing, false);
  assert.equal(await readFile(file, 'utf8'), suggested.body.text);
  await new Promise(resolve => server.close(resolve));
  call = await start();
  assert.equal((await call('state')).body.revision, name);
  assert.equal((await call('restore')).code, 200);
  assert.equal(await readFile(file, 'utf8'), original);
  assert.equal((await call('state')).body.revision, '');
});
