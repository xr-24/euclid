# Developing Euclid from inside Euclid

Euclid owns the authoring, review, testing, and activation workflow. Git, Codex,
Godot, and Blender can run as background workers. The user can inspect a change,
try it against separate saves, and decide when to install it.

## 1. General source authoring

Start a development request from F2. Give the agent a checkout pinned to a Git
revision so it can find relevant code and create, edit, or remove source files
and tests. Bring the exact diff back to F4 for review, isolated checks, playable
preview, and commit. Keep the active world and primary checkout separate from
the draft until the user installs it.

Start with a single active Godot source draft. Then add revision requests against
the same draft, durable task history, separate workspaces for concurrent agents,
and conflict review when the primary branch advances. Expand eligible source
areas alongside their validation and activation paths.

Acceptance test. Ask F2 to add undoable group duplication to the Grid palette
and write a regression test. The agent finds the implementation, the user
reviews the diff, and the isolated preview can duplicate and undo a group in
one edit. The user can finish the workflow from inside Euclid.

## 2. Session continuity and safe activation

Define reload boundaries for plugins, UI, scenes, and other replaceable
subsystems. For core changes, the launcher should verify the new boot and
restore the development session, including the conversation, draft, and
workspace. Test save migrations on copies before activation and keep an
independent fallback for launcher, gateway, and runtime failures.

## 3. Debugging and performance

Expose runtime errors, test failures, rendered captures, and frame timings in
Workbench. Let agents reproduce a problem, run named diagnostics, and attach
before-and-after evidence to a draft. Use fixed camera views, resolution, and
graphics profiles for rendering comparisons. A representative test is finding
and verifying the cause of a villa frame-time regression from inside Euclid.

## 4. Scene and asset development

Extend scene editing beyond The Grid with stable entity IDs and undo. Let
Workbench run named Blender exports and Godot imports in a draft, preserve
source assets and licensing metadata, and preview the result in-world before
commit. Keep the asset build, rendering, and gateway modules independent.
