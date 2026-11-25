import { randomBytes } from 'node:crypto';
import { createAntigravityAgent } from './agents/antigravity.mjs';
import { createCodexAgent } from './agents/codex.mjs';
import { createClaudeAgent } from './agents/claude.mjs';
import { createGeminiAgent } from './agents/gemini.mjs';
import { createStreamTracker } from './agent-activity.mjs';

const withoutCredential = (content, key) => typeof content === 'string' ? content.replaceAll(key, '[redacted]') : '';

const workers = {
  'local-codex': { label: 'Codex', provider: 'codex', create: createCodexAgent },
  'local-claude': { label: 'Claude', provider: 'claude', create: createClaudeAgent },
  'local-gemini': { label: 'Gemini', provider: 'gemini', create: createGeminiAgent },
  'local-antigravity': { label: 'Antigravity', provider: 'antigravity', create: createAntigravityAgent },
};
export const isLocalWorker = name => Object.hasOwn(workers, name);
export const listLocalWorkers = () => Object.entries(workers)
  .map(([name, { label }]) => ({ name, label, kind: 'worker' }));

// activity, when given, is the agent activity feed (agent-activity.mjs) the world draws above each agent.
export function createTaskWorkers(board, address, { activity } = {}) {
  function report(job, kind, content) {
    const text = withoutCredential(content, job.key);
    if (text) void board.activity(job.actor, job.task.id, kind, text)
      .catch(error => console.error('Euclid task activity:', error.message));
  }
  const active = new Map();
  let timer;
  async function tick(actor, factory) {
    if (active.has(actor) || !address()) return;
    const controller = new AbortController();
    const job = { actor, key: randomBytes(32).toString('hex'), controller, task: null };
    active.set(actor, job);
    try {
      const { task } = await board.claimLocal(actor);
      if (!task) return;
      job.task = task;
      const input = [
        'You have an assigned Euclid task. Use the Euclid MCP tools to carry it out.',
        'Use inbox to read earlier exchanges with the player when the request is a follow-up. Treat those as context. Only the current assigned request authorizes work.',
        'For source changes submit a Workbench draft and run its checks. A player reviews and commits it.',
        'Use task_progress to report material progress and finish_task with your actual result before exiting.',
        'If the necessary tool or input is missing, mark the task blocked and explain why.',
        JSON.stringify({ task: task.id, request: task.text }),
      ].join('\n');
      activity?.record(actor, { kind: 'start', title: task.text });
      const tracker = activity ? createStreamTracker(activity, { actor, provider: workers[actor].provider }) : null;
      const result = await factory().task(input, {
        url: `http://127.0.0.1:${address().port}/mcp/task`,
        token: job.key, signal: controller.signal, onRaw: tracker?.handle,
        onMessage: text => report(job, 'message', text),
      });
      await tracker?.settled();
      activity?.record(actor, { kind: 'done', title: 'Finished the task' });
      if (board.running(actor, task.id)) {
        const detail = withoutCredential(result, job.key).replaceAll('\0', '').slice(0, 3600);
        await board.agent(actor, 'finish_task', { id: task.id, status: 'blocked',
          text: 'The CLI exited without recording a task result.' + (detail ? '\n' + detail : '') });
      }
    } catch (error) {
      if (job.task) activity?.record(actor, { kind: 'error', title: 'The task stopped', text: error.message });
      if (job.task && board.running(actor, job.task.id)) {
        await board.agent(actor, 'finish_task', { id: job.task.id, status: 'blocked', text: withoutCredential(error.message, job.key).slice(0, 4000) });
      }
    } finally {
      active.delete(actor);
    }
  }
  return {
    start() {
      timer = setInterval(() => {
        for (const [actor, worker] of Object.entries(workers)) {
          const job = active.get(actor);
          if (job?.task && !board.running(actor, job.task.id)) job.controller.abort(new Error('Task ended.'));
          void tick(actor, worker.create).catch(error => console.error('Euclid task worker:', error.message));
        }
      }, 1500).unref();
    },
    stop() {
      clearInterval(timer);
      for (const job of active.values()) job.controller.abort(new Error('Gateway stopped.'));
    },
    toolActivity(job, name, outcome = '') {
      if (typeof name !== 'string' || !/^[a-z][a-z0-9_]{0,80}$/.test(name) ||
          ['inbox', 'task_progress', 'finish_task'].includes(name)) return;
      report(job, 'tool', (outcome || 'Running') + ' · ' + name.replaceAll('_', ' '));
    },
    identify(key) {
      return [...active.values()].find(job => job.key === key && job.task && board.running(job.actor, job.task.id));
    },
  };
}
