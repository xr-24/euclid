import assert from 'node:assert/strict';
import { mkdir, mkdtemp, readFile, readdir, rm, stat, symlink, utimes, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { assertSeparateBase, linkBase, syncBase } from './preview-base.mjs';

async function project(t) {
  const area = await mkdtemp(path.join(os.tmpdir(), 'euclid-preview-base-'));
  t.after(() => rm(area, { recursive: true, force: true }));
  const root = path.join(area, 'project');
  const files = {
    'world/assets/villa/statue.glb': 'statue mesh',
    'world/assets/villa/statue.glb.import': 'live import settings',
    'world/assets/README.md': 'art pack notes',
    'world/.godot/imported/statue.glb-1.scn': 'imported statue',
    'world/.godot/uid_cache.bin': 'uids',
    'world/.godot/editor/layout.cfg': 'not part of the base',
    'world/scripts/world.gd': 'not part of the base',
  };
  // A fractional timestamp exercises the precision lost when a copy gets a Date.
  const when = Date.parse('2026-11-01T12:00:00Z') / 1000 + 0.00075;
  for (const [name, text] of Object.entries(files)) {
    await mkdir(path.dirname(path.join(root, name)), { recursive: true });
    await writeFile(path.join(root, name), text);
    await utimes(path.join(root, name), when, when);
  }
  return { area, root, base: path.join(area, 'project/.local/preview-base') };
}

test('the base mirrors only art and import files and links them into a preview', async t => {
  const { area, root, base } = await project(t);
  const output = [];
  const names = await syncBase(root, base, { onOutput: line => output.push(line) });
  assert.deepEqual(names, ['world/assets/README.md', 'world/assets/villa/statue.glb', 'world/assets/villa/statue.glb.import',
    'world/.godot/imported/statue.glb-1.scn', 'world/.godot/uid_cache.bin']);
  assert.match(output.join(''), /Updating 5 preview art and import files/);
  for (const name of names) {
    const [live, copy] = await Promise.all([stat(path.join(root, name)), stat(path.join(base, name))]);
    assert.notEqual(copy.ino, live.ino, `${name} is a copy, never a link to the live project`);
    assert.equal(copy.mtime.getTime(), live.mtime.getTime());
  }

  const tree = path.join(area, 'draft/preview');
  await mkdir(path.join(tree, 'world/assets/villa'), { recursive: true });
  await writeFile(path.join(tree, 'world/assets/villa/statue.glb.import'), 'reviewed import settings');
  assert.deepEqual(await linkBase(base, tree, names), { linked: 4, copied: 0 });
  assert.equal(await readFile(path.join(tree, 'world/assets/villa/statue.glb.import'), 'utf8'), 'reviewed import settings');
  for (const name of names.filter(name => !name.endsWith('.import'))) {
    assert.equal((await stat(path.join(tree, name))).ino, (await stat(path.join(base, name))).ino, name);
  }

  output.length = 0;
  await syncBase(root, base, { onOutput: line => output.push(line) });
  assert.deepEqual(output, [], 'an unchanged project copies nothing');
});

test('a preview that writes through a link never reaches the project, and the next sync repairs the base', async t => {
  const { area, root, base } = await project(t);
  const names = await syncBase(root, base);
  const tree = path.join(area, 'draft/preview');
  await linkBase(base, tree, names);
  const imported = 'world/.godot/imported/statue.glb-1.scn';
  await writeFile(path.join(tree, imported), 'reimported by the preview');

  assert.equal(await readFile(path.join(root, imported), 'utf8'), 'imported statue');
  assert.equal(await readFile(path.join(base, imported), 'utf8'), 'reimported by the preview');
  await syncBase(root, base);
  assert.equal(await readFile(path.join(base, imported), 'utf8'), 'imported statue');
  assert.equal(await readFile(path.join(tree, imported), 'utf8'), 'reimported by the preview', 'the old preview keeps its own file');
});

test('the base follows edits and removals and clears interrupted copies', async t => {
  const { root, base } = await project(t);
  await syncBase(root, base);
  const statue = 'world/assets/villa/statue.glb';
  await writeFile(path.join(root, statue), 'statue MESH');
  await utimes(path.join(root, statue), new Date('2026-11-02T12:00:00Z'), new Date('2026-11-02T12:00:00Z'));
  await rm(path.join(root, 'world/.godot/uid_cache.bin'));
  await writeFile(path.join(base, `${statue}.euclid-partial`), 'half a copy');

  const output = [];
  const names = await syncBase(root, base, { onOutput: line => output.push(line) });
  assert.match(output.join(''), /Updating 1 preview art and import file /);
  assert.equal(await readFile(path.join(base, statue), 'utf8'), 'statue MESH');
  assert.equal(names.includes('world/.godot/uid_cache.bin'), false);
  const villa = await readdir(path.join(base, 'world/assets/villa'));
  assert.deepEqual(villa.sort(), ['statue.glb', 'statue.glb.import']);
  await assert.rejects(stat(path.join(base, 'world/.godot/uid_cache.bin')), { code: 'ENOENT' });
});

test('the base refuses symbolic links and any location that overlaps the world', async t => {
  const { area, root, base } = await project(t);
  assert.throws(() => assertSeparateBase(root, root), /must not contain the project world/);
  assert.throws(() => assertSeparateBase(root, path.join(root, 'world')), /outside the project world/);
  assert.throws(() => assertSeparateBase(root, path.join(root, 'world/.godot/base')), /outside the project world/);
  assert.doesNotThrow(() => assertSeparateBase(root, base));
  await rm(base, { recursive: true, force: true });

  const outside = path.join(area, 'outside.txt');
  await writeFile(outside, 'elsewhere');
  try { await symlink(outside, path.join(root, 'world/assets/link.txt')); }
  catch (error) { if (error.code === 'EPERM') return t.skip('Symbolic links need extra rights on this machine.'); throw error; }
  await assert.rejects(syncBase(root, base), /symbolic link/);
});
