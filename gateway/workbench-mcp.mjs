import { setTimeout as delay } from 'node:timers/promises';
import { agentPrimer } from './agent-primer.mjs';
import { taskTools } from './agent-tasks.mjs';

const text = (description, maxLength) => ({ type: 'string', description, minLength: 1, maxLength });
const version = { type: 'string', pattern: '^[a-f0-9]{64}$', description: 'The draft version from draft_status, submit_draft or patch_draft.' };
const read = { annotations: { readOnlyHint: true } };
const sourcePath = { type: 'string', maxLength: 200, description: 'A path from list_source, such as world/scripts/world.gd.' };

// Development tools for a connected agent. They cover reading source, submitting
// a draft, running its checks and reading the results. Committing, previewing
// and reverting stay with the person in Euclid's Workbench. Each agent sees its own draft.
export const developmentTools = [
  { name: 'list_source', description: 'List the files you can read. A draft may change Godot source in world/, gateway source and tests in gateway/, README.md and docs/. The kernel files, AGENTS.md, package.json and scripts/ are read-only.',
    inputSchema: { type: 'object', properties: {}, additionalProperties: false }, ...read },
  { name: 'read_source', description: 'Read one file. While a draft is active this returns the draft’s version of the file.',
    inputSchema: { type: 'object', properties: { path: sourcePath }, required: ['path'], additionalProperties: false }, ...read },
  { name: 'search_source', description: 'Search source files for text or a regex. While a draft is active this searches the draft’s files.',
    inputSchema: { type: 'object', properties: {
      query: text('Literal text or regular expression to search for.', 200),
      path_prefix: { type: 'string', maxLength: 160, description: 'Optional path prefix filter, such as world/scripts/.' },
      regex: { type: 'boolean', description: 'Treat query as a case-insensitive regular expression.' },
      max_results: { type: 'integer', minimum: 1, maximum: 100, description: 'Maximum matching lines to return (default 60).' },
    }, required: ['query'], additionalProperties: false }, ...read },
  { name: 'draft_status', description: 'Report your source draft: its version, files, diff, check status and output, ' +
      'and whether the main branch has moved past its base. other_drafts lists the drafts other agents hold, their files and ' +
      'whether each is live in the world; avoid editing those files. ' +
      'live says what happened when the running world last loaded the draft: active (with the tier: instant, in_place, zone ' +
      'or restart), refused by the quick gate, rolled_back after an error (with the errors and their file and line), or unloaded; and frame_ms, render time before and after the load in milliseconds. ' +
      'Drafts of text files under world/ load live before their checks finish.',
    inputSchema: { type: 'object', properties: {}, additionalProperties: false }, ...read },
  { name: 'list_extensions', description: 'List the kinds of extension Euclid takes, whether each previews live in the running world ' +
      'or needs a restart, and every installed extension with its kind, id, files and version. draft_status names the kinds your draft changes.',
    inputSchema: { type: 'object', properties: {}, additionalProperties: false }, ...read },
  { name: 'task_history', description: 'List recent Workbench events, newest first: drafts, revisions, checks with their scope, ' +
      'commits, discards, reverts and live loads. Each entry names the draft, its owner and files. Pass draft to see one draft’s history.',
    inputSchema: { type: 'object', properties: { draft: { type: 'string', pattern: '^[a-f0-9-]{36}$', description: 'A draft id from draft_status or an earlier entry.' } },
      additionalProperties: false }, ...read },
  { name: 'read_gateway_log', description: 'Read the redacted tail of the gateway reload logs and your draft’s preview log.',
    inputSchema: { type: 'object', properties: {
      limit: { type: 'integer', minimum: 200, maximum: 12000, description: 'Maximum characters from the end of each log (default 8000).' },
    }, required: [], additionalProperties: false }, ...read },
  { name: 'submit_draft', description: 'Create your source draft, or revise it by sending changes on top of its current version. ' +
      'Send complete file contents. Euclid validates the paths and builds the reviewed Git diff. Each agent has at most one draft, ' +
      'and other agents may hold drafts at the same time; draft_status lists theirs under other_drafts.',
    inputSchema: { type: 'object', properties: {
      request: text('What this change is for, in one or two sentences.', 600),
      summary: text('What changed, for the reviewer.', 320),
      files: { type: 'array', maxItems: 24, items: { type: 'object', properties: { path: sourcePath, content: { type: 'string' } },
        required: ['path', 'content'], additionalProperties: false } },
      delete: { type: 'array', maxItems: 24, items: sourcePath },
      version: { ...version, description: 'Required when revising: the current version of your draft.' },
    }, required: ['request'], additionalProperties: false } },
  { name: 'patch_draft', description: 'Create your source draft, or revise it with targeted text edits, new files and deletions. ' +
      'Prefer patch_draft over submit_draft when modifying existing files.',
    inputSchema: { type: 'object', properties: {
      request: text('What this change is for, in one or two sentences.', 600),
      summary: text('What changed, for the reviewer.', 320),
      edits: { type: 'array', maxItems: 48, items: { type: 'object', properties: {
        path: sourcePath, old_text: { type: 'string', minLength: 1 }, new_text: { type: 'string' }, replace_all: { type: 'boolean' },
      }, required: ['path', 'old_text', 'new_text'], additionalProperties: false } },
      create: { type: 'array', maxItems: 24, items: { type: 'object', properties: { path: sourcePath, content: { type: 'string' } },
        required: ['path', 'content'], additionalProperties: false } },
      delete: { type: 'array', maxItems: 24, items: sourcePath },
      version: { ...version, description: 'Required when revising: the current version of your draft.' },
    }, required: ['request'], additionalProperties: false } },
  { name: 'run_checks', description: 'Start the isolated project checks for your draft. They take a few minutes; poll draft_status for the result.',
    inputSchema: { type: 'object', properties: { version }, required: ['version'], additionalProperties: false } },
  { name: 'run_targeted_test', description: 'Run a single fast Node test file or Godot core_tests.gd against your draft without waiting for full checks. Does not mark checks as passed.',
    inputSchema: { type: 'object', properties: {
      version,
      kind: { type: 'string', enum: ['node', 'godot_core'], description: 'Test runner to use: node or godot_core.' },
      target: { type: 'string', maxLength: 160, description: 'For kind="node", a .test.mjs file under gateway/ or scripts/.' },
      filter: { type: 'string', maxLength: 120, description: 'Optional test name pattern (node) or test filter (godot_core).' },
    }, required: ['version', 'kind'], additionalProperties: false } },
  { name: 'rebase_draft', description: 'Replay your draft onto the current tip of the main branch after it moved. ' +
      'The draft keeps its id and needs fresh checks. A conflict names the files and leaves the draft unchanged.',
    inputSchema: { type: 'object', properties: { version }, required: ['version'], additionalProperties: false } },
  { name: 'discard_draft', description: 'Discard your draft and its checks.',
    inputSchema: { type: 'object', properties: { version }, required: ['version'], additionalProperties: false },
    annotations: { destructiveHint: true } },
];

