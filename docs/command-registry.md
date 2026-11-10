# Commands and entity schemas

Project-owned definitions in `world/data/commands` are the shared command catalog.
The gateway and Godot read the same files. Adding a built-in command requires
its declaration and its handler. MCP discovery, F2 planning, scene scoping,
and handler selection use that declaration.

## Definitions

Each command has a name, description, service, handler, field schemas, required
fields, effect, world-mutation flag, undo ownership, scope, and visible surfaces.
The services are scene editing, world operations, animation, asset preparation,
and development drafts. Surfaces are `palette`, `f2`, and `mcp`.

`schema.json` owns reusable argument definitions, entity types, and editable
properties. The schema subset shared by JavaScript and GDScript includes types,
references, alternatives, string patterns and lengths, numeric ranges, array
lengths, required object fields, and rejection of unknown fields.
`uniqueBy` validates named settings without repeated keys. `multipleOfHint`
is an inspector step size.

The MCP projection expands schema references. The F2 projection supplies
descriptions and argument schemas only for commands available in the current
context. Its structured-output envelope is validated against the selected
command after planning. Additional argument fields are generated from the live
catalog. Empty unused envelope values retain compatibility with existing agent
responses.

Each running world publishes its loaded registry with its session. The gateway
validates and caches that snapshot for discovery and planning. A Workbench
preview can expose new command names and changed ranges while the primary
world keeps its own catalog. Older clients use the installed catalog.

Palette numeric fields and action buttons use the shared declarations. Entity
factories remain trusted Godot code. The entity schema selects a factory and
provides defaults, dimensions, supported behavior outputs, and asset sources.

## Handler and transaction ownership

`workshop/command_registry.gd` resolves scene commands to the existing
`WorldTools` methods. The local aliases used by the palette and saved plugins
remain supported. Public scene arguments are translated by
`workshop/scene_commands.gd`. Persistent scene mutations still pass through
`WorldTools._commit`, which saves the snapshot and undo journal together before
changing the scene.

`agents/world_commands.gd` owns travel, environment creation, companion control,
and imported-model operations. `agents/development_commands.gd` owns the F2
development routes. The coordinator supplies the active session and checks
that a delayed result still belongs to its originating scene.

Undo ownership is explicit. `scene` commands use the scene journal.
`prop` covers saved prop animation, while companion motion uses its own save.
`none` covers commands with no undo operation. A new mutation handler must use
its declared owner's transaction API.

## Runtime capabilities

Workshop actions and behavior attachments are projected from their live
catalogs using the templates in `schema.json`. A previewed action appears in
MCP and F2 discovery. Discard removes it. Actions retain their scene and
revision checks when invoked.

Each available behavior supplies an `attach_behavior_<id>` command. Its native
arguments include the entity target and the numeric settings declared by the
plugin. The command delegates to the ordinary behavior attachment path.
Both generic behavior tools and existing workshop wrappers remain available.

Manifests and handlers are reviewed project source. Imported model metadata
cannot register code or handlers.

## Verification

`gateway/command-registry.test.mjs` runs Godot's
`diagnostics/command_contract.gd` when the project Godot binary is available.
It compares the complete loaded catalogs, verifies handler resolution, and
checks the same accepted and rejected argument cases in both languages.
Gateway tests also exercise runtime discovery, invocation, range validation,
and removal.
