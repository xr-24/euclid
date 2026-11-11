import { constants } from 'node:fs';
import { copyFile, link, lstat, mkdir, readdir, rename, rm, statfs, utimes } from 'node:fs/promises';
import path from 'node:path';

// The local art pack and Godot's import cache are about 2 GiB, too much to copy for
// every check. The runner keeps one private copy of them, the base, and hard-links
// its files into each disposable preview. The primary checkout is only ever read. A
// preview that writes through a link changes the base, never the user's project,
// and the next sync sees the changed size or time and replaces that file.
export const baseSources = Object.freeze(['world/assets', 'world/.godot/imported', 'world/.godot/uid_cache.bin']);
const partialSuffix = '.euclid-partial';
const reserve = 512 * 1024 ** 2;
const gib = bytes => (bytes / 1024 ** 3).toFixed(2);
const same = (a, b) => Boolean(b) && a.size === b.size && Math.trunc(a.mtimeMs) === Math.trunc(b.mtimeMs);

async function walk(root, name, signal, files) {
  signal?.throwIfAborted();
  let info;
  try { info = await lstat(path.join(root, name)); }
  catch (error) { if (error.code === 'ENOENT') return; throw error; }
  if (info.isSymbolicLink()) throw new Error('The preview project contains a symbolic link.');
  if (info.isDirectory()) {
    for (const entry of (await readdir(path.join(root, name))).sort()) await walk(root, `${name}/${entry}`, signal, files);
  } else if (info.isFile()) files.set(name, info);
}

async function inventory(root, signal) {
  const files = new Map();
  for (const source of baseSources) await walk(root, source, signal, files);
  return files;
}

export function assertSeparateBase(root, base) {
  const world = path.resolve(root, 'world');
  const relative = path.relative(world, path.resolve(base));
  if (!relative || (!relative.startsWith('..') && !path.isAbsolute(relative))) throw new Error('The preview base must be outside the project world.');
  const back = path.relative(path.resolve(base), world);
  if (!back || (!back.startsWith('..') && !path.isAbsolute(back))) throw new Error('The preview base must not contain the project world.');
}

// Bring the base in line with the primary checkout and return the files it holds.
export async function syncBase(root, base, { signal, onOutput = () => {} } = {}) {
  assertSeparateBase(root, base);
  await mkdir(base, { recursive: true });
  const wanted = await inventory(root, signal);
  const present = await inventory(base, signal);
  const stale = [...wanted].filter(([name, info]) => !same(info, present.get(name)));
  if (stale.length) {
    const bytes = stale.reduce((sum, [, info]) => sum + info.size, 0);
    const disk = await statfs(base);
    if (disk.bavail * disk.bsize < bytes + reserve) throw new Error(`Free at least ${gib(bytes + reserve)} GiB to update the preview art and import cache.`);
    onOutput(`Updating ${stale.length} preview art and import ${stale.length === 1 ? 'file' : 'files'} (${gib(bytes)} GiB).\n`);
  }
  for (const [name, info] of stale) {
    signal?.throwIfAborted();
    const target = path.join(base, name);
    const partial = target + partialSuffix;
    await mkdir(path.dirname(target), { recursive: true });
    await copyFile(path.join(root, name), partial);
    await utimes(partial, info.atime, info.mtime);
    // Replacing the name leaves any older preview's link on the previous file.
    await rename(partial, target);
  }
  for (const name of present.keys()) if (!wanted.has(name)) await rm(path.join(base, name), { force: true });
  return [...wanted.keys()];
}

// Link the base's files into a preview tree. A file the tree already has, such as a
// tracked .import file from the reviewed worktree, stays as it is. Where a link is not
// possible, for example across drives, the file is copied instead.
export async function linkBase(base, tree, names, { signal } = {}) {
  const directories = new Set();
  let linked = 0, copied = 0;
  for (const name of names) {
    signal?.throwIfAborted();
    const source = path.join(base, name), target = path.join(tree, name);
    const directory = path.dirname(target);
    if (!directories.has(directory)) { await mkdir(directory, { recursive: true }); directories.add(directory); }
    try { await link(source, target); linked++; }
    catch (error) {
      if (error.code === 'EEXIST') continue;
      if (!['EXDEV', 'EPERM', 'ENOTSUP', 'EMLINK', 'EACCES'].includes(error.code)) throw error;
      try { await copyFile(source, target, constants.COPYFILE_EXCL); copied++; }
      catch (failure) { if (failure.code !== 'EEXIST') throw failure; }
    }
  }
  return { linked, copied };
}
