import assert from 'node:assert/strict';
import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { draftKinds, kindsFile, listExtensions, loadKinds } from './extensions.mjs';
import { gridAppearance } from './workbench-grid.mjs';
import { shorelineAppearance } from './workbench-shoreline.mjs';

const project = fileURLToPath(new URL('../', import.meta.url));

test('the shared kind table matches the candidates the Workbench serves', async () => {
  const kinds = await loadKinds(project);
  const kind = id => kinds.find(item => item.id === id);
  assert.deepEqual(kinds.filter(item => item.live).map(item => item.id), ['grid_palette', 'shoreline', 'grid', 'workshop_tool', 'behavior', 'environment', 'command', 'hot']);
  assert.equal(kind('shoreline').candidate, shorelineAppearance.payload);
  assert.equal(kind('grid').candidate, gridAppearance.payload);
  assert.equal(kind('shoreline').activation, shorelineAppearance.activation);
  assert.equal(kind('grid').activation, gridAppearance.activation);
  assert.ok(kind('shoreline').files.test(shorelineAppearance.file) && kind('grid').files.test(gridAppearance.file));
  assert.deepEqual(draftKinds(kinds, ['world/scripts/ui/grid_palette.gd']), ['grid_palette']);
  assert.deepEqual(draftKinds(kinds, ['world/data/workshop_tools/reset_demo.json']), ['workshop_tool']);
  assert.deepEqual(draftKinds(kinds, ['world/scripts/plugins/pulse.gd', 'world/data/behavior_plugins/pulse.json']), ['behavior']);
  assert.deepEqual(draftKinds(kinds, ['world/data/zones/villa/zone.json', 'world/data/commands/scene.json', 'docs/x.md']),
    ['environment', 'command', 'source']);
  assert.deepEqual(draftKinds(kinds, ['world/data/commands/schema.json']), ['hot'], 'the command schema is not a command set');
  assert.deepEqual(draftKinds(kinds, ['world/project.godot', 'world/assets/rock.png']), ['source'], 'engine settings and binary assets are not hot loaded');
});

test('installed extensions are listed as one kind of record', async () => {
  const kinds = await loadKinds(project);
  const installed = await listExtensions(project, kinds);
  const ids = installed.map(item => `${item.kind}:${item.id}`);
  for (const expected of ['grid_palette:grid_palette', 'shoreline:shoreline', 'grid:grid', 'behavior:proximity_pulse',
    'environment:construct', 'environment:villa', 'environment:beach', 'command:world', 'command:scene', 'command:development']) {
    assert.ok(ids.includes(expected), expected);
  }
  for (const item of installed) {
    assert.deepEqual(Object.keys(item).slice(0, 6), ['kind', 'id', 'name', 'files', 'live', 'activation'], item.id);
    assert.equal(item.live, kinds.find(kind => kind.id === item.kind).live);
    for (const file of item.files) assert.ok(kinds.some(kind => kind.files.test(file)), file);
  }
});

test('a malformed kind table is refused and packages are read from their folders', async t => {
  const area = await mkdtemp(path.join(os.tmpdir(), 'euclid-extensions-'));
  t.after(() => rm(area, { recursive: true, force: true }));
  await assert.rejects(loadKinds(area), /could not be read/);
  await mkdir(path.join(area, 'world/data/workshop_tools'), { recursive: true });
  await mkdir(path.join(area, 'world/data/behavior_plugins'), { recursive: true });
  const write = (name, value) => writeFile(path.join(area, name), JSON.stringify(value));
  await write(kindsFile, { schema_version: 1, kinds: [{ id: 'behavior', name: 'Behavior', description: '', files: '^x$', live: true }] });
  await assert.rejects(loadKinds(area), /describes behavior incompletely/);
  await write(kindsFile, { schema_version: 1, kinds: [
    { id: 'workshop_tool', name: 'Workshop action', description: '', files: '^world/data/workshop_tools/[a-z_]+\\.json$', live: true, candidate: 'workshop_tool', activation: 'live' },
    { id: 'behavior', name: 'Behavior', description: '', files: '^world/data/behavior_plugins/[a-z_]+\\.json$', live: true, candidate: 'plugin', activation: 'live' }] });
  await write('world/data/workshop_tools/reset_demo.json', { schema_version: 1, name: 'Reset demo', zone: 'lab' });
  await write('world/data/workshop_tools/Bad Name.json', { name: 'ignored' });
  await write('world/data/behavior_plugins/blink.json', { schema_version: 1, id: 'blink', name: 'Blink', entity_type: 'lamp' });
  await write('world/data/behavior_plugins/wrong.json', { id: 'other' });
  const kinds = await loadKinds(area);
  assert.deepEqual((await listExtensions(area, kinds)).map(item => [item.kind, item.id, item.name, item.detail]), [
    ['workshop_tool', 'reset_demo', 'Reset demo', 'Grid space lab'], ['behavior', 'blink', 'Blink', 'Package, for lamp']]);
});

test('hot loading takes text files under world/ that no restart-only kind claims', async () => {
  const { hotFiles, readHotFiles } = await import('./workbench-hot.mjs');
  const kinds = await loadKinds(project);
  assert.deepEqual(hotFiles(kinds, ['world/scripts/world_art.gd', 'world/shaders/sky.gdshader', 'docs/x.md', 'gateway/a.mjs']),
    ['world/scripts/world_art.gd', 'world/shaders/sky.gdshader']);
  assert.equal(hotFiles(kinds, ['docs/x.md']), null, 'nothing in world/ to load');
  assert.equal(hotFiles(kinds, ['world/scripts/a.gd', 'world/project.godot']), null, 'engine settings need a restart');
  assert.equal(hotFiles(kinds, ['world/scripts/a.gd', 'world/assets/rock.glb']), null, 'binary assets need an import');
  assert.deepEqual(hotFiles(kinds, ['world/data/zones/villa/zone.json', 'world/data/commands/world.json']),
    ['world/data/zones/villa/zone.json', 'world/data/commands/world.json'], 'environment packages and command sets hot load');
  const files = await readHotFiles(project, ['world/data/hot_reload.json']);
  assert.match(files['world/data/hot_reload.json'], /"rules"/);
  await assert.rejects(readHotFiles(project, ['world/scripts/missing.gd']), /removed in this draft/);
});

test('agents get a primer built from the live data when they connect', async () => {
  const { agentPrimer } = await import('./agent-primer.mjs');
  const primer = agentPrimer();
  for (const phrase of ['capture_view', 'pointed_at', 'tweak_property', 'submit_draft', 'frame_ms', 'save_environment',
    'project source', 'environment package', 'scripts/world.gd → restart', 'Never put passwords']) {
    assert.ok(primer.includes(phrase), phrase);
  }
  assert.ok(primer.length < 4000, 'the primer stays short');
});
