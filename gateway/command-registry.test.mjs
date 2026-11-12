import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';
import test from 'node:test';
import { commands, commandFor, installedSnapshot, mcpTools, mcpToolsFor, nativePlan, normalizePlannerPlan, plannerCommands, plannerSchema,
  runtimeCommands, runtimePlan, validRegistry, validWorldPlan } from './command-registry.mjs';

const id = 'a'.repeat(32);
const cases = [
  { tool: 'spawn_prop', target: 'traffic_cone', zone: 'villa', changes: { scale: 2 } },
  { tool: 'spawn_prop', target: 'traffic_cone', changes: { position: [1, 2] } },
  { tool: 'edit_entity', target: id, changes: { yaw: 90, scale: null } },
  { tool: 'edit_entity', target: id, changes: { scale: 4.1 } },
  { tool: 'edit_entity', target: id, changes: {} },
  { tool: 'duplicate_entity', target: id, changes: { yaw: 90 } },
  { tool: 'undo_scene', target: '', zone: 'villa' },
  { tool: 'undo_scene', target: 'unrequested' },
  { tool: 'set_behavior', target: id, behavior: null },
  { tool: 'set_behavior', target: id, behavior: { id: 'pulse', settings: [{ key: 'x', value: 1 }, { key: 'x', value: 2 }] } },
  { tool: 'draft_source', target: '' },
  { tool: 'add_piece', target: 'shape', piece_values: { size: [1, 2, 3], material: { color: 'ff7700' } } },
  { tool: 'add_piece', target: 'made_up', piece_values: {} },
  { tool: 'edit_piece', target: 'ground', piece_values: { script: 'res://untrusted.gd' } },
];
const expected = [true, false, true, false, false, false, true, false, true, false, true, true, false, false];

test('a preview session owns its command catalog and argument schemas', () => {
  const snapshot = structuredClone(installedSnapshot);
  snapshot.schema.$defs.fixture_distance = { type: 'number', minimum: 0, maximum: 10 };
  snapshot.commands.push({ ...commandFor('follow'), name: 'fixture_follow', fields: { distance: 'fixture_distance' }, required: ['distance'] });
  snapshot.schema.$defs.scale.maximum = 2;
  const context = { command_registry: snapshot, current: 'construct' };
  assert(validRegistry(snapshot));
  assert(mcpToolsFor(context).some(command => command.name === 'fixture_follow'));
  assert(!mcpTools.some(command => command.name === 'fixture_follow'));
  assert(validWorldPlan({ tool: 'fixture_follow', target: '', distance: 4 }, context));
  assert(!validWorldPlan({ tool: 'fixture_follow', target: '', distance: 11 }, context));
  assert(plannerSchema(plannerCommands(context), context).properties.distance);
  assert(!validWorldPlan({ tool: 'fixture_follow', target: '' }));
  assert.equal(nativePlan(commandFor('edit_entity', context),
    { zone: 'construct', target: id, changes: { scale: 3 } }, context), null);
  assert(nativePlan(commandFor('edit_entity'), { zone: 'construct', target: id, changes: { scale: 3 } }));
  const cyclic = structuredClone(snapshot);
  cyclic.schema.$defs.scale = { $ref: '#/$defs/scale' };
  assert(!validRegistry(cyclic));
});

test('the planner and MCP expose registered piece fields for editable environments', () => {
  const context = { piece_edit: true, current: 'custom' };
  const values = { material: { roughness: 0.6 } };
  const plan = { tool: 'edit_piece', target: 'ground', piece_values: { ...values, material: { ...values.material, color: null }, size: null } };
  assert.deepEqual(normalizePlannerPlan(plan, context).piece_values, values);
  const tools = mcpToolsFor(context);
  const edit = tools.find(tool => tool.name === 'edit_piece');
  assert.equal(edit.inputSchema.properties.piece_values.properties.material.properties.roughness.maximum, 1);
  assert(!validWorldPlan({ tool: 'edit_piece', target: 'ground', piece_values: values }, { piece_edit: false }, true));
  const schema = plannerSchema(plannerCommands(context), context);
  assert(schema.properties.piece_values.anyOf[0].properties.material.anyOf[0].properties.roughness.anyOf);
});

