# Environment packages

Each folder under `world/data/zones/<id>` contains a version 1 `zone.json`.
The package owns its piece tree, spawn, editing bounds, lighting and atmosphere,
water features, content layers, capabilities, workstation style, fallback,
and named camera views.

The shipped packages retain the stable IDs `construct`, `villa`, and `beach`.
Existing locations, prop saves, and dressing IDs retain their meaning.
Application assignments continue to live in `world/data/world.json`.

## Adding a package

Copy a package folder, give it a matching folder name and `id`, and set a
`name`, optional `description`, and optional `color`. The catalog discovers
the folder on startup. Configure its spawn, bounds, and views for its content.

Declare geometry using the registered types in `pieces`. The Grid and Open Ground use
this contract. The villa and shore still use reviewed legacy builders and declare their
water and content layers in package data. A legacy builder receives a private context with
the detached root, package and manifest. Returning false requests the package fallback.

## Creating an environment from a package

F2 and MCP environment creation accept an optional `template` environment ID.
Try **Create a new environment called Garden Annex using Villa Aurelia as its
template**. Omission uses The Grid.

The new environment has its own stable ID, prop save, piece document, and undo history.
It copies the source environment's current piece tree. A package can increment
`piece_revision` to add new root pieces to older documents and their undo snapshots.
Existing Grid saves gain the structural pieces once, and later saves respect intentional
removals.
Packages can supply `piece_replacements` with exact previous root records. An upgrade can
replace those untouched defaults while preserving locally edited pieces.

## Views and capabilities

`views` maps names to player positions and camera targets.
`benchmark_views` and `capture_views` select those names. Diagnostics reads
the lists from the active package.

`capabilities.workshop` controls workshop availability.
`capabilities.scene_edit` controls scene mutations through the shared tool
boundary. `graphics` supplies the existing balanced-rendering policy.
Lighting values are copied from the package into renderer-owned resources.
`piece_bounds` can extend the piece editing area beyond the prop placement bounds.
