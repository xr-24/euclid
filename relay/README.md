# Euclid relay

A small Cloudflare Worker that lets cloud agents reach Euclid without opening anything on your
machine. Euclid dials out to the relay over a WebSocket; agents send ordinary MCP requests to the
relay over HTTPS, and the relay passes them to Euclid and returns the answers. Euclid checks every
agent credential and applies its permissions, so the relay itself trusts no agent.

It runs on your own Cloudflare account. One Durable Object holds Euclid's connection using the
WebSocket Hibernation API, so an idle relay is not billed for the time it waits. Cloudflare's free
Workers plan includes SQLite-backed Durable Objects, which this uses.

## Set it up once

1. Create a Cloudflare account if you do not have one.
2. From this folder, sign in and deploy:

   ```
   npx wrangler login
   npx wrangler deploy
   ```

   Wrangler prints the relay's address, such as `https://euclid-relay.<your-account>.workers.dev`.
3. In Euclid, open **F4 → Agents**, paste that address, leave the key empty and choose **Connect**.
   Euclid shows a new relay key.
4. Give the key to the relay, from this folder, and paste it when asked:

   ```
   npx wrangler secret put EUCLID_RELAY_KEY
   ```

Euclid keeps trying until the relay has its key, then shows **Connected**. Add agents on the same
screen. Each cloud agent gets the relay address followed by `/mcp` and its own credential as an
`Authorization: Bearer` header.

## What the relay can see

Requests and answers pass through the relay in the clear, including source code and agent
credentials. Run it on an account you control. Euclid still limits what any remote agent can do:
only the development tools, checks only for agents you allow, and commits only by you in the
Workbench.

## Routes

| Route | Who | Purpose |
| --- | --- | --- |
| `GET /euclid` (WebSocket) | Euclid | Euclid's outbound connection. It must send the relay key first. A newer connection replaces an older one. |
| `POST /mcp` | Cloud agents | MCP requests, passed to Euclid. 503 while Euclid is offline, 504 if it does not answer within 60 seconds. |
| `GET /` | Anyone | `{"service": "euclid-relay", "connected": true or false}` |

`relay-core.mjs` holds the logic and uses only Web APIs. The gateway's tests run it in Node with an
in-memory socket (`gateway/relay.test.mjs`). `worker.mjs` adapts it to Workers and Durable Objects.
