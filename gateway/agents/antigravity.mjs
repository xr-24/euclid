import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { agentEnvironment, isFile, searchPath, run, streamEvents, vendorCredentials } from './process.mjs';

const schemaLimit = 24000;
const installMessage = 'Install Antigravity CLI (agy) or set EUCLID_AGY_BIN to its executable.';
const authMessage = 'Sign in to Antigravity before running tasks.';
const authenticationFailure = /sign in|not authenticated|unauthorized|api key|login required|oauth|not logged in/i;
const planPrompt = 'Follow the instructions, input, and JSON Schema supplied on standard input. Reply only with valid JSON matching the schema.';
const authorPrompt = 'Carry out the instructions supplied on standard input in the current directory.';

export async function resolveAntigravityBinary(env = process.env) {
  if (env.EUCLID_AGY_BIN) return env.EUCLID_AGY_BIN;
  if (process.platform !== 'win32') return 'agy';
  const directories = [...searchPath(env)];
  if (env.LOCALAPPDATA) {
    directories.push(
      path.join(env.LOCALAPPDATA, 'Programs', 'Antigravity'),
      path.join(env.LOCALAPPDATA, 'Programs', 'antigravity'),
    );
  }
  if (env.USERPROFILE) directories.push(path.join(env.USERPROFILE, '.local', 'bin'));
  for (const directory of new Set(directories)) {
    const native = path.join(directory, 'agy.exe');
    if (await isFile(native)) return native;
  }
  throw new Error(installMessage);
}

function parseJsonReply(stdout) {
  const reply = JSON.parse(stdout);
  if (reply?.is_error || reply?.status === 'error' || reply?.error) {
    throw new Error(reply.error?.message ?? reply.result ?? 'Antigravity returned an error.');
  }
  const candidate = reply && typeof reply === 'object' && 'structured_output' in reply ? reply.structured_output
    : reply && typeof reply === 'object' && 'response' in reply ? reply.response
    : reply && typeof reply === 'object' && 'result' in reply ? reply.result : reply;
  const value = typeof candidate === 'string'
    ? JSON.parse(candidate.trim().replace(/^```(?:json)?\s*/i, '').replace(/\s*```$/, '').trim())
    : candidate;
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('No structured output.');
  return value;
}

