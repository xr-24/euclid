import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { setTimeout as sleep } from 'node:timers/promises';
import { createRelayCore } from '../relay/relay-core.mjs';
import { agentUrl, relaySocketUrl } from './relay-link.mjs';
import { createGateway } from './server.mjs';

// The relay core from relay/, with an in-memory stand-in for the WebSocket between it and Euclid.
function relayHub(key) {
  let euclid = null;
  const core = createRelayCore({ key, timeout: 3000, link: {
    current: () => euclid,
    adopt: socket => {
      if (euclid && euclid !== socket) euclid.close(4002, 'Replaced by a newer Euclid connection');
      euclid = socket;
    },
  } });
  const hub = { core, opened: [], drop: () => euclid?.close(1006, 'Network lost') };
  hub.WebSocket = class {
    constructor(url) {
      hub.opened.push(url);
      const client = this;
      this.server = { send: text => setImmediate(() => client.onmessage?.({ data: text })), close: (code, reason) => client.ended(code, reason) };
      setImmediate(() => this.onopen?.());
    }
    send(text) { setImmediate(() => core.message(this.server, text)); }
    close(code = 1000, reason = '') { this.ended(code, reason); }
    ended(code, reason) {
      if (this.done) return;
      this.done = true;
      if (euclid === this.server) { core.closed(this.server); euclid = null; }
      setImmediate(() => this.onclose?.({ code, reason }));
    }
  };
  return hub;
}

async function until(read, test, what) {
  for (let attempt = 0; attempt < 150; attempt++) {
    const value = await read();
    if (test(value)) return value;
    await sleep(20);
  }
  assert.fail(`Never reached: ${what}`);
}

test('relay addresses become the socket and agent URLs', () => {
  assert.equal(relaySocketUrl('https://euclid-relay.me.workers.dev'), 'wss://euclid-relay.me.workers.dev/euclid');
  assert.equal(agentUrl('https://euclid-relay.me.workers.dev/whatever?x=1'), 'https://euclid-relay.me.workers.dev/mcp');
  assert.equal(relaySocketUrl('http://127.0.0.1:8787'), 'ws://127.0.0.1:8787/euclid');
  assert.throws(() => relaySocketUrl('http://relay.example.com'), /Use https/);
  assert.throws(() => relaySocketUrl('relay'), /Enter the relay address/);
  assert.throws(() => createRelayCore({ key: 'short', link: {} }), /at least 32/);
});

test('Euclid dials out to the relay and answers cloud agents through it', async t => {
  const area = await mkdtemp(path.join(os.tmpdir(), 'euclid-relay-'));
  const key = 'k'.repeat(64);
  const hub = relayHub(key);
  const workbenchSecret = 'w'.repeat(64);
  const dataDir = path.join(area, 'data');
  const open = () => createGateway({ dataDir, token: 'relay-test-secret', workbenchToken: workbenchSecret, workbenchRoot: area,
    relayOptions: { WebSocketImpl: hub.WebSocket, delays: [20], pingEvery: 50 } });
  const first = await open();
  const gateways = [first];
  t.after(async () => {
    for (const { server, relay } of gateways) {
      relay.stop();
      server.closeAllConnections();
      if (server.listening) await new Promise(resolve => server.close(resolve));
    }
    await rm(area, { recursive: true, force: true });
  });
  await new Promise(resolve => first.server.listen(0, '127.0.0.1', resolve));
  const origin = `http://127.0.0.1:${first.server.address().port}`;
  const manage = async (action, body = {}) => {
    const response = await fetch(`${origin}/v1/agents/${action}`, { method: 'POST', body: JSON.stringify(body),
      headers: { Authorization: 'Bearer relay-test-secret', 'X-Euclid-Workbench': workbenchSecret, 'Content-Type': 'application/json' } });
    return { status: response.status, body: await response.json() };
  };
  const agentCall = (credential, method, params) => hub.core.forward({ authorization: `Bearer ${credential}`,
    contentType: 'application/json', body: JSON.stringify({ jsonrpc: '2.0', id: 1, method, params }), address: '203.0.113.7' });

  assert.equal((await agentCall('eua_' + 'a'.repeat(64), 'tools/list')).status, 503, 'agents hear that Euclid is offline');
  const cloud = (await manage('issue', { name: 'cloud', remote: true })).body.token;
  assert.equal((await manage('relay', { action: 'configure', url: 'http://relay.example.com' })).status, 400);
  const configured = (await manage('relay', { action: 'configure', url: 'https://relay.test', key })).body;
  assert.deepEqual([configured.generated, configured.agent_url], [false, 'https://relay.test/mcp']);
  await until(async () => (await manage('relay')).body.state, state => state === 'connected', 'connected');
  assert.equal(hub.opened[0], 'wss://relay.test/euclid');
  assert.match(await readFile(path.join(dataDir, 'relay.json'), 'utf8'), /relay\.test/);

  // Agents' calls go through the relay to the same remote handler the tunnel uses.
  const listed = await agentCall(cloud, 'tools/list');
  assert.equal(listed.status, 200);
  const tools = JSON.parse(listed.body).result.tools.map(item => item.name);
  assert.ok(tools.includes('submit_draft') && !tools.includes('run_checks'));
  assert.equal((await agentCall('eua_' + 'b'.repeat(64), 'tools/list')).status, 401);
  assert.equal((await hub.core.forward({ authorization: `Bearer ${cloud}`, contentType: 'application/json',
    body: JSON.stringify({ jsonrpc: '2.0', method: 'notifications/initialized' }) })).status, 202);
  const agents = (await manage('list')).body;
  assert.deepEqual([agents.agents[0].name, agents.agents[0].last_seen.via, agents.relay.state], ['cloud', 'relay', 'connected']);
  const activity = (await manage('activity', { limit: 5 })).body.entries;
  assert.ok(activity.some(entry => entry.agent === 'cloud' && entry.via === 'relay' && entry.address === '203.0.113.7'));

  // A dropped connection comes back by itself.
  hub.drop();
  await until(async () => (await manage('relay')).body.state, state => state === 'connected' && hub.opened.length >= 2, 'reconnected');
  assert.equal((await agentCall(cloud, 'tools/list')).status, 200);

  // A second Euclid takes over the relay, and the first does not fight it.
  const second = await open();
  gateways.push(second);
  await second.relay.start();
  await until(async () => (await manage('relay')).body.state, state => state === 'replaced', 'replaced');
  await sleep(100);
  assert.equal(second.relay.status().state, 'connected');
  assert.equal(first.relay.status().state, 'replaced');
  second.relay.stop();

  // A wrong key is refused once and not retried. Forgetting the relay removes its settings.
  const refused = (await manage('relay', { action: 'configure', url: 'https://relay.test', key: 'x'.repeat(40) })).body;
  assert.equal(refused.generated, false);
  await until(async () => (await manage('relay')).body.state, state => state === 'refused', 'refused');
  const generated = (await manage('relay', { action: 'configure', url: 'https://relay.test' })).body;
  assert.equal(generated.generated, true);
  assert.match(generated.key, /^[a-f0-9]{64}$/);
  assert.equal((await manage('relay', { action: 'forget' })).body.state, 'off');
  await assert.rejects(readFile(path.join(dataDir, 'relay.json')), { code: 'ENOENT' });
});
