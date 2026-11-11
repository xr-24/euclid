// Euclid's relay as a Cloudflare Worker. Euclid dials wss://<worker>/euclid; cloud agents use
// https://<worker>/mcp. One Durable Object holds Euclid's socket with the WebSocket Hibernation API,
// so an idle relay costs nothing while it waits. Deploy with `npx wrangler deploy`, then set the key
// Euclid's Cloud Agents screen gives you with `npx wrangler secret put EUCLID_RELAY_KEY`.
import { createRelayCore } from './relay-core.mjs';

const respond = (status, value) => new Response(typeof value === 'string' ? value : JSON.stringify(value),
  { status, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' } });

export default {
  async fetch(request, env) {
    if (typeof env.EUCLID_RELAY_KEY !== 'string' || env.EUCLID_RELAY_KEY.length < 32) {
      return respond(503, { error: 'This relay has no key yet. Set it with npx wrangler secret put EUCLID_RELAY_KEY.' });
    }
    const { pathname } = new URL(request.url);
    if (!['/', '/euclid', '/mcp'].includes(pathname)) return respond(404, { error: 'Not found' });
    return env.RELAY.get(env.RELAY.idFromName('euclid')).fetch(request);
  },
};

export class EuclidRelay {
  constructor(state, env) {
    this.state = state;
    const isEuclid = socket => socket.deserializeAttachment()?.euclid === true;
    this.core = createRelayCore({ key: env.EUCLID_RELAY_KEY, link: {
      current: () => state.getWebSockets().find(isEuclid) ?? null,
      adopt: socket => {
        for (const other of state.getWebSockets()) {
          if (other !== socket && isEuclid(other)) other.close(4002, 'Replaced by a newer Euclid connection');
        }
        socket.serializeAttachment({ euclid: true });
      },
    } });
  }

  async fetch(request) {
    const { pathname } = new URL(request.url);
    if (pathname === '/euclid') {
      if ((request.headers.get('Upgrade') ?? '').toLowerCase() !== 'websocket') return respond(426, { error: 'Expected a WebSocket' });
      const [client, server] = Object.values(new WebSocketPair());
      this.state.acceptWebSocket(server);
      server.serializeAttachment({ euclid: false });
      return new Response(null, { status: 101, webSocket: client });
    }
    if (pathname === '/mcp') {
      if (request.headers.get('Origin')) return respond(403, { error: 'Browser origins are not supported' });
      if (request.method !== 'POST') return respond(405, { error: 'Use POST' });
      const answer = await this.core.forward({ authorization: request.headers.get('Authorization') ?? '',
        contentType: request.headers.get('Content-Type') ?? '', body: await request.text(),
        address: request.headers.get('CF-Connecting-IP') ?? '' });
      return answer.status === 202 ? new Response(null, { status: 202 }) : respond(answer.status, answer.body);
    }
    return respond(200, { service: 'euclid-relay', connected: this.core.connected() });
  }

  webSocketMessage(socket, message) {
    this.core.message(socket, typeof message === 'string' ? message : new TextDecoder().decode(message));
  }

  webSocketClose(socket) {
    this.core.closed(socket);
  }

  webSocketError(socket) {
    this.core.closed(socket);
  }
}
