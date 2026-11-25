import { createAntigravityAgent } from './antigravity.mjs';
import { createClaudeAgent } from './claude.mjs';
import { createCodexAgent } from './codex.mjs';
import { createGeminiAgent } from './gemini.mjs';

// An agent adapter is { id, label, structured(input, schema, signal), author(input, options) }.
// `plan` covers every one-shot structured proposal. `author` edits a source workspace.
const factories = { codex: createCodexAgent, claude: createClaudeAgent, gemini: createGeminiAgent, antigravity: createAntigravityAgent };
const roles = { plan: 'EUCLID_AGENT_PLAN', author: 'EUCLID_AGENT_AUTHOR' };

export function agentId(role, env = process.env) {
  if (!Object.hasOwn(roles, role)) throw new Error(`Unknown agent role "${role}".`);
  const id = String(env[roles[role]] || env.EUCLID_AGENT || 'codex').trim().toLowerCase();
  if (!Object.hasOwn(factories, id)) {
    throw new Error(`Unknown Euclid agent "${id}". Set EUCLID_AGENT to ${Object.keys(factories).join(', ')}.`);
  }
  return id;
}

export const agentFor = (role, env = process.env) => factories[agentId(role, env)]({ env });

// The selection is read on each call, so a test or launcher can change it per request.
export const structuredAgent = (input, schema, signal) => agentFor('plan').structured(input, schema, signal);
