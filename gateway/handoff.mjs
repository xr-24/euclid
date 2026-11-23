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

export async function verifySurvival(port, credentials, { signal } = {}) {
  const origin = `http://127.0.0.1:${port}`;
  const bearer = { Authorization: `Bearer ${credentials?.token ?? ''}` };
  const workbench = { ...bearer, 'X-Euclid-Workbench': credentials?.workbench_token ?? '' };
  const json = { 'Content-Type': 'application/json' };
  const probeSignal = () => (signal ? AbortSignal.any([signal, AbortSignal.timeout(2000)]) : AbortSignal.timeout(2000));
  const checks = [
    ['GET /health', '/health', { method: 'GET' }, 200,
      data => (data?.service === 'construct-gateway' ? '' : 'unexpected service identity')],
    ['GET /v1/world (unauthenticated)', '/v1/world', { method: 'GET' }, 401],
    ['GET /v1/world (authenticated)', '/v1/world', { method: 'GET', headers: bearer }, 200],
    ['POST /v1/workbench/state (no workbench token)', '/v1/workbench/state',
      { method: 'POST', headers: { ...bearer, ...json }, body: '{}' }, 403],
    ['POST /v1/workbench/state (authenticated)', '/v1/workbench/state',
      { method: 'POST', headers: { ...workbench, ...json }, body: '{}' }, 200],
    ['POST /v1/workbench/history (authenticated)', '/v1/workbench/history',
      { method: 'POST', headers: { ...workbench, ...json }, body: '{}' }, 200],
    ['POST /v1/workbench/restore (no workbench token)', '/v1/workbench/restore',
      { method: 'POST', headers: { ...bearer, ...json }, body: '{}' }, 403],
    ['POST /v1/workbench/reload (no workbench token)', '/v1/workbench/reload',
      { method: 'POST', headers: { ...bearer, ...json }, body: '{}' }, 403],
  ];
  for (const [label, url, options, expectedStatus, validate] of checks) {
    let response;
    try {
      response = await fetch(origin + url, { ...options, signal: probeSignal() });
    } catch (error) {
      return { ok: false, reason: `${label}: ${error.message}` };
    }
    if (response.status !== expectedStatus) {
      await response.body?.cancel().catch(() => {});
      return { ok: false, reason: `${label}: expected ${expectedStatus}, got ${response.status}` };
    }
    if (validate) {
      try {
        const problem = validate(await response.json());
        if (problem) return { ok: false, reason: `${label}: ${problem}` };
      } catch (error) {
        return { ok: false, reason: `${label}: invalid JSON (${error.message})` };
      }
    } else {
      await response.body?.cancel().catch(() => {});
    }
  }
  return { ok: true };
}

async function answers(port, credentials, child, timeout) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline && child.exitCode === null && child.signalCode === null) {
    const result = await verifySurvival(port, credentials, { signal: AbortSignal.timeout(1000) });
    if (result.ok) return true;
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
    if (await answers(port, credentials, child, startTimeout)) {
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
