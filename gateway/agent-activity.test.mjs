import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { createActivityFeed, createStreamTracker, createToolObserver, diffLines, isHiddenPath, redact, replyFromBoard } from './agent-activity.mjs';

test('activity redacts token-like strings and hides secret files', () => {
  assert.equal(redact('key = sk-abcdefghijklmnopqrstuvwx'), 'key = [redacted]');
  assert.equal(redact('const token = "abc123def456"'), 'const token = "[redacted]"');
  assert.match(redact('ghp_' + 'a'.repeat(30)), /\[redacted\]/);
  assert.equal(redact('let total = sum(values)'), 'let total = sum(values)');
  for (const name of ['.env', 'config/.env.local', 'keys/server.pem', '.local/sketchfab-key.txt', 'docs/secrets.md'])
    assert.equal(isHiddenPath(name), true, name);
  assert.equal(isHiddenPath('world/scripts/world.gd'), false);
  const feed = createActivityFeed();
  const event = feed.record('local-claude', { kind: 'read', path: '.env', title: 'Reading .env', lines: [{ n: 1, text: 'A=1' }] });
  assert.equal(event.hidden, true);
  assert.equal(event.lines, undefined);
});

test('activity diffs lines into hunks numbered in the new file', () => {
  const before = ['one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten'].join('\n');
  const after = ['one', 'two', 'THREE', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten', 'eleven'].join('\n');
  const hunks = diffLines(before, after);
  assert.equal(hunks.length, 2);
  assert.deepEqual(hunks[0].lines.filter(line => line.t !== ' ').map(line => `${line.t}${line.n}:${line.text}`), ['-3:three', '+3:THREE']);
  assert.deepEqual(hunks[1].lines.filter(line => line.t === '+').map(line => line.n), [11]);
  assert.equal(diffLines('', 'a\nb')[0].lines.every(line => line.t === '+'), true);
});

test('the activity feed is bounded, ordered, and long-polls', async () => {
  const feed = createActivityFeed({ limit: 3 });
  for (let index = 0; index < 5; index++) feed.record('local-codex', { kind: 'think', title: `step ${index}` });
  const { events, next } = feed.since(0);
  assert.deepEqual(events.map(event => event.seq), [3, 4, 5]);
  assert.equal(next, 5);
  assert.equal(feed.record('bad name!', { kind: 'think' }), null);
  assert.equal(feed.record('local-codex', { kind: 'unknown' }), null);
  const waiting = feed.wait(5, { timeout: 2000 });
  setTimeout(() => feed.record('local-codex', { kind: 'say', title: 'done', text: 'Finished.' }), 20);
  const woke = await waiting;
  assert.equal(woke.events[0].kind, 'say');
  assert.equal((await feed.wait(99, { timeout: 10 })).reset, true);
});

test('MCP tool calls become read, edit and tool events', async () => {
  const feed = createActivityFeed();
  const observer = createToolObserver(feed, { readDraftFile: async () => 'a\nb\nc' });
  observer.after('scout', 'read_source', { path: 'world/a.gd' }, { ok: true, content: 'extends Node\nfunc go():\n\tpass' });
  observer.after('scout', 'search_source', { query: 'func go' }, { ok: true, matches: [{ path: 'world/a.gd', line: 2, text: 'func go():' }] });
  const context = await observer.before('scout', 'submit_draft', { files: [{ path: 'world/a.gd', content: 'a\nB\nc' }] });
  observer.after('scout', 'submit_draft', { request: 'x', files: [{ path: 'world/a.gd', content: 'a\nB\nc' }] }, { ok: true }, context);
  const patchContext = await observer.before('scout', 'patch_draft', { edits: [{ path: 'world/a.gd', old_text: 'b', new_text: '$$&' }], create: [{ path: 'world/new.gd', content: 'x\n' }] });
  observer.after('scout', 'patch_draft', { request: 'y', edits: [{ path: 'world/a.gd', old_text: 'b', new_text: '$$&' }], create: [{ path: 'world/new.gd', content: 'x\n' }], delete: ['world/old.gd'] }, { ok: true }, patchContext);
  observer.after('scout', 'add_piece', { target: 'house' }, { ok: true });
  const [read, search, edit, patched, created, deleted, tool] = feed.since(0).events;
  assert.equal(read.kind, 'read');
  assert.deepEqual(read.lines.map(line => line.n), [1, 2, 3]);
  assert.equal(search.kind, 'search');
  assert.deepEqual(search.results, ['world/a.gd:2 func go():']);
  assert.equal(edit.kind, 'edit');
  assert.equal(edit.added, 1);
  assert.equal(edit.removed, 1);
  assert.equal(patched.kind, 'edit');
  assert.deepEqual(patched.hunks[0].lines.filter(line => line.t !== ' ').map(line => line.t + line.text), ['-b', '+$$&']);
  assert.equal(created.kind, 'write');
  assert.equal(deleted.kind, 'delete');
  assert.equal(tool.title, 'add piece · house');
});

test('a Claude Code stream shows reads with their lines and edits as diffs', async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), 'activity-'));
  const workspace = path.join(root, 'work');
  const original = path.join(root, 'base');
  await mkdir(path.join(workspace, 'world'), { recursive: true });
  await mkdir(path.join(original, 'world'), { recursive: true });
  await writeFile(path.join(original, 'world', 'a.gd'), 'var x = 1\nvar y = 2\n');
  await writeFile(path.join(workspace, 'world', 'a.gd'), 'var x = 1\nvar y = 3\n');
  try {
    const feed = createActivityFeed();
    const tracker = createStreamTracker(feed, { actor: 'local-claude', provider: 'claude', workspace, original });
    const file = path.join(workspace, 'world', 'a.gd');
    tracker.handle({ type: 'assistant', message: { content: [{ type: 'thinking', thinking: 'Look at a.gd first.' },
      { type: 'tool_use', id: 'r1', name: 'Read', input: { file_path: file } }] } });
    tracker.handle({ type: 'user', message: { content: [{ type: 'tool_result', tool_use_id: 'r1', content: '     1→var x = 1\n     2→var y = 2' }] } });
    tracker.handle({ type: 'assistant', message: { content: [{ type: 'tool_use', id: 'e1', name: 'Edit', input: { file_path: file, old_string: 'y = 2', new_string: 'y = 3' } }] } });
    tracker.handle({ type: 'user', message: { content: [{ type: 'tool_result', tool_use_id: 'e1', content: 'ok' }] } });
    tracker.handle({ type: 'assistant', message: { content: [{ type: 'tool_use', id: 'm1', name: 'mcp__euclid__inbox', input: {} }] } });
    tracker.handle({ type: 'user', message: { content: [{ type: 'tool_result', tool_use_id: 'm1', content: '{}' }] } });
    await tracker.settled();
    const events = feed.since(0).events;
    assert.deepEqual(events.map(event => event.kind), ['think', 'read', 'edit']);
    assert.equal(events[1].path, 'world/a.gd');
    assert.deepEqual(events[1].lines.map(line => line.text), ['var x = 1', 'var y = 2']);
    assert.deepEqual(events[2].hunks[0].lines.filter(line => line.t !== ' ').map(line => line.t + line.text), ['-var y = 2', '+var y = 3']);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('a Codex stream shows shell reads, searches and file changes', async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), 'activity-'));
  await mkdir(path.join(root, 'docs'), { recursive: true });
  await writeFile(path.join(root, 'docs', 'b.md'), '# New\n');
  try {
    const feed = createActivityFeed();
    const tracker = createStreamTracker(feed, { actor: 'local-codex', provider: 'codex', workspace: root });
    tracker.handle({ type: 'item.completed', item: { type: 'command_execution', command: "bash -lc 'sed -n 10,12p docs/a.md'",
      aggregated_output: 'ten\neleven\ntwelve\n', exit_code: 0 } });
    tracker.handle({ type: 'item.completed', item: { type: 'command_execution', command: "bash -lc 'rg -n preview world'",
      aggregated_output: 'world/x.gd:3:preview\n', exit_code: 0 } });
    tracker.handle({ type: 'item.completed', item: { type: 'file_change', changes: [{ path: 'docs/b.md', kind: 'add' }] } });
    tracker.handle({ type: 'item.completed', item: { type: 'agent_message', text: 'Added the page.' } });
    await tracker.settled();
    const events = feed.since(0).events;
    assert.deepEqual(events.map(event => event.kind), ['read', 'search', 'write', 'say']);
    assert.deepEqual(events[0].lines.map(line => line.n), [10, 11, 12, 13]);
    assert.equal(events[2].added, 2);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('Gemini and Antigravity streams show reads, edits, searches, commands and coalesced says', async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), 'activity-'));
  const workspace = path.join(root, 'work');
  const original = path.join(root, 'base');
  await mkdir(path.join(workspace, 'world'), { recursive: true });
  await mkdir(path.join(original, 'world'), { recursive: true });
  await writeFile(path.join(original, 'world', 'a.gd'), 'var x = 1\nvar y = 2\n');
  await writeFile(path.join(workspace, 'world', 'a.gd'), 'var x = 1\nvar y = 3\n');
  try {
    for (const [actor, provider] of [['local-gemini', 'gemini'], ['local-antigravity', 'antigravity']]) {
      const feed = createActivityFeed();
      const tracker = createStreamTracker(feed, { actor, provider, workspace, original });
      const file = path.join(workspace, 'world', 'a.gd');
      tracker.handle({ type: 'thought', thought: 'Inspect a.gd first.' });
      tracker.handle({ type: 'message', role: 'assistant', content: 'Reading ', delta: true });
      tracker.handle({ type: 'message', role: 'assistant', content: 'now.', delta: true });
      tracker.handle({ type: 'tool_use', tool_id: 'r1', tool_name: 'read_file', parameters: { file_path: file } });
      tracker.handle({ type: 'tool_result', tool_id: 'r1', status: 'success', output: 'var x = 1\nvar y = 2\n' });
      tracker.handle({ type: 'tool_use', tool_id: 's1', tool_name: 'grep_search', parameters: { query: 'var y' } });
      tracker.handle({ type: 'tool_result', tool_id: 's1', status: 'success', output: `${file}:2:var y = 2\n` });
      tracker.handle({ type: 'tool_use', tool_id: 'e1', tool_name: 'write_file', parameters: { file_path: file } });
      tracker.handle({ type: 'tool_result', tool_id: 'e1', status: 'success', output: 'ok' });
      tracker.handle({ type: 'tool_use', tool_id: 'c1', tool_name: 'run_shell_command', parameters: { command: 'node --version' } });
      tracker.handle({ type: 'tool_result', tool_id: 'c1', status: 'success', output: 'v22.0.0\n' });
      tracker.handle({ type: 'tool_use', tool_id: 'm1', tool_name: 'mcp__euclid__inbox', parameters: {} });
      tracker.handle({ type: 'tool_result', tool_id: 'm1', status: 'success', output: '{}' });
      tracker.handle({ type: 'message', role: 'assistant', content: 'All ', delta: true });
      tracker.handle({ type: 'message', role: 'assistant', content: 'done.', delta: true });
      tracker.handle({ type: 'result', status: 'success' });
      await tracker.settled();
      const events = feed.since(0).events;
      assert.deepEqual(events.map(event => event.kind), ['think', 'say', 'read', 'search', 'edit', 'run', 'say']);
      assert.equal(events[1].text, 'Reading now.');
      assert.equal(events[2].path, 'world/a.gd');
      assert.deepEqual(events[2].lines.map(line => line.text), ['var x = 1', 'var y = 2', '']);
      assert.deepEqual(events[3].results, ['world/a.gd:2:var y = 2']);
      assert.deepEqual(events[4].hunks[0].lines.filter(line => line.t !== ' ').map(line => line.t + line.text), ['-var y = 2', '+var y = 3']);
      assert.equal(events[5].command, 'node --version');
      assert.equal(events[6].text, 'All done.');
    }
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('replies to the player on the task board reach the activity feed', async () => {
  const { createTaskBoard } = await import('./agent-tasks.mjs');
  const { mkdtemp, rm } = await import('node:fs/promises');
  const { tmpdir } = await import('node:os');
  const { join } = await import('node:path');
  const dir = await mkdtemp(join(tmpdir(), 'euclid-replies-'));
  try {
    const feed = createActivityFeed();
    const board = await createTaskBoard(join(dir, 'tasks.json'), { onChange(event, actor, value) {
      const reply = replyFromBoard(event, value);
      if (reply) feed.record(reply.actor, reply);
    } });
    const { task } = await board.player('assign', { to: 'scout', text: 'Find the fountain.' });
    await board.agent('scout', 'claim_task', {});
    await board.agent('scout', 'task_progress', { id: task.id, text: 'Checking the courtyard.' });
    await board.agent('scout', 'send_message', { to: 'builder', text: 'Not for the player.' });
    await board.agent('scout', 'send_message', { to: 'you', text: 'It is by the pool.\n\nWant me to light it?' });
    await board.agent('scout', 'finish_task', { id: task.id, status: 'completed', text: 'Found it by the pool.' });
    await board.player('send_message', { to: 'scout', text: 'Thanks!' });
    const { events } = feed.since(0);
    assert.deepEqual(events.map(event => [event.actor, event.kind, event.title, event.text]), [
      ['scout', 'reply', 'Update', 'Checking the courtyard.'],
      ['scout', 'reply', 'Says', 'It is by the pool.\n\nWant me to light it?'],
      ['scout', 'reply', 'Done', 'Found it by the pool.'],
    ]);
    const long = 'word '.repeat(700);
    assert.equal(feed.record('scout', { kind: 'reply', text: long }).text.length, 3499);
    assert.ok(feed.record('scout', { kind: 'say', text: long }).text.length <= 600);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});
