// The relay between cloud agents and one Euclid. Euclid connects outward over a WebSocket and
// proves it knows the relay key; agents send ordinary MCP requests over HTTPS, which the relay
// passes to Euclid and whose answers it returns. The relay checks nothing about agents itself:
// Euclid authenticates every agent credential and applies its permissions. Whoever runs the relay
// can read what passes through it, so run it on an account you control.
//
// Uses only Web APIs, so the Cloudflare Worker and the Node tests share it. `link` keeps track of
// which socket is Euclid: { current() -> socket or null, adopt(socket) }.
export const PROTOCOL = 1;
export const REQUEST_LIMIT = 512 * 1024;

function equal(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string') return false;
  let difference = a.length ^ b.length;
  for (let index = 0; index < Math.max(a.length, b.length); index++) {
    difference |= (a.charCodeAt(index) || 0) ^ (b.charCodeAt(index) || 0);
  }
  return difference === 0;
}

const json = value => JSON.stringify(value);

export function createRelayCore({ key, link, timeout = 60000 }) {
  const pending = new Map();
  if (typeof key !== 'string' || key.length < 32) throw new Error('The relay key must be at least 32 characters.');

  return {
    connected: () => link.current() !== null,

    // A message from a socket. Until a socket says hello with the key, it is not Euclid.
    message(socket, text) {
      let data;
      try { data = JSON.parse(text); } catch { socket.close(4000, 'Invalid message'); return; }
      if (link.current() !== socket) {
        if (data?.type === 'hello' && data.version === PROTOCOL && equal(data.key, key)) {
          link.adopt(socket);
          socket.send(json({ type: 'ready', version: PROTOCOL }));
        } else {
          socket.close(4001, 'Wrong relay key or protocol');
        }
        return;
      }
      if (data?.type === 'response' && pending.has(data.id)) {
        const entry = pending.get(data.id);
        pending.delete(data.id);
        clearTimeout(entry.timer);
        entry.resolve({ status: Number(data.status) || 502, body: typeof data.body === 'string' ? data.body : '' });
      } else if (data?.type === 'ping') {
        socket.send(json({ type: 'pong', at: data.at }));
      }
    },

    // A socket closed. If it was Euclid, its waiting agents are told at once.
    closed(socket) {
      if (link.current() !== null && link.current() !== socket) return;
      for (const entry of pending.values()) {
        clearTimeout(entry.timer);
        entry.resolve({ status: 503, body: json({ error: 'Euclid went offline.' }) });
      }
      pending.clear();
    },

    // An agent's MCP request. Resolves to { status, body } with body as text.
    forward({ authorization = '', contentType = '', body = '', address = '' }) {
      const euclid = link.current();
      if (!euclid) return Promise.resolve({ status: 503, body: json({ error: 'Euclid is not connected to this relay.' }) });
      if (body.length > REQUEST_LIMIT) return Promise.resolve({ status: 413, body: json({ error: 'Payload too large' }) });
      const id = crypto.randomUUID();
      return new Promise(resolve => {
        const timer = setTimeout(() => {
          pending.delete(id);
          resolve({ status: 504, body: json({ error: 'Euclid did not answer in time.' }) });
        }, timeout);
        pending.set(id, { resolve, timer });
        euclid.send(json({ type: 'request', id, authorization, content_type: contentType, body, address }));
      });
    },
  };
}
