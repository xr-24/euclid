import { lstat, readFile, realpath } from 'node:fs/promises';
import path from 'node:path';

// Hot loading (world/scripts/extensions/hot_load.gd): the running world loads a draft's text
// files without a restart. The gateway serves the reviewed text; the world decides how much of
// itself to refresh. Checks still gate the commit, not the preview.

export const hotLimit = 4 * 1024 * 1024;
const text = /\.(gd|gdshader|gdshaderinc|json|tscn|tres|cfg|txt|md|csv|html|css|js|svg)$/;

// The draft's files the world can hot load, or null when one of its world files cannot be: a
// binary asset, the engine settings, or a kind the table marks as needing a restart. Files
// outside world/ do not count: the gateway reloads itself on commit and docs need nothing.
export function hotFiles(kinds, names) {
  const world = names.filter(name => name.startsWith('world/'));
  if (!world.length) return null;
  for (const name of world) {
    if (name === 'world/project.godot' || name.startsWith('world/.godot/') || !text.test(name) || name.includes('..')) return null;
    const kind = kinds.find(item => item.files.test(name));
    if (kind && !kind.live) return null;
  }
  return world;
}

// The reviewed text of each file in the worktree. A removed file cannot be hot loaded.
export async function readHotFiles(worktree, names) {
  const base = await realpath(worktree);
  const files = {};
  let size = 0;
  for (const name of names) {
    const file = path.join(base, name);
    const info = await lstat(file).catch(() => null);
    if (!info) throw new Error(`${name} was removed in this draft. Commit it and restart Euclid to apply it.`);
    if (!info.isFile() || await realpath(file) !== file) throw new Error(`${name} cannot be hot loaded.`);
    size += info.size;
    if (size > hotLimit) throw new Error('This draft is too large to hot load. Commit it and restart Euclid.');
    const content = new TextDecoder('utf-8', { fatal: true }).decode(await readFile(file));
    if (content.includes('\0')) throw new Error(`${name} is not a text file.`);
    files[name] = content;
  }
  return files;
}
