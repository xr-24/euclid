import { randomUUID } from 'node:crypto';
import { commandFor, isRuntimeName, isWorkshopName, limits, mcpTools, mcpToolsFor, nativePlan, runtimeCommands, runtimePlan, validRegistry, validWorldPlan } from './command-registry.mjs';

export { validWorldPlan };
export const tools = mcpTools;
const idPattern = /^[a-z0-9_-]{1,64}$/;
const sessionPattern = /^[a-f0-9]{32}$/;
const workshopText = (value, length) => typeof value === 'string' && value.length <= length && Boolean(value.trim()) && !/[\x00-\x1f\x7f]/.test(value);
function validWorkshopCatalog(catalog, context) {
  if (catalog === undefined) return true;
  if (!Array.isArray(catalog) || catalog.length > limits.workshop_actions) return false;
  const names = new Set();
  for (const tool of catalog) {
    if (typeof tool?.name !== 'string' || !isWorkshopName(tool.name, context) || names.has(tool.name) ||
        !workshopText(tool.label, 48) || !workshopText(tool.description, 180) ||
        typeof tool.revision !== 'string' || !/^[a-f0-9]{64}$/.test(tool.revision)) return false;
    names.add(tool.name);
  }
  return true;
}

export function validContext(context) {
  return typeof context?.current === 'string' && Array.isArray(context.environments) &&
    context.environments.length > 0 && context.environments.length <= limits.environments &&
    validRegistry(context.command_registry) && validWorkshopCatalog(context.workshop_tools, context) &&
    context.environments.some(zone => zone?.id === context.current) &&
    context.environments.every(zone => typeof zone?.id === 'string' && idPattern.test(zone.id) &&
      typeof zone.name === 'string' && zone.name.length <= 96 &&
      typeof zone.description === 'string' && zone.description.length <= 180);
}