const clip = (value, limit) => typeof value !== 'string' || value.length <= limit ? value ?? ''
  : `${value.slice(0, limit)}\n[truncated: ${value.length - limit} more characters]`;
const tail = (value, limit) => typeof value === 'string' && value.length > limit ? value.slice(-limit) : value ?? '';

function validValue(rule, value) {
  if (rule.enum && !rule.enum.includes(value)) return false;
  if (rule.type === 'object') {
    if (value === null || typeof value !== 'object' || Array.isArray(value)) return false;
    const { properties = {}, required = [], additionalProperties } = rule;
    if (additionalProperties === false && Object.keys(value).some(key => !Object.hasOwn(properties, key))) return false;
    if (required.some(key => !Object.hasOwn(value, key))) return false;
    return Object.entries(value).every(([key, item]) => !Object.hasOwn(properties, key) || validValue(properties[key], item));
  }
  if (rule.type === 'array') {
    if (!Array.isArray(value) || value.length < (rule.minItems ?? 0) || value.length > (rule.maxItems ?? Infinity)) return false;
    return !rule.items || value.every(item => validValue(rule.items, item));
  }
  if (rule.type === 'boolean') return typeof value === 'boolean';
  if (rule.type === 'integer' || rule.type === 'number') {
    const ok = rule.type === 'integer' ? Number.isInteger(value) : (typeof value === 'number' && Number.isFinite(value));
    return ok && value >= (rule.minimum ?? -Infinity) && value <= (rule.maximum ?? Infinity);
  }
  return typeof value === 'string' && value.length >= (rule.minLength ?? 0) && value.length <= (rule.maxLength ?? Infinity) &&
    (!rule.pattern || new RegExp(rule.pattern).test(value));
}

