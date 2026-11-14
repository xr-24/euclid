import { spawn } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { createScreen } from './screen.mjs';

// Interactive shells for the person, kept by the gateway so they outlive a restart of the world.
// Each session runs a shell under Windows ConPTY through conpty-host.ps1 and keeps its screen in a
// headless emulator; the world draws snapshots and sends keystrokes. Sessions end when the gateway
// process is replaced, because the host ends its shell when its input closes.
const hostScript = fileURLToPath(new URL('./conpty-host.ps1', import.meta.url));
export const shells = Object.freeze({ powershell: 'powershell.exe -NoLogo', pwsh: 'pwsh.exe -NoLogo', cmd: 'cmd.exe' });
const sessionId = /^[a-f0-9-]{36}$/;

export function frame(type, payload = Buffer.alloc(0)) {
  const header = Buffer.alloc(5);
  header.write(type, 0, 'latin1');
  header.writeUInt32LE(payload.length, 1);
  return Buffer.concat([header, payload]);
}

// The person's own shell keeps their environment, but never the gateway's credentials.
export function terminalEnvironment(env) {
  const result = { ...env };
  for (const name of Object.keys(result)) {
    if (/^(?:CONSTRUCT_GATEWAY_TOKEN|EUCLID_WORKBENCH_TOKEN|EUCLID_GATEWAY_HANDOFF|EUCLID_DEVELOPMENT_TOKEN|ELEVENLABS_API_KEY)$/i.test(name)) delete result[name];
  }
  for (const name of Object.keys(result)) {
    if (name.toUpperCase() === 'TERM') delete result[name];
  }
  result.TERM = 'xterm-256color';
  return result;
}

function windowsHost({ commandLine, cwd, cols, rows, env }) {
  return spawn('powershell.exe', ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', hostScript,
    '-CommandLine', commandLine, '-Cwd', cwd, '-Cols', String(cols), '-Rows', String(rows)],
  { cwd, env, windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] });
}

export function createTerminalSessions({ root, spawnHost = process.platform === 'win32' ? windowsHost : null,
  env = process.env, maxSessions = 4, scrollback = 2000 } = {}) {
  const sessions = new Map();

  function describe(session) {
    const { cols, rows } = session.screen.size;
    return { id: session.id, shell: session.shell, alive: session.alive, exit_code: session.exitCode, exit_error: session.error,
      title: session.screen.snapshot().title, cols, rows, created_at: session.created };
  }

  function notify(session) {
    for (const wake of session.waiters) wake();
    session.waiters.clear();
  }

  function send(session, type, payload) {
    if (session.alive && session.child.stdin.writable) session.child.stdin.write(frame(type, payload));
  }

  function sessionFor(id) {
    const session = typeof id === 'string' && sessionId.test(id) ? sessions.get(id) : undefined;
    if (!session) throw new Error('There is no terminal session with that id.');
    return session;
  }

  function finished(session, code, message = '') {
    if (!session.alive) return;
    session.alive = false;
    session.exitCode = code;
    session.error = message;
    session.screen.write(`\r\n\x1b[2m[${message || `The shell exited with code ${code}.`}]\x1b[0m\r\n`);
    notify(session);
  }

  return {
    open({ shell = 'powershell', cols = 120, rows = 32 } = {}) {
      if (!spawnHost) throw new Error('The embedded terminal needs Windows ConPTY.');
      if (!Object.hasOwn(shells, shell)) throw new Error(`Choose a shell: ${Object.keys(shells).join(', ')}.`);
      if ([...sessions.values()].filter(item => item.alive).length >= maxSessions) {
        throw new Error(`Close a terminal first. Euclid keeps at most ${maxSessions} open.`);
      }
      const screen = createScreen({ cols: Number(cols) || 120, rows: Number(rows) || 32, scrollback });
      const { cols: width, rows: height } = screen.size;
      const child = spawnHost({ commandLine: shells[shell], cwd: root, cols: width, rows: height, env: terminalEnvironment(env) });
      const session = { id: randomUUID(), shell, child, screen, alive: true, exitCode: null, error: '', created: new Date().toISOString(),
        waiters: new Set(), stderr: '' };
      sessions.set(session.id, session);
      child.stdin.on('error', () => {});
      child.stdout.on('data', chunk => {
        screen.write(chunk);
        for (const reply of screen.takeReplies()) send(session, 'd', Buffer.from(reply));
        notify(session);
      });
      child.stderr.setEncoding('utf8');
      child.stderr.on('data', chunk => { session.stderr = (session.stderr + chunk).slice(-2000); });
      child.on('error', error => finished(session, null, `The terminal host could not start: ${error.message}`));
      child.on('exit', code => finished(session, code, code === 0 ? '' : session.stderr.trim().split('\n').pop() ?? ''));
      return describe(session);
    },

    list: () => [...sessions.values()].map(describe),

    write(id, data) {
      const session = sessionFor(id);
      if (!session.alive) throw new Error('This terminal has ended. Open a new one.');
      if (typeof data !== 'string' || !data.length || Buffer.byteLength(data) > 64 * 1024) throw new Error('Send 1 byte to 64 KiB of input.');
      send(session, 'd', Buffer.from(data, 'utf8'));
      return { ok: true };
    },

    resize(id, cols, rows) {
      const session = sessionFor(id);
      session.screen.resize(Number(cols) || 0, Number(rows) || 0);
      const size = session.screen.size;
      const payload = Buffer.alloc(4);
      payload.writeUInt16LE(size.cols, 0);
      payload.writeUInt16LE(size.rows, 2);
      send(session, 'r', payload);
      notify(session);
      return describe(session);
    },

    // Waits up to `wait` ms for a screen newer than `since`, then returns the session and its screen.
    async read(id, { since = -1, wait = 0, offset = 0, signal } = {}) {
      const session = sessionFor(id);
      const limit = Math.max(0, Math.min(25000, Number(wait) || 0));
      if (session.screen.version <= since && session.alive && limit > 0) {
        await new Promise(resolve => {
          const timer = setTimeout(done, limit);
          function done() {
            clearTimeout(timer);
            session.waiters.delete(done);
            signal?.removeEventListener('abort', done);
            resolve();
          }
          session.waiters.add(done);
          signal?.addEventListener('abort', done, { once: true });
        });
      }
      return { ...describe(session), screen: session.screen.snapshot(Number(offset) || 0) };
    },

    close(id) {
      const session = sessionFor(id);
      sessions.delete(id);
      if (session.alive) {
        send(session, 'x');
        session.child.stdin.end();
        const timer = setTimeout(() => { if (session.alive) session.child.kill(); }, 2000);
        timer.unref?.();
      }
      notify(session);
      return { ok: true };
    },

    closeAll() {
      for (const id of [...sessions.keys()]) this.close(id);
    },
  };
}
