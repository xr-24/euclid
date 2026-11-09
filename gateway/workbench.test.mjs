import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { setTimeout as sleep } from 'node:timers/promises';
import os from 'node:os';
import path from 'node:path';
import { createGateway } from './server.mjs';
import { fingerprint } from './workbench-source.mjs';

test('workbench checks and commits an isolated two-file Git draft, and reverts it', async t => {
  const folder = await mkdtemp(path.join(os.tmpdir(), 'euclid-workbench-test-'));
  const root = path.join(folder, 'project');
  const dataDir = path.join(folder, 'gateway');
  const name = 'world/scripts/example.gd';
  const other = 'world/scripts/other.gd';
  const plugin = 'world/scripts/plugins/proximity_pulse.gd';
  const file = path.join(root, name);
  const original = 'extends Node\nconst VALUE := 1\n';
  const otherOriginal = 'extends Node\nconst LABEL := "Old"\n';
  const git = (...args) => execFileSync('git', args, { cwd: root, encoding: 'utf8', windowsHide: true }).trim();
  await mkdir(path.dirname(file), { recursive: true });
  await writeFile(file, original);
  await writeFile(path.join(root, other), otherOriginal);
  await mkdir(path.join(root, 'world/scripts/plugins'));
  await mkdir(path.join(root, 'world/data'));
  await writeFile(path.join(root, plugin), original);
  await writeFile(path.join(root, 'world/data/behavior_plugins.json'), JSON.stringify({ schema_version: 1, plugins: [{ id: 'proximity_pulse' }] }));
  git('init', '-q');
  git('config', 'user.name', 'Euclid Test');
  git('config', 'user.email', 'test@example.invalid');
  git('config', 'core.autocrlf', 'false');
  git('add', '.');
  git('commit', '-qm', 'Baseline');
  const base = git('rev-parse', 'HEAD');
  let server;
  let fail = true;
  let playing = false;
  const runner = {
    async check(draft, output) {
      assert.equal(await readFile(file, 'utf8'), original);
      assert.match(await readFile(path.join(draft.worktree, name), 'utf8'), /VALUE := 2/);
      assert.match(await readFile(path.join(draft.worktree, other), 'utf8'), /"New"/);
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
      runner, propose: async () => ({ summary: 'Raise the value and update the label.', edits: [
        { file: name, original: 'VALUE := 1', replacement: 'VALUE := 2' },
        { file: other, original: '"Old"', replacement: '"New"' },
      ] }),
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
  const originals = await Promise.all([name, other].map(async name => ({ name, ...(await call('read', { name })).body })));
  const suggested = await call('propose', { files: originals, prompt: 'Raise the value and update the label' });
  const files = suggested.body.files.map(file => ({ ...file, hash: originals.find(item => item.name === file.name).hash }));
  assert.equal(files[0].text, original.replace(':= 1', ':= 2'));
  const staged = await call('stage', { files });
  assert.equal(staged.code, 200, JSON.stringify(staged.body));
  const id = staged.body.draft.id;
  assert.match(staged.body.draft.diff, /\+const VALUE := 2/);
  assert.match(staged.body.draft.diff, /\+const LABEL := "New"/);
  assert.equal(await readFile(file, 'utf8'), original);
  await new Promise(resolve => server.close(resolve));
  call = await start();
  const recovered = (await call('state')).body.draft;
  assert.equal(recovered.id, id);
  assert.equal(recovered.status, 'staged');
  assert.equal(recovered.diff, staged.body.draft.diff);
  const accept = { id, message: 'Update value and label' };
  assert.equal((await call('apply', accept)).code, 400);
  assert.equal((await call('play', { id })).code, 400);
  assert.equal((await call('live', { id })).code, 400);
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
  assert.equal((await call('apply', accept)).code, 400);
  fail = false;
  assert.equal((await checks()).status, 'passed');
  assert.equal((await call('play', { id })).body.playing, true);
  await writeFile(file, original.replace(':= 1', ':= 3'));
  const blocked = await call('apply', accept);
  assert.equal(blocked.code, 400);
  assert.match(blocked.body.error, /local changes/);
  assert.equal((await call('state')).body.draft.id, id);
  await writeFile(file, original);
  git('commit', '--allow-empty', '-qm', 'Concurrent change');
  assert.match((await call('apply', accept)).body.error, /main branch moved/);
  assert.equal((await call('state')).body.draft.id, id);
  git('reset', '--soft', base);
  const applied = await call('apply', accept);
  assert.equal(applied.code, 200, JSON.stringify(applied.body));
  assert.equal(applied.body.draft, null);
  assert.equal(applied.body.playing, false);
  assert.equal(await readFile(file, 'utf8'), files[0].text);
  assert.equal(await readFile(path.join(root, other), 'utf8'), files[1].text);
  assert.equal(git('rev-parse', 'HEAD^'), base);
  assert.equal(git('log', '-1', '--format=%s'), accept.message);
  assert.equal(git('status', '--porcelain'), '');
  assert.equal(git('worktree', 'list', '--porcelain').split('\n').filter(line => line.startsWith('worktree ')).length, 1);
  await new Promise(resolve => server.close(resolve));
  call = await start();
  const revision = (await call('state')).body.revision;
  assert.equal(revision, applied.body.commit);
  assert.equal((await call('restore', { revision })).code, 200);
  assert.equal(await readFile(file, 'utf8'), original);
  assert.equal(await readFile(path.join(root, other), 'utf8'), otherOriginal);
  assert.equal(git('rev-parse', 'HEAD^'), revision);
  assert.equal((await call('state')).body.revision, '');

  const before = (await call('read', { name: plugin })).body;
  const liveDraft = (await call('stage', { files: [{ name: plugin, hash: before.hash, text: files[0].text }] })).body.draft;
  assert.equal(liveDraft.live, true);
  assert.equal((await call('live', { id: liveDraft.id }, false)).code, 403);
  const live = (await call('live', { id: liveDraft.id })).body.live;
  assert.deepEqual(live, { draft: liveDraft.id, plugin: 'proximity_pulse', source: files[0].text, digest: fingerprint(files[0].text) });
  assert.equal(await readFile(path.join(root, plugin), 'utf8'), original);
  assert.equal((await call('discard', { id: liveDraft.id })).body.draft, null);
});
