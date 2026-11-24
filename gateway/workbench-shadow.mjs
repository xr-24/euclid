import { spawn } from 'node:child_process';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { createInterface } from 'node:readline';
import { redact } from './agent-activity.mjs';
import { fingerprint, isGatewayPath } from './workbench-source.mjs';

const secretEnv = /^(?:CONSTRUCT_|EUCLID_|SKETCHFAB_|OPENAI_|CODEX_|ANTHROPIC_|GEMINI_API_KEY|GOOGLE_API_KEY|ELEVENLABS_|NODE_TEST_CONTEXT$)/i;
const allowedPath = /^\/(?:health|v1\/|mcp\/dev(?:\/|$)|mcp\/agent$)/;

function strippedEnv(extra = {}) {
  const env = {};
  for (const [key, value] of Object.entries(process.env)) {
    if (!secretEnv.test(key)) env[key] = value;
  }
  return { ...env, ...extra };
}

function killChild(child) {
  if (!child || child.exitCode !== null || child.signalCode !== null) return;
  if (process.platform === 'win32' && child.pid) {
    const killer = spawn('taskkill.exe', ['/PID', String(child.pid), '/T', '/F'], { windowsHide: true, stdio: 'ignore' });
    killer.on('error', () => { try { child.kill(); } catch {} });
  } else {
    try { child.kill(); } catch {}
  }
}

function terminate(child, waitMs = 3000) {
  if (!child || child.exitCode !== null || child.signalCode !== null) return Promise.resolve();
  return new Promise(resolve => {
    const done = () => { clearTimeout(timer); resolve(); };
    const timer = setTimeout(done, waitMs);
    timer.unref?.();
    child.once('close', done);
    killChild(child);
  });
}

function runPreflight(entry, cwd, timeout, signal) {
  signal?.throwIfAborted();
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [entry, '--preflight'], {
      cwd, env: strippedEnv(), windowsHide: true, stdio: ['ignore', 'ignore', 'pipe'],
    });
    let stderr = '';
    let failure;
    child.stderr.setEncoding('utf8');
    child.stderr.on('data', chunk => { stderr = (stderr + chunk).slice(-4096); });
    const fail = error => {
      if (failure) return;
      failure = error;
      killChild(child);
    };
    const abort = () => fail(signal.reason instanceof Error ? signal.reason : new Error(String(signal.reason || 'Aborted')));
    const timer = setTimeout(() => fail(new Error(`Shadow gateway preflight timed out after ${timeout / 1000} seconds.`)), timeout);
    timer.unref?.();
    signal?.addEventListener('abort', abort, { once: true });
    child.once('error', error => {
      clearTimeout(timer);
      signal?.removeEventListener('abort', abort);
      reject(error);
    });
    child.once('close', code => {
      clearTimeout(timer);
      signal?.removeEventListener('abort', abort);
      if (failure) return reject(failure);
      if (code !== 0) return reject(new Error(`Shadow gateway preflight failed: ${redact(stderr).slice(-800)}`));
      resolve();
    });
  });
}

function waitForReady(child, getStderr, timeout, signal) {
  return new Promise((resolve, reject) => {
    const rl = createInterface({ input: child.stdout, crlfDelay: Infinity });
    let settled = false;
    const finish = fn => value => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      signal?.removeEventListener('abort', onAbort);
      child.off('error', onError);
      child.off('exit', onExit);
      rl.close();
      fn(value);
    };
    const ok = finish(resolve);
    const fail = finish(reject);
    const onAbort = () => fail(signal.reason instanceof Error ? signal.reason : new Error(String(signal.reason || 'Aborted')));
    const onError = error => fail(error);
    const onExit = code => fail(new Error(`Shadow gateway exited (${code ?? 'signal'}) before ready: ${redact(getStderr()).slice(-800)}`));
    const timer = setTimeout(() => fail(new Error(`Shadow gateway did not become ready within ${timeout / 1000} seconds.`)), timeout);
    timer.unref?.();
    signal?.addEventListener('abort', onAbort, { once: true });
    child.once('error', onError);
    child.once('exit', onExit);
    rl.on('error', () => {});
    rl.on('line', line => {
      let parsed;
      try { parsed = JSON.parse(line); } catch { return; }
      if (parsed?.shadow_ready === true && Number.isInteger(parsed.port) && parsed.port > 0) ok(parsed.port);
    });
  });
}

