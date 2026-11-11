import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { setTimeout as sleep } from 'node:timers/promises';
import { createRemoteServer } from './remote.mjs';
import { createGateway } from './server.mjs';

async function listen(server) {
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  return `http://127.0.0.1:${server.address().port}`;
}

test('remote agents reach only the development tools, with their own credential and no checks by default', async t => {
  const area = await mkdtemp(path.join(os.tmpdir(), 'euclid-remote-'));
  const root = path.join(area, 'project');
  const script = 'world/scripts/example.gd';
  await mkdir(path.join(root, 'world/scripts'), { recursive: true });
  await writeFile(path.join(root, script), 'extends Node\n');
  const git = (...args) => execFileSync('git', args, { cwd: root, windowsHide: true, encoding: 'utf8' }).trim();
  git('init', '-q');
  for (const [key, value] of [['core.autocrlf', 'false'], ['user.name', 'Fixture'], ['user.email', 'fixture@example.invalid']]) git('config', key, value);
  git('add', '.');
  git('commit', '-qm', 'Fixture');
  let checks = 0;
  const runner = { async check() { checks++; return { scope: 'full' }; }, playing: () => false, async stop() {} };
  const workbenchSecret = 'w'.repeat(64);
  const dataDir = path.join(area, 'data');
  const { server, remoteServer, remoteAudited } = await createGateway({ dataDir, token: 'remote-test-secret',
    workbenchToken: workbenchSecret, workbenchRoot: root, workbenchOptions: { runner } });
  t.after(async () => {
    for (const item of [server, remoteServer]) {
      item.closeAllConnections();
      if (item.listening) await new Promise(resolve => item.close(resolve));
    }
    await rm(area, { recursive: true, force: true });
  });
  const local = await listen(server);
  const outside = await listen(remoteServer);
  const issue = async body => {
    const response = await fetch(`${local}/v1/agents/issue`, { method: 'POST', body: JSON.stringify(body),
      headers: { Authorization: 'Bearer remote-test-secret', 'X-Euclid-Workbench': workbenchSecret, 'Content-Type': 'application/json' } });
    return { status: response.status, body: await response.json() };
  };
  const send = (body, headers = {}, method = 'POST', route = '/mcp') => fetch(outside + route,
    { method, headers: { 'Content-Type': 'application/json', ...headers }, body: method === 'POST' ? JSON.stringify(body) : undefined });
  const rpc = async (credential, method, params) => {
    const response = await send({ jsonrpc: '2.0', id: 1, method, params }, { Authorization: `Bearer ${credential}` });
    return response.status === 200 ? response.json() : { status: response.status };
  };
  const tool = async (credential, name, args = {}) => {
    const answer = await rpc(credential, 'tools/call', { name, arguments: args });
    return answer.result ? { ...JSON.parse(answer.result.content[0].text), isError: answer.result.isError } : answer;
  };

  assert.equal((await issue({ name: 'helper', checks: true })).status, 400, 'checks are only a remote permission');
  const localOnly = (await issue({ name: 'helper' })).body.token;
  const cloud = (await issue({ name: 'cloud', remote: true })).body;
  const trusted = (await issue({ name: 'trusted', remote: true, checks: true })).body;
  assert.deepEqual([cloud.remote, cloud.checks, trusted.checks], [true, false, true]);

  // Only the MCP route exists, only for remote credentials, and never from a browser.
  assert.equal((await send({}, {}, 'GET')).status, 405);
  assert.equal((await send({}, { Authorization: `Bearer ${cloud.token}` }, 'POST', '/v1/workbench/state')).status, 404);
  assert.equal((await send({}, { Authorization: `Bearer ${cloud.token}`, Origin: 'https://example.com' })).status, 403);
  assert.equal((await rpc('eua_' + 'a'.repeat(64), 'tools/list')).status, 401);
  assert.equal((await rpc(localOnly, 'tools/list')).status, 401, 'a local credential does not work from outside');
  assert.equal((await rpc('remote-test-secret', 'tools/list')).status, 401, 'the gateway credential does not work from outside');

  const offered = (await rpc(cloud.token, 'tools/list')).result.tools.map(item => item.name);
  assert.equal(offered.includes('run_checks'), false);
  assert.ok(offered.includes('submit_draft') && offered.includes('read_source'));
  assert.ok((await rpc(trusted.token, 'tools/list')).result.tools.some(item => item.name === 'run_checks'));

  const submitted = await tool(cloud.token, 'submit_draft', { request: 'Add a note', files: [{ path: script, content: 'extends Node\n# cloud\n' }] });
  assert.equal(submitted.isError, false, submitted.message);
  let draft;
  for (let attempt = 0; attempt < 100 && draft?.status !== 'staged'; attempt++) {
    draft = (await tool(cloud.token, 'draft_status')).draft;
    if (draft?.status !== 'staged') await sleep(20);
  }
  assert.equal(draft.owner, 'cloud');
  const refused = await rpc(cloud.token, 'tools/call', { name: 'run_checks', arguments: { version: draft.version } });
  assert.equal(refused.error.code, -32602);
  assert.equal(checks, 0);

  // A revoked credential stops working at once. Every call is audited without its arguments.
  await fetch(`${local}/v1/agents/revoke`, { method: 'POST', body: JSON.stringify({ name: 'cloud' }),
    headers: { Authorization: 'Bearer remote-test-secret', 'X-Euclid-Workbench': workbenchSecret, 'Content-Type': 'application/json' } });
  assert.equal((await rpc(cloud.token, 'tools/list')).status, 401);
  await remoteAudited();
  const audit = (await readFile(path.join(dataDir, 'remote-audit.jsonl'), 'utf8')).trim().split('\n').map(line => JSON.parse(line));
  assert.ok(audit.some(entry => entry.agent === 'cloud' && entry.tool === 'submit_draft' && entry.status === 200));
  assert.ok(audit.some(entry => entry.agent === 'cloud' && entry.tool === 'run_checks' && entry.error === -32602));
  assert.ok(audit.filter(entry => entry.status === 401).length >= 4);
  assert.equal(JSON.stringify(audit).includes('# cloud'), false, 'file contents never reach the audit log');
  assert.equal(JSON.stringify(audit).includes(cloud.token), false);
});

test('each remote agent has its own request budget', async t => {
  const area = await mkdtemp(path.join(os.tmpdir(), 'euclid-remote-budget-'));
  const tokens = { a: 'eua_' + 'a'.repeat(64), b: 'eua_' + 'b'.repeat(64) };
  const credentials = {
    identify: token => Object.keys(tokens).find(name => tokens[name] === token) ?? null,
    permissions: () => ({ remote: true, checks: false }),
  };
  const development = { async rpc(agent, message) { return { jsonrpc: '2.0', id: message.id, result: { agent } }; } };
  const { server, audited } = createRemoteServer({ credentials, development, auditFile: path.join(area, 'audit.jsonl'), perMinute: 3 });
  t.after(async () => {
    server.closeAllConnections();
    if (server.listening) await new Promise(resolve => server.close(resolve));
    await audited();
    await rm(area, { recursive: true, force: true });
  });
  const url = await listen(server);
  const call = name => fetch(`${url}/mcp`, { method: 'POST', body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'ping' }),
    headers: { Authorization: `Bearer ${tokens[name]}`, 'Content-Type': 'application/json' } }).then(response => response.status);
  assert.deepEqual([await call('a'), await call('a'), await call('a'), await call('a')], [200, 200, 200, 429]);
  assert.equal(await call('b'), 200, 'one agent cannot spend another agent’s budget');
});
