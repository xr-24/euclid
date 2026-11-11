import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { createGateway } from '../server.mjs';

// Echoes typed bytes back, like a shell with nothing else to say.
const echoHost = `
let buffer = Buffer.alloc(0);
process.stdin.on('data', chunk => {
  buffer = Buffer.concat([buffer, chunk]);
  while (buffer.length >= 5 && buffer.length >= 5 + buffer.readUInt32LE(1)) {
    const type = String.fromCharCode(buffer[0]);
    const payload = buffer.subarray(5, 5 + buffer.readUInt32LE(1));
    buffer = buffer.subarray(5 + payload.length);
    if (type === 'x') process.exit(0);
    if (type === 'd') process.stdout.write(payload);
  }
});
process.stdout.write('PS> ');
`;

test('the terminal routes need the Workbench capability and stream a session', async t => {
  const area = await mkdtemp(path.join(os.tmpdir(), 'euclid-terminal-route-'));
  const host = path.join(area, 'host.cjs');
  await writeFile(host, echoHost);
  const workbenchSecret = 'w'.repeat(64);
  const { server } = await createGateway({ dataDir: path.join(area, 'data'), token: 'terminal-test-secret', workbenchToken: workbenchSecret,
    workbenchRoot: area, terminalOptions: { spawnHost: ({ cwd, env }) => spawn(process.execPath, [host], { cwd, env, stdio: ['pipe', 'pipe', 'pipe'] }) } });
  t.after(async () => {
    server.closeAllConnections();
    if (server.listening) await new Promise(resolve => server.close(resolve));
    await rm(area, { recursive: true, force: true });
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const origin = `http://127.0.0.1:${server.address().port}`;
  const call = async (action, body = {}, capability = workbenchSecret) => {
    const response = await fetch(`${origin}/v1/terminal/${action}`, { method: 'POST', body: JSON.stringify(body),
      headers: { Authorization: 'Bearer terminal-test-secret', 'X-Euclid-Workbench': capability, 'Content-Type': 'application/json' } });
    return { status: response.status, body: await response.json() };
  };
  const text = screen => screen.lines.map(line => line.map(run => run[0]).join('')).join('\n');

  assert.equal((await call('open', {}, 'x'.repeat(64))).status, 403);
  const opened = await call('open', { shell: 'powershell', cols: 30, rows: 6 });
  assert.equal(opened.status, 200, JSON.stringify(opened.body));
  const id = opened.body.id;
  let read = await call('read', { id, since: -1, wait: 2000 });
  for (let attempt = 0; attempt < 20 && !text(read.body.screen).includes('PS>'); attempt++) {
    read = await call('read', { id, since: read.body.screen.version, wait: 500 });
  }
  assert.match(text(read.body.screen), /^PS>/);
  const waiting = call('read', { id, since: read.body.screen.version, wait: 5000 });
  assert.equal((await call('write', { id, data: 'dir' })).body.ok, true);
  assert.match(text((await waiting).body.screen), /^PS> dir/, 'a waiting read returns as soon as the shell answers');
  assert.deepEqual([(await call('resize', { id, cols: 40, rows: 8 })).body.cols, (await call('list')).body.sessions.length], [40, 1]);
  assert.equal((await call('write', { id: 'nope', data: 'x' })).status, 400);
  assert.equal((await call('close', { id })).body.ok, true);
  assert.deepEqual((await call('list')).body.sessions, []);
});
