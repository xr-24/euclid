# Environment packages

Each folder under `world/data/zones/<id>` contains a version 1 `zone.json`.
The package owns its builder, spawn, editing bounds, lighting and atmosphere,
water features, content layers, capabilities, workstation style, fallback,
and named camera views.

The shipped packages retain the stable IDs `construct`, `villa`, and `beach`.
Existing locations, prop saves, and dressing IDs retain their meaning.
Application assignments continue to live in `world/data/world.json`.

## Adding a package

Copy a package folder, give it a matching folder name and `id`, and set a
`name`, optional `description`, and optional `color`. The catalog discovers
the folder on startup. Configure its spawn, bounds, and views for its content.

`builder` names a reviewed script beneath `res://scripts/zones/`. It must
extend `RefCounted` and implement `static func build(context) -> bool`.
The private build context contains the detached root, package, manifest,
and appearance snapshot. The builder adds geometry and registers props there.
It returns false to use the package's fallback.

The Grid uses a small adapter to the same contract. Villa and shore builders
consume their package's water feature list. The villa's dressing and vegetation
paths are package layers. Future builder-specific layers can use the same
package data.

Packages are executable project content when they select a builder. Workbench
checks and preview apply before deployment. Imported asset metadata stays
outside this package loader.

## Creating an environment from a package

F2 and MCP environment creation accept an optional `template` environment ID.
Try **Create a new environment called Garden Annex using Villa Aurelia as its
template**. Omission uses The Grid.

The new environment has its own stable ID, prop save, and undo history. It
references the installed source package for geometry and defaults, so later
package revisions also update those defaults. Local prop overrides remain
scoped to that environment.

Existing custom Grid saves load with their original template.

## Views and capabilities

`views` maps names to player positions and camera targets.
`benchmark_views` and `capture_views` select those names. Diagnostics reads
the lists from the active package.

`capabilities.workshop` controls workshop availability.
`capabilities.scene_edit` controls scene mutations through the shared tool
boundary. `graphics` supplies the existing balanced-rendering policy.
Lighting values are copied from the package into renderer-owned resources.
