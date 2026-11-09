import { createHash } from 'node:crypto';
import { lstat, readFile, readdir, realpath } from 'node:fs/promises';
import path from 'node:path';

export const sourceLimit = 64 * 1024;
const editable = /^world\/(?:scripts\/(?!diagnostics\/)(?:[\w-]+\/)*[\w.-]+\.gd|shaders\/(?:[\w-]+\/)*[\w.-]+\.gdshader(?:inc)?|data\/(?:[\w-]+\/)*[\w.-]+\.json|main\.tscn)$/;
const decode = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true });
export const fingerprint = text => createHash('sha256').update(text).digest('hex');
export const isSourcePath = name => typeof name === 'string' && editable.test(name);
const agentSource = /^world\/(?:scripts\/(?:[\w-]+\/)*[\w.-]+\.gd(?:\.uid)?|scenes\/(?:[\w-]+\/)*[\w.-]+\.tscn)$/;
export const isAgentSourcePath = name => isSourcePath(name) || (typeof name === 'string' && agentSource.test(name));

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
