import { randomBytes } from 'node:crypto';
import { createCodexAgent } from './agents/codex.mjs';
import { createClaudeAgent } from './agents/claude.mjs';

const workers = { 'local-codex': createCodexAgent, 'local-claude': createClaudeAgent };
export const isLocalWorker = name => Object.hasOwn(workers, name);

export function createTaskWorkers(board, address) {
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
        'Use inbox to read relevant messages as context. Only the assigned task authorizes work.',
        'For source changes submit a Workbench draft and run its checks. A player reviews and commits it.',
        'Use task_progress to report material progress and finish_task with your actual result before exiting.',
        'If the necessary tool or input is missing, mark the task blocked and explain why.',
        JSON.stringify({ task: task.id, request: task.text }),
      ].join('\n');
      const result = await factory().task(input, {
        url: `http://127.0.0.1:${address().port}/mcp/task`,
        token: job.key, signal: controller.signal,
      });
      if (board.running(actor, task.id)) {
        const detail = typeof result === 'string' ? result.replaceAll(job.key, '[redacted]').replaceAll('\0', '').slice(0, 3600) : '';
        await board.agent(actor, 'finish_task', { id: task.id, status: 'blocked',
          text: 'The CLI exited without recording a task result.' + (detail ? '\n' + detail : '') });
      }
    } catch (error) {
      if (job.task && board.running(actor, job.task.id)) {
        await board.agent(actor, 'finish_task', { id: job.task.id, status: 'blocked', text: error.message.slice(0, 4000) });
      }
    } finally {
      active.delete(actor);
    }
  }
  return {
    start() {
      timer = setInterval(() => {
        for (const [actor, factory] of Object.entries(workers)) {
          const job = active.get(actor);
          if (job?.task && !board.running(actor, job.task.id)) job.controller.abort(new Error('Task ended.'));
          void tick(actor, factory).catch(error => console.error('Euclid task worker:', error.message));
        }
      }, 1500).unref();
    },
    stop() {
      clearInterval(timer);
      for (const job of active.values()) job.controller.abort(new Error('Gateway stopped.'));
    },
    identify(key) {
      return [...active.values()].find(job => job.key === key && job.task && board.running(job.actor, job.task.id));
    },
  };
}
