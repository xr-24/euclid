import { mkdtemp, readFile, rmdir } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { agentEnvironment, isFile, run, searchPath, streamEvents, vendorCredentials } from './process.mjs';

// Windows passes the schema on the command line, which holds about 32,000 characters.
const schemaLimit = 24000;
// No user or project customizations, no MCP servers, and nothing saved to disk.
const isolated = ['--safe-mode', '--strict-mcp-config', '--disallowedTools', 'mcp__*', '--no-session-persistence'];
const planPrompt = 'Follow the instructions and input supplied on standard input. Reply only with the structured output.';
const authorPrompt = 'Carry out the instructions supplied on standard input in the current directory.';

export async function resolveClaudeBinary(env = process.env) {
  if (env.EUCLID_CLAUDE_BIN) return env.EUCLID_CLAUDE_BIN;
  if (process.platform !== 'win32') return 'claude';
  // Node's execFile cannot launch npm's .cmd shim, so look for the native executable.
  const directories = searchPath(env);
  if (env.USERPROFILE) directories.push(path.join(env.USERPROFILE, '.local', 'bin'));
  for (const directory of directories) {
    const native = path.join(directory, 'claude.exe');
    if (await isFile(native)) return native;
  }
  throw new Error('Install Claude Code or set EUCLID_CLAUDE_BIN to its executable.');
}

// Claude Code in non-interactive mode, under whichever sign-in the local
// installation already uses. EUCLID_CLAUDE_MODEL optionally picks the model.
export function createClaudeAgent({ env = process.env,
  launcher = async () => ({ file: await resolveClaudeBinary(env), args: [] }) } = {}) {
  const model = env.EUCLID_CLAUDE_MODEL ? ['--model', env.EUCLID_CLAUDE_MODEL] : [];

  async function signedIn(signal) {
    const { file, args } = await launcher();
    const childEnv = agentEnvironment(env, vendorCredentials.openai);
    try {
      await run(file, [...args, 'auth', 'status'], { env: childEnv, signal, timeout: 10000 });
    } catch (error) {
      // A request cancelled during the sign-in check is cancelled, not signed out.
      if (signal?.aborted) throw signal.reason ?? error;
      if (['ENOENT', 'ENOTDIR'].includes(error.code)) throw new Error('Install Claude Code or set EUCLID_CLAUDE_BIN to its executable.');
      throw new Error('Sign in to Claude Code using claude auth login.');
    }
    return { file, args, env: childEnv };
  }

  return {
    id: 'claude',
    label: 'Claude',

    // One reply that matches a JSON schema. Every built-in and MCP tool is removed.
    async structured(input, schema, signal) {
      const { file, args, env: childEnv } = await signedIn(signal);
      const definition = JSON.stringify(typeof schema === 'string' ? JSON.parse(await readFile(schema, 'utf8')) : schema);
      if (definition.length > schemaLimit) throw new Error('This request’s command catalog is too large for the Claude Code adapter.');
      const cwd = await mkdtemp(path.join(os.tmpdir(), 'euclid-plan-'));
      try {
        const { stdout } = await run(file, [...args, '-p', '--output-format', 'json', '--json-schema', definition,
          '--tools', '', ...isolated, '--permission-mode', 'dontAsk', ...model, planPrompt,
        ], { cwd, env: childEnv, signal, timeout: 70000, maxBuffer: 1024 * 1024 }, input);
        const reply = JSON.parse(stdout);
        const value = reply?.structured_output;
        if (reply.is_error || value === null || typeof value !== 'object') throw new Error('No structured output.');
        return value;
      } catch {
        throw new Error('Claude Code could not complete the request. Check claude auth status and your plan limits.');
      } finally {
        await rmdir(cwd).catch(() => {});
      }
    },

    // Edits files inside the workspace and returns the agent's closing message.
    // Restricted mode confines the file tools to the workspace; no tool runs commands.
    async author(input, { workspace, onProgress, signal, timeout }) {
      const { file, args, env: childEnv } = await signedIn(signal);
      let result = null;
      let steps = 0;
      const code = await streamEvents(file, [...args, '-p', '--output-format', 'stream-json', '--verbose', '--restricted',
        '--tools', 'Read,Edit,Write,Glob,Grep', ...isolated, '--permission-mode', 'acceptEdits', ...model, authorPrompt,
      ], { cwd: workspace, env: childEnv, signal, timeout, input,
        timeoutMessage: 'The source agent timed out. Try a smaller change.',
        onEvent(event) {
          if (event.type === 'result') result = event;
          if (event.type !== 'assistant' || !Array.isArray(event.message?.content)) return;
          for (const block of event.message.content) {
            if (block?.type === 'tool_use') onProgress(`Claude started workspace step ${++steps}.\n`);
          }
        } });
      if (code !== 0 || result?.subtype !== 'success' || result.is_error) {
        throw new Error('Claude Code did not finish editing the workspace. Check claude auth status and local workspace permissions.');
      }
      return typeof result.result === 'string' ? result.result : '';
    },
  };
}
