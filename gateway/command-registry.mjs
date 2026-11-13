import { readFileSync, readdirSync } from 'node:fs';

const directory = new URL('../world/data/commands/', import.meta.url);
const read = name => JSON.parse(readFileSync(new URL(name, directory), 'utf8'));
const world = read('../world.json');
const workshop = world.workshop_zone ?? world.startup_zone ?? world.zones[0].id;
const gridBounds = read(`../zones/${workshop}/zone.json`).bounds;

function createRegistry(snapshot) {
  if (snapshot?.version !== 1 || snapshot.schema?.version !== 1 || !snapshot.schema.$defs ||
      !Array.isArray(snapshot.commands) || snapshot.commands.length > 256) throw new Error('Invalid live command registry');
  const schema = snapshot.schema;
  const entries = snapshot.commands;
  if (!schema.entity_types || typeof schema.entity_types !== 'object' ||
      typeof schema.runtime_commands?.workshop?.source !== 'string' ||
      !Object.hasOwn(schema.$defs, schema.runtime_commands?.workshop?.name_rule) ||
      typeof schema.runtime_commands?.behavior?.source !== 'string' ||
      typeof schema.runtime_commands?.behavior?.prefix !== 'string' ||
      !Array.isArray(schema.action_properties) || !Array.isArray(schema.prefab_properties) ||
      !schema.limits || !['environments', 'workshop_actions', 'runtime_behaviors'].every(key =>
        Number.isInteger(schema.limits[key]) && schema.limits[key] > 0 && schema.limits[key] <= 1024)) {
    throw new Error('Invalid command registry policies');
  }
  validateDefinitions(schema.$defs);
  for (const name of ['entity', 'zone', 'behavior', 'prop_changes']) {
    if (!Object.hasOwn(schema.$defs, name)) throw new Error('Missing core argument definition: ' + name);
  }
  const definitions = schema.$defs;
  const commandMap = new Map();
  const localNames = new Set();
  for (const command of entries) {
    if (!/^[a-z][a-z0-9_]*$/.test(command.name) || commandMap.has(command.name) ||
        !['scene', 'world', 'animation', 'assets', 'development'].includes(command.service) ||
        typeof command.handler !== 'string' || !command.handler ||
        !Array.isArray(command.surfaces) || command.surfaces.some(surface => !['palette', 'f2', 'mcp'].includes(surface)) ||
        !['read', 'write', 'preview', 'draft', 'undo'].includes(command.effect) ||
        !['scene', 'session'].includes(command.scope) || !['scene', 'prop', 'piece', 'none'].includes(command.undo) ||
        typeof command.mutates_world !== 'boolean' ||
        !command.fields || Object.values(command.fields).some(key => !Object.hasOwn(definitions, key)) ||
        !Array.isArray(command.required) || command.required.some(key => !Object.hasOwn(command.fields, key)) ||
        (command.local && localNames.has(command.local))) throw new Error('Invalid command definition: ' + command.name);
    commandMap.set(command.name, command);
    if (command.local) localNames.add(command.local);
  }

  const commands = [...commandMap.values()];
  const limits = schema.limits;
  const entityTypes = schema.entity_types;
  const actionProperties = schema.action_properties;
  const validField = (name, value) => Object.hasOwn(definitions, name) && valid(value, definitions[name]);
  const validActionProperty = (name, value) => schema.action_properties.includes(name) && validField(name, value) &&
    (name !== 'position' || value.every((axis, index) => axis >= gridBounds[0][index] && axis <= gridBounds[0][index] + gridBounds[1][index]));
  const isWorkshopName = name => valid(name, definitions[schema.runtime_commands.workshop.name_rule]);
  const commandFor = name => commandMap.get(name);
  const available = (command, context) => !command.availability || context?.[command.availability] === true;
  const object = (properties = {}, required = []) => ({ type: 'object', properties, required, additionalProperties: false });
  const isObject = value => value !== null && typeof value === 'object' && !Array.isArray(value);

  function resolve(rule) {
    if (rule.$ref) return resolve(definitions[rule.$ref.split('/').at(-1)]);
    if (Array.isArray(rule)) return rule.map(resolve);
    if (!isObject(rule)) return rule;
    return Object.fromEntries(Object.entries(rule).filter(([key]) => !['multipleOfHint', 'uniqueBy'].includes(key)).map(([key, value]) =>
      [key, isObject(value) || Array.isArray(value) ? resolve(value) : value]));
  }

  function valid(value, rule) {
    if (rule.$ref) return valid(value, definitions[rule.$ref.split('/').at(-1)]);
    if (rule.anyOf) return rule.anyOf.some(choice => valid(value, choice));
    if (rule.enum && !rule.enum.includes(value)) return false;
    switch (rule.type) {
      case 'null': return value === null;
      case 'boolean': return typeof value === 'boolean';
      case 'string':
        return typeof value === 'string' && [...value].length <= (rule.maxLength ?? Infinity) &&
          (!rule.pattern || new RegExp(rule.pattern).test(value));
      case 'number':
        return Number.isFinite(value) && value >= (rule.minimum ?? -Infinity) && value <= (rule.maximum ?? Infinity);
      case 'array':
        return Array.isArray(value) && value.length >= (rule.minItems ?? 0) && value.length <= (rule.maxItems ?? Infinity) &&
          value.every(item => valid(item, rule.items)) &&
          (!rule.uniqueBy || new Set(value.map(item => item[rule.uniqueBy])).size === value.length);
      case 'object': {
        if (!isObject(value) || Object.keys(value).length < (rule.minProperties ?? 0)) return false;
        return rule.required.every(key => Object.hasOwn(value, key)) &&
          Object.entries(value).every(([key, entry]) => Object.hasOwn(rule.properties, key) && valid(entry, rule.properties[key]));
      }
      default: return false;
    }
  }

  function inputSchema(command, native = false) {
    const names = native ? command.mcp_arguments ?? {} : {};
    const nativeKey = key => Object.keys(names).find(name => names[name] === key) ?? key;
    const fields = Object.fromEntries(Object.entries(command.fields).map(([key, type]) => [nativeKey(key), definitions[type]]));
    const required = command.required.map(nativeKey);
    if (command.scope === 'scene' && (!native || !command.catalog)) fields.zone = definitions.zone;
    if (native && command.require_zone) required.push('zone');
    return object(fields, required);
  }

  const mcpTools = commands.filter(command => command.surfaces.includes('mcp')).map(command => ({
    name: command.name,
    description: command.description + (command.undo === 'scene' ? ' The edit supports scene undo.' :
      command.undo === 'piece' ? ' The edit supports undo_piece.' : ''),
    inputSchema: resolve(inputSchema(command, true)),
    ...(command.effect === 'read' || command.destructive ?
      { annotations: { ...(command.effect === 'read' ? { readOnlyHint: true } : {}), ...(command.destructive ? { destructiveHint: true } : {}) } } : {}),
  }));

  function nativePlan(command, args) {
    if (!command?.surfaces.includes('mcp') || !valid(args, inputSchema(command, true))) return null;
    return { tool: command.name, target: '', ...Object.fromEntries(Object.entries(args).map(([key, value]) =>
      [command.mcp_arguments?.[key] ?? key, value])) };
  }

  const placeholders = { target: '', name: '', template: '', preserve_rig: false, clip: null, behavior: null, changes: null };

  function validWorldPlan(plan, context, native = false) {
    if (!isObject(plan) || typeof plan.tool !== 'string' || typeof plan.target !== 'string') return false;
    const command = commandFor(plan.tool);
    if (!command || !command.surfaces.some(surface => surface === 'f2' || surface === 'mcp') ||
        (context && (!command.surfaces.includes(native ? 'mcp' : 'f2') || !available(command, context)))) return false;
    const args = {};
    for (const [key, value] of Object.entries(plan)) {
      if (key === 'tool') continue;
      if (key === 'changes' && isObject(value)) {
        const changes = Object.fromEntries(Object.entries(value).filter(([, entry]) => entry !== null));
        if (!Object.keys(changes).length && !command.required.includes('changes')) continue;
        args.changes = changes;
      } else if (!(value === null && !command.required.includes(key)) &&
          !(Object.hasOwn(placeholders, key) && value === placeholders[key] && !command.required.includes(key))) {
        args[key] = value;
      }
    }
    if (!valid(args, inputSchema(command))) return false;
    if (command.fields.target === 'prop_type' && context && !native && !schema.entity_types[args.target]?.built_in &&
        !(Array.isArray(context.scene_assets) && context.scene_assets.some(asset => asset?.id === args.target))) return false;
    if (command.catalog && context &&
        !(Array.isArray(context[command.catalog]) && context[command.catalog].some(entry => entry?.name === args.target))) return false;
    return !args.clip || JSON.stringify(args.clip).length <= 32000;
  }

  function plannerCommands(context) {
    return [...commands.filter(command => command.surfaces.includes('f2') && available(command, context)), ...runtimeCommands(context)];
  }

  function plannerCatalog(context) {
    return plannerCommands(context).map(command => ({
      name: command.name, description: command.description,
      arguments: resolve(inputSchema(command)),
      effect: command.effect ?? commandFor(command.base).effect,
      undo: command.undo ?? commandFor(command.base).undo,
    }));
  }

  function runtimeCommands(context) {
    const { workshop, behavior } = schema.runtime_commands;
    const catalog = (source, limit) => Array.isArray(context?.[source]) ? context[source].slice(0, limit) : [];
    const actions = catalog(workshop.source, limits.workshop_actions).filter(entry => valid(entry?.name, definitions[workshop.name_rule])).map(entry => ({
      name: entry.name, description: entry.description, fields: {}, required: [], inputSchema: object(),
      base: workshop.base, revision: entry.revision,
    }));
    const attachments = catalog(behavior.source, limits.runtime_behaviors).filter(entry => valid(entry?.id, definitions.behavior.properties.id) &&
      typeof entry.name === 'string' && isObject(entry.settings)).map(entry => {
      const settings = Object.fromEntries(Object.entries(entry.settings).filter(([key, spec]) =>
        valid(key, definitions.behavior.properties.id) && Number.isFinite(spec?.minimum) && Number.isFinite(spec?.maximum))
        .map(([key, spec]) => [key, { type: 'number', minimum: spec.minimum, maximum: spec.maximum }]));
      const fields = { target: definitions.entity, settings: object(settings) };
      const required = ['target'];
      if (entry.output === 'door_open') {
        fields.target_entity = definitions.entity;
        required.push('target_entity');
      }
      return {
        name: behavior.prefix + entry.id, description: 'Attach the registered behavior ' + entry.name + '.',
        fields: { target: 'entity', behavior: 'behavior' }, required: ['target'], inputSchema: object(fields, required),
        base: behavior.base, behavior: entry.id,
      };
    });
    return [...actions, ...attachments];
  }

  function isRuntimeName(name) {
    const { behavior } = schema.runtime_commands;
    return typeof name === 'string' && (isWorkshopName(name) || name.startsWith(behavior.prefix));
  }

  function runtimePlan(command, args, context) {
    if (!valid(args, command.inputSchema)) return null;
    const base = commandFor(command.base);
    const plan = { tool: base.name, zone: context.current, target: args.target ?? command.name };
    if (command.revision) plan.revision = command.revision;
    if (command.behavior) plan.behavior = {
      id: command.behavior, target_entity: args.target_entity ?? '',
      settings: Object.entries(args.settings ?? {}).map(([key, value]) => ({ key, value })),
    };
    return plan;
  }

  function normalizePlannerPlan(plan, context) {
    if (isObject(plan?.piece_values)) {
      const filled = value => isObject(value) ? Object.fromEntries(Object.entries(value)
        .filter(([, entry]) => entry !== null).map(([key, entry]) => [key, filled(entry)])) : value;
      plan = { ...plan, piece_values: filled(plan.piece_values) };
    }
    if (validWorldPlan(plan, context)) return plan;
    const command = runtimeCommands(context).find(entry => entry.name === plan?.tool);
    if (!command) return null;
    if (command.revision && (plan.target === '' || plan.target === command.name)) {
      const normalized = { ...plan, tool: command.base, target: command.name };
      return validWorldPlan(normalized, context) ? normalized : null;
    }
    if (command.behavior && (plan.behavior == null || plan.behavior.id === command.behavior)) {
      const normalized = { ...plan, tool: command.base,
        behavior: plan.behavior ?? { id: command.behavior, settings: [], target_entity: '' } };
      if (!validWorldPlan(normalized, context)) return null;
      const { settings, target_entity: door } = normalized.behavior;
      const args = { target: normalized.target, settings: Object.fromEntries(settings.map(({ key, value }) => [key, value])),
        ...(door ? { target_entity: door } : {}) };
      return valid(args, command.inputSchema) ? normalized : null;
    }
    return null;
  }

  // The planner uses a strict envelope. The command schema is applied again to the result.
  function structured(rule, nullableOptional = false) {
    const clean = Object.fromEntries(Object.entries(rule).filter(([key]) =>
      ['type', 'description', 'enum', 'properties', 'items', 'anyOf'].includes(key)));
    if (clean.type === 'object') {
      clean.properties = Object.fromEntries(Object.entries(clean.properties).map(([key, field]) => {
        const formatted = structured(field, nullableOptional);
        return [key, nullableOptional && !rule.required.includes(key)
          ? { anyOf: [formatted, { type: 'null' }] } : formatted];
      }));
      clean.required = Object.keys(clean.properties);
      clean.additionalProperties = false;
    }
    if (clean.items) clean.items = structured(clean.items, nullableOptional);
    if (clean.anyOf) clean.anyOf = clean.anyOf.map(option => structured(option, nullableOptional));
    return clean;
  }

  function plannerSchema(catalog) {
    const nullable = rule => ({ anyOf: [structured(resolve(rule)), { type: 'null' }] });
    const changes = Object.fromEntries(Object.entries(definitions.prop_changes.properties).map(([key, rule]) => [key, nullable(rule)]));
    const fields = {
      tool: { type: 'string', enum: catalog.map(command => command.name) },
      target: { type: 'string', description: 'The selected command target, or an empty string.' },
      name: { type: 'string', description: 'The requested prefab name, or an empty string.' },
      template: { type: 'string', description: 'The environment ID to copy, or an empty string for the default.' },
      preserve_rig: { type: 'boolean', description: 'True when importing a rigged model.' },
      clip: nullable(definitions.clip), behavior: nullable(definitions.behavior),
      changes: { anyOf: [object(changes, Object.keys(changes)), { type: 'null' }] },
    };
    const additional = new Map();
    for (const command of catalog) {
      for (const [key, type] of Object.entries(command.fields)) {
        if (key === 'zone' || Object.hasOwn(fields, key)) continue;
        if (!additional.has(key)) additional.set(key, new Set());
        additional.get(key).add(type);
      }
    }
    for (const [key, types] of additional) {
      const choices = [...types].map(type => structured(resolve(definitions[type]), type === 'piece_values'));
      fields[key] = { anyOf: [...choices, { type: 'null' }] };
    }
    return object(fields, Object.keys(fields));
  }

  return { commands, limits, entityTypes, actionProperties, validField, validActionProperty, isWorkshopName, commandFor, available, object, mcpTools, nativePlan, validWorldPlan, plannerCommands, plannerCatalog, runtimeCommands, isRuntimeName, runtimePlan, normalizePlannerPlan, plannerSchema };
}

