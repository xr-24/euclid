import { createHash } from 'node:crypto';
import { cp, lstat, mkdir, mkdtemp, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { isAgentSourcePath, normalizeEdit, sourceLimit } from './workbench-source.mjs';

export const sourceDraftLimit = 24;
const workspaceLimit = 32 * 1024 * 1024;
const decoder = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true });

async function inventory(root, signal) {
  const files = new Map();
  let entries = 0;
  let bytes = 0;
  async function scan(directory, relative) {
    for (const item of await readdir(directory, { withFileTypes: true })) {
      signal.throwIfAborted();
      if (++entries > 4096) throw new Error('The source workspace has too many entries.');
      const name = relative ? relative + '/' + item.name : item.name;
      const file = path.join(directory, item.name);
      const info = await lstat(file);
      if (info.isDirectory()) {
        await scan(file, name);
      } else {
        if (!info.isFile() || info.nlink !== 1) throw new Error('The source workspace contains a link or special file.');
        bytes += info.size;
        if (bytes > workspaceLimit) throw new Error('The source workspace exceeds 32 MiB.');
        files.set(name, createHash('sha256').update(await readFile(file)).digest('hex'));
      }
    }
  }
  await scan(root, '');
  return files;
}

async function readText(file) {
  const bytes = await readFile(file);
  if (bytes.length > sourceLimit) throw new Error('Each edited source file must fit within 64 KiB.');
  return decoder.decode(bytes);
}

export async function writeAgentDraft({ worktree, request, author, onProgress, signal, intent }) {
  const workspace = await mkdtemp(path.join(os.tmpdir(), 'euclid-source-'));
  try {
    // The worker gets source bytes from the pinned checkout. Its writable directory
    // sits outside the primary repo and carries no Git metadata or local assets.
    await cp(worktree, workspace, { recursive: true, filter: source => {
      signal.throwIfAborted();
      return path.relative(worktree, source) !== '.git';
    } });
    const before = await inventory(workspace, signal);
    const summary = await author({ workspace, request, onProgress, signal });
    const after = await inventory(workspace, signal);
    const changed = [...new Set([...before.keys(), ...after.keys()])].filter(name => before.get(name) !== after.get(name)).sort();
    if (changed.length > sourceDraftLimit) throw new Error(`Split the request into drafts of up to ${sourceDraftLimit} files.`);
    const names = [];
    const added = [];
    for (const name of changed) {
      signal.throwIfAborted();
      if (!isAgentSourcePath(name)) throw new Error(`The source agent changed a path outside the draft scope: ${name}`);
      const destination = path.join(worktree, name);
      if (after.has(name)) {
        const original = before.has(name) ? await readText(destination) : '';
        const text = normalizeEdit(original, await readText(path.join(workspace, name)));
        if (before.has(name) && text === original) continue;
        await mkdir(path.dirname(destination), { recursive: true });
        await writeFile(destination, text, { flag: before.has(name) ? 'w' : 'wx' });
        if (!before.has(name)) added.push(name);
      } else {
        await rm(destination);
      }
      names.push(name);
    }
    if (!names.length) throw new Error('Codex returned without a source change.');
    if (added.length) await intent(added);
    return { names, summary: typeof summary === 'string' ? summary.slice(0, 640) : '' };
  } finally {
    await rm(workspace, { recursive: true, force: true });
  }
}
