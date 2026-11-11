import { randomUUID } from 'node:crypto';
import { readFile, rename, writeFile } from 'node:fs/promises';
import { setTimeout as delay } from 'node:timers/promises';

export const person = '@player';
const agentName = /^[a-z0-9_-]{1,32}$/;
const active = task => task.status === 'queued' || task.status === 'working';
const publicTask = ({ session, ...task }) => task;
const text = value => {
  if (typeof value !== 'string' || !value.trim() || value.length > 4000 || value.includes('\0')) {
    throw new Error('Enter 1 to 4000 characters.');
  }
  return value.trim();
};
const target = (name, extra) => {
  if (name !== extra && (typeof name !== 'string' || !agentName.test(name))) throw new Error('Enter a valid agent name.');
  return name;
};

export async function createTaskBoard(file) {
  let state = await readFile(file, 'utf8').then(JSON.parse, error => {
    if (error.code !== 'ENOENT') throw error;
    return { version: 1, tasks: [], messages: [], journal: [] };
  });
  if (state.version !== 1 || !['tasks', 'messages', 'journal'].every(key => Array.isArray(state[key]))) {
    throw new Error('The task board could not be read.');
  }
  let queue = Promise.resolve();
  function change(actor, event, apply) {
    const operation = queue.then(async () => {
      const next = structuredClone(state);
      const at = new Date().toISOString();
      const value = apply(next, at);
      if (!value) return { ok: true, task: null };
      next.journal = [...next.journal, { at, event, actor, id: value.id, to: value.to,
        status: value.status, text: (value.update ?? value.text).slice(0, 4000) }].slice(-2000);
      await writeFile(file + '.tmp', JSON.stringify(next), { mode: 0o600 });
      await rename(file + '.tmp', file);
      state = next;
      return { ok: true, [event === 'message' ? 'message' : 'task']: value };
    });
    queue = operation.catch(() => {});
    return operation;
  }
  function inbox(actor, peer) {
    const filter = item => !peer || item === peer;
    return {
      ok: true,
      tasks: state.tasks.filter(task => actor === person
        ? filter(task.owner || task.to)
        : task.owner === actor || (!task.owner && [actor, '*'].includes(task.to))).slice(-20).map(publicTask),
      messages: state.messages.filter(message => message.from === actor && filter(message.to)
        || message.to === actor && filter(message.from)).slice(-12),
    };
  }
  async function call(actor, name, args, signal) {
    switch (name) {
      case 'inbox': return inbox(actor, args.peer ? target(args.peer === 'you' ? person : args.peer, person) : undefined);
      case 'task_log':
        return { ok: true, entries: state.journal.slice(-20).reverse() };
      case 'assign':
        return change(actor, name, (next, at) => {
          const to = target(args.to, '*');
          const body = text(args.text);
          if (next.tasks.filter(active).length >= 128) throw new Error('The task board already holds 128 active tasks.');
          const session = typeof args.session === 'string' && /^[a-f0-9]{32}$/.test(args.session) ? args.session : '';
          const task = { id: randomUUID(), to, text: body, owner: '', status: 'queued', at, session };
          const history = next.tasks.filter(task => !active(task)).slice(-128);
          next.tasks = [...history, ...next.tasks.filter(active), task];
          return task;
        });
      case 'claim_task': {
        const deadline = Date.now() + (args.wait === 'yes' ? 8000 : 0);
        do {
          signal?.throwIfAborted();
          const result = await change(actor, name, next => {
            if (next.tasks.some(task => task.owner === actor && task.status === 'working')) {
              throw new Error('Finish your current task before claiming another.');
            }
            const task = next.tasks.find(task => task.status === 'queued' && task.to === actor)
              ?? (args.namedOnly ? null : next.tasks.find(task => task.status === 'queued' && task.to === '*'));
            if (task) Object.assign(task, { owner: actor, status: 'working' });
            return task;
          });
          if (result.task || Date.now() >= deadline) return result;
          await delay(400, undefined, { signal });
        } while (true);
      }
      case 'task_progress':
      case 'finish_task':
      case 'cancel':
        return change(actor, name, (next, at) => {
          const task = next.tasks.find(task => task.id === args.id && active(task));
          if (!task || (actor !== person && (task.owner !== actor || task.status !== 'working'))) {
            throw new Error('Choose an active task you own.');
          }
          if (name === 'finish_task' && !['completed', 'failed', 'blocked'].includes(args.status)) throw new Error('Choose completed, failed or blocked.');
          task.update = text(args.text);
          task.updated_at = at;
          if (name !== 'task_progress') task.status = name === 'cancel' ? 'cancelled' : args.status;
          return task;
        });
      case 'send_message':
        return change(actor, 'message', (next, at) => {
          const to = target(args.to === 'you' ? person : args.to, person);
          const message = { id: randomUUID(), from: actor, to, at, text: text(args.text) };
          next.messages = [...next.messages, message].slice(-512);
          return message;
        });
      default: throw new Error('Unknown task action.');
    }
  }
  return {
    player: (action, args, signal) => {
      if (!['assign', 'cancel', 'inbox', 'send_message', 'task_log'].includes(action)) throw new Error('Unknown player task action.');
      return call(person, action, args, signal);
    },
    agent: async (actor, action, args, signal) => {
      if (!agentName.test(actor) || !taskTools.some(tool => tool.name === action)) throw new Error('Unknown agent task action.');
      const result = await call(actor, action, args, signal);
      if (result.task) result.task = publicTask(result.task);
      return result;
    },
    claimLocal: actor => state.tasks.some(task => task.status === 'queued' && task.to === actor)
      ? call(actor, 'claim_task', { namedOnly: true }) : { task: null },
    working: () => state.tasks.filter(task => task.status === 'working').map(task => ({ id: task.owner, task: task.update || task.text })),
    running: (actor, id) => state.tasks.some(task => task.id === id && task.owner === actor && task.status === 'working'),
  };
}

const field = { type: 'string', maxLength: 4000 };
function tool(name, description, keys, required = keys) {
  return { name, description, inputSchema: { type: 'object',
    properties: Object.fromEntries(keys.map(key => [key, field])), required, additionalProperties: false } };
}
export const taskTools = [
  tool('claim_task', 'Claim your next assigned or open task. Set wait to yes to wait briefly.', ['wait'], []),
  tool('task_progress', 'Report progress on your active task.', ['id', 'text']),
  tool('finish_task', 'Finish your active task with completed, failed or blocked and a result.', ['id', 'status', 'text']),
  tool('inbox', 'Read your tasks and private messages. Optionally filter messages by peer.', ['peer'], []),
  tool('send_message', 'Send a message to a named agent or to you for the player.', ['to', 'text']),
];
