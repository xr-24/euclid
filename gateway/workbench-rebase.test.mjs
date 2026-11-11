import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdir, mkdtemp, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { setTimeout as sleep } from 'node:timers/promises';
import { createWorkbench } from './workbench.mjs';

const first = 'world/scripts/first.gd';
const second = 'world/scripts/second.gd';
const original = 'extends Node\n\nconst SPEED := 1\n\nfunc _ready():\n\tpass\n';

async function project(t) {
  const area = await mkdtemp(path.join(os.tmpdir(), 'euclid-rebase-test-'));
  t.after(() => rm(area, { recursive: true, force: true }));
  const root = path.join(area, 'project');
  await mkdir(path.join(root, 'world/scripts'), { recursive: true });
  await writeFile(path.join(root, first), original);
  await writeFile(path.join(root, second), 'extends Node\n');
  const git = (...args) => execFileSync('git', args, { cwd: root, windowsHide: true, encoding: 'utf8' }).trim();
  git('init', '-q');
  for (const [key, value] of [['core.autocrlf', 'false'], ['user.name', 'Fixture'], ['user.email', 'fixture@example.invalid']]) git('config', key, value);
  git('add', '.');
  git('commit', '-qm', 'Fixture');
  const commitOnMain = async (name, text, message) => {
    await writeFile(path.join(root, name), text);
    git('add', '.');
    git('commit', '-qm', message);
    return git('rev-parse', 'HEAD');
  };
  const storage = path.join(area, 'workbench');
  const workbench = createWorkbench(root, storage, { runner: { async check() { return { scope: 'full' }; }, playing: () => false, async stop() {} } });
  const call = (action, body = {}) => workbench(action, body, new AbortController().signal);
  async function settled(status) {
    for (let attempt = 0; attempt < 150; attempt++) {
      const { draft } = await call('state');
      if (draft?.status === status) return draft;
      await sleep(20);
    }
    assert.fail(`The draft did not reach ${status}.`);
  }
  async function submit(content) {
    await call('submit', { owner: 'codex', prompt: 'Faster', files: [{ path: first, content }] });
    return settled('staged');
  }
  const checkouts = async draft => (await readdir(path.join(storage, `git-draft-${draft.id}`), { withFileTypes: true }))
    .filter(item => item.isDirectory()).length;
  return { root, git, commitOnMain, call, settled, submit, checkouts };
}

test('a draft rebased onto a moved main branch keeps its change and needs fresh checks', async t => {
  const { root, git, commitOnMain, call, settled, submit, checkouts } = await project(t);
  const faster = original.replace('SPEED := 1', 'SPEED := 2');
  const draft = await submit(faster);
  await call('check', { id: draft.id, version: draft.version });
  await settled('passed');
  await assert.rejects(call('rebase', { id: draft.id, version: draft.version }), /already based on the tip/);

  const moved = await commitOnMain(second, 'extends Node\n# Moved on\n', 'Unrelated work');
  await assert.rejects(call('apply', { id: draft.id, version: draft.version, message: 'Too late' }), /main branch moved/);
  await assert.rejects(call('rebase', { id: draft.id, version: 'f'.repeat(64) }), /current (?:source )?draft version/);

  const { draft: rebased } = await call('rebase', { id: draft.id, version: draft.version });
  assert.equal(rebased.id, draft.id);
  assert.equal(rebased.version, draft.version, 'an identical patch keeps its version, but its checks start over');
  assert.deepEqual([rebased.base, rebased.status, rebased.check_status, rebased.has_previous], [moved, 'staged', '', false]);
  assert.deepEqual(rebased.files, [first]);
  assert.match(rebased.diff, /-const SPEED := 1\n\+const SPEED := 2/);
  assert.doesNotMatch(rebased.diff, /Moved on/);
  assert.equal(await checkouts(rebased), 1, 'the old checkout is removed');
  await assert.rejects(call('apply', { id: draft.id, version: rebased.version, message: 'Unchecked' }), /pass the project checks/);

  await call('check', { id: draft.id, version: rebased.version });
  await settled('passed');
  const applied = await call('apply', { id: draft.id, version: rebased.version, message: 'Faster after rebase' });
  assert.equal(git('rev-parse', 'HEAD^'), moved);
  assert.equal(await readFile(path.join(root, first), 'utf8'), faster);
  assert.equal(await readFile(path.join(root, second), 'utf8'), 'extends Node\n# Moved on\n');
  const history = (await call('history', { draft: draft.id })).entries.map(item => item.event).reverse();
  assert.deepEqual(history, ['drafted', 'checked', 'rebased', 'checked', 'committed']);
  assert.equal((await call('history', { limit: 3 })).entries[2].commit, moved);
  assert.equal(applied.commit, git('rev-parse', 'HEAD'));
});

test('a conflicting rebase names the files and leaves the draft as it was', async t => {
  const { root, commitOnMain, call, submit, checkouts } = await project(t);
  const draft = await submit(original.replace('SPEED := 1', 'SPEED := 2'));
  await commitOnMain(first, original.replace('SPEED := 1', 'SPEED := 3'), 'Competing speed');
  await assert.rejects(call('rebase', { id: draft.id, version: draft.version }), /conflicts with the main branch in world\/scripts\/first\.gd/);
  const { draft: unchanged } = await call('state');
  assert.deepEqual([unchanged.version, unchanged.base, unchanged.status], [draft.version, draft.base, 'staged']);
  assert.equal(await checkouts(draft), 1);
  assert.match(await readFile(path.join(root, first), 'utf8'), /SPEED := 3/);
});

test('a draft already on the main branch is not rebased into an empty change', async t => {
  const { commitOnMain, call, submit } = await project(t);
  const faster = original.replace('SPEED := 1', 'SPEED := 2');
  const draft = await submit(faster);
  await commitOnMain(first, faster, 'Same change by hand');
  await assert.rejects(call('rebase', { id: draft.id, version: draft.version }), /already contains every change/);
  assert.equal((await call('state')).draft.version, draft.version);
});
