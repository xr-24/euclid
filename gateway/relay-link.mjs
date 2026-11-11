import { randomBytes } from 'node:crypto';
import { mkdir, readFile, rename, rm, writeFile } from 'node:fs/promises';
import path from 'node:path';

// Euclid's outbound connection to a relay (see relay/). Euclid dials the relay, proves it knows the
// relay key, and answers the agents' MCP requests the relay passes on through the same handler as
// the tunnel endpoint. Nothing on this machine listens for the outside. The settings live in
// .local/relay.json; the key never leaves this machine except to the relay it belongs to.
const PROTOCOL = 1;
const retryDelays = [1000, 2000, 5000, 15000, 30000];

export function relaySocketUrl(address) {
  let url;
  try { url = new URL(address); } catch { throw new Error('Enter the relay address, such as https://euclid-relay.example.workers.dev.'); }
  if (!['https:', 'wss:', 'http:', 'ws:'].includes(url.protocol)) throw new Error('The relay address must start with https://.');
  const local = ['localhost', '127.0.0.1', '[::1]'].includes(url.hostname);
  if (['http:', 'ws:'].includes(url.protocol) && !local) throw new Error('Use https:// for a relay on the internet.');
  url.protocol = url.protocol === 'http:' || url.protocol === 'ws:' ? 'ws:' : 'wss:';
  url.pathname = '/euclid';
  url.search = '';
  url.hash = '';
  return url.toString();
}

export function agentUrl(address) {
  const url = new URL(relaySocketUrl(address));
  url.protocol = url.protocol === 'ws:' ? 'http:' : 'https:';
  url.pathname = '/mcp';
  return url.toString();
}

export function createRelayLink({ endpoint, file, WebSocketImpl = globalThis.WebSocket, delays = retryDelays, pingEvery = 30000 }) {
  let settings = null;
  let socket = null;
  let timer = null;
  let ping = null;
  let attempt = 0;
  let stopped = true;
  let status = { state: 'off', error: '', since: new Date().toISOString(), requests: 0 };

  const set = (state, error = '') => {
    if (status.state !== state || status.error !== error) status = { ...status, state, error, since: new Date().toISOString() };
  };

  async function save(value) {
    await mkdir(path.dirname(file), { recursive: true });
    await writeFile(`${file}.next`, JSON.stringify(value), { mode: 0o600 });
    await rename(`${file}.next`, file);
  }

  function disconnect() {
    clearTimeout(timer);
    clearInterval(ping);
    timer = null;
    ping = null;
    const current = socket;
    socket = null;
    if (current) {
      current.onclose = null;
      try { current.close(1000, 'Euclid disconnected'); } catch { /* already closed */ }
    }
  }

  function retry() {
    if (stopped || !settings) return;
    const wait = delays[Math.min(attempt, delays.length - 1)];
    attempt++;
    timer = setTimeout(connect, wait);
  }

  function connect() {
    if (stopped || !settings) return;
    if (typeof WebSocketImpl !== 'function') { set('error', 'This Node has no WebSocket client. Use Node 22 or later.'); return; }
    set('connecting');
    let current;
    try { current = new WebSocketImpl(relaySocketUrl(settings.url)); }
    catch (error) { set('error', error.message); retry(); return; }
    socket = current;
    current.onopen = () => current.send(JSON.stringify({ type: 'hello', version: PROTOCOL, key: settings.key }));
    current.onmessage = async event => {
      let data;
      try { data = JSON.parse(typeof event.data === 'string' ? event.data : Buffer.from(event.data).toString('utf8')); } catch { return; }
      if (data.type === 'ready') {
        attempt = 0;
        set('connected');
        clearInterval(ping);
        ping = setInterval(() => { if (socket === current) current.send(JSON.stringify({ type: 'ping', at: Date.now() })); }, pingEvery);
        ping.unref?.();
      } else if (data.type === 'request' && typeof data.id === 'string') {
        status = { ...status, requests: status.requests + 1 };
        let answer;
        try {
          answer = await endpoint.handle({ authorization: String(data.authorization ?? ''), contentType: String(data.content_type ?? ''),
            text: String(data.body ?? ''), address: String(data.address ?? ''), via: 'relay' });
        } catch {
          answer = { status: 500, body: { error: 'Euclid could not process the request.' } };
        }
        if (socket === current) {
          current.send(JSON.stringify({ type: 'response', id: data.id, status: answer.status,
            body: answer.body === null ? '' : JSON.stringify(answer.body) }));
        }
      }
    };
    current.onerror = () => {};
    current.onclose = event => {
      if (socket !== current) return;
      socket = null;
      clearInterval(ping);
      // A wrong key will not fix itself, and a newer Euclid took over the relay. Neither retries.
      if (event.code === 4001) { set('refused', 'The relay refused the key. Set the same key on the relay and connect again.'); return; }
      if (event.code === 4002) { set('replaced', 'Another Euclid connected to this relay.'); return; }
      set('offline', event.reason || 'The relay connection closed. Euclid will try again.');
      retry();
    };
  }

  return {
    async start() {
      try { settings = JSON.parse(await readFile(file, 'utf8')); }
      catch { settings = null; }
      if (!settings?.url || typeof settings.key !== 'string') { settings = null; return; }
      stopped = false;
      attempt = 0;
      connect();
    },

    // Saves the relay address and key, then connects. A new key is generated when none is given.
    async configure({ url, key }) {
      relaySocketUrl(url);
      const given = typeof key === 'string' && key.trim() !== '';
      const chosen = given ? key.trim() : randomBytes(32).toString('hex');
      if (chosen.length < 32) throw new Error('A relay key must be at least 32 characters.');
      disconnect();
      settings = { url: String(url).trim(), key: chosen };
      await save(settings);
      stopped = false;
      attempt = 0;
      connect();
      return { ...this.status(), key: chosen, generated: !given };
    },

    reconnect() {
      if (!settings) throw new Error('Set a relay address first.');
      disconnect();
      stopped = false;
      attempt = 0;
      connect();
      return this.status();
    },

    async forget() {
      stopped = true;
      disconnect();
      settings = null;
      await rm(file, { force: true });
      set('off');
      return this.status();
    },

    stop() {
      stopped = true;
      disconnect();
    },

    status: () => ({ ...status, url: settings?.url ?? '', agent_url: settings ? agentUrl(settings.url) : '' }),
  };
}
