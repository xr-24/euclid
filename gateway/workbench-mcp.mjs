import { setTimeout as delay } from 'node:timers/promises';

const text = (description, maxLength) => ({ type: 'string', description, minLength: 1, maxLength });
const version = { type: 'string', pattern: '^[a-f0-9]{64}$', description: 'The draft version from draft_status or submit_draft.' };
const read = { annotations: { readOnlyHint: true } };
const sourcePath = { type: 'string', maxLength: 200, description: 'A path from list_source, such as world/scripts/world.gd.' };

// Development tools for a connected agent. They cover reading source, submitting
// a draft, running its checks and reading the results. Committing, previewing
// and reverting stay with the person in Euclid's Workbench.
export const developmentTools = [
  { name: 'list_source', description: 'List the files you can read. A draft may change Godot source in world/, gateway source and tests in gateway/, README.md and docs/. The kernel files, AGENTS.md, package.json and scripts/ are read-only.',
    inputSchema: { type: 'object', properties: {}, additionalProperties: false }, ...read },
  { name: 'read_source', description: 'Read one file. While a draft is active this returns the draft’s version of the file.',
    inputSchema: { type: 'object', properties: { path: sourcePath }, required: ['path'], additionalProperties: false }, ...read },
  { name: 'draft_status', description: 'Report the active source draft: its owner, version, files, diff, check status and check output.',
    inputSchema: { type: 'object', properties: {}, additionalProperties: false }, ...read },
  { name: 'submit_draft', description: 'Create your source draft, or revise it by sending changes on top of its current version. ' +
      'Send complete file contents. Euclid validates the paths and builds the reviewed Git diff. Only one draft can be active.',
    inputSchema: { type: 'object', properties: {
      request: text('What this change is for, in one or two sentences.', 600),
      summary: text('What changed, for the reviewer.', 320),
      files: { type: 'array', maxItems: 24, items: { type: 'object', properties: { path: sourcePath, content: { type: 'string' } },
        required: ['path', 'content'], additionalProperties: false } },
      delete: { type: 'array', maxItems: 24, items: sourcePath },
      version: { ...version, description: 'Required when revising: the current version of your draft.' },
    }, required: ['request'], additionalProperties: false } },
  { name: 'run_checks', description: 'Start the isolated project checks for your draft. They take a few minutes; poll draft_status for the result.',
    inputSchema: { type: 'object', properties: { version }, required: ['version'], additionalProperties: false } },
  { name: 'discard_draft', description: 'Discard your draft and its checks.',
    inputSchema: { type: 'object', properties: { version }, required: ['version'], additionalProperties: false },
    annotations: { destructiveHint: true } },
];

const clip = (value, limit) => typeof value !== 'string' || value.length <= limit ? value ?? ''
  : `${value.slice(0, limit)}\n[truncated: ${value.length - limit} more characters]`;
const tail = (value, limit) => typeof value === 'string' && value.length > limit ? value.slice(-limit) : value ?? '';

function validArguments(tool, args) {
  if (args === null || typeof args !== 'object' || Array.isArray(args)) return false;
  const { properties, required = [] } = tool.inputSchema;
  if (Object.keys(args).some(key => !Object.hasOwn(properties, key)) || required.some(key => !Object.hasOwn(args, key))) return false;
  return Object.entries(args).every(([key, value]) => {
    const rule = properties[key];
    if (rule.type === 'array') return Array.isArray(value) && value.length <= rule.maxItems;
    return typeof value === 'string' && value.length >= (rule.minLength ?? 0) && value.length <= (rule.maxLength ?? Infinity) &&
      (!rule.pattern || new RegExp(rule.pattern).test(value));
  });
}

