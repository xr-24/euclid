import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { agentEnvironment, isFile, searchPath, run, streamEvents, vendorCredentials } from './process.mjs';

const schemaLimit = 24000;
const installMessage = 'Install Gemini CLI or set EUCLID_GEMINI_BIN to its executable.';
const authMessage = 'Run gemini once to sign in with your Google account.';
const authenticationFailure = /sign in|not authenticated|unauthorized|api key|login required|oauth/i;
const planPrompt = 'Follow the instructions, input, and JSON Schema supplied on standard input. Reply only with valid JSON matching the schema.';
const authorPrompt = 'Carry out the instructions supplied on standard input in the current directory.';

async function resolveGeminiCommand(env = process.env) {
  if (env.EUCLID_GEMINI_BIN) return { file: env.EUCLID_GEMINI_BIN, args: [] };
  if (process.platform !== 'win32') return { file: 'gemini', args: [] };
  const directories = [...searchPath(env)];
  if (env.APPDATA) directories.push(path.join(env.APPDATA, 'npm'));
  if (env.USERPROFILE) directories.push(path.join(env.USERPROFILE, '.local', 'bin'));
  for (const directory of new Set(directories)) {
    const native = path.join(directory, 'gemini.exe');
    if (await isFile(native)) return { file: native, args: [] };
    const bundle = path.join(directory, 'node_modules', '@google', 'gemini-cli', 'bundle', 'gemini.js');
    if (await isFile(bundle)) return { file: process.execPath, args: [bundle] };
  }
  throw new Error(installMessage);
}

export async function resolveGeminiBinary(env = process.env) {
  const command = await resolveGeminiCommand(env);
  return command.args[0] ?? command.file;
}

function parseJsonReply(stdout) {
  const reply = JSON.parse(stdout);
  if (reply?.error) throw new Error(reply.error.message ?? JSON.stringify(reply.error));
  const candidate = reply && typeof reply === 'object' && 'response' in reply ? reply.response
    : reply && typeof reply === 'object' && 'result' in reply ? reply.result : reply;
  const value = typeof candidate === 'string'
    ? JSON.parse(candidate.trim().replace(/^```(?:json)?\s*/i, '').replace(/\s*```$/, '').trim())
    : candidate;
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('No structured output.');
  return value;
}

// Gemini CLI under the local Google sign-in. Vendor API keys are removed so runs
// stay on subscription OAuth. EUCLID_GEMINI_MODEL optionally picks the model.
export function createGeminiAgent({ env = process.env,
  launcher = async () => resolveGeminiCommand(env) } = {}) {
  const model = env.EUCLID_GEMINI_MODEL ? ['-m', env.EUCLID_GEMINI_MODEL] : [];
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
    id: 'gemini',
    label: 'Gemini',

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
        let stderr = '';
        const flush = () => {
          const text = buffer.trim();
          buffer = '';
          if (!text || authenticationFailure.test(text)) return;
          last = text;
          onMessage(text);
        };
        let code;
        try {
          code = await streamEvents(file, [
            ...args, '-p', 'Carry out the Euclid task supplied on standard input.',
            '--output-format', 'stream-json', '--approval-mode', 'yolo',
            '--allowed-mcp-server-names', 'euclid', ...model,
          ], {
            cwd, env: { ...childEnv(), EUCLID_TASK_TOKEN: token }, signal, timeout: 600000,
            input, timeoutMessage: 'Gemini exceeded the ten-minute task limit.',
            onStderr(chunk) { if (stderr.length < 4096) stderr += chunk; },
            onEvent(event) {
              onRaw?.(event);
              if (event.type === 'message' && event.role === 'assistant' && typeof event.content === 'string') {
                if (event.delta) buffer += event.content;
                else {
                  flush();
                  const text = event.content.trim();
                  if (text && !authenticationFailure.test(text)) { last = text; onMessage(text); }
                }
              } else if (event.type === 'tool_use') {
                flush();
              } else if (event.type === 'error' && event.severity !== 'warning' && typeof event.message === 'string') {
                failure = event.message;
              } else if (event.type === 'result') {
                flush();
                if (event.status === 'error') failure = event.error?.message || failure || 'Gemini task failed.';
              }
            },
          });
        } catch (error) {
          throw mapFailure(error, signal);
        }
        if (code !== 0 || failure) {
          const detail = `${failure}\n${stderr}`.trim();
          if (authenticationFailure.test(detail)) throw new Error(authMessage);
          throw new Error(failure || stderr.trim() || 'Gemini exited before completing the task. Check its sign-in and CLI availability.');
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
      if (definition.length > schemaLimit) throw new Error('This request’s command catalog is too large for the Gemini adapter.');
      const cwd = await mkdtemp(path.join(os.tmpdir(), 'euclid-plan-'));
      try {
        await mkdir(path.join(cwd, '.gemini'), { recursive: true });
        await writeFile(path.join(cwd, '.gemini', 'settings.json'), JSON.stringify({ mcpServers: {} }));
        const { stdout } = await run(file, [
          ...args, '-p', planPrompt, '--output-format', 'json', '--approval-mode', 'plan', ...model,
        ], { cwd, env: childEnv(), signal, timeout: 70000, maxBuffer: 1024 * 1024 }, `${input}\n\nJSON Schema:\n${definition}`);
        return parseJsonReply(stdout);
      } catch (error) {
        throw mapFailure(error, signal, 'Gemini could not complete the request. Check your Gemini CLI sign-in and plan limits.');
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
      let stderr = '';
      const flush = () => {
        const text = buffer.trim();
        buffer = '';
        if (text && !authenticationFailure.test(text)) lastMessage = text;
      };
      let code;
      try {
        code = await streamEvents(file, [
          ...args, '-p', authorPrompt, '--output-format', 'stream-json', '--approval-mode', 'auto_edit', ...model,
        ], {
          cwd: workspace, env: childEnv(), signal, timeout, input,
          timeoutMessage: 'The source agent timed out. Try a smaller change.',
          onStderr(chunk) { if (stderr.length < 4096) stderr += chunk; },
          onEvent(event) {
            onRaw?.(event);
            if (event.type === 'tool_use') {
              flush();
              onProgress(`Gemini started workspace step ${++steps}.\n`);
            } else if (event.type === 'message' && event.role === 'assistant' && typeof event.content === 'string') {
              if (event.delta) buffer += event.content;
              else {
                flush();
                const text = event.content.trim();
                if (text && !authenticationFailure.test(text)) lastMessage = text;
              }
            } else if (event.type === 'error' && event.severity !== 'warning' && typeof event.message === 'string') {
              failure = event.message;
            } else if (event.type === 'result') {
              flush();
              if (event.status === 'error') failure = event.error?.message || failure || 'Gemini did not finish editing the workspace.';
            }
          },
        });
      } catch (error) {
        throw mapFailure(error, signal);
      }
      if (code !== 0 || failure) {
        const detail = `${failure}\n${stderr}`.trim();
        if (authenticationFailure.test(detail)) throw new Error(authMessage);
        throw new Error(failure || 'Gemini did not finish editing the workspace. Check CLI sign-in and local workspace permissions.');
      }
      return lastMessage;
    },
  };
}
