import { spawn } from 'node:child_process';
import { closeSync, openSync } from 'node:fs';
import path from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';

// Replaces the running gateway with a new process on the same port and with the
// same credentials, so the world, agents and launcher files stay valid. The old
// process keeps serving unless the replacement proves it can start, and resumes
// if the replacement fails afterwards. This file is part of the draft kernel.
export const handoffVariable = 'EUCLID_GATEWAY_HANDOFF';
const credential = value => typeof value === 'string' && /^[\w.-]{16,128}$/.test(value);

// Read once by a replacement gateway, then removed so no child process inherits it.
export function inheritedHandoff(env) {
  const text = env[handoffVariable];
  if (!text) return null;
  delete env[handoffVariable];
  let value;
  try { value = JSON.parse(text); } catch { value = null; }
  const { token, workbench_token, development_token, port } = value ?? {};
  if (![token, workbench_token, development_token].every(credential) || !Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error('The gateway handoff is invalid.');
  }
  return { token, workbench_token, development_token, port };
}

function finished(child, timeout) {
  return new Promise(resolve => {
    let output = '';
    child.stderr?.setEncoding('utf8').on('data', chunk => { output = (output + chunk).slice(-600); });
    const timer = setTimeout(() => { child.kill(); resolve({ ok: false, output: 'It did not finish in time.' }); }, timeout);
    child.once('error', error => { clearTimeout(timer); resolve({ ok: false, output: error.message }); });
    child.once('close', code => { clearTimeout(timer); resolve({ ok: code === 0, output: output.trim() }); });
  });
}

async function answers(port, token, child, timeout) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline && child.exitCode === null && child.signalCode === null) {
    try {
      const response = await fetch(`http://127.0.0.1:${port}/v1/world`, { headers: { Authorization: `Bearer ${token}` }, signal: AbortSignal.timeout(1000) });
      if (response.ok) return true;
    } catch {}
    await delay(100);
  }
  return false;
}

export async function listen(server, port, attempts = 1) {
  for (let attempt = 1; ; attempt++) {
    try {
      await new Promise((resolve, reject) => {
        server.once('error', reject);
        server.listen(port, '127.0.0.1', () => { server.off('error', reject); resolve(); });
      });
      return;
    } catch (error) {
      if (error.code !== 'EADDRINUSE' || attempt >= attempts) throw error;
      await delay(150);
    }
  }
}

export function createHandoff({ entry, cwd, port, credentials, server, logDirectory, env = process.env,
  startTimeout = 30000, exit = () => process.exit(0) }) {
  let running = null;
  let notice = '';

  function logFile(name) {
    // The launcher's own log files stay open in the first gateway, so replacements append to their own.
    try { return openSync(path.join(logDirectory, name), 'a'); } catch { return 'ignore'; }
  }

  async function replace() {
    const check = await finished(spawn(process.execPath, [entry, '--preflight'],
      { cwd, env, windowsHide: true, stdio: ['ignore', 'ignore', 'pipe'] }), startTimeout);
    if (!check.ok) throw new Error(`The new gateway code failed its startup check, so the running gateway was kept. ${check.output}`.trim());
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
    const stdio = ['ignore', logFile('gateway-reload.log'), logFile('gateway-reload-error.log')];
    const child = spawn(process.execPath, [entry], { cwd, windowsHide: true, detached: true, stdio,
      env: { ...env, [handoffVariable]: JSON.stringify({ ...credentials, port }) } });
    for (const handle of stdio) if (typeof handle === 'number') closeSync(handle);
    child.once('error', () => {});
    if (await answers(port, credentials.token, child, startTimeout)) {
      child.unref();
      return exit();
    }
    child.kill();
    await listen(server, port, 40);
    throw new Error('The replacement gateway did not start, so the previous gateway resumed. See .local/gateway-reload-error.log.');
  }

  return {
    // Returns at once. The replacement begins after the current response has been sent.
    start() {
      if (running) return;
      notice = '';
      running = delay(250).then(replace).catch(error => { notice = error.message; }).finally(() => { running = null; });
    },
    notice: () => notice,
    settled: () => running ?? Promise.resolve(),
  };
}
