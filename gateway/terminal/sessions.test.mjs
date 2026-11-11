import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { createTerminalSessions, frame, terminalEnvironment } from './sessions.mjs';

// A stand-in for conpty-host.ps1: it reads the same frames and behaves like a tiny shell.
const fakeHost = `
const out = process.stdout;
out.write('ready\\x1b[6n');
let buffer = Buffer.alloc(0);
let line = '';
process.stdin.on('data', chunk => {
  buffer = Buffer.concat([buffer, chunk]);
  while (buffer.length >= 5) {
    const type = String.fromCharCode(buffer[0]);
    const length = buffer.readUInt32LE(1);
    if (buffer.length < 5 + length) return;
    const payload = buffer.subarray(5, 5 + length);
    buffer = buffer.subarray(5 + length);
    if (type === 'x') process.exit(0);
    if (type === 'r') out.write('[size ' + payload.readUInt16LE(0) + 'x' + payload.readUInt16LE(2) + ']\\r\\n');
    if (type === 'd') {
      const text = payload.toString();
      if (text.startsWith('\\x1b[')) { out.write(' cpr' + JSON.stringify(text) + '\\r\\n> '); continue; }
      for (const ch of text) {
        if (ch === '\\r') { out.write('\\r\\n' + (line === 'exit' ? '' : 'ran ' + line + '\\r\\n> ')); if (line === 'exit') process.exit(3); line = ''; }
        else { line += ch; out.write(ch); }
      }
    }
  }
});
process.stdin.on('end', () => process.exit(9));
out.write(JSON.stringify(Object.keys(process.env).filter(name => /TOKEN|HANDOFF/.test(name))) + '\\r\\n');
`;

async function sessions(t, options = {}) {
  const area = await mkdtemp(path.join(os.tmpdir(), 'euclid-terminal-'));
  const script = path.join(area, 'host.cjs');
  await writeFile(script, fakeHost);
  const spawned = [];
  const manager = createTerminalSessions({ root: area, env: { PATH: process.env.PATH, CONSTRUCT_GATEWAY_TOKEN: 'secret',
    EUCLID_WORKBENCH_TOKEN: 'secret', EUCLID_GATEWAY_HANDOFF: '{}', OPENAI_API_KEY: 'kept' },
  spawnHost: ({ cwd, env }) => {
    const child = spawn(process.execPath, [script], { cwd, env, stdio: ['pipe', 'pipe', 'pipe'] });
    spawned.push(child);
    return child;
  }, ...options });
  t.after(async () => {
    manager.closeAll();
    for (const child of spawned) if (child.exitCode === null) child.kill();
    await rm(area, { recursive: true, force: true, maxRetries: 10, retryDelay: 100 });
  });
  return manager;
}

const screenText = result => result.screen.lines.map(line => line.map(run => run[0]).join('')).join('\n');
async function until(manager, id, test, since = -1) {
  let result;
  for (let attempt = 0; attempt < 40; attempt++) {
    result = await manager.read(id, { since, wait: 250 });
    if (test(result)) return result;
    since = result.screen.version;
  }
  assert.fail(`The terminal never showed what was expected:\n${screenText(result)}`);
}

test('a session relays keystrokes, answers cursor queries, and keeps the gateway credentials out', async t => {
  const manager = await sessions(t);
  const opened = manager.open({ shell: 'powershell', cols: 40, rows: 8 });
  assert.deepEqual([opened.alive, opened.cols, opened.rows], [true, 40, 8]);
  let result = await until(manager, opened.id, value => screenText(value).includes('cpr'));
  assert.match(screenText(result), /cpr"\\u001b\[1;6R"/, 'the cursor position report goes back to the program');
  assert.match(screenText(result), /^ready\[\]/, 'no gateway credential reaches the shell');
  manager.write(opened.id, 'git status\r');
  result = await until(manager, opened.id, value => screenText(value).includes('ran git status'), result.screen.version);
  const resized = manager.resize(opened.id, 60, 10);
  assert.deepEqual([resized.cols, resized.rows], [60, 10]);
  result = await until(manager, opened.id, value => screenText(value).includes('[size 60x10]'));
  assert.equal(manager.list().length, 1);
  manager.write(opened.id, 'exit\r');
  result = await until(manager, opened.id, value => !value.alive);
  assert.equal(result.exit_code, 3);
  assert.match(screenText(result), /\[The terminal host could not start|exited with code 3/);
  assert.throws(() => manager.write(opened.id, 'more'), /has ended/);
  manager.close(opened.id);
  await assert.rejects(manager.read(opened.id), /no terminal session/);
});

test('reads wait for a newer screen, and sessions are limited and validated', async t => {
  const manager = await sessions(t, { maxSessions: 2 });
  const first = manager.open();
  const seen = await until(manager, first.id, value => screenText(value).includes('cpr'));
  const started = Date.now();
  const quiet = await manager.read(first.id, { since: seen.screen.version, wait: 300 });
  assert.ok(Date.now() - started >= 250, 'a read with nothing new waits');
  assert.equal(quiet.screen.version, seen.screen.version);
  const pending = manager.read(first.id, { since: seen.screen.version, wait: 5000 });
  manager.write(first.id, 'x');
  assert.ok((await pending).screen.version > seen.screen.version, 'new output wakes a waiting read at once');
  manager.open({ shell: 'cmd' });
  assert.throws(() => manager.open(), /at most 2 open/);
  assert.throws(() => manager.open({ shell: 'bash' }), /Choose a shell/);
  assert.throws(() => manager.write(first.id, ''), /1 byte to 64 KiB/);
  assert.throws(() => manager.write('not-an-id', 'x'), /no terminal session/);
  assert.throws(() => createTerminalSessions({ root: '.', spawnHost: null }).open(), /needs Windows ConPTY/);
});

test('frames and the shell environment follow the host protocol', () => {
  assert.deepEqual([...frame('r', Buffer.from([1, 2, 3, 4]))], [0x72, 4, 0, 0, 0, 1, 2, 3, 4]);
  assert.deepEqual([...frame('x')], [0x78, 0, 0, 0, 0]);
  assert.deepEqual(Object.keys(terminalEnvironment({ CONSTRUCT_GATEWAY_TOKEN: 1, euclid_workbench_token: 1, EUCLID_GATEWAY_HANDOFF: 1,
    OPENAI_API_KEY: 1, PATH: 1 })).sort(), ['OPENAI_API_KEY', 'PATH', 'TERM']);
  assert.equal(terminalEnvironment({ Term: 'dumb' }).TERM, 'xterm-256color');
});