function validateDefinitions(definitions) {
  if (typeof definitions !== 'object' || Array.isArray(definitions) || Object.keys(definitions).length > 128) {
    throw new Error('Invalid command argument definitions');
  }
  function visit(rule, parents = [], depth = 0) {
    if (!rule || typeof rule !== 'object' || Array.isArray(rule) || depth > 24) throw new Error('Invalid argument schema');
    if (rule.$ref) {
      const key = rule.$ref.split('/').at(-1);
      if (!Object.hasOwn(definitions, key) || parents.includes(key)) throw new Error('Invalid or cyclic argument reference');
      return visit(definitions[key], [...parents, key], depth + 1);
    }
    if (rule.anyOf) {
      if (!Array.isArray(rule.anyOf) || !rule.anyOf.length || rule.anyOf.length > 8) throw new Error('Invalid schema alternatives');
      return rule.anyOf.forEach(option => visit(option, parents, depth + 1));
    }
    if (!['null', 'boolean', 'number', 'string', 'object', 'array'].includes(rule.type)) throw new Error('Unsupported argument type');
    if (rule.pattern !== undefined) {
      if (typeof rule.pattern !== 'string' || rule.pattern.length > 512) throw new Error('Invalid argument pattern');
      new RegExp(rule.pattern);
    }
    if (rule.type === 'object') {
      if (!rule.properties || typeof rule.properties !== 'object' || !Array.isArray(rule.required) ||
          rule.required.some(key => !Object.hasOwn(rule.properties, key))) throw new Error('Invalid object schema');
      Object.values(rule.properties).forEach(field => visit(field, parents, depth + 1));
    }
    if (rule.type === 'array') visit(rule.items, parents, depth + 1);
  }
  for (const [key, rule] of Object.entries(definitions)) visit(rule, [key]);
}

