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

The Workbench keeps a journal of every draft: who drafted it, each revision and
check with its scope, and whether it was committed, discarded or reverted. It
survives restarts and outlives the draft. Connected agents read it with
`task_history`, and `POST /v1/workbench/history` returns it.

When the main branch moves past a draft, the Workbench `rebase` action replays
the reviewed patch onto the new tip with a three-way merge. The draft keeps its
id, loses its earlier versions, and needs fresh checks. A conflict names the
files and leaves the draft as it was. Agents use `rebase_draft`.

Each connected agent can have [its own credential](agents.md#agent-credentials).
The gateway takes the agent's name from it, and the shared route can no longer
use that name.

Up to four drafts can be open at once, one per connected agent plus the
person's, each in its own worktree. See [several agents at once](agents.md#several-agents-at-once).

F4 lists the open drafts beside its title, offers **Rebase** when the main
branch has moved, labels gateway reloads, and shows the journal in a
**History** tab.

**Remaining.** Let checks for different drafts run side by side. Bring the gateway and
docs into the F4 editor, and label gateway activation in the Workbench.

## 2. Session continuity and safe activation

Euclid reopens the active draft and its last completed checks, the F2
conversation, and the selected F4 file and review tab. The launcher verifies
boot and retains a separate last-known-good launch path.

The Grid palette now has a live reload boundary for checked palette-only
drafts. It carries the view into the preview, restores the working panel on
failure or discard, and keeps a committed preview active.

That boundary is now the shared `ui/panel_swap.gd`, so another panel becomes hot-swappable by stating its contract in a subclass. Extend it to the remaining UI and to scene subsystems. Test save
migrations on copies before activation and extend independent fallback
coverage for launcher, gateway, and runtime failures.

The [embedded terminal proposal](terminal-blueprint.md) covers interactive shell
sessions, including a later gateway-hosted session that can reconnect after a restart.

## 3. Debugging and performance

F2 and F4 can run the fixed-view villa benchmark. Workbench keeps frame times,
rendered captures, and benchmark logs with the Git baseline or measured draft
version. Diagnostics also shows ordinary preview output and errors. Codex
can use both kinds of evidence to inform a revision.

Checks and benchmarks no longer copy about 2 GiB of art and import cache each
time. The runner keeps one private copy, updates only changed files, and
hard-links it into each preview. Across drives it falls back to copying.

Checks are scoped to what a draft changes. Documentation runs nothing, and
gateway code skips the Godot core and smoke tests.

**Remaining.** Attach rendered screenshots to check results. Add
moving routes and repeatable transition measurements, then use them to isolate
villa regressions from inside Euclid.

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
