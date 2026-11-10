import { execFile, spawn } from 'node:child_process';
import { stat } from 'node:fs/promises';
import path from 'node:path';
import { createInterface } from 'node:readline';

// Euclid's own service credentials. No agent process inherits them.
const euclidSecrets = ['CONSTRUCT_GATEWAY_TOKEN', 'CONSTRUCT_GATEWAY_URL', 'EUCLID_WORKBENCH_TOKEN', 'SKETCHFAB_API_TOKEN'];
export const vendorCredentials = {
  openai: ['OPENAI_API_KEY', 'OPENAI_BASE_URL', 'CODEX_API_KEY', 'CODEX_ACCESS_TOKEN', 'CODEX_OPENAI_BASE_URL'],
  anthropic: ['ANTHROPIC_API_KEY', 'ANTHROPIC_AUTH_TOKEN', 'CLAUDE_CODE_OAUTH_TOKEN'],
};

export function agentEnvironment(env, remove = []) {
  const child = { ...env };
  for (const key of [...euclidSecrets, ...remove]) delete child[key];
  return child;
}

export async function isFile(file) {
  try { return (await stat(file)).isFile(); }
  catch (error) {
    if (['ENOENT', 'ENOTDIR', 'EACCES'].includes(error.code)) return false;
    throw error;
  }
}

export function searchPath(env) {
  const value = Object.entries(env).find(([key]) => key.toLowerCase() === 'path')?.[1] ?? '';
  return value.split(path.delimiter).map(item => item.replace(/^"|"$/g, '')).filter(Boolean);
}

// Runs one short command to completion with the given text on standard input.
export function run(file, args, options, input = '') {
  return new Promise((resolve, reject) => {
    const child = execFile(file, args, { maxBuffer: 256 * 1024, ...options, windowsHide: true },
      (error, stdout, stderr) => error ? reject(error) : resolve({ stdout, stderr }));
    child.stdin.on('error', () => {});
    child.stdin.end(input);
  });
}

// Runs a long agent job and hands each JSON line of its output to onEvent.
// Resolves with the exit code. Abort and timeout stop the whole process tree.
export function streamEvents(file, args, { cwd, env, signal, timeout, timeoutMessage, input = '', onEvent }) {
  signal.throwIfAborted();
  return new Promise((resolve, reject) => {
    const child = spawn(file, args, { cwd, env, windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] });
    let failure;
    const lines = createInterface({ input: child.stdout, crlfDelay: Infinity });
    lines.on('line', line => {
      let event;
      try { event = JSON.parse(line); } catch { return; }
      if (event && typeof event === 'object') onEvent(event);
    });
    child.stderr.resume();
    function stop(error) {
      if (failure) return;
      failure = error;
      if (process.platform === 'win32' && child.pid) {
        const killer = spawn('taskkill.exe', ['/PID', String(child.pid), '/T', '/F'], { windowsHide: true, stdio: 'ignore' });
        killer.once('error', () => child.kill());
      } else child.kill();
    }
    const abort = () => stop(signal.reason);
    signal.addEventListener('abort', abort, { once: true });
    const timer = setTimeout(() => stop(new Error(timeoutMessage)), timeout);
    child.once('error', error => { failure ??= error; });
    child.once('close', code => {
      clearTimeout(timer);
      signal.removeEventListener('abort', abort);
      lines.close();
      if (failure) reject(failure);
      else resolve(code);
    });
    child.stdin.on('error', () => {});
    child.stdin.end(input);
  });
}