const entries = [];
for (const file of readdirSync(directory).sort()) {
  if (!file.endsWith('.json') || file === 'schema.json') continue;
  const manifest = read(file);
  if (manifest.version !== 1 || !Array.isArray(manifest.commands)) throw new Error('Invalid command manifest: ' + file);
  entries.push(...manifest.commands);
}
const schema = read('schema.json');
const pieces = JSON.parse(readFileSync(new URL('../world/data/pieces/types.json', import.meta.url), 'utf8'));
const { id: pieceId, type: _pieceType, ...pieceFields } = pieces.common;
for (const { fields } of Object.values(pieces.types)) {
  for (const [key, rule] of Object.entries(fields)) {
    if (!Object.hasOwn(pieceFields, key)) pieceFields[key] = rule;
    else {
      const choices = pieceFields[key].anyOf ?? [pieceFields[key]];
      if (!choices.some(choice => JSON.stringify(choice) === JSON.stringify(rule))) {
        pieceFields[key] = { anyOf: [...choices, rule] };
      }
    }
  }
}
Object.assign(schema.$defs, {
  piece_id: pieceId,
  piece_values: { type: 'object', properties: pieceFields, required: [] },
  piece_type: { type: 'string', enum: Object.keys(pieces.types) },
});
export const installedSnapshot = { version: 1, schema, commands: entries };
const installed = createRegistry(installedSnapshot);
const cached = new Map();

