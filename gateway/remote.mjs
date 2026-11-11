import { appendFile, mkdir } from 'node:fs/promises';
import http from 'node:http';
import path from 'node:path';

// The outside endpoint for agents that run elsewhere, such as cloud agents. It is a separate server
// on its own port so a tunnel exposes this one route and nothing else: not the world, the Workbench,
// the terminal or the main gateway. Only agent credentials issued with the remote permission work
// here, sent as a standard bearer token. A remote agent gets the development tools, without
// run_checks unless its credential also has the checks permission, because checks run the draft's
// code on this machine. Every call is written to an audit log.
export function createRemoteServer({ credentials, development, auditFile, perMinute = 120 }) {
  const budgets = new Map();
  let writes = Promise.resolve();

  function audit(entry) {
    const line = JSON.stringify({ at: new Date().toISOString(), ...entry }) + '\n';
    writes = writes.then(async () => {
      await mkdir(path.dirname(auditFile), { recursive: true });
      await appendFile(auditFile, line);
    }).catch(error => console.error(`Remote audit: ${error.message}`));
    return writes;
  }

  function reply(res, code, value) {
    res.writeHead(code, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' });
    res.end(JSON.stringify(value));
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
    const address = req.socket.remoteAddress;
    try {
      // Browsers never belong here, and nothing but the MCP route exists.
      if (req.headers.origin) return reply(res, 403, { error: 'Browser origins are not supported' });
      if (req.url !== '/mcp') return reply(res, 404, { error: 'Not found' });
      if (req.method !== 'POST') return reply(res, 405, { error: 'Use POST' });
      const header = req.headers.authorization ?? '';
      const agent = header.startsWith('Bearer ') ? credentials.identify(header.slice(7)) : null;
      const permissions = agent ? credentials.permissions(agent) : null;
      if (!agent || !permissions?.remote) {
        await audit({ agent: agent ?? '', address, status: 401 });
        return reply(res, 401, { error: 'Connect with an agent credential issued for remote use.' });
      }
      if (!withinBudget(agent)) {
        await audit({ agent, address, status: 429 });
        return reply(res, 429, { error: 'Rate limit exceeded' });
      }
      if (!(req.headers['content-type'] ?? '').startsWith('application/json')) return reply(res, 415, { error: 'Use application/json' });
      const text = await readBody(req, 512 * 1024);
      if (text === null) {
        req.resume();
        return reply(res, 413, { error: 'Payload too large' });
      }
      let message;
      try { message = JSON.parse(text); } catch { return reply(res, 400, { error: 'Invalid JSON' }); }
      const controller = new AbortController();
      res.once('close', () => controller.abort());
      const result = await development.rpc(agent, message, controller.signal, { checks: permissions.checks });
      await audit({ agent, address, method: message?.method ?? '', tool: message?.params?.name ?? '',
        status: result === null ? 202 : 200, ...(result?.error ? { error: result.error.code } : {}),
        ...(result?.result?.isError ? { tool_error: true } : {}) });
      if (res.destroyed) return;
      if (result === null) return res.writeHead(202).end();
      return reply(res, 200, result);
    } catch {
      if (!res.headersSent) reply(res, 500, { error: 'The remote endpoint could not process the request' });
    }
  });
  server.requestTimeout = 30000;
  server.headersTimeout = 10000;
  return { server, audited: () => writes };
}
