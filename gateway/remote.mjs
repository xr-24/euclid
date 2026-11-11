import { appendFile, mkdir, readFile } from 'node:fs/promises';
import http from 'node:http';
import path from 'node:path';

// The outside door for agents that run elsewhere, such as cloud agents. Requests arrive either on a
// separate local port that a tunnel points at, or through a relay that Euclid dials out to. Both go
// through handle(). Only agent credentials issued with the remote permission work here, sent as a
// standard bearer token. A remote agent gets the development tools, without run_checks unless its
// credential also has the checks permission, because checks run the draft's code on this machine.
// Every call is written to an audit log, without its arguments.
export function createRemoteEndpoint({ credentials, development, auditFile, perMinute = 120 }) {
  const budgets = new Map();
  const seen = new Map();
  let writes = Promise.resolve();

  function audit(entry) {
    const line = JSON.stringify({ at: new Date().toISOString(), ...entry }) + '\n';
    if (entry.agent && entry.status !== 401) seen.set(entry.agent, { at: new Date().toISOString(), via: entry.via });
    writes = writes.then(async () => {
      await mkdir(path.dirname(auditFile), { recursive: true });
      await appendFile(auditFile, line);
    }).catch(error => console.error(`Remote audit: ${error.message}`));
    return writes;
  }

  function withinBudget(agent) {
    const now = Date.now();
    const budget = budgets.get(agent);
    if (!budget || now - budget.start > 60000) {
      budgets.set(agent, { start: now, count: 1 });
      return true;
    }
    return ++budget.count <= perMinute;
  }

  // One MCP request from outside. Returns { status, body } where body is null for a notification.
  async function handle({ authorization = '', contentType = '', text = '', address = '', via = 'tunnel', signal }) {
    const agent = authorization.startsWith('Bearer ') ? credentials.identify(authorization.slice(7)) : null;
    const permissions = agent ? credentials.permissions(agent) : null;
    if (!agent || !permissions?.remote) {
      await audit({ agent: agent ?? '', address, via, status: 401 });
      return { status: 401, body: { error: 'Connect with an agent credential issued for remote use.' } };
    }
    if (!withinBudget(agent)) {
      await audit({ agent, address, via, status: 429 });
      return { status: 429, body: { error: 'Rate limit exceeded' } };
    }
    if (!contentType.startsWith('application/json')) return { status: 415, body: { error: 'Use application/json' } };
    if (Buffer.byteLength(text) > 512 * 1024) return { status: 413, body: { error: 'Payload too large' } };
    let message;
    try { message = JSON.parse(text); } catch { return { status: 400, body: { error: 'Invalid JSON' } }; }
    const result = await development.rpc(agent, message, signal ?? new AbortController().signal, { checks: permissions.checks });
    await audit({ agent, address, via, method: message?.method ?? '', tool: message?.params?.name ?? '',
      status: result === null ? 202 : 200, ...(result?.error ? { error: result.error.code } : {}),
      ...(result?.result?.isError ? { tool_error: true } : {}) });
    return { status: result === null ? 202 : 200, body: result };
  }

  async function entries() {
    const text = await readFile(auditFile, 'utf8').catch(() => '');
    return text.split('\n').slice(-2000).flatMap(line => { try { return [JSON.parse(line)]; } catch { return []; } });
  }

  return {
    handle,
    audited: () => writes,
    lastSeen: name => seen.get(name) ?? null,
    // Recovers each agent's last call from the audit log after a restart.
    async prime() {
      for (const entry of await entries()) {
        if (entry.agent && entry.status !== 401 && typeof entry.at === 'string') seen.set(entry.agent, { at: entry.at, via: entry.via ?? 'tunnel' });
      }
    },
    // The most recent calls, newest first.
    async recent(limit = 30) {
      await writes;
      return (await entries()).slice(-Math.max(1, Math.min(200, limit))).reverse();
    },
  };
}

// The tunnel's local port: one route, POST /mcp, served by the shared handler.
export function createRemoteServer(endpoint) {
  function reply(res, code, value) {
    res.writeHead(code, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' });
    res.end(JSON.stringify(value));
  }
  async function readBody(req, limit) {
    const chunks = [];
    let size = 0;
    for await (const chunk of req) {
      size += chunk.length;
      if (size > limit) return null;
      chunks.push(chunk);
    }
    return Buffer.concat(chunks).toString('utf8');
  }
  const server = http.createServer(async (req, res) => {
    try {
      // Browsers never belong here, and nothing but the MCP route exists.
      if (req.headers.origin) return reply(res, 403, { error: 'Browser origins are not supported' });
      if (req.url !== '/mcp') return reply(res, 404, { error: 'Not found' });
      if (req.method !== 'POST') return reply(res, 405, { error: 'Use POST' });
      const text = await readBody(req, 512 * 1024 + 1);
      if (text === null) {
        req.resume();
        return reply(res, 413, { error: 'Payload too large' });
      }
      const controller = new AbortController();
      res.once('close', () => controller.abort());
      const { status, body } = await endpoint.handle({ authorization: req.headers.authorization ?? '',
        contentType: req.headers['content-type'] ?? '', text, address: req.socket.remoteAddress, via: 'tunnel', signal: controller.signal });
      if (res.destroyed) return;
      if (body === null) return res.writeHead(202).end();
      return reply(res, status, body);
    } catch {
      if (!res.headersSent) reply(res, 500, { error: 'The remote endpoint could not process the request' });
    }
  });
  server.requestTimeout = 30000;
  server.headersTimeout = 10000;
  return server;
}
