import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { setTimeout as sleep } from 'node:timers/promises';
import { createWorkbench } from './workbench.mjs';

const scripts = ['alpha', 'beta', 'gamma', 'delta', 'local'].map(name => `world/scripts/${name}.gd`);

test('several agents hold drafts at once, and the person reviews them one at a time', async t => {
  const area = await mkdtemp(path.join(os.tmpdir(), 'euclid-parallel-test-'));
  t.after(() => rm(area, { recursive: true, force: true }));
  const root = path.join(area, 'project');
  await mkdir(path.join(root, 'world/scripts'), { recursive: true });
  for (const name of scripts) await writeFile(path.join(root, name), 'extends Node\n');
  const git = (...args) => execFileSync('git', args, { cwd: root, windowsHide: true, encoding: 'utf8' }).trim();
  git('init', '-q');
  for (const [key, value] of [['core.autocrlf', 'false'], ['user.name', 'Fixture'], ['user.email', 'fixture@example.invalid']]) git('config', key, value);
  git('add', '.');
  git('commit', '-qm', 'Fixture');

  // Checks for alpha's draft wait until the test releases them.
  let release;
  const held = new Promise(resolve => { release = resolve; });
  const checked = [];
  const runner = {
    async check(change, log, signal) {
      checked.push(change.owner ?? 'workbench');
      if (change.owner === 'alpha' && checked.filter(name => name === 'alpha').length === 1) {
        await Promise.race([held, new Promise((_, reject) => signal.addEventListener('abort', () => reject(signal.reason)))]);
      }
      return { scope: 'full' };
    },
    playing: () => false, async stop() {},
  };
  const storage = path.join(area, 'workbench');
  let workbench = createWorkbench(root, storage, { runner });
  const call = (action, body = {}) => workbench(action, body, new AbortController().signal);
  async function until(test, owner) {
    for (let attempt = 0; attempt < 150; attempt++) {
      const state = await call('state', owner ? { owner } : {});
      if (test(state)) return state;
      await sleep(20);
    }
    assert.fail('The workbench did not settle.');
  }
  const staged = owner => until(state => state.draft?.status === 'staged' && !state.operation, owner).then(state => state.draft);
  async function submit(owner, file) {
    await call('submit', { owner, prompt: `Work by ${owner}`, files: [{ path: file, content: `extends Node\n# ${owner}\n` }] });
    return staged(owner);
  }

  // The person stages a draft, then three agents open drafts beside it.
  const local = scripts[4];
  const { hash } = await call('read', { name: local });
  await call('stage', { files: [{ name: local, hash, text: 'extends Node\n# person\n' }] });
  const mine = (await call('state')).draft;
  const alpha = await submit('alpha', scripts[0]);
  const beta = await submit('beta', scripts[1]);
  const gamma = await submit('gamma', scripts[2]);
  await assert.rejects(call('submit', { owner: 'delta', prompt: 'One too many', files: [{ path: scripts[3], content: 'x' }] }), /already holds 4 drafts/);
  await assert.rejects(call('submit', { owner: 'alpha', prompt: 'A second', files: [{ path: scripts[3], content: 'x' }] }), /Commit or discard/);

  let state = await call('state');
  assert.equal(state.draft.id, mine.id, 'the person keeps their own draft in view');
  assert.deepEqual(state.drafts.map(item => item.owner).sort(), ['', 'alpha', 'beta', 'gamma']);
  assert.equal((await call('state', { owner: 'beta' })).draft.id, beta.id);
  assert.equal((await call('file', { owner: 'beta', name: scripts[1] })).text, 'extends Node\n# beta\n');
  assert.equal((await call('file', { owner: 'alpha', name: scripts[1] })).text, 'extends Node\n');
  await assert.rejects(call('submit', { owner: 'beta', id: alpha.id, version: alpha.version, prompt: 'Take over',
    files: [{ path: scripts[0], content: 'x' }] }), /only revise its own draft/);

  // Alpha's checks run. Discarding gamma meanwhile does not cancel them; another check waits its turn.
  await call('check', { id: alpha.id, version: alpha.version, owner: 'alpha' });
  await assert.rejects(call('check', { id: beta.id, version: beta.version, owner: 'beta' }), /busy/);
  await call('discard', { id: gamma.id, version: gamma.version, owner: 'gamma' });
  assert.equal((await call('state', { owner: 'gamma' })).draft, null);
  assert.equal((await call('state', { owner: 'alpha' })).draft.status, 'checking');
  release();
  await until(state => state.draft?.status === 'passed' && !state.operation, 'alpha');

  // The person commits alpha's draft. Beta's now sits behind the main branch and is rebased before it commits.
  await call('focus', { id: alpha.id });
  assert.equal((await call('state')).draft.id, alpha.id);
  const first = await call('apply', { id: alpha.id, version: alpha.version, message: 'Alpha work' });
  assert.equal(first.draft.id, mine.id, 'focus moves to the next open draft');
  await call('check', { id: beta.id, version: beta.version, owner: 'beta' });
  await until(state => state.draft?.status === 'passed' && !state.operation, 'beta');
  await assert.rejects(call('apply', { id: beta.id, version: beta.version, message: 'Beta work' }), /main branch moved/);
  await call('rebase', { id: beta.id, version: beta.version, owner: 'beta' });
  await call('check', { id: beta.id, version: beta.version, owner: 'beta' });
  await until(state => state.draft?.status === 'passed' && !state.operation, 'beta');
  await call('apply', { id: beta.id, version: beta.version, message: 'Beta work' });
  assert.equal(await readFile(path.join(root, scripts[0]), 'utf8'), 'extends Node\n# alpha\n');
  assert.equal(await readFile(path.join(root, scripts[1]), 'utf8'), 'extends Node\n# beta\n');
  assert.deepEqual(git('log', '--format=%s', '-3').split('\n'), ['Beta work', 'Alpha work', 'Fixture']);

  // Open drafts survive a restart, and the person's draft is in view again.
  const delta = await submit('delta', scripts[3]);
  workbench = createWorkbench(root, storage, { runner });
  state = await call('state');
  assert.equal(state.draft.id, mine.id);
  assert.deepEqual(state.drafts.map(item => item.owner).sort(), ['', 'delta']);
  assert.equal((await call('state', { owner: 'delta' })).draft.version, delta.version);
  assert.deepEqual(checked, ['alpha', 'beta', 'beta']);
});
