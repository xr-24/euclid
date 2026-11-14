import { readFile } from 'node:fs/promises';
import path from 'node:path';

// What agents are doing, as a short feed of display events the world draws above each agent:
// files read (with the lines), edits (with diff hunks), searches, commands, world tools, and
// what the agent says or thinks. Events are built from two sources: calls an agent makes
// through Euclid's MCP tools (observeTool) and the event stream of a local CLI agent editing a
// source snapshot (tracker). Every event passes the same filter: secret-looking files show no
// content, token-like strings are redacted, and sizes are capped.

const LIMIT = 400;
const LINES = 48;
const WIDTH = 160;
const HUNKS = 4;
const HUNK_LINES = 28;
const CONTEXT = 2;
// reply is what an agent tells the player in chat: a message, a task update or a task's result.
export const KINDS = ['read', 'search', 'edit', 'write', 'delete', 'run', 'tool', 'think', 'say', 'reply', 'start', 'done', 'error'];

const hiddenPath = /(^|[\\/])(\.env[^\\/]*|\.ssh|\.local|\.git|node_modules)([\\/]|$)|secret|credential|password|token|private[-_]?key|id_(rsa|ed25519)|\.(pem|key|p12|pfx|keystore)$/i;
const tokenLike = [
  /\b(?:sk|pk|rk)-[A-Za-z0-9_-]{16,}/g, /\bgh[pousr]_[A-Za-z0-9]{20,}/g, /\bxox[abprs]-[A-Za-z0-9-]{10,}/g, /\bAKIA[0-9A-Z]{16}\b/g,
  /\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}/g, /\b[A-Fa-f0-9]{40,}\b/g, /\b[A-Za-z0-9+/]{48,}={0,2}/g,
];
// An assignment to a secret-sounding name keeps the name and hides the value.
const assignment = /((?:password|passwd|secret|token|api[_-]?key|authorization|bearer)\s*["']?\s*[:=]\s*["']?)[^\s"',;]{6,}/gi;

export function redact(text) {
  let value = String(text ?? '');
  for (const pattern of tokenLike) value = value.replace(pattern, '[redacted]');
  return value.replace(assignment, '$1[redacted]');
}

const clipLine = line => {
  const clean = redact(String(line).replace(/\t/g, '    ').replace(/[\u0000-\u0008\u000b-\u001f\u007f]/g, ''));
  return clean.length > WIDTH ? clean.slice(0, WIDTH - 1) + '…' : clean;
};
const splitLines = text => String(text ?? '').replace(/\r\n?/g, '\n').split('\n');
const sentence = (text, limit = 220) => {
  const value = redact(String(text ?? '').replace(/\s+/g, ' ').trim());
  return value.length > limit ? value.slice(0, limit - 1) + '…' : value;
};

// Like sentence, but keeps paragraph breaks, for replies long enough to read in parts.
const paragraphs = (text, limit) => {
  const value = redact(String(text ?? '').replace(/\r\n?/g, '\n').replace(/[^\S\n]+/g, ' ')
    .replace(/ ?\n ?/g, '\n').replace(/\n{3,}/g, '\n\n').trim());
  return value.length > limit ? value.slice(0, limit - 1) + '…' : value;
};

export const isHiddenPath = name => hiddenPath.test(String(name ?? ''));

// A display path relative to the agent's workspace; paths outside it are hidden.
function relative(root, name) {
  if (typeof name !== 'string' || !name) return null;
  if (!root || !path.isAbsolute(name)) return name.replace(/\\/g, '/').replace(/^\.\//, '');
  const inside = path.relative(root, name);
  if (!inside || inside.startsWith('..') || path.isAbsolute(inside)) return null;
  return inside.replace(/\\/g, '/');
}

// Numbered lines [{n, text}] from the first `first` of a text, capped.
function excerpt(text, first = 1, count = LINES) {
  return splitLines(text).slice(0, count).map((line, index) => ({ n: first + index, text: clipLine(line) }));
}

// Line diff as hunks of { start, lines: [{ t: ' ' | '-' | '+', n, text }] }, n being the line in
// the new file (or the old one for removals). Trims the common ends, then an LCS on the rest.
export function diffLines(before, after) {
  const a = splitLines(before);
  const b = splitLines(after);
  if (before === '' || before == null) a.length = 0;
  let head = 0;
  while (head < a.length && head < b.length && a[head] === b[head]) head++;
  let tail = 0;
  while (tail < a.length - head && tail < b.length - head && a[a.length - 1 - tail] === b[b.length - 1 - tail]) tail++;
  const x = a.slice(head, a.length - tail);
  const y = b.slice(head, b.length - tail);
  const ops = [];
  if (x.length * y.length <= 250000) {
    const table = Array.from({ length: x.length + 1 }, () => new Uint32Array(y.length + 1));
    for (let i = x.length - 1; i >= 0; i--) for (let j = y.length - 1; j >= 0; j--) {
      table[i][j] = x[i] === y[j] ? table[i + 1][j + 1] + 1 : Math.max(table[i + 1][j], table[i][j + 1]);
    }
    let i = 0;
    let j = 0;
    while (i < x.length || j < y.length) {
      if (i < x.length && j < y.length && x[i] === y[j]) { ops.push([' ', x[i]]); i++; j++; }
      // Removals before additions, as a reader expects a replaced line to read.
      else if (i < x.length && (j >= y.length || table[i + 1][j] >= table[i][j + 1])) ops.push(['-', x[i++]]);
      else ops.push(['+', y[j++]]);
    }
  } else {
    for (const line of x) ops.push(['-', line]);
    for (const line of y) ops.push(['+', line]);
  }
  // Number every op against the new file, keeping context from the trimmed ends.
  const all = [];
  for (let k = Math.max(0, head - CONTEXT); k < head; k++) all.push({ t: ' ', n: k + 1, text: b[k] });
  let newLine = head + 1;
  let oldLine = head + 1;
  for (const [t, text] of ops) {
    if (t === '+') all.push({ t, n: newLine++, text });
    else if (t === '-') all.push({ t, n: oldLine++, text });
    else { all.push({ t, n: newLine++, text }); oldLine++; }
  }
  for (let k = b.length - tail; k < Math.min(b.length, b.length - tail + CONTEXT); k++) all.push({ t: ' ', n: k + 1, text: b[k] });
  // Hunks: each changed line with CONTEXT lines either side, merged where they touch.
  const ranges = [];
  all.forEach((line, index) => {
    if (line.t === ' ') return;
    const low = Math.max(0, index - CONTEXT);
    const high = Math.min(all.length - 1, index + CONTEXT);
    const last = ranges.at(-1);
    if (last && low <= last[1] + 1) last[1] = Math.max(last[1], high);
    else ranges.push([low, high]);
  });
  return ranges.slice(0, HUNKS).map(([low, high]) => ({
    start: all[low].n,
    lines: all.slice(low, high + 1).slice(0, HUNK_LINES).map(line => ({ t: line.t, n: line.n, text: clipLine(line.text) })),
  }));
}

const countChanges = hunks => hunks.reduce((sum, hunk) => {
  for (const line of hunk.lines) { if (line.t === '+') sum.added++; else if (line.t === '-') sum.removed++; }
  return sum;
}, { added: 0, removed: 0 });

// The feed: a bounded ring of events with increasing sequence numbers, and long-poll waiting.
export function createActivityFeed({ limit = LIMIT, now = () => Date.now() } = {}) {
  const events = [];
  let seq = 0;
  const waiting = new Set();

  function record(actor, event) {
    if (typeof actor !== 'string' || !/^[A-Za-z0-9._-]{1,100}$/.test(actor) || !KINDS.includes(event?.kind)) return null;
    const entry = clean({ ...event, actor, seq: ++seq, at: now() });
    events.push(entry);
    if (events.length > limit) events.splice(0, events.length - limit);
    for (const wake of waiting) wake();
    return entry;
  }

  function since(after = 0, max = 64) {
    let from = Number.isInteger(after) && after >= 0 ? after : 0;
    // A position past the end means the gateway restarted since the client last asked.
    const reset = from > seq;
    if (reset) from = 0;
    // A client that fell far behind skips to the newest events instead of replaying old ones.
    const result = events.filter(event => event.seq > from).slice(-max);
    return { events: result, next: result.length ? result.at(-1).seq : from, reset };
  }

  async function wait(after = 0, { timeout = 20000, signal } = {}) {
    if (after > seq || events.some(event => event.seq > after)) return since(after);
    await new Promise(resolve => {
      let timer;
      const done = () => { clearTimeout(timer); waiting.delete(done); signal?.removeEventListener?.('abort', done); resolve(); };
      timer = setTimeout(done, timeout);
      waiting.add(done);
      signal?.addEventListener?.('abort', done, { once: true });
    });
    return since(after);
  }

  return { record, since, wait, get seq() { return seq; } };
}

// Shapes an event for display: only known fields, bounded sizes, secret paths emptied.
function clean(event) {
  const out = { seq: event.seq, at: event.at, actor: event.actor, kind: event.kind, title: sentence(event.title ?? '', 160) };
  if (typeof event.source === 'string') out.source = event.source.slice(0, 40);
  if (typeof event.path === 'string') out.path = event.path.slice(0, 200);
  if (typeof event.tool === 'string') out.tool = event.tool.slice(0, 80);
  const hidden = out.path && isHiddenPath(out.path);
  if (hidden) out.hidden = true;
  if (!hidden) {
    if (Array.isArray(event.lines)) out.lines = event.lines.slice(0, LINES).map(line => ({ n: Number(line.n) || 0, text: clipLine(line.text) }));
    if (Array.isArray(event.focus) && event.focus.length === 2) out.focus = event.focus.map(Number);
    if (Array.isArray(event.hunks)) {
      out.hunks = event.hunks.slice(0, HUNKS).map(hunk => ({ start: Number(hunk.start) || 1,
        lines: hunk.lines.slice(0, HUNK_LINES).map(line => ({ t: ['+', '-'].includes(line.t) ? line.t : ' ', n: Number(line.n) || 0, text: clipLine(line.text) })) }));
      const { added, removed } = countChanges(out.hunks);
      out.added = Number(event.added ?? added);
      out.removed = Number(event.removed ?? removed);
    }
    if (typeof event.command === 'string') out.command = clipLine(event.command);
    if (Array.isArray(event.output)) out.output = event.output.slice(-16).map(clipLine);
    if (typeof event.text === 'string') out.text = event.kind === 'reply' ? paragraphs(event.text, 4000) : sentence(event.text, 600);
    if (Array.isArray(event.results)) out.results = event.results.slice(0, 12).map(clipLine);
  }
  if (typeof event.ok === 'boolean') out.ok = event.ok;
  return out;
}

// Read a file the agent can see, or '' when it is missing or too large.
async function readSmall(file) {
  try {
    const text = await readFile(file, 'utf8');
    return text.length > 512 * 1024 ? '' : text;
  } catch { return ''; }
}

const toolTitle = (name, args = {}) => {
  const detail = args.path ?? args.target ?? args.id ?? args.name ?? args.query ?? args.text ?? args.prompt ?? '';
  return `${String(name).replace(/^mcp__[^_]+__/, '').replace(/_/g, ' ')}${detail ? ` · ${sentence(detail, 80)}` : ''}`;
};

// Calls an agent makes through Euclid's MCP tools. `before` returns the context `after` needs,
// such as a file's previous text so a submitted draft can be shown as a diff.
export function createToolObserver(feed, { readDraftFile = async () => '' } = {}) {
  return {
    async before(agent, name, args) {
      if (name !== 'submit_draft' || !Array.isArray(args?.files)) return {};
      const previous = {};
      for (const file of args.files.slice(0, 24)) {
        if (typeof file?.path === 'string' && !isHiddenPath(file.path)) previous[file.path] = await readDraftFile(agent, file.path).catch(() => '');
      }
      return { previous };
    },
    after(agent, name, args = {}, result = {}, context = {}) {
      const ok = result?.ok !== false;
      switch (name) {
        case 'read_source':
          return feed.record(agent, { kind: 'read', source: 'mcp', path: args.path, title: `Reading ${args.path}`,
            lines: ok ? excerpt(result.content ?? '') : [], ok });
        case 'list_source':
          return feed.record(agent, { kind: 'search', source: 'mcp', title: 'Listing source files',
            results: (result.files ?? []).slice(0, 12).map(file => typeof file === 'string' ? file : file?.path ?? ''), ok });
        case 'submit_draft': {
          const events = [];
          for (const file of (args.files ?? []).slice(0, 8)) {
            const before = context.previous?.[file.path] ?? '';
            const hunks = diffLines(before, file.content ?? '');
            events.push(feed.record(agent, { kind: before ? 'edit' : 'write', source: 'mcp', path: file.path,
              title: `${before ? 'Editing' : 'Writing'} ${file.path}`, hunks, ok }));
          }
          for (const gone of (args.delete ?? []).slice(0, 8)) events.push(feed.record(agent, { kind: 'delete', source: 'mcp', path: gone, title: `Deleting ${gone}`, ok }));
          return events;
        }
        case 'run_checks':
          return feed.record(agent, { kind: 'run', source: 'mcp', title: 'Running the project checks', command: 'euclid checks', ok });
        default:
          return feed.record(agent, { kind: 'tool', source: 'mcp', tool: name, title: toolTitle(name, args), ok,
            text: !ok && typeof result?.message === 'string' ? result.message : undefined });
      }
    },
  };
}

// Reads a CLI's JSON event stream while it edits a source snapshot. `workspace` is the agent's
// directory; `original` holds the files as they were before it started, for diffs.
export function createStreamTracker(feed, { actor, provider, workspace = '', original = '' }) {
  const pending = new Map();
  const known = new Map();
  const record = event => feed.record(actor, { source: provider, ...event });

  async function previous(rel) {
    if (known.has(rel)) return known.get(rel);
    return original ? readSmall(path.join(original, rel)) : '';
  }
  async function current(rel) { return workspace ? readSmall(path.join(workspace, rel)) : ''; }
  async function changed(rel, kind) {
    const before = await previous(rel);
    const after = kind === 'delete' ? '' : await current(rel);
    known.set(rel, after);
    if (kind === 'delete') return record({ kind: 'delete', path: rel, title: `Deleting ${rel}` });
    return record({ kind: before ? 'edit' : 'write', path: rel, title: `${before ? 'Editing' : 'Writing'} ${rel}`, hunks: diffLines(before, after) });
  }

  const text = content => typeof content === 'string' ? content
    : Array.isArray(content) ? content.map(part => part?.type === 'text' ? part.text : '').join('\n') : '';

  // Claude Code's Read results come as "   12→line" (or with a tab).
  function numbered(output) {
    const lines = [];
    for (const raw of splitLines(output)) {
      const match = /^\s*(\d+)(?:→|\t)(.*)$/.exec(raw);
      if (match) lines.push({ n: Number(match[1]), text: match[2] });
    }
    return lines.slice(0, LINES);
  }

  async function claudeTool(use, result) {
    const input = use.input ?? {};
    const name = use.name;
    if (name.startsWith('mcp__')) return null; // The MCP observer reports these.
    const rel = relative(workspace, input.file_path ?? input.notebook_path);
    const output = text(result?.content);
    const failed = Boolean(result?.is_error);
    switch (name) {
      case 'Read':
        if (!rel) return null;
        return record({ kind: 'read', path: rel, title: `Reading ${rel}`, lines: numbered(output), ok: !failed,
          focus: input.offset ? [Number(input.offset), Number(input.offset) + Number(input.limit ?? LINES) - 1] : undefined });
      case 'Edit': case 'MultiEdit': case 'Write': case 'NotebookEdit':
        if (!rel) return null;
        return failed ? record({ kind: 'error', path: rel, title: `Could not edit ${rel}`, text: output }) : changed(rel, 'edit');
      case 'Grep':
        return record({ kind: 'search', title: `Searching for ${sentence(input.pattern, 60)}`, results: splitLines(output).filter(Boolean).slice(0, 12)
          .map(line => line.startsWith(workspace) ? relative(workspace, line) ?? '' : line) });
      case 'Glob':
        return record({ kind: 'search', title: `Finding ${sentence(input.pattern, 60)}`, results: splitLines(output).filter(Boolean).slice(0, 12)
          .map(line => relative(workspace, line) ?? line) });
      case 'Bash':
        return record({ kind: 'run', title: sentence(input.description || 'Running a command', 120), command: String(input.command ?? ''),
          output: splitLines(output).slice(-16), ok: !failed });
      default:
        return record({ kind: 'tool', tool: name, title: toolTitle(name, input), ok: !failed });
    }
  }

  // Codex runs shell commands for reading; recognise the common ones to show the file itself.
  function codexRead(command, output) {
    const inner = String(command).replace(/^(?:\S*(?:bash|zsh|sh|pwsh|powershell)(?:\.exe)?\s+(?:-lc|-c|-Command)\s+)(['"])([\s\S]*)\1$/, '$2');
    let match = /^(?:sed|gsed)\s+-n\s+['"]?(\d+),(\d+)p['"]?\s+(\S+)$/.exec(inner.trim());
    if (match) return { path: match[3], first: Number(match[1]), lines: excerpt(output, Number(match[1])) };
    match = /^nl\s+-ba\s+(\S+)(?:\s*\|\s*sed\s+-n\s+['"]?(\d+),(\d+)p['"]?)?$/.exec(inner.trim());
    if (match) return { path: match[1], lines: numbered(output) };
    match = /^(?:cat|type|Get-Content)\s+(\S+)$/.exec(inner.trim());
    if (match) return { path: match[1], lines: excerpt(output) };
    match = /^head\s+(?:-n\s*)?-?(\d+)\s+(\S+)$/.exec(inner.trim());
    if (match) return { path: match[2], lines: excerpt(output) };
    return null;
  }

  async function codexItem(type, item) {
    switch (item?.type) {
      case 'command_execution': {
        if (type !== 'item.completed') return null;
        const output = String(item.aggregated_output ?? '');
        const read = codexRead(item.command, output);
        if (read) {
          const rel = relative(workspace, path.resolve(workspace || '.', read.path.replace(/^['"]|['"]$/g, '')));
          if (rel) return record({ kind: 'read', path: rel, title: `Reading ${rel}`, lines: read.lines });
        }
        if (/^\s*(?:\S*(?:bash|sh)\s+-lc\s+['"])?\s*(rg|grep|git grep|find|fd|ls)\b/.test(String(item.command))) {
          return record({ kind: 'search', title: sentence(item.command, 120), results: splitLines(output).filter(Boolean).slice(0, 12) });
        }
        return record({ kind: 'run', title: 'Running a command', command: String(item.command ?? ''), output: splitLines(output).slice(-16),
          ok: item.exit_code === 0 || item.exit_code === undefined });
      }
      case 'file_change': {
        if (type !== 'item.completed' || !Array.isArray(item.changes)) return null;
        const out = [];
        for (const change of item.changes.slice(0, 8)) {
          const rel = relative(workspace, path.isAbsolute(change.path ?? '') ? change.path : path.resolve(workspace || '.', change.path ?? ''));
          if (rel) out.push(await changed(rel, change.kind === 'delete' ? 'delete' : 'edit'));
        }
        return out;
      }
      case 'reasoning':
        return type === 'item.completed' && item.text ? record({ kind: 'think', title: 'Thinking', text: item.text }) : null;
      case 'agent_message':
        return type === 'item.completed' && item.text ? record({ kind: 'say', title: 'Says', text: item.text }) : null;
      default:
        return null;
    }
  }

  let queue = Promise.resolve();
  function handle(event) {
    // Events are processed in order; file reads for diffs must not overtake later edits.
    queue = queue.then(() => dispatch(event)).catch(() => {});
    return queue;
  }
  async function dispatch(event) {
    if (!event || typeof event !== 'object') return;
    if (provider === 'claude') {
      if (event.type === 'assistant' && Array.isArray(event.message?.content)) {
        for (const block of event.message.content) {
          if (block?.type === 'tool_use') pending.set(block.id, block);
          else if (block?.type === 'thinking' && block.thinking) record({ kind: 'think', title: 'Thinking', text: block.thinking });
          else if (block?.type === 'text' && block.text?.trim()) record({ kind: 'say', title: 'Says', text: block.text });
        }
      } else if (event.type === 'user' && Array.isArray(event.message?.content)) {
        for (const block of event.message.content) {
          if (block?.type !== 'tool_result' || !pending.has(block.tool_use_id)) continue;
          const use = pending.get(block.tool_use_id);
          pending.delete(block.tool_use_id);
          await claudeTool(use, block);
        }
      }
    } else if (provider === 'codex' && typeof event.type === 'string' && event.type.startsWith('item.')) {
      await codexItem(event.type, event.item);
    }
  }
  return { handle, settled: () => queue };
}

// What an agent tells the player through the task board, as a reply event: a message to the
// player, an update on a task, or the result a task finished with. Returns null for anything else.
export function replyFromBoard(event, value) {
  if (!value || typeof value !== 'object') return null;
  if (event === 'message') {
    return value.to === '@player' && typeof value.text === 'string'
      ? { actor: value.from, kind: 'reply', title: 'Says', text: value.text } : null;
  }
  if (!['task_progress', 'finish_task'].includes(event) || typeof value.update !== 'string' || !value.owner) return null;
  const title = event === 'task_progress' ? 'Update' : value.status === 'completed' ? 'Done' : `Task ${value.status}`;
  return { actor: value.owner, kind: 'reply', title, text: value.update, ok: value.status !== 'failed' };
}
