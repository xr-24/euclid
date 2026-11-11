import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { setTimeout as sleep } from 'node:timers/promises';
import os from 'node:os';
import path from 'node:path';
import { createGateway } from './server.mjs';
import { developmentTools } from './workbench-mcp.mjs';

test('a connected agent reads source, submits and revises a draft, and runs its checks', async t => {
  const area = await mkdtemp(path.join(os.tmpdir(), 'euclid-dev-mcp-test-'));
  const root = path.join(area, 'project');
  const script = 'world/scripts/example.gd';
  const obsolete = 'world/scripts/old.gd';
  const added = 'world/scripts/diagnostics/example_test.gd';
  await mkdir(path.join(root, 'world/scripts'), { recursive: true });
  await mkdir(path.join(root, 'docs'));
  await writeFile(path.join(root, script), 'extends Node\nconst READY := false\n');
  await writeFile(path.join(root, obsolete), 'extends Node\n');
  await writeFile(path.join(root, 'README.md'), '# Fixture\n');
  await writeFile(path.join(root, 'docs/architecture.md'), 'Fixture architecture.\n');
  await writeFile(path.join(root, 'package.json'), '{}\n');
  const git = (...args) => execFileSync('git', args, { cwd: root, windowsHide: true, encoding: 'utf8' }).trim();
  git('init', '-q');
  git('config', 'user.name', 'Euclid Test');
  git('config', 'user.email', 'test@example.invalid');
  git('config', 'core.autocrlf', 'false');
  git('add', '.');
  git('commit', '-qm', 'Fixture');
  const base = git('rev-parse', 'HEAD');
  let checks = 0;
  const runner = {
    async check(draft, log) {
      checks++;
      const source = await readFile(path.join(draft.worktree, script), 'utf8');
      log(`Checked ${source.length} characters.\n`);
      if (!source.includes('READY := true')) throw new Error('READY must be true.');
      return { scope: 'full' };
    },
    playing: () => false,
    async stop() {},
  };
  const capability = 'd'.repeat(64);
  const { server, developmentToken } = await createGateway({ dataDir: path.join(area, 'data'), token: 'dev-test-secret',
    developmentToken: capability, workbenchRoot: root, workbenchOptions: { runner } });
  assert.equal(developmentToken, capability);
  t.after(async () => {
    server.closeAllConnections();
    if (server.listening) await new Promise(resolve => server.close(resolve));
    await rm(area, { recursive: true, force: true });
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const origin = `http://127.0.0.1:${server.address().port}`;
  const headers = { Authorization: 'Bearer dev-test-secret', 'Content-Type': 'application/json' };
  const post = (route, body, auth = headers) => fetch(origin + route, { method: 'POST', headers: auth, body: JSON.stringify(body) });
  const rpc = async (method, params, agent = 'claude') =>
    (await post(`/mcp/dev/${capability}/${agent}`, { jsonrpc: '2.0', id: 1, method, params })).json();
  const tool = async (name, args = {}, agent) => {
    const answer = await rpc('tools/call', { name, arguments: args }, agent);
    assert.ok(answer.result, JSON.stringify(answer.error));
    return { ...JSON.parse(answer.result.content[0].text), isError: answer.result.isError };
  };
  async function until(status) {
    for (let attempt = 0; attempt < 100; attempt++) {
      const { draft } = await tool('draft_status');
      if (draft?.status === status) return draft;
      await sleep(20);
    }
    assert.fail('Draft did not reach ' + status);
  }

  // Both credentials are required, and the endpoint only speaks MCP over POST.
  assert.equal((await post(`/mcp/dev/${capability}`, {}, { 'Content-Type': 'application/json' })).status, 401);
  assert.equal((await post(`/mcp/dev/${'e'.repeat(64)}/claude`, { jsonrpc: '2.0', id: 1, method: 'ping' })).status, 403);
  assert.equal((await fetch(`${origin}/mcp/dev/${capability}`, { headers })).status, 405);
  assert.equal((await post(`/mcp/dev/${capability}/Bad%20Name`, { jsonrpc: '2.0', id: 1, method: 'ping' })).status, 404);
  assert.equal((await post(`/mcp/dev/${capability}`, { jsonrpc: '2.0', method: 'notifications/initialized' })).status, 202);
  assert.equal((await rpc('initialize')).result.serverInfo.name, 'euclid-workbench');

  // No tool can commit, preview, revert or run arbitrary workbench actions.
  const listed = (await rpc('tools/list')).result.tools.map(item => item.name);
  assert.deepEqual(listed, ['list_source', 'read_source', 'draft_status', 'task_history', 'submit_draft', 'run_checks', 'rebase_draft', 'discard_draft']);
  assert.deepEqual(listed, developmentTools.map(item => item.name));
  for (const name of ['apply', 'play', 'live', 'restore', 'stage']) {
    assert.equal((await rpc('tools/call', { name, arguments: {} })).error.code, -32602);
  }
  assert.equal((await rpc('tools/call', { name: 'read_source', arguments: { path: script, extra: true } })).error.code, -32602);
  assert.equal((await rpc('tools/call', { name: 'run_checks', arguments: { version: 'latest' } })).error.code, -32602);

  assert.deepEqual((await tool('list_source')).files, ['README.md', 'docs/architecture.md', 'package.json', obsolete, script].sort());
  assert.equal((await tool('read_source', { path: script })).content, 'extends Node\nconst READY := false\n');
  assert.equal((await tool('read_source', { path: 'README.md' })).content, '# Fixture\n');
  assert.equal((await tool('read_source', { path: 'package.json' })).content, '{}\n');
  for (const name of ['world/project.godot', '.git/config', '.local/gateway.json', '../project/README.md', 'world/scripts/../../package.json']) {
    assert.equal((await tool('read_source', { path: name })).isError, true, name);
  }
  assert.deepEqual(await tool('draft_status'), { ok: true, draft: null, busy: '', other_drafts: [], isError: false });

  // Submissions are validated before and after they are written.
  const rejected = async (args, pattern) => {
    const answer = await tool('submit_draft', { request: 'Try an invalid draft', ...args });
    assert.equal(answer.isError, true);
    assert.match(answer.message, pattern);
    assert.equal((await tool('draft_status')).draft, null);
  };
  await rejected({ files: [{ path: 'gateway/workbench-git.mjs', content: 'x' }] }, /cannot change gateway\/workbench-git\.mjs/);
  await rejected({ files: [{ path: 'scripts/start.ps1', content: 'x' }] }, /cannot change scripts\/start\.ps1/);
  await rejected({ delete: ['package.json'] }, /cannot change package\.json/);
  await rejected({ files: [{ path: 'world/project.godot', content: 'x' }] }, /cannot change world\/project\.godot/);
  await rejected({ files: [{ path: script, content: 'a' }, { path: script, content: 'b' }] }, /more than once/);
  await rejected({}, /Submit 1 to 24 files/);
  await rejected({ delete: ['world/scripts/missing.gd'] }, /does not exist in the draft/);
  await rejected({ files: [{ path: script, content: 'extends Node\nconst READY := false\n' }] }, /without a source change/);
  await rejected({ files: [{ path: script, content: 'x' }], version: 'f'.repeat(64) }, /no active draft to revise/);
  assert.equal((await tool('run_checks', { version: 'f'.repeat(64) })).isError, true);

  const first = await tool('submit_draft', { request: 'Mark the example ready', summary: 'Adds   a test and\nremoves the old script.',
    files: [{ path: script, content: 'extends Node\nconst READY := maybe\n' }, { path: added, content: 'extends SceneTree\n' }], delete: [obsolete] });
  assert.equal(first.isError, false, first.message);
  assert.deepEqual(first.draft.files, [added, script, obsolete]);
  assert.deepEqual([first.draft.status, first.draft.owner, first.draft.yours], ['staged', 'claude', true]);
  assert.equal(first.draft.summary, 'Adds a test and removes the old script.');
  assert.equal(first.draft.diff, undefined);
  const staged = (await tool('draft_status')).draft;
  assert.match(staged.diff, /\+const READY := maybe/);
  assert.equal(git('rev-parse', 'HEAD'), base);
  assert.equal(git('status', '--porcelain'), '');
  assert.equal((await tool('read_source', { path: script })).content, 'extends Node\nconst READY := maybe\n');
  assert.equal((await tool('read_source', { path: obsolete })).isError, true);

  // Another agent sees claude's draft only as a neighbour and cannot check, revise or discard it.
  const seen = await tool('draft_status', {}, 'codex');
  assert.equal(seen.draft, null);
  assert.deepEqual(seen.other_drafts.map(item => [item.owner, item.status, item.files]), [['claude', 'staged', [added, script, obsolete]]]);
  for (const [name, args] of [['run_checks', { version: staged.version }], ['discard_draft', { version: staged.version }],
    ['rebase_draft', { version: staged.version }],
    ['submit_draft', { request: 'Take over', version: staged.version, files: [{ path: script, content: 'x' }] }]]) {
    const answer = await tool(name, args, 'codex');
    assert.equal(answer.isError, true, name);
    assert.match(answer.message, /belongs to claude/, name);
  }
  // It can hold a draft of its own at the same time. Each agent reads and sees its own.
  const parallel = await tool('submit_draft', { request: 'Second draft', files: [{ path: obsolete, content: 'extends Node\n# codex\n' }] }, 'codex');
  assert.equal(parallel.isError, false, parallel.message);
  assert.deepEqual([parallel.draft.owner, parallel.draft.files], ['codex', [obsolete]]);
  assert.equal((await tool('draft_status')).draft.version, staged.version);
  assert.deepEqual((await tool('draft_status')).other_drafts.map(item => item.owner), ['codex']);
  assert.equal((await tool('read_source', { path: obsolete }, 'codex')).content, 'extends Node\n# codex\n');
  assert.equal((await tool('read_source', { path: obsolete })).isError, true, 'claude’s draft deletes this file');
  assert.match((await tool('submit_draft', { request: 'Third', files: [{ path: script, content: 'x' }] }, 'codex')).message, /current version to revise/);
  assert.equal((await tool('discard_draft', { version: parallel.draft.version }, 'codex')).isError, false);
  assert.equal(checks, 0);

  // The owner runs checks, reads the failure, and revises on top of the draft.
  assert.match((await tool('run_checks', { version: 'f'.repeat(64) })).message, /current version/);
  const started = await tool('run_checks', { version: staged.version });
  assert.equal(started.isError, false, started.message);
  assert.equal(started.draft.version, staged.version);
  const failed = await until('failed');
  assert.equal(failed.error, 'READY must be true.');
  assert.match(failed.output, /Checked \d+ characters/);
  assert.match((await tool('submit_draft', { request: 'Fix it', files: [{ path: script, content: 'x' }] })).message, /current version to revise/);
  const second = await tool('submit_draft', { request: 'Fix the failing check', version: failed.version,
    files: [{ path: script, content: 'extends Node\nconst READY := true\n' }] });
  assert.equal(second.isError, false, second.message);
  assert.notEqual(second.draft.version, failed.version);
  assert.deepEqual([second.draft.id, second.draft.status, second.draft.owner], [failed.id, 'staged', 'claude']);
  assert.deepEqual(second.draft.files, [added, script, obsolete]);
  assert.match((await tool('run_checks', { version: failed.version })).message, /current version/);
  await tool('run_checks', { version: second.draft.version });
  const passed = await until('passed');
  assert.equal(checks, 2);
  assert.equal(passed.check_status, 'passed');
  assert.equal(passed.check_scope, 'full');
  assert.deepEqual([passed.base, passed.behind_main], [base, false]);
  assert.match((await tool('rebase_draft', { version: passed.version })).message, /already based on the tip/);
  assert.match(passed.diff, /\+const READY := true/);

  // Passing checks do not install anything. The commit stays in the Workbench.
  assert.equal(git('rev-parse', 'HEAD'), base);
  assert.match(await readFile(path.join(root, script), 'utf8'), /READY := false/);

  // Someone else commits to main. The agent sees it and replays its draft onto the new tip.
  await writeFile(path.join(root, 'world/scripts/unrelated.gd'), 'extends Node\n');
  git('add', '.');
  git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'Unrelated');
  const moved = git('rev-parse', 'HEAD');
  assert.equal((await tool('draft_status')).draft.behind_main, true);
  assert.match((await tool('rebase_draft', { version: passed.version }, 'codex')).message, /belongs to claude/);
  const rebased = await tool('rebase_draft', { version: passed.version });
  assert.equal(rebased.isError, false, rebased.message);
  const after = (await tool('draft_status')).draft;
  assert.deepEqual([after.base, after.behind_main, after.status, after.check_status], [moved, false, 'staged', '']);
  const discarded = await tool('discard_draft', { version: after.version });
  assert.deepEqual([discarded.isError, discarded.draft], [false, null]);
  assert.equal(git('worktree', 'list').split('\n').length, 1);

  // The journal keeps the draft's story after the draft is gone.
  const history = await tool('task_history', { draft: passed.id });
  assert.equal(history.isError, false);
  assert.deepEqual(history.entries.map(item => [item.event, item.status ?? '', item.owner]).reverse(), [
    ['drafted', '', 'claude'], ['checked', 'failed', 'claude'], ['revised', '', 'claude'], ['checked', 'passed', 'claude'], ['rebased', '', 'claude'], ['discarded', '', 'claude']]);
  assert.equal(history.entries[2].scope, 'full');
  assert.match(history.entries[4].error, /READY must be true/);
  assert.deepEqual(history.entries[0].files, [added, script, obsolete]);
  assert.equal(history.entries[1].commit, moved);
  assert.equal((await rpc('tools/call', { name: 'task_history', arguments: { draft: 'not-an-id' } })).error.code, -32602);
});

test('a submitted draft keeps its owner across a gateway restart', async t => {
  const { createWorkbench } = await import('./workbench.mjs');
  const area = await mkdtemp(path.join(os.tmpdir(), 'euclid-owner-test-'));
  t.after(() => rm(area, { recursive: true, force: true }));
  const root = path.join(area, 'project');
  const script = 'world/scripts/example.gd';
  await mkdir(path.join(root, 'world/scripts'), { recursive: true });
  await writeFile(path.join(root, script), 'extends Node\n');
  const git = (...args) => execFileSync('git', args, { cwd: root, windowsHide: true, encoding: 'utf8' }).trim();
  git('init', '-q');
  git('config', 'core.autocrlf', 'false');
  git('add', '.');
  git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'Fixture');
  const options = { runner: { async check() {}, playing: () => false, async stop() {} } };
  const connect = () => createWorkbench(root, path.join(area, 'workbench'), options);
  const call = (workbench, action, body = {}) => workbench(action, body, new AbortController().signal);
  async function staged(workbench) {
    for (let attempt = 0; attempt < 100; attempt++) {
      const { draft } = await call(workbench, 'state');
      if (draft?.status === 'staged') return draft;
      await sleep(20);
    }
    assert.fail('The submission was not staged.');
  }
  const first = connect();
  await call(first, 'submit', { owner: 'grok', prompt: 'Add a comment', files: [{ path: script, content: 'extends Node\n# Note\n' }] });
  const draft = await staged(first);
  assert.deepEqual([draft.owner, draft.agent_source, draft.from_world, draft.can_revise], ['grok', true, true, true]);
  const recovered = await staged(connect());
  assert.deepEqual([recovered.id, recovered.version, recovered.owner], [draft.id, draft.version, 'grok']);
  // Only the owner revises its draft, and the revision keeps the owner.
  await assert.rejects(call(first, 'submit', { owner: 'Not A Name', id: draft.id, version: draft.version, prompt: 'Revise',
    files: [{ path: script, content: 'extends Node\n# Revised\n' }] }), /only revise its own draft/);
  await call(first, 'submit', { owner: 'grok', id: draft.id, version: draft.version, prompt: 'Revise',
    files: [{ path: script, content: 'extends Node\n# Revised\n' }] });
  const revised = await staged(first);
  assert.deepEqual([revised.owner, revised.id], ['grok', draft.id]);
  assert.notEqual(revised.version, draft.version);
});