export function createShadowPreview({ idleMs = 120_000, preflightTimeout = 20_000, startTimeout = 15_000 } = {}) {
  let active = null;

  function touch() {
    if (!active) return;
    if (active.timer) clearTimeout(active.timer);
    active.timer = setTimeout(() => { void stop(); }, idleMs);
    active.timer.unref?.();
  }

  async function stop(draftId) {
    if (!active) return { ok: true, stopped: false };
    if (draftId && active.draftId !== draftId) return { ok: true, stopped: false };
    const current = active;
    active = null;
    if (current.timer) clearTimeout(current.timer);
    await terminate(current.child, 3000);
    await rm(current.dataDir, { recursive: true, force: true }).catch(() => {});
    return { ok: true, stopped: true };
  }

  async function start(draft, signal) {
    signal?.throwIfAborted();
    if (!draft?.names?.some(isGatewayPath)) {
      throw new Error('Previewing the shadow gateway requires a draft that changes gateway/ files.');
    }
    await stop();
    const entry = path.join(draft.worktree, 'gateway/server.mjs');
    await runPreflight(entry, draft.worktree, preflightTimeout, signal);
    signal?.throwIfAborted();

    const dataDir = await mkdtemp(path.join(os.tmpdir(), 'euclid-shadow-'));
    let child;
    let stderr = '';
    const getStderr = () => redact(stderr.slice(-4096));
    try {
      child = spawn(process.execPath, [entry], {
        cwd: draft.worktree,
        env: strippedEnv({ EUCLID_SHADOW_PREVIEW: '1', EUCLID_DATA_DIR: dataDir }),
        windowsHide: true,
        stdio: ['ignore', 'pipe', 'pipe'],
      });
      child.stderr.setEncoding('utf8');
      child.stderr.on('data', chunk => { stderr = (stderr + chunk).slice(-4096); });
      const port = await waitForReady(child, getStderr, startTimeout, signal);
      const { token, workbench_token, development_token } = JSON.parse(
        await readFile(path.join(dataDir, 'gateway.json'), 'utf8'),
      );
      active = {
        draftId: draft.id,
        version: fingerprint(draft.diff),
        child,
        port,
        dataDir,
        tokens: { token, workbench_token, development_token },
        getStderr,
        timer: null,
      };
      child.once('exit', () => {
        if (active?.child === child) {
          const current = active;
          active = null;
          if (current.timer) clearTimeout(current.timer);
          void rm(current.dataDir, { recursive: true, force: true }).catch(() => {});
        }
      });
      touch();
      return { ok: true, running: true, draft: active.draftId, version: active.version, port: active.port, stderr: active.getStderr() };
    } catch (error) {
      await terminate(child, 3000);
      await rm(dataDir, { recursive: true, force: true }).catch(() => {});
      throw error;
    }
  }

  async function call(draft, { method = 'GET', path: reqPath = '/health', body, auth = 'bearer' } = {}, signal) {
    if (!active || active.draftId !== draft.id || active.version !== fingerprint(draft.diff)) {
      throw new Error('Start the shadow gateway for this draft version first.');
    }
    touch();
    if (method !== 'GET' && method !== 'POST') throw new Error('Shadow gateway method must be GET or POST.');
    if (typeof reqPath !== 'string' || !reqPath.startsWith('/') || reqPath.includes('..') || reqPath.includes('\\') || !allowedPath.test(reqPath)) {
      throw new Error('Invalid shadow gateway path.');
    }
    if (!['none', 'bearer', 'workbench'].includes(auth)) throw new Error('Invalid shadow gateway auth mode.');
    const resolved = reqPath === '/mcp/dev'
      ? `/mcp/dev/${active.tokens.development_token}/shadow-probe`
      : reqPath.replaceAll('{{dev_token}}', active.tokens.development_token);
    const headers = auth === 'none' ? {}
      : auth === 'bearer' ? { Authorization: `Bearer ${active.tokens.token}` }
      : { Authorization: `Bearer ${active.tokens.token}`, 'X-Euclid-Workbench': active.tokens.workbench_token };
    const options = {
      method,
      headers,
      signal: signal ? AbortSignal.any([signal, AbortSignal.timeout(10000)]) : AbortSignal.timeout(10000),
    };
    if (method === 'POST' && body !== undefined) {
      options.headers['Content-Type'] = 'application/json';
      options.body = JSON.stringify(body);
    }
    const response = await fetch(`http://127.0.0.1:${active.port}${resolved}`, options);
    const raw = await response.text();
    let responseBody;
    if ((response.headers.get('content-type') ?? '').includes('application/json')) {
      try { responseBody = JSON.parse(raw); } catch { responseBody = raw.slice(0, 16000); }
    } else {
      responseBody = raw.slice(0, 16000);
    }
    return { ok: true, status: response.status, body: responseBody, stderr: active.getStderr() };
  }

  function status(draft) {
    if (!active || active.draftId !== draft.id) return { ok: true, running: false };
    return {
      ok: true,
      running: true,
      draft: active.draftId,
      version: active.version,
      stale: active.version !== fingerprint(draft.diff),
      port: active.port,
      stderr: active.getStderr(),
    };
  }

  return { start, call, stop, status };
}
