import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdir, mkdtemp, readFile, rm, stat, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { setTimeout as sleep } from 'node:timers/promises';
import { createAgentCredentials } from './agent-credentials.mjs';
import { createGateway } from './server.mjs';

test('credentials are stored as hashes, identify one agent, rotate and revoke', async t => {
  const area = await mkdtemp(path.join(os.tmpdir(), 'euclid-agent-credentials-'));
  t.after(() => rm(area, { recursive: true, force: true }));
  const file = path.join(area, 'agents.json');
  const store = await createAgentCredentials(file);
  const grok = await store.issue('grok');
  const claude = await store.issue('claude');
  assert.match(grok.token, /^eua_[a-f0-9]{64}$/);
  assert.equal(store.identify(grok.token), 'grok');
  assert.equal(store.identify(claude.token), 'claude');
  for (const wrong of [undefined, '', 'eua_' + '0'.repeat(64), grok.token + 'x', grok.token.toUpperCase(), ['x']]) assert.equal(store.identify(wrong), null);
  const saved = await readFile(file, 'utf8');
  assert.equal(saved.includes(grok.token), false, 'the token itself is never written');
  if (process.platform !== 'win32') assert.equal((await stat(file)).mode & 0o077, 0);
  await assert.rejects(store.issue('Not A Name'), /lowercase letters/);
  await assert.rejects(store.issue('../x'), /lowercase letters/);

  const reopened = await createAgentCredentials(file);
  assert.equal(reopened.identify(grok.token), 'grok');
  const rotated = await reopened.issue('grok');
  assert.equal(reopened.identify(grok.token), null);
  assert.equal(reopened.identify(rotated.token), 'grok');
  assert.deepEqual(reopened.list().map(item => item.name), ['claude', 'grok']);
  assert.equal(await reopened.revoke('grok'), true);
  assert.equal(await reopened.revoke('grok'), false);
  assert.equal(reopened.identify(rotated.token), null);
  assert.equal(reopened.reserved('grok'), false);
  assert.equal(reopened.reserved('claude'), true);
});

test('each agent connects with its own credential and cannot act on another agent’s draft', async t => {
  const area = await mkdtemp(path.join(os.tmpdir(), 'euclid-agent-route-'));
  const root = path.join(area, 'project');
  const script = 'world/scripts/example.gd';
  await mkdir(path.join(root, 'world/scripts'), { recursive: true });
  await writeFile(path.join(root, script), 'extends Node\n');
  const git = (...args) => execFileSync('git', args, { cwd: root, windowsHide: true, encoding: 'utf8' }).trim();
  git('init', '-q');
  for (const [key, value] of [['core.autocrlf', 'false'], ['user.name', 'Fixture'], ['user.email', 'fixture@example.invalid']]) git('config', key, value);
  git('add', '.');
  git('commit', '-qm', 'Fixture');

  const capability = 'd'.repeat(64);
  const workbenchSecret = 'w'.repeat(64);
  const runner = { async check() { return { scope: 'full' }; }, playing: () => false, async stop() {} };
  const servers = [];
  async function open() {
    const { server } = await createGateway({ dataDir: path.join(area, 'data'), token: 'agent-test-secret', developmentToken: capability,
      workbenchToken: workbenchSecret, workbenchRoot: root, workbenchOptions: { runner } });
    servers.push(server);
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    return `http://127.0.0.1:${server.address().port}`;
  }
  t.after(async () => {
    for (const server of servers) {
      server.closeAllConnections();
      if (server.listening) await new Promise(resolve => server.close(resolve));
    }
    await rm(area, { recursive: true, force: true });
  });
  let origin = await open();
  const headers = { Authorization: 'Bearer agent-test-secret', 'Content-Type': 'application/json' };
  const post = (route, body, extra = {}) => fetch(origin + route, { method: 'POST', headers: { ...headers, ...extra }, body: JSON.stringify(body) });
  const manage = async (action, body = {}, secret = workbenchSecret) => {
    const response = await post(`/v1/agents/${action}`, body, { 'X-Euclid-Workbench': secret });
    return { status: response.status, body: await response.json() };
  };
  const call = async (agent, name, args = {}) => {
    const response = await post('/mcp/agent', { jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name, arguments: args } },
      { 'X-Euclid-Agent': agent });
    if (response.status !== 200) return { status: response.status, ...(await response.json()) };
    const answer = await response.json();
    return { ...JSON.parse(answer.result.content[0].text), isError: answer.result.isError };
  };
  const shared = async (name, tool, args = {}) => (await post(`/mcp/dev/${capability}/${name}`,
    { jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name: tool, arguments: args } })).status;

  // Only the Workbench capability issues credentials.
  assert.equal((await manage('issue', { name: 'grok' }, 'x'.repeat(64))).status, 403);
  assert.equal((await post('/v1/agents/issue', { name: 'grok' })).status, 403);
  assert.equal((await manage('issue', { name: 'Bad Name' })).status, 400);
  const grok = (await manage('issue', { name: 'grok' })).body.token;
  const claude = (await manage('issue', { name: 'claude' })).body.token;
  assert.deepEqual((await manage('list')).body.agents.map(item => item.name), ['claude', 'grok']);

  assert.equal((await call('eua_' + 'f'.repeat(64), 'draft_status')).status, 403);
  assert.equal((await post('/mcp/agent', {}, { Authorization: 'Bearer wrong', 'X-Euclid-Agent': grok })).status, 401);
  // A reserved name cannot be borrowed through the shared route. Unreserved names still work there.
  assert.equal(await shared('grok', 'draft_status'), 403);
  assert.equal(await shared('codex', 'draft_status'), 200);

  const submitted = await call(grok, 'submit_draft', { request: 'Add a note', files: [{ path: script, content: 'extends Node\n# Note\n' }] });
  assert.equal(submitted.isError, false, submitted.message);
  let draft;
  for (let attempt = 0; attempt < 100 && draft?.status !== 'staged'; attempt++) {
    draft = (await call(grok, 'draft_status')).draft;
    if (draft?.status !== 'staged') await sleep(20);
  }
  assert.deepEqual([draft.owner, draft.yours], ['grok', true]);
  const other = await call(claude, 'discard_draft', { version: draft.version });
  assert.equal(other.isError, true);
  assert.match(other.message, /belongs to grok/);

  // Credentials survive a gateway restart. A revoked credential stops working at once.
  servers[0].closeAllConnections();
  await new Promise(resolve => servers[0].close(resolve));
  origin = await open();
  assert.equal((await call(grok, 'draft_status')).draft.yours, true);
  assert.equal((await manage('revoke', { name: 'grok' })).body.revoked, true);
  assert.equal((await call(grok, 'draft_status')).status, 403);
  assert.equal(await shared('grok', 'draft_status'), 200, 'a revoked name is a plain label again');
});
