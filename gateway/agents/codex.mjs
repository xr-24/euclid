import { mkdtemp, rmdir, unlink, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { resolveCodexBinary } from '../codex-cli.mjs';
import { agentEnvironment, run, streamEvents, vendorCredentials } from './process.mjs';

const isolated = ['--ignore-user-config', '--ignore-rules', '--skip-git-repo-check', '--ephemeral'];
const offline = ['--disable', 'apps', '--disable', 'plugins', '-c', 'web_search="disabled"',
  '-c', 'project_doc_max_bytes=0', '-c', 'forced_login_method="chatgpt"'];

// The Codex CLI under the local ChatGPT sign-in. API keys are removed so a run
// never bills an API account.
export function createCodexAgent({ env = process.env,
  launcher = async () => ({ file: await resolveCodexBinary(env), args: [] }) } = {}) {
  async function signedIn(signal) {
    const { file, args } = await launcher();
    const childEnv = agentEnvironment(env, [...vendorCredentials.openai, ...vendorCredentials.anthropic]);
    let login;
    try {
      login = await run(file, [...args, 'login', 'status'], { env: childEnv, signal, timeout: 5000 });
    } catch (error) {
      // A request cancelled during the sign-in check is cancelled, not signed out.
      if (signal?.aborted) throw signal.reason ?? error;
      if (['ENOENT', 'ENOTDIR'].includes(error.code)) throw new Error('Install the Codex CLI or set EUCLID_CODEX_BIN to its executable.');
      throw new Error('Sign in to Codex with your ChatGPT account using codex login.');
    }
    if (!/^Logged in using ChatGPT\s*$/im.test(login.stdout + '\n' + login.stderr)) {
      throw new Error('This adapter uses ChatGPT sign-in. Check codex login status.');
    }
    return { file, args, env: childEnv };
  }

  return {
    id: 'codex',
    label: 'Codex',

    // onRaw sees every event of the CLI's stream, for the activity feed.
    async task(input, { url, token, signal, onMessage = () => {}, onRaw }) {
      const { file, args, env: childEnv } = await signedIn(signal);
      const cwd = await mkdtemp(path.join(os.tmpdir(), 'euclid-task-'));
      try {
        let last = '';
        let failure = '';
        const code = await streamEvents(file, [...args, '-a', 'never', 'exec', ...isolated, ...offline,
          '--sandbox', 'read-only', '--disable', 'shell_tool',
          '-c', `mcp_servers.euclid.url=${JSON.stringify(url)}`,
          '-c', 'mcp_servers.euclid.bearer_token_env_var="EUCLID_TASK_TOKEN"',
          '-c', 'mcp_servers.euclid.default_tools_approval_mode="approve"',
          '-c', 'mcp_servers.euclid.tool_timeout_sec=90', '--json', '-',
        ], { cwd, env: { ...childEnv, EUCLID_TASK_TOKEN: token }, signal, timeout: 600000,
          input, timeoutMessage: 'Codex exceeded the ten-minute task limit.',
          onEvent(event) {
            onRaw?.(event);
            if (event.type === 'error' && typeof event.message === 'string') failure = event.message;
            if (event.type === 'turn.failed' && typeof event.error?.message === 'string') failure = event.error.message;
            if (event.type === 'item.completed' && event.item?.type === 'agent_message' && typeof event.item.text === 'string') {
              last = event.item.text;
              onMessage(last);
            }
          },
        });
        if (code !== 0) throw new Error(failure || 'Codex exited before completing the task. Check its sign-in and CLI availability.');
        return last;
      } finally {
        await rmdir(cwd).catch(() => {});
      }
    },

    // One reply that matches a JSON schema. No tools, shell, or network.
    async structured(input, schema, signal) {
      const { file, args, env: childEnv } = await signedIn(signal);
      const cwd = await mkdtemp(path.join(os.tmpdir(), 'euclid-grid-'));
      const generated = typeof schema === 'string' ? null : path.join(cwd, 'output.schema.json');
      try {
        if (generated) await writeFile(generated, JSON.stringify(schema));
        const { stdout } = await run(file, [...args,
          '-a', 'never', 'exec', ...isolated, '--sandbox', 'read-only', '--disable', 'shell_tool', ...offline,
          '--color', 'never', '--output-schema', generated ?? schema, '-',
        ], { cwd, env: childEnv, signal, timeout: 70000 }, input);
        return JSON.parse(stdout);
      } catch {
        throw new Error('Codex could not complete the request. Check your CLI sign-in and plan limits.');
      } finally {
        if (generated) await unlink(generated).catch(() => {});
        await rmdir(cwd).catch(() => {});
      }
    },

    // Edits files inside the workspace and returns the agent's closing message.
    async author(input, { workspace, onProgress, onRaw, signal, timeout }) {
      const { file, args, env: childEnv } = await signedIn(signal);
      let complete = false;
      let message = '';
      let commands = 0;
      const code = await streamEvents(file, [...args,
        '-a', 'never', 'exec', ...isolated, '--sandbox', 'workspace-write', ...offline,
        '-c', 'sandbox_workspace_write.network_access=false', '-c', 'shell_environment_policy.inherit="core"',
        ...(process.platform === 'win32' ? ['-c', 'windows.sandbox="unelevated"'] : []),
        '--color', 'never', '--json', '-',
      ], { cwd: workspace, env: childEnv, signal, timeout, input,
        timeoutMessage: 'The source agent timed out. Try a smaller change.',
        onEvent(event) {
          onRaw?.(event);
          if (event.type === 'turn.completed') complete = true;
          if (event.type !== 'item.completed') return;
          if (event.item?.type === 'command_execution') onProgress(`Codex completed workspace command ${++commands}.\n`);
          else if (event.item?.type === 'agent_message' && typeof event.item.text === 'string') message = event.item.text;
        } });
      if (code !== 0 || !complete) {
        throw new Error('Codex did not finish editing the workspace. Check CLI sign-in and local workspace permissions.');
      }
      return message;
    },
  };
}
