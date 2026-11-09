import { createHash, randomUUID } from 'node:crypto';
import { execFile } from 'node:child_process';
import { lstat, mkdir, readFile, readdir, realpath, rename, rm, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { promisify } from 'node:util';

export const sourceLimit = 64 * 1024;
const execute = promisify(execFile);
const editable = /^world\/(?:scripts\/(?!diagnostics\/)(?:[\w-]+\/)*[\w.-]+\.gd|shaders\/(?:[\w-]+\/)*[\w.-]+\.gdshader(?:inc)?|data\/(?:[\w-]+\/)*[\w.-]+\.json|main\.tscn)$/;
const decode = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true });
export const fingerprint = text => createHash('sha256').update(text).digest('hex');
export const isSourcePath = name => typeof name === 'string' && editable.test(name);

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

export function normalizeEdit(original, text) {
  if (typeof text !== 'string' || text.includes('\0')) throw new Error('An edit must be UTF-8 text.');
  const normalized = text.replace(/\r\n/g, '\n');
  const formatted = original.includes('\r\n') ? normalized.replace(/\n/g, '\r\n') : normalized;
  if (Buffer.byteLength(formatted) > sourceLimit) throw new Error('An edit must fit within 64 KiB.');
  return formatted;
}

export async function reviewDiff(directory, name, before, after) {
  const left = path.join(directory, 'before', name);
  const right = path.join(directory, 'after', name);
  await mkdir(path.dirname(left), { recursive: true });
  await mkdir(path.dirname(right), { recursive: true });
  await Promise.all([writeFile(left, before), writeFile(right, after)]);
  try {
    const { stdout } = await execute('git', ['-c', 'core.autocrlf=false', 'diff', '--no-index', '--no-ext-diff', '--no-textconv', '--no-color', '--', `before/${name}`, `after/${name}`],
      { cwd: directory, windowsHide: true, timeout: 5000, maxBuffer: 256 * 1024 });
    return stdout;
  } catch (error) {
    if (error.code === 1 && error.stdout) return error.stdout;
    throw new Error('Git could not produce the review diff.');
  }
}

export async function replaceSource(root, name, expected, text) {
  const current = await readSource(root, name);
  if (current.hash !== expected) throw new Error('The source changed on disk. Reopen it before applying or restoring.');
  const temporary = `${current.file}.${randomUUID()}.tmp`;
  await writeFile(temporary, text, { flag: 'wx' });
  try {
    if ((await readSource(root, name)).hash !== expected) throw new Error('The source changed on disk. Reopen it before applying or restoring.');
    await rename(temporary, current.file);
  } finally {
    await rm(temporary, { force: true });
  }
}