export function createWorldBridge(assets) {
  const sessions = new Map();
  function prune() {
    const now = Date.now();
    for (const [id, session] of sessions) {
      if (now - session.seen > 12000 && !session.pending) sessions.delete(id);
    }
  }
  function sync(body) {
    if (typeof body?.session !== 'string' || !sessionPattern.test(body.session) || !validContext(body.context)) return null;
    prune();
    if (!sessions.has(body.session)) {
      if (sessions.size >= 8) return null;
      sessions.set(body.session, { pending: null });
    }
    const session = sessions.get(body.session);
    session.context = body.context;
    session.seen = Date.now();
    const pending = session.pending;
    if (pending && body.result?.id === pending.command.id && typeof body.result.value?.ok === 'boolean') {
      pending.finish(body.result.value);
    }
    return { command: session.pending?.command ?? null };
  }

  async function call(id, plan, signal, actor) {
    prune();
    const session = sessions.get(id);
    if (!session || Date.now() - session.seen > 12000) return { ok: false, message: 'Open the Codex CLI from a running Euclid world.' };
    if (commandFor(plan.tool, session.context)?.bridge === 'context') return { ok: true, ...session.context };
    if (session.pending) return { ok: false, message: 'Euclid is still applying another world tool.' };
    if (signal.aborted) return { ok: false, message: 'World tool cancelled.' };
    return new Promise(resolve => {
      const finish = result => {
        clearTimeout(timer);
        signal.removeEventListener('abort', abort);
        session.pending = null;
        resolve(result);
      };
      const abort = () => finish({ ok: false, message: 'World tool cancelled.' });
      const timer = setTimeout(() => finish({ ok: false, message: 'Euclid did not report a result. Inspect the current environment before retrying.' }), 35000);
      const scope = commandFor(plan.tool, session.context)?.scope === 'scene' ? { zone: session.context.current } : {};
      const command = { id: randomUUID(), ...scope, ...plan, ...(actor ? { agent_peer: actor } : {}),
        expires_at: (Date.now() + 35000) / 1000 };
      session.pending = { command, finish };
      signal.addEventListener('abort', abort, { once: true });
    });
  }

  async function rpc(session, message, signal, actor = '') {
    const id = message?.id ?? null;
    const reply = result => ({ jsonrpc: '2.0', id, result });
    const error = (code, message) => ({ jsonrpc: '2.0', id, error: { code, message } });
    if (message?.jsonrpc !== '2.0' || typeof message.method !== 'string') return error(-32600, 'Invalid request');
    if (message.id === undefined) return null;
    prune();
    const world = sessions.get(session);
    const context = world && Date.now() - world.seen <= 12000 ? world.context : null;
    const catalog = context?.workshop_tools ?? [];
    const runtime = runtimeCommands(context);
    function runAction(name) {
      const descriptor = catalog.find(tool => tool.name === name);
      return descriptor ? call(session, {
        tool: 'run_workshop_tool', target: descriptor.name, revision: descriptor.revision, zone: world.context.current,
      }, signal) : { ok: false, message: 'That workshop action is no longer registered here. List the current tools.' };
    }

    switch (message.method) {
      case 'initialize':
        return reply({
          protocolVersion: '2025-03-26', capabilities: { tools: {} },
          serverInfo: { name: 'euclid-world', version: '0.1.0' },
          instructions: 'Use these tools for the live Euclid world. Call list_environments to discover destinations.',
        });
      case 'ping': return reply({});
      case 'tools/list': return reply({ tools: [...mcpToolsFor(context), ...runtime.map(({ name, description, inputSchema }) => ({
        name, description, inputSchema,
      }))] });
      case 'tools/call': {
        const name = message.params?.name;
        const args = message.params?.arguments ?? {};
        const definition = commandFor(name, context);
        // A world result may carry a JPEG (capture_view): agents receive it as an image, not text.
        const send = result => {
          const { image, ...details } = result ?? {};
          const content = [{ type: 'text', text: JSON.stringify(image === undefined ? result : details) }];
          if (typeof image === 'string' && image.length <= 3000000 && /^[A-Za-z0-9+/]+={0,2}$/.test(image)) {
            content.push({ type: 'image', mimeType: 'image/jpeg', data: image });
          }
          return reply({ content, isError: !result?.ok });
        };
        if (!definition && isRuntimeName(name, context)) {
          const command = runtime.find(entry => entry.name === name);
          if (!command) return send({ ok: false, message: 'That command is no longer registered in this scene.' });
          const plan = runtimePlan(command, args, context);
          return plan ? send(await call(session, plan, signal)) : error(-32602, 'Invalid registered command arguments');
        }
        const plan = nativePlan(definition, args, context);
        if (!plan) return error(-32602, 'Invalid world tool arguments');
        if (definition.bridge === 'workshop_catalog') return send({ ok: true, tools: catalog });
        if (definition.catalog === 'workshop_tools') return send(await runAction(plan.target));
        if (definition.service === 'assets' || definition.bridge === 'assets_list') {
          if (!assets) return error(-32603, 'The asset service is unavailable.');
          try {
            if (definition.bridge !== 'spawn_ready') {
              const handler = definition.gateway_handler ?? definition.handler;
              if (typeof assets[handler] !== 'function') return error(-32603, 'The asset command has no handler.');
              return send(await assets[handler](...(definition.parameters ?? []).map(key => args[key])));
            }
            if ((await assets.status(args.asset_id)).status !== 'ready') {
              return send({ ok: false, message: 'Wait for asset_status to report ready before spawning.' });
            }
            const { asset_id: target, ...placement } = args;
            return send(await call(session, { tool: definition.handler, target, ...placement }, signal));
          } catch (failure) {
            return send({ ok: false, message: failure.message });
          }
        }
        if (!validWorldPlan(plan, context, true)) return error(-32602, 'Invalid world tool arguments');
        return send(await call(session, plan, signal, actor));
      }
      default: return error(-32601, 'Method not found');
    }
  }
  return { sync, rpc };
}