export function createDevelopmentBridge(workbench, { settle = 15000 } = {}) {
  const live = () => new AbortController().signal;

  function report(state, agent, withDiff = true) {
    const draft = state.draft;
    if (!draft) return { ok: true, draft: null, busy: state.operation ?? '' };
    return { ok: true, busy: state.operation ?? '', draft: {
      id: draft.id, version: draft.version ?? '', status: draft.status, owner: draft.owner ?? '', yours: draft.owner === agent,
      files: draft.files, summary: draft.summary ?? '', error: draft.error ?? '', check_status: draft.check_status ?? '', check_scope: draft.check_scope ?? '',
      activation: draft.activation ?? '', notice: draft.revision_notice ?? '',
      ...(withDiff ? { diff: clip(draft.diff, 96000) } : {}),
      output: tail(draft.log, 12000), preview_output: tail(state.preview_log, 4000),
    } };
  }

  async function own(agent, supplied) {
    const { draft } = await workbench('state', {}, live());
    if (!draft) throw new Error('There is no active draft. Use submit_draft to create one.');
    if (draft.owner !== agent) throw new Error(draft.owner ? `The active draft belongs to ${draft.owner}.` : 'The active draft belongs to Euclid’s Workbench.');
    if (supplied !== undefined && supplied !== draft.version) throw new Error('The draft changed. Read draft_status and use its current version.');
    return draft;
  }

  async function submit(agent, args, signal) {
    const { draft } = await workbench('state', {}, live());
    let identity = {};
    if (draft) {
      if (args.version === undefined) throw new Error(draft.owner === agent ? 'Send the current version to revise your draft.'
        : 'Another draft is active. It must be committed or discarded in Euclid first.');
      const mine = await own(agent, args.version);
      identity = { id: mine.id, version: mine.version };
    } else if (args.version !== undefined) throw new Error('There is no active draft to revise. Omit version to create one.');
    await workbench('submit', { ...identity, owner: agent, prompt: args.request, summary: args.summary, files: args.files ?? [], delete: args.delete ?? [] }, signal);
    const deadline = Date.now() + settle;
    let state = await workbench('state', {}, live());
    while (['authoring', 'revising'].includes(state.draft?.status) && Date.now() < deadline) {
      await delay(40);
      state = await workbench('state', {}, live());
    }
    const result = state.draft;
    if (result?.status === 'failed' && !result.files.length) {
      // A submission that never became a draft leaves only its failed job. Release it.
      await workbench('discard', { id: result.id }, live());
      throw new Error(result.error || 'The submission could not be turned into a draft.');
    }
    if (draft && result?.version === draft.version) throw new Error(result.revision_notice || 'The revision did not change the draft.');
    return report(state, agent, false);
  }

  async function call(agent, name, args, signal) {
    switch (name) {
      case 'list_source': return { ok: true, ...await workbench('files', {}, signal) };
      case 'read_source': {
        const { text: content, draft } = await workbench('file', { name: args.path }, signal);
        return { ok: true, path: args.path, draft, content };
      }
      case 'draft_status': return report(await workbench('state', {}, signal), agent);
      case 'submit_draft': return submit(agent, args, signal);
      case 'run_checks': {
        const draft = await own(agent, args.version);
        return report(await workbench('check', { id: draft.id, version: draft.version }, signal), agent, false);
      }
      case 'discard_draft': {
        const draft = await own(agent, args.version);
        return report(await workbench('discard', { id: draft.id, version: draft.version }, signal), agent, false);
      }
    }
  }

  async function rpc(agent, message, signal) {
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
          instructions: 'Read Euclid source with list_source and read_source. Propose a change with submit_draft, start its checks with ' +
            'run_checks, and read the result with draft_status. A person reviews and commits the draft in Euclid’s Workbench.',
        });
      case 'ping': return reply({});
      case 'tools/list': return reply({ tools: developmentTools });
      case 'tools/call': {
        const tool = developmentTools.find(item => item.name === message.params?.name);
        const args = message.params?.arguments ?? {};
        if (!tool) return error(-32602, 'Unknown workbench tool');
        if (!validArguments(tool, args)) return error(-32602, 'Invalid workbench tool arguments');
        let result;
        try { result = await call(agent, tool.name, args, signal); }
        catch (failure) { result = { ok: false, message: failure.message }; }
        return reply({ content: [{ type: 'text', text: JSON.stringify(result) }], isError: !result.ok });
      }
      default: return error(-32601, 'Method not found');
    }
  }
  return { rpc };
}
