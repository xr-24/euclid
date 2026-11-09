import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { resolveCodexBinary } from './codex-cli.mjs';

test('explicit Codex executable overrides discovery', async () => {
  const file = path.join(os.tmpdir(), 'custom codex', 'codex.exe');
  assert.equal(await resolveCodexBinary({ EUCLID_CODEX_BIN: file }), file);
});

test('Windows discovers native Codex without a fresh desktop PATH', { skip: process.platform !== 'win32' }, async t => {
  const folder = await mkdtemp(path.join(os.tmpdir(), 'euclid-codex-'));
  t.after(() => rm(folder, { recursive: true, force: true }));
  const appData = path.join(folder, 'Roaming');
  const localData = path.join(folder, 'Local');
  const env = { PATH: path.join(folder, 'empty-path'), APPDATA: appData, LOCALAPPDATA: localData };
  async function touch(file) {
    await mkdir(path.dirname(file), { recursive: true });
    await writeFile(file, 'discovery fixture, never execute');
  }
  const desktop = path.join(localData, 'OpenAI', 'Codex', 'bin', 'installed-build', 'codex.exe');
  await touch(desktop);
  assert.equal(await resolveCodexBinary(env), desktop);

  const triple = process.arch === 'arm64' ? 'aarch64-pc-windows-msvc' : 'x86_64-pc-windows-msvc';
  const npm = path.join(appData, 'npm', 'node_modules', '@openai', 'codex', 'node_modules',
    '@openai', `codex-win32-${process.arch}`, 'vendor', triple, 'bin', 'codex.exe');
  await touch(path.join(appData, 'npm', 'codex.cmd'));
  await touch(npm);
  assert.equal(await resolveCodexBinary(env), npm);

  const native = path.join(env.PATH, 'codex.exe');
  await touch(native);
  assert.equal(await resolveCodexBinary(env), native);
  assert.equal(await resolveCodexBinary({ Path: env.PATH }), native);
  await assert.rejects(resolveCodexBinary({ PATH: folder }), /Install the Codex CLI/);
});