// Antigravity CLI (agy) under the local Antigravity subscription sign-in.
// Vendor API keys are removed so runs stay on subscription auth.
export function createAntigravityAgent({ env = process.env,
  launcher = async () => ({ file: await resolveAntigravityBinary(env), args: [] }) } = {}) {
  const model = env.EUCLID_AGY_MODEL ? ['--model', env.EUCLID_AGY_MODEL] : [];
  const childEnv = () => agentEnvironment(env, [
    ...vendorCredentials.google, ...vendorCredentials.openai, ...vendorCredentials.anthropic,
  ]);

  function mapFailure(error, signal, fallback) {
    if (signal?.aborted) return signal.reason ?? error;
    if (['ENOENT', 'ENOTDIR'].includes(error?.code)) return new Error(installMessage);
    const detail = `${error?.stderr ?? ''}\n${error?.stdout ?? ''}\n${error?.message ?? ''}`;
    if (authenticationFailure.test(detail)) return new Error(authMessage);
    return fallback ? new Error(fallback) : error;
  }

  return {
    id: 'antigravity',
    label: 'Antigravity',

    async task(input, { url, token, signal, onMessage = () => {}, onRaw }) {
      signal?.throwIfAborted?.();
      const { file, args } = await launcher();
      const cwd = await mkdtemp(path.join(os.tmpdir(), 'euclid-task-'));
      try {
        await mkdir(path.join(cwd, '.gemini'), { recursive: true });
        await writeFile(path.join(cwd, '.gemini', 'settings.json'), JSON.stringify({
          mcpServers: { euclid: { url, type: 'http', headers: { Authorization: 'Bearer ${EUCLID_TASK_TOKEN}' } } },
        }));
        let buffer = '';
        let last = '';
        let failure = '';
        let resultEvent = null;
        let stderr = '';
        const emit = text => {
          const clean = text.trim();
          if (!clean || authenticationFailure.test(clean)) return;
          last = clean;
          onMessage(clean);
        };
        const flush = () => {
          const text = buffer;
          buffer = '';
          emit(text);
        };
        let code;
        try {
          code = await streamEvents(file, [
            ...args, '-p', 'Carry out the Euclid task supplied on standard input.',
            '--output-format', 'stream-json', '--mode', 'accept-edits', ...model,
          ], {
            cwd, env: { ...childEnv(), EUCLID_TASK_TOKEN: token }, signal, timeout: 600000,
            input, timeoutMessage: 'Antigravity exceeded the ten-minute task limit.',
            onStderr(chunk) { if (stderr.length < 4096) stderr += chunk; },
            onEvent(event) {
              onRaw?.(event);
              if (event.type === 'message' && event.role === 'assistant' && typeof event.content === 'string') {
                if (event.delta) buffer += event.content;
                else { flush(); emit(event.content); }
              } else if (event.type === 'assistant' && !event.message?.error && !event.error &&
                  !event.parent_tool_use_id && Array.isArray(event.message?.content)) {
                flush();
                for (const block of event.message.content) {
                  if (block?.type === 'text' && typeof block.text === 'string') emit(block.text);
                }
              } else if (event.type === 'tool_use') {
                flush();
              } else if (event.type === 'error' && event.severity !== 'warning' && typeof event.message === 'string') {
                failure = event.message;
              } else if (event.type === 'result') {
                flush();
                resultEvent = event;
                if (event.status === 'error' || event.is_error) {
                  failure = event.error?.message || (typeof event.result === 'string' ? event.result : '') || failure || 'Antigravity task failed.';
                } else if (typeof event.result === 'string' && event.result.trim() && !last) {
                  last = event.result.trim();
                }
              }
            },
          });
        } catch (error) {
          throw mapFailure(error, signal);
        }
        if (code !== 0 || failure || resultEvent?.is_error || resultEvent?.status === 'error') {
          const detail = `${failure}\n${stderr}`.trim();
          if (authenticationFailure.test(detail)) throw new Error(authMessage);
          throw new Error(failure || stderr.trim() || 'Antigravity exited before completing the task. Check its sign-in and CLI availability.');
        }
        return last;
      } finally {
        await rm(cwd, { recursive: true, force: true }).catch(() => {});
      }
    },

    async structured(input, schema, signal) {
      signal?.throwIfAborted?.();
      const { file, args } = await launcher();
      const definition = JSON.stringify(typeof schema === 'string' ? JSON.parse(await readFile(schema, 'utf8')) : schema);
      if (definition.length > schemaLimit) throw new Error('This request’s command catalog is too large for the Antigravity adapter.');
      const cwd = await mkdtemp(path.join(os.tmpdir(), 'euclid-plan-'));
      try {
        await mkdir(path.join(cwd, '.gemini'), { recursive: true });
        await writeFile(path.join(cwd, '.gemini', 'settings.json'), JSON.stringify({ mcpServers: {} }));
        const { stdout } = await run(file, [
          ...args, '-p', planPrompt, '--output-format', 'json', '--mode', 'plan', ...model,
        ], { cwd, env: childEnv(), signal, timeout: 70000, maxBuffer: 1024 * 1024 }, `${input}\n\nJSON Schema:\n${definition}`);
        return parseJsonReply(stdout);
      } catch (error) {
        throw mapFailure(error, signal, 'Antigravity could not complete the request. Check your Antigravity CLI sign-in and plan limits.');
      } finally {
        await rm(cwd, { recursive: true, force: true }).catch(() => {});
      }
    },

    async author(input, { workspace, onProgress, onRaw, signal, timeout }) {
      signal?.throwIfAborted?.();
      const { file, args } = await launcher();
      let steps = 0;
      let buffer = '';
      let lastMessage = '';
      let failure = '';
      let resultEvent = null;
      let stderr = '';
      const flush = () => {
        const text = buffer.trim();
        buffer = '';
        if (text && !authenticationFailure.test(text)) lastMessage = text;
      };
      let code;
      try {
        code = await streamEvents(file, [
          ...args, '-p', authorPrompt, '--output-format', 'stream-json', '--mode', 'accept-edits', ...model,
        ], {
          cwd: workspace, env: childEnv(), signal, timeout, input,
          timeoutMessage: 'The source agent timed out. Try a smaller change.',
          onStderr(chunk) { if (stderr.length < 4096) stderr += chunk; },
          onEvent(event) {
            onRaw?.(event);
            if (event.type === 'tool_use') {
              flush();
              onProgress(`Antigravity started workspace step ${++steps}.\n`);
            } else if (event.type === 'message' && event.role === 'assistant' && typeof event.content === 'string') {
              if (event.delta) buffer += event.content;
              else {
                flush();
                const text = event.content.trim();
                if (text && !authenticationFailure.test(text)) lastMessage = text;
              }
            } else if (event.type === 'assistant' && Array.isArray(event.message?.content)) {
              flush();
              for (const block of event.message.content) {
                if (block?.type === 'tool_use') onProgress(`Antigravity started workspace step ${++steps}.\n`);
                else if (block?.type === 'text' && typeof block.text === 'string') {
                  const text = block.text.trim();
                  if (text && !authenticationFailure.test(text)) lastMessage = text;
                }
              }
            } else if (event.type === 'error' && event.severity !== 'warning' && typeof event.message === 'string') {
              failure = event.message;
            } else if (event.type === 'result') {
              flush();
              resultEvent = event;
              if (event.status === 'error' || event.is_error) {
                failure = event.error?.message || (typeof event.result === 'string' ? event.result : '') || failure || 'Antigravity did not finish editing the workspace.';
              } else if (typeof event.result === 'string' && event.result.trim()) {
                lastMessage = event.result.trim();
              }
            }
          },
        });
      } catch (error) {
        throw mapFailure(error, signal);
      }
      if (code !== 0 || failure || resultEvent?.is_error || resultEvent?.status === 'error') {
        const detail = `${failure}\n${stderr}`.trim();
        if (authenticationFailure.test(detail)) throw new Error(authMessage);
        throw new Error(failure || 'Antigravity did not finish editing the workspace. Check CLI sign-in and local workspace permissions.');
      }
      return lastMessage;
    },
  };
}
