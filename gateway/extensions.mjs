import { readFile, readdir } from 'node:fs/promises';
import path from 'node:path';

// One table of the kinds of extension Euclid takes, shared with Godot. The gateway uses it to
// name what a draft changes and to list what is installed; Godot registers its live kinds in the
// same order (world/scripts/extensions/live_kinds.gd), and a core test holds the two together.
export const kindsFile = 'world/data/extension_kinds.json';
const kindId = /^[a-z][a-z0-9_]{0,31}$/;
const activations = new Set(['live', 'reload_palette', 'reload_grid', 'restart', 'gateway_restart', 'none']);

export async function loadKinds(root) {
  let table;
  try { table = JSON.parse(await readFile(path.join(root, kindsFile), 'utf8')); }
  catch (error) { throw new Error(`${kindsFile} could not be read: ${error.message}`); }
  if (table?.schema_version !== 1 || !Array.isArray(table.kinds) || !table.kinds.length) throw new Error(`${kindsFile} must list version 1 kinds.`);
  const seen = new Set();
  return table.kinds.map(kind => {
    const { id, name, description, files, live, candidate, activation } = kind ?? {};
    if (!kindId.test(id ?? '') || seen.has(id)) throw new Error(`${kindsFile} has an invalid or repeated kind id.`);
    seen.add(id);
    if (typeof name !== 'string' || !name || typeof description !== 'string' || typeof files !== 'string' || !files.startsWith('^') ||
        !files.endsWith('$') || typeof live !== 'boolean' || !activations.has(activation) || (live && !kindId.test(candidate ?? ''))) {
      throw new Error(`${kindsFile} describes ${id} incompletely.`);
    }
    return Object.freeze({ id, name, description, live, activation, files: new RegExp(files), ...(live ? { candidate } : {}) });
  });
}

// The kinds a draft's files belong to, in table order. Files no kind claims count as source.
export function draftKinds(kinds, names) {
  const found = new Set();
  for (const name of names) {
    const kind = kinds.find(item => item.files.test(name));
    found.add(kind ? kind.id : 'source');
  }
  return [...kinds.map(item => item.id), 'source'].filter(id => found.has(id));
}

async function readJson(file) {
  try { return JSON.parse(await readFile(file, 'utf8')); } catch { return null; }
}

async function names(directory) {
  try { return (await readdir(directory, { withFileTypes: true })).sort((a, b) => a.name.localeCompare(b.name)); }
  catch { return []; }
}

// Every installed extension as one kind of record:
// { kind, id, name, files, live, activation, version?, detail? }.
export async function listExtensions(root, kinds) {
  const at = name => path.join(root, name);
  const record = (kind, id, name, files, extra = {}) => {
    const definition = kinds.find(item => item.id === kind);
    return { kind, id, name, files, live: definition?.live ?? false, activation: definition?.activation ?? 'restart', ...extra };
  };
  const found = [];
  const known = new Set(kinds.map(kind => kind.id));
  if (known.has('grid_palette')) found.push(record('grid_palette', 'grid_palette', 'Grid palette', ['world/scripts/ui/grid_palette.gd']));
  for (const [kind, file] of [['shoreline', 'world/data/shoreline_appearance.json'], ['grid', 'world/data/grid_appearance.json']]) {
    const profile = known.has(kind) ? await readJson(at(file)) : null;
    if (profile) found.push(record(kind, kind, kinds.find(item => item.id === kind).name, [file], { version: profile.schema_version }));
  }
  if (known.has('workshop_tool')) {
    for (const item of await names(at('world/data/workshop_tools'))) {
      const match = /^([a-z][a-z0-9_]{0,31})\.json$/.exec(item.name);
      const tool = match && item.isFile() ? await readJson(at(`world/data/workshop_tools/${item.name}`)) : null;
      if (tool) found.push(record('workshop_tool', match[1], tool.name ?? match[1], [`world/data/workshop_tools/${item.name}`],
        { version: tool.schema_version, detail: tool.zone ? `Grid space ${tool.zone}` : undefined }));
    }
  }
  if (known.has('behavior')) {
    const builtin = await readJson(at('world/data/behavior_plugins.json'));
    for (const plugin of builtin?.plugins ?? []) {
      found.push(record('behavior', plugin.id, plugin.name ?? plugin.id, [`world/scripts/plugins/${plugin.id}.gd`, 'world/data/behavior_plugins.json'],
        { version: builtin.schema_version, detail: `Built in, for ${plugin.entity_type}` }));
    }
    for (const item of await names(at('world/data/behavior_plugins'))) {
      const match = /^([a-z_][a-z0-9_]{0,39})\.json$/.exec(item.name);
      const plugin = match && item.isFile() ? await readJson(at(`world/data/behavior_plugins/${item.name}`)) : null;
      if (plugin?.id === match?.[1]) found.push(record('behavior', plugin.id, plugin.name ?? plugin.id,
        [`world/scripts/plugins/${plugin.id}.gd`, `world/data/behavior_plugins/${item.name}`],
        { version: plugin.schema_version, detail: plugin.entity_type ? `Package, for ${plugin.entity_type}` : 'Package' }));
    }
  }
  if (known.has('environment')) {
    const world = await readJson(at('world/data/world.json'));
    for (const item of await names(at('world/data/zones'))) {
      const zone = item.isDirectory() ? await readJson(at(`world/data/zones/${item.name}/zone.json`)) : null;
      if (zone?.id !== item.name) continue;
      const entry = (world?.zones ?? []).find(candidate => candidate.id === zone.id);
      found.push(record('environment', zone.id, entry?.name ?? zone.id, [`world/data/zones/${item.name}/zone.json`],
        { version: zone.schema_version, detail: zone.builder ? `Builder ${zone.builder}` : undefined }));
    }
  }
  if (known.has('command')) {
    for (const set of ['world', 'scene', 'development']) {
      const commands = await readJson(at(`world/data/commands/${set}.json`));
      if (commands) found.push(record('command', set, `${set[0].toUpperCase()}${set.slice(1)} commands`, [`world/data/commands/${set}.json`],
        { version: commands.version, detail: `${(commands.commands ?? []).length} commands` }));
    }
  }
  return found.map(item => Object.fromEntries(Object.entries(item).filter(([, value]) => value !== undefined)));
}