function registryFor(context) {
  const snapshot = context?.command_registry;
  if (snapshot === undefined) return installed;
  const key = JSON.stringify(snapshot);
  if (key.length > 100000) throw new Error('The command registry exceeds its size limit');
  if (!cached.has(key)) {
    const registry = createRegistry(JSON.parse(key));
    if (cached.size >= 16) cached.delete(cached.keys().next().value);
    cached.set(key, registry);
  }
  return cached.get(key);
}

export function validRegistry(snapshot) {
  try { registryFor({ command_registry: snapshot }); return true; }
  catch { return false; }
}
export const commands = installed.commands;
export const mcpTools = installed.mcpTools;
export const limits = installed.limits;
export const entityTypes = installed.entityTypes;
export const actionProperties = installed.actionProperties;
export const object = installed.object;
export const validField = installed.validField;
export const validActionProperty = installed.validActionProperty;
export const entityTypesFor = context => registryFor(context).entityTypes;
export const mcpToolsFor = context => registryFor(context).mcpTools;
export const commandFor = (name, context) => registryFor(context).commandFor(name);
export const nativePlan = (command, args, context) => registryFor(context).nativePlan(command, args);
export const validWorldPlan = (plan, context, native = false) => registryFor(context).validWorldPlan(plan, context, native);
export const plannerCommands = context => registryFor(context).plannerCommands(context);
export const plannerCatalog = context => registryFor(context).plannerCatalog(context);
export const plannerSchema = (catalog, context) => registryFor(context).plannerSchema(catalog);
export const runtimeCommands = context => registryFor(context).runtimeCommands(context);
export const runtimePlan = (command, args, context) => registryFor(context).runtimePlan(command, args, context);
export const isRuntimeName = (name, context) => registryFor(context).isRuntimeName(name);
export const isWorkshopName = (name, context) => registryFor(context).isWorkshopName(name);
export const normalizePlannerPlan = (plan, context) => registryFor(context).normalizePlannerPlan(plan, context);