const validArguments = (tool, args) => validValue(tool.inputSchema, args);

// observer, when given, sees each tool call before and after it runs (agent-activity.mjs createToolObserver).
export function createDevelopmentBridge(workbench, { settle = 15000, tasks, extraTools = [], callExtra, observer } = {}) {
  const live = () => new AbortController().signal;
  const tools = [...developmentTools, ...(tasks ? taskTools : []), ...extraTools];

  // Other agents' drafts, so an agent can avoid overlapping work.
  // Who is touching what: other drafts' files, and whether each is live in the world right now.
  const others = (state, agent) => (state.drafts ?? []).filter(item => item.owner !== agent)
    .map(({ owner, files, status, summary, live }) => ({ owner: owner || 'workbench', files, status, summary, live: live === true }));

  function report(state, agent, withDiff = true) {
    const draft = state.draft;
    if (!draft) return { ok: true, draft: null, busy: state.operation ?? '', other_drafts: others(state, agent) };
    return { ok: true, busy: state.operation ?? '', other_drafts: others(state, agent), draft: {
      id: draft.id, version: draft.version ?? '', status: draft.status, owner: draft.owner ?? '', yours: draft.owner === agent,
      files: draft.files, summary: draft.summary ?? '', error: draft.error ?? '', check_status: draft.check_status ?? '', check_scope: draft.check_scope ?? '',
      activation: draft.activation ?? '', notice: draft.revision_notice ?? '', base: draft.base ?? '', kinds: draft.kinds ?? [],
      captures: draft.check_captures ?? [], live: draft.live_result ?? null,
      ...(withDiff ? { diff: clip(draft.diff, 96000) } : {}),
      output: tail(draft.log, 12000), preview_output: tail(state.preview_log, 4000),
    } };
  }

  const belongsTo = owner => owner ? `That draft belongs to ${owner}.` : 'That draft belongs to Euclid’s Workbench.';

  async function own(agent, supplied) {
    const { draft, drafts = [] } = await workbench('state', { owner: agent }, live());
    if (!draft) {
      const other = supplied !== undefined && drafts.find(item => item.version === supplied);
      throw new Error(other ? belongsTo(other.owner) : 'You have no active draft. Use submit_draft to create one.');
    }
    if (draft.owner !== agent) throw new Error(belongsTo(draft.owner));
    if (supplied !== undefined && supplied !== draft.version) throw new Error('The draft changed. Read draft_status and use its current version.');
    return draft;
  }

  async function submit(agent, args, signal, action = 'submit') {
    const { draft, drafts = [] } = await workbench('state', { owner: agent }, live());
    let identity = {};
    if (draft) {
      if (args.version === undefined) throw new Error('Send the current version to revise your draft.');
      const mine = await own(agent, args.version);
      identity = { id: mine.id, version: mine.version };
    } else if (args.version !== undefined) {
      const other = drafts.find(item => item.version === args.version);
      throw new Error(other ? belongsTo(other.owner) : 'There is no active draft to revise. Omit version to create one.');
    }
    const payload = action === 'patch'
      ? { edits: args.edits ?? [], create: args.create ?? [], delete: args.delete ?? [] }
      : { files: args.files ?? [], delete: args.delete ?? [] };
    await workbench(action, { ...identity, owner: agent, prompt: args.request, summary: args.summary, ...payload }, signal);
    const deadline = Date.now() + settle;
    let state = await workbench('state', { owner: agent }, live());
    while (['authoring', 'revising'].includes(state.draft?.status) && Date.now() < deadline) {
      await delay(40);
      state = await workbench('state', { owner: agent }, live());
    }
    const result = state.draft;
    if (result?.status === 'failed' && !result.files.length) {
      // A submission that never became a draft leaves only its failed job. Release it.
      await workbench('discard', { id: result.id, owner: agent }, live());
      throw new Error(result.error || 'The submission could not be turned into a draft.');
    }
    if (draft && result?.version === draft.version) throw new Error(result.revision_notice || 'The revision did not change the draft.');
    return report(state, agent, false);
  }

  async function call(agent, name, args, signal) {
    if (tasks && taskTools.some(tool => tool.name === name)) return tasks.agent(agent, name, args, signal);
    if (extraTools.some(tool => tool.name === name)) return callExtra(agent, name, args, signal);
    switch (name) {
      case 'list_source': return { ok: true, ...await workbench('files', { owner: agent }, signal) };
      case 'read_source': {
        const { text: content, draft } = await workbench('file', { name: args.path, owner: agent }, signal);
        return { ok: true, path: args.path, draft, content };
      }
      case 'search_source': return { ok: true, ...await workbench('search', {
        owner: agent, query: args.query, pathPrefix: args.path_prefix, regex: args.regex === true, maxResults: args.max_results,
      }, signal) };
      case 'draft_status': {
        const result = report(await workbench('state', { owner: agent }, signal), agent);
        if (result.draft) {
          const { head } = await workbench('head', {}, signal);
          result.draft.behind_main = Boolean(result.draft.base) && head !== result.draft.base;
        }
        return result;
      }
      case 'rebase_draft': {
        const draft = await own(agent, args.version);
        return report(await workbench('rebase', { id: draft.id, version: draft.version, owner: agent }, signal), agent, false);
      }
      case 'list_extensions': return { ok: true, ...await workbench('extensions', {}, signal) };
      case 'task_history': return { ok: true, ...await workbench('history', { limit: 50, draft: args.draft }, signal) };
      case 'read_gateway_log': return await workbench('logs', { owner: agent, limit: args.limit }, signal);
      case 'submit_draft': return submit(agent, args, signal, 'submit');
      case 'patch_draft': return submit(agent, args, signal, 'patch');
      case 'run_checks': {
        const draft = await own(agent, args.version);
        return report(await workbench('check', { id: draft.id, version: draft.version, owner: agent }, signal), agent, false);
      }
      case 'run_targeted_test': {
        const draft = await own(agent, args.version);
        return await workbench('targeted', { id: draft.id, version: draft.version, owner: agent, kind: args.kind, target: args.target, filter: args.filter }, signal);
      }
      case 'discard_draft': {
        const draft = await own(agent, args.version);
        return report(await workbench('discard', { id: draft.id, version: draft.version, owner: agent }, signal), agent, false);
      }
    }
  }

  // policy.checks === false hides run_checks and run_targeted_test, for agents that must not run code on this machine.
  async function rpc(agent, message, signal, policy = {}) {
    const offered = tools.filter(tool => (policy.checks !== false || !['run_checks', 'run_targeted_test'].includes(tool.name)) &&
      (policy.tools?.(tool.name) ?? true));
    const id = message?.id ?? null;
    const reply = result => ({ jsonrpc: '2.0', id, result });
    const error = (code, text) => ({ jsonrpc: '2.0', id, error: { code, message: text } });
    if (message?.jsonrpc !== '2.0' || typeof message.method !== 'string') return error(-32600, 'Invalid request');
    if (message.id === undefined) return null;
    switch (message.method) {
      case 'initialize':
        return reply({
          protocolVersion: '2025-03-26', capabilities: { tools: {} },
          serverInfo: { name: 'euclid-workbench', version: '0.1.0' },
          instructions: 'Read Euclid source with list_source, read_source and search_source. Propose a change with patch_draft or submit_draft, start its checks with ' +
            'run_checks, and read the result with draft_status. If the main branch moved, rebase_draft replays your draft onto it. ' +
            'task_history shows what happened to earlier drafts. ' +
            'A person reviews and commits the draft in Euclid’s Workbench.\n\n' + agentPrimer(),
        });
      case 'ping': return reply({});
      case 'tools/list': return reply({ tools: offered });
      case 'tools/call': {
        const tool = offered.find(item => item.name === message.params?.name);
        const args = message.params?.arguments ?? {};
        if (!tool) return error(-32602, 'Unknown workbench tool');
        if (!validArguments(tool, args)) return error(-32602, 'Invalid workbench tool arguments');
        let result;
        const seen = await observer?.before(agent, tool.name, args).catch(() => ({}));
        try { result = await call(agent, tool.name, args, signal); }
        catch (failure) { result = { ok: false, message: failure.message }; }
        try { observer?.after(agent, tool.name, args, result, seen ?? {}); } catch {}
        const { image, ...details } = result;
        const content = [{ type: 'text', text: JSON.stringify(details) }];
        if (image) content.push({ type: 'image', mimeType: 'image/jpeg', data: image });
        return reply({ content, isError: !result.ok });
      }
      default: return error(-32601, 'Method not found');
    }
  }
  return { rpc };
}
