import { createHash } from 'node:crypto';
import { lstat, readFile, readdir, realpath } from 'node:fs/promises';
import path from 'node:path';

export const sourceLimit = 64 * 1024;
const editable = /^world\/(?:scripts\/(?!diagnostics\/)(?:[\w-]+\/)*[\w.-]+\.gd|shaders\/(?:[\w-]+\/)*[\w.-]+\.gdshader(?:inc)?|data\/(?:[\w-]+\/)*[\w.-]+\.json|main\.tscn)$/;
const decode = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true });
export const fingerprint = text => createHash('sha256').update(text).digest('hex');
export const isSourcePath = name => typeof name === 'string' && editable.test(name);
const agentSource = /^world\/(?:scripts\/(?:[\w-]+\/)*[\w.-]+\.gd(?:\.uid)?|scenes\/(?:[\w-]+\/)*[\w.-]+\.tscn)$/;
// The kernel decides what a draft may change, verifies and commits it, isolates its
// checks, and replaces the running gateway. No draft may change it. The launcher,
// check and recovery scripts under scripts/ and the files in the project root are
// outside every draft as well, so a bad change can always be reviewed and undone.
export const kernel = Object.freeze(['gateway/handoff.mjs', 'gateway/preview-base.mjs', 'gateway/workbench-git.mjs',
  'gateway/workbench-runner.mjs', 'gateway/workbench-source.mjs']);
export const isKernelPath = name => kernel.includes(name);
export const isGatewayPath = name => typeof name === 'string' && name.startsWith('gateway/');
const harness = /^(?:gateway\/(?:[\w-]+\/)*[\w.-]+\.(?:mjs|json)|docs\/[\w.-]+\.md|README\.md)$/;
export const isAgentSourcePath = name => isSourcePath(name) ||
  (typeof name === 'string' && (agentSource.test(name) || (harness.test(name) && !isKernelPath(name))));

export async function listSources(root) {
  const files = ['world/main.tscn'];
  async function scan(directory) {
    for (const item of await readdir(path.join(root, directory), { withFileTypes: true })) {
      const name = `${directory}/${item.name}`;
      if (item.isDirectory()) await scan(name);
      else if (item.isFile() && editable.test(name) && (await lstat(path.join(root, name))).size <= sourceLimit) files.push(name);
    }
  }
  for (const directory of ['world/scripts', 'world/shaders', 'world/data']) await scan(directory);
  return files.sort();
}

export async function readSource(root, name) {
  if (!isSourcePath(name)) throw new Error('Choose a source file from the workbench.');
  const base = await realpath(root);
  const file = path.join(base, name);
  const info = await lstat(file);
  if (!info.isFile() || info.size > sourceLimit || await realpath(file) !== file) throw new Error('This source file cannot be edited in the workbench.');
  const text = decode.decode(await readFile(file));
  if (text.includes('\0')) throw new Error('Choose a UTF-8 text file.');
  return { file, text, hash: fingerprint(text) };
}

export function normalizeEdit(original, text, limit = sourceLimit) {
  if (typeof text !== 'string' || text.includes('\0')) throw new Error('An edit must be UTF-8 text.');
  const normalized = text.replace(/\r\n/g, '\n');
  const formatted = original.includes('\r\n') ? normalized.replace(/\n/g, '\r\n') : normalized;
  if (Buffer.byteLength(formatted) > limit) throw new Error(`An edit must fit within ${limit / 1024} KiB.`);
  return formatted;
}

// What a connected agent may read: everything a source draft may change, plus the kernel,
// the project guides and the launcher scripts.
export const agentFileLimit = 256 * 1024;
const reference = /^(?:AGENTS\.md|package\.json|scripts\/[\w.-]+\.(?:ps1|mjs|py|sh))$/;
const isAgentReadable = name => isAgentSourcePath(name) || isKernelPath(name) || (typeof name === 'string' && reference.test(name));

export async function listAgentSources(root) {
  const files = [];
  async function scan(directory) {
    let items;
    try { items = await readdir(path.join(root, directory), { withFileTypes: true }); }
    catch (error) { if (error.code === 'ENOENT') return; throw error; }
    for (const item of items) {
      const name = `${directory}/${item.name}`;
      if (item.isDirectory()) await scan(name);
      else if (item.isFile() && !name.endsWith('.uid') && isAgentReadable(name) &&
        (await lstat(path.join(root, name))).size <= agentFileLimit) files.push(name);
    }
  }
  for (const directory of ['docs', 'gateway', 'scripts', 'world/scripts', 'world/shaders', 'world/data', 'world/scenes']) await scan(directory);
  for (const name of ['README.md', 'AGENTS.md', 'package.json', 'world/main.tscn']) {
    const info = await lstat(path.join(root, name)).catch(error => { if (error.code !== 'ENOENT') throw error; });
    if (info?.isFile() && info.size <= agentFileLimit) files.push(name);
  }
  return files.sort();
}

export async function readAgentSource(root, name) {
  if (!isAgentReadable(name)) throw new Error('Choose a file from list_source.');
  const base = await realpath(root);
  const file = path.join(base, name);
  const info = await lstat(file).catch(error => { if (error.code !== 'ENOENT') throw error; });
  if (!info) throw new Error(`${name} does not exist.`);
  if (!info.isFile() || info.size > agentFileLimit || await realpath(file) !== file) throw new Error('This file cannot be read through the workbench.');
  const text = decode.decode(await readFile(file));
  if (text.includes('\0')) throw new Error('Choose a UTF-8 text file.');
  return { text, hash: fingerprint(text) };
}
