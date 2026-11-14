import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { test } from 'node:test';
import { createTaskBoard } from './agent-tasks.mjs';
import { createGateway } from './server.mjs';

async function temporary(t) {
  const dir = await mkdtemp(path.join(os.tmpdir(), 'euclid-tasks-'));
  t.after(() => rm(dir, { recursive: true, force: true }));
  return dir;
}

test('tasks have a single claimant, private replies, and a durable journal', async t => {
  const file = path.join(await temporary(t), 'tasks.json');
  const board = await createTaskBoard(file);
  const { task } = await board.player('assign', { to: '*', text: 'Count the props.' });
  const [a, b] = await Promise.all(['muse', 'codex'].map(name => board.agent(name, 'claim_task', {})));
  const winner = a.task ?? b.task;
  assert.equal(winner.id, task.id);
  assert.equal(Boolean(a.task) !== Boolean(b.task), true);
  const other = winner.owner === 'muse' ? 'codex' : 'muse';
  await assert.rejects(board.agent(other, 'task_progress', { id: task.id, text: 'Spoof' }), /you own/);
  await board.agent(winner.owner, 'task_progress', { id: task.id, text: 'Counting' });
  await board.activity(other, task.id, 'tool', 'Discard this');
  await board.activity(winner.owner, task.id, 'tool', 'Running · list entities');
  assert.equal((await board.player('inbox', {})).tasks[0].activity[0].text, 'Running · list entities');
  assert.equal((await board.agent(winner.owner, 'inbox', {})).tasks[0].activity, undefined);
  await board.agent(winner.owner, 'send_message', { to: 'you', text: 'Three props.' });
  assert.deepEqual((await board.agent(other, 'inbox', {})).messages, []);
  await board.agent(winner.owner, 'finish_task', { id: task.id, text: 'Found three.', status: 'completed' });
  await board.activity(winner.owner, task.id, 'tool', 'Discard late activity');
  const restored = await createTaskBoard(file);
  const [finished] = (await restored.player('inbox', {})).tasks;
  assert.equal(finished.status, 'completed');
  assert.deepEqual(finished.activity.map(item => item.text), ['Running · list entities']);
  assert.equal((await restored.player('inbox', {})).messages[0].text, 'Three props.');
  assert.deepEqual((await restored.player('task_log', {})).entries.map(item => item.event),
    ['finish_task', 'message', 'task_progress', 'claim_task', 'assign']);
});

test('player task and screenshot routes are protected and images go only to the named agent', async t => {
  const dataDir = await temporary(t);
  const gateway = await createGateway({ dataDir, token: 'task-test', workbenchToken: 'person-test' });
  await new Promise(resolve => gateway.server.listen(0, '127.0.0.1', resolve));
  t.after(async () => {
    gateway.server.closeAllConnections();
    await new Promise(resolve => gateway.server.close(resolve));
  });
  const base = `http://127.0.0.1:${gateway.server.address().port}`;
  const post = (url, body, person = false) => fetch(base + url, { method: 'POST', body: JSON.stringify(body),
    headers: { Authorization: 'Bearer task-test', 'Content-Type': 'application/json', ...(person && { 'X-Euclid-Workbench': 'person-test' }) } });
  const keys = new Map();
  for (const name of ['muse', 'other']) {
    keys.set(name, (await (await post('/v1/agents/issue', { name }, true)).json()).token);
  }
  const call = async (agent, name, args = {}) => {
    const response = await fetch(base + '/mcp/agent', { method: 'POST',
      headers: { Authorization: 'Bearer task-test', 'Content-Type': 'application/json', 'X-Euclid-Agent': keys.get(agent) },
      body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name, arguments: args } }) });
    return (await response.json()).result;
  };
  const task = { to: 'muse', text: 'Inspect the Grid.', session: '1'.repeat(32) };
  assert.equal((await post('/v1/tasks/assign', task)).status, 403);
  const shared = await post(`/mcp/dev/${gateway.developmentToken}/unreserved`, { jsonrpc: '2.0', id: 1, method: 'tools/list' });
  assert.equal((await shared.json()).result.tools.some(tool => tool.name === 'inbox'), false);
  assert.equal((await post('/v1/tasks/assign', task, true)).status, 200);
  assert.equal(JSON.parse((await call('other', 'claim_task')).content[0].text).task, null);
  const claimed = JSON.parse((await call('muse', 'claim_task')).content[0].text).task;
  assert.equal(claimed.text, task.text);
  assert.equal(claimed.session, undefined);
  await post('/v1/tasks/send_message', { to: 'other', text: 'A separate conversation.' }, true);
  await call('muse', 'send_message', { to: 'you', text: 'Muse replied.' });
  const inbox = await post('/v1/tasks/inbox', { peers: ['muse', 'other'] }, true);
  const { conversations } = await inbox.json();
  assert.deepEqual(conversations.muse.messages.map(message => message.text), ['Muse replied.']);
  assert.deepEqual(conversations.other.messages.map(message => message.text), ['A separate conversation.']);
  assert.deepEqual(conversations.other.tasks, []);
  const image = Buffer.from([0xff, 0xd8, 0xff, 0xd9]).toString('base64');
  assert.equal((await post('/v1/tasks/share_view', { to: 'muse', image }, true)).status, 200);
  assert.equal((await call('other', 'look_at_world')).isError, true);
  assert.deepEqual((await call('muse', 'look_at_world')).content[1], { type: 'image', mimeType: 'image/jpeg', data: image });
});
