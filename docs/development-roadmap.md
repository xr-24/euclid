# Developing Euclid from inside Euclid

Euclid owns the authoring, review, testing, and activation workflow. Git, Codex,
Godot, and Blender can run as background workers. The user can inspect a change,
try it against separate saves, and decide when to install it.

## 1. General source authoring

**In place.** F2 starts one Godot source task in a workspace pinned to a Git
revision. Codex can find code and create, edit, or remove source files and tests.
F4 reviews the exact diff before the user runs isolated checks, opens a playable
preview, or commits. The group duplication proof exercised this flow through
preview and verified that one Undo removed the duplicated group.

F4 also has a tabbed source editor with quick-open, find/replace, syntax highlighting,
per-file undo, and local recovery of unstaged buffers. F2 retains prompt recall
and scrollback across restarts. See the [Workbench editor guide](../README.md#workbench-editor).

F2 and F4 can revise the active agent-authored source draft using the existing
patch and latest checks. F4 shows the revision diff and can restore the previous
patch. Each revision or restore needs fresh checks.

A connected agent can read source, submit and revise its own draft, and run
its checks through the [development MCP endpoint](agents.md#development-tools-for-connected-agents).
Drafts record the agent that owns them.

Agent drafts can also change gateway source and tests, `README.md` and
`docs/`. A fixed kernel and the launcher scripts stay outside every draft, and
a commit that touches the gateway replaces the gateway process in place. See
[what a draft may change](draft-scope.md).

**Remaining.** Add durable task history, separate workspaces for concurrent
agents, and conflict review when the primary branch advances. Bring the
gateway and docs into the F4 editor, and label gateway activation in the
Workbench.

## 2. Session continuity and safe activation

Euclid reopens the active draft and its last completed checks, the F2
conversation, and the selected F4 file and review tab. The launcher verifies
boot and retains a separate last-known-good launch path.

The Grid palette now has a live reload boundary for checked palette-only
drafts. It carries the view into the preview, restores the working panel on
failure or discard, and keeps a committed preview active.

Expand reload boundaries to other UI and scene subsystems. Test save
migrations on copies before activation and extend independent fallback
coverage for launcher, gateway, and runtime failures.

The [embedded terminal proposal](terminal-blueprint.md) covers interactive shell
sessions, including a later gateway-hosted session that can reconnect after a restart.

## 3. Debugging and performance

F2 and F4 can run the fixed-view villa benchmark. Workbench keeps frame times,
rendered captures, and benchmark logs with the Git baseline or measured draft
version. Diagnostics also shows ordinary preview output and errors. Codex
can use both kinds of evidence to inform a revision.

**Remaining.** Add moving routes and repeatable transition measurements, then
use them to isolate villa regressions from inside Euclid.

## 4. Scene and asset development

The Grid, villa, and beach share a live prop editor, installed asset library,
and agent commands. Each scene saves placed props by stable ID and retains
its own undo history across restarts. Villa furnishings, garden props, beach
scenery, the pier, floating props, and workstations can be transformed,
hidden, and restored to authored defaults from the same tools.

Environment packages now declare reviewed builders, spawn, bounds, lighting,
water features, content layers, editing capabilities, and named capture and
benchmark views. New package folders are discovered at startup. Custom
environments can reference an installed package with separate prop saves.

**Remaining.** Add editing tools for larger authored systems such as terrain,
batched planting, and water. Let Workbench run named Blender exports and
Godot imports in a draft, preserve source assets and
licensing metadata, and preview the result in-world before commit. Keep the
asset build, rendering, and gateway modules independent.

## 5. Shared capability and entity definitions

`world/data/commands` supplies the command catalog for MCP, F2, the palette,
and Godot dispatch. Scene edits keep the existing atomic save and undo
transaction. Runtime workshop actions and behavior attachments project
through the registry. Shared entity definitions provide trusted factory
selection, defaults, dimensions, editing ranges, and supported outputs.

Cross-language tests compare the full loaded catalogs, handler mappings, and
validation results. World and development operations have separate handler
services, keeping their command-specific code out of the coordinator.