test('command projections enforce schema, surface, availability and runtime bindings', () => {
  assert.deepEqual(cases.map(plan => validWorldPlan(plan)), expected);
  assert.equal(nativePlan(commandFor('edit_entity'), { target: id, changes: { yaw: 90 } }), null);
  assert.equal(nativePlan(commandFor('draft_source'), {}), null);
  const context = { current: 'construct', grid_development: true,
    workshop_tools: [{ name: 'grid_action_reset', description: 'Reset the test props', revision: 'b'.repeat(64) }],
    behaviors: [{ id: 'pulse', name: 'Pulse', settings: { radius: { minimum: 1, maximum: 12 } } }] };
  const schema = plannerSchema(plannerCommands(context));
  assert(schema.properties.tool.enum.includes('draft_grid'));
  assert(!schema.properties.tool.enum.includes('draft_source'));
  assert(!schema.properties.tool.enum.includes('spawn_entity'));
  assert.equal(normalizePlannerPlan({ tool: 'grid_action_reset', target: '' }, context).target, 'grid_action_reset');
  assert.equal(normalizePlannerPlan({ tool: 'grid_action_reset', target: '' }, { ...context, workshop_tools: [] }), null);
  const attachment = runtimeCommands(context).find(command => command.name === 'attach_behavior_pulse');
  assert.equal(runtimePlan(attachment, { target: id, settings: { radius: 13 } }, context), null);
  assert.equal(runtimePlan(attachment, { target: id, settings: { radius: 6 } }, context).behavior.id, 'pulse');
  assert.equal(normalizePlannerPlan({ tool: 'attach_behavior_pulse', target: id, behavior: null }, context).tool, 'set_behavior');
});

const project = fileURLToPath(new URL('../world/', import.meta.url));
const bundledGodot = process.platform === 'win32' ? 'Godot_v4.7.2-stable_win64_console.exe' : 'Godot_v4.7.2-stable_linux.x86_64';
const godot = process.env.GODOT_BIN ?? fileURLToPath(new URL(`../.tools/godot/${bundledGodot}`, import.meta.url));
test('Godot and gateway load identical commands and resolve their handlers', { skip: !existsSync(godot) }, async () => {
  const { stdout, stderr } = await promisify(execFile)(godot, ['--headless', '--path', path.resolve(project),
    '--script', 'res://scripts/diagnostics/command_contract.gd', '--quit-after', '120'], {
    windowsHide: true, timeout: 25000, env: { ...process.env, EUCLID_COMMAND_CONTRACT_CASES: JSON.stringify(cases) },
  });
  assert.doesNotMatch(stderr, /(?:SCRIPT ERROR|ERROR):/);
  const marker = stdout.split(/\r?\n/).find(line => line.startsWith('EUCLID_COMMAND_CONTRACT '));
  assert(marker, stdout);
  const contract = JSON.parse(marker.slice('EUCLID_COMMAND_CONTRACT '.length));
  const ordered = list => list.toSorted((a, b) => a.name.localeCompare(b.name));
  assert.deepEqual(ordered(contract.catalog), ordered(commands));
  assert.deepEqual(contract.checks, expected);
  assert.deepEqual(contract.piece_values, installedSnapshot.schema.$defs.piece_values);
  assert.deepEqual(contract.catalog.filter(command => command.surfaces.includes('mcp')).map(command => command.name).sort(),
    mcpTools.map(command => command.name).sort());
  for (const command of commands.filter(command => command.service !== 'assets')) {
    assert.equal(contract.handlers[command.name], true, command.name);
  }
});
