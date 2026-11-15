# Live editing: the next seams

Goal: a change to Euclid, made by an agent or by you, reaches the running world
as seamlessly as possible. It needs no restart, no manual loading and no
waiting, and it works for any file, not a list of editable properties. [Hot
loading](architecture.md#hot-loading) is the base this plan builds on. Each
item below names what is missing, what will change and how we know it works.

Status: everything below is **done**. Each item names the commit's tests.

## 1. Agents learn what happened to their change (done)

Missing: an agent submits a draft and it loads into your world, but the agent
never learns whether it loaded, which tier it used, whether it rolled back or
why.

Change:
- The world reports every load, failure, rollback and unload to the gateway
  (`POST /v1/workbench/live-report`).
- The draft carries the report as `live_result`, and the agents' `draft_status`
  tool returns it.
- The agent's activity panel shows the result above its head.
- A rollback includes the first error and its file and line, so the agent can
  revise without you passing it along.
- No screenshot is sent with a report: what the agent may see of your screen
  stays your choice, through `/share-view`.

Verified by: gateway tests for the route and the draft state, and the world's
hot check recording the reports of a sequence of loads.

## 2. Live tweak, then keep (done)

Missing: tuning a value (a light's energy, a colour, a position) takes a source
edit and a reload.

Change:
- Three commands, available on every surface (F2, the palette and MCP):
  - `inspect_scene` lists a node's children and properties;
  - `tweak_property` sets any property on any node now;
  - `keep_tweaks` writes the tweaks held this session into
    `world/data/tweaks.json` as a draft.
- The world applies tweaks from that file whenever an environment is built,
  and to the rest of the world at startup.
- Tweaks address nodes by path from the world root, so this works for any
  property of any node without a list.

Verified by: core tests for the tweak layer, and the hot check tweaking a node
in the real world.

## 3. Two live drafts on the same file (done)

Missing: when two live drafts change the same file, discarding the earlier one
put back the text it saw at load time, silently undoing the later one.

Change: each file keeps a stack of layers, one per live draft, over the
committed text:
- Discarding a draft removes only its layer.
- Committing a draft folds its layer into the base.
- The world always shows the top layer.

Verified by: the hot check loads two drafts on one file, discards the lower one
and keeps the upper one's text.

## 4. Assets without a restart (done)

Missing: downloaded models and materials already load at runtime, but once one
was cached there was no way to load it again after its files were replaced.

Change:
- `refresh_asset` (by `asset_id` for a model, or by `material`) clears every
  cache layer for it: the model's scene, or the material's decoded maps, its
  texture set and the materials built from it.
- It rebuilds the environment when the environment uses that asset.
- Scripts can declare `static func _hot_changed(paths)` to refresh any other
  cache when hot loading changes files. The package registry, the command
  registry and the tweak layer do.

Project art stays out of Git, so it never travels in a draft.

Verified by: core tests for cache invalidation.

## 5. Faster commit checks (done)

Missing: a commit's checks took about 6.5 minutes whatever the draft changed.

Change: checks are scoped by what the draft touches:
- A draft of Godot scripts, shaders or scenes runs every Godot check but skips
  the gateway tests (scope `world`), because the gateway never reads those
  files. World data still runs everything, because the gateway reads it.
- Screenshots of every environment are taken only when a draft changes how
  something looks or is built: shaders, scenes, assets, rendering, zones,
  pieces and simulation scripts, `world_art.gd`, and environment data.

Checks no longer block seeing a change, since hot loading runs first; they
only gate the commit.

Verified by: gateway tests for the scope rules.

## 6. In-world edits into the project (done)

Missing: props you place, pieces you edit and atmosphere you set live in your
user data. They do not ship with the project or show up in Git history.

Change:
- `save_environment` turns the current environment's in-world edits into a
  draft of its package, `world/data/zones/<id>/zone.json`:
  - its pieces, which include the props you placed and the terrain you
    sculpted;
  - its atmosphere settings.
- Unchanged pieces keep their exact text. New and changed ones follow the
  package's own formatting, so the diff shows only what you changed.
- The piece revision rises, so your saved document folds into the new
  defaults after the commit.
- Environments made in Euclid live only in your user data; they have no
  package to save into yet.

Verified by: a core test of changed, added and removed pieces and atmosphere
on a real package, and the hot check exporting an unedited environment byte
for byte.

## Smaller seams (done)

- **Shader gate.** Changed shaders compile before they load. A shader that
  fails to compile is refused with its error, like a script that fails.
- **Rewind timeline.** The wrist computer's **Live** page lists the changes
  loaded live, newest first. Selecting one unloads it. The draft stays open, so
  **Load live** brings it back.
- **Environment packages and command sets.** These are now hot: a changed
  `zone.json` rebuilds the environment, and a changed command set reloads the
  command registry. Agents see the new tools on the world's next sync.

# Working together in the world

The next round makes the loop of asking for a change, seeing it and approving
it work without leaving the world, for you and for agents. Status: **planned**,
**done**, updated as each lands.

## A. Agent vision (done)

Agents can see the world: through your eyes when they need to, or from a
camera they place.

- `capture_view` renders the 3D world off-screen and returns an image to the
  agent. It can look from your current view or from a point the agent chooses,
  aimed at a point or a node. It can also use a named camera the agent placed
  earlier with `place_camera`. The image comes back to the agent as an
  image. It is 768 by 432, includes the first-person body, and is checked by
  `-- --vision-check <dir>` (needs a renderer).
- The render never contains Euclid's interface or private surfaces: terminals,
  desktop and app panels, and anything else in the `private_world_surfaces`
  group. Agents see the world, not your screen.
- **Agent vision** on the wrist's System page sets what is allowed: your view
  and placed cameras, placed cameras only, or off. A short notice tells you
  each time an agent looks.

## B. Point and ask (done)

You look at something and press a key. Your next message to an agent then
carries what you are looking at: the node's path, its piece or asset ID, its
material and where you stand. "Make this warmer" then needs no searching.

## C. Approvals in the world (done)

When something needs your yes, a card appears by the agent (or in front of
you) with a one-key answer: loading a connected agent's draft live,
committing a draft whose checks passed. F4 remains for reading diffs. A soft
restart still happens on its own, with a notice; asking first would leave a
half-loaded change waiting on you.

## D. Status strip (done)

A thin line at the edge of your view shows what is live, which checks are
running, which approvals wait and the last rollback.

## E. Frame-time cost of every live load (done)

Each live load measures the main view's render time (CPU and GPU, not capped
by vsync) over 20 frames before and after. It reports the difference with the
load, to you and to the draft's agent as `frame_ms`. The compatibility
renderer does not measure render time, so there the figure is left out.

## F. A primer for agents (planned)

On connecting, agents receive a short, current briefing built from the same
data files: what loads live and at which tier, tweaks versus drafts, saving
environments, vision, and the house rules.

## Smaller (planned)

- **Undo by agent.** "Undo what scout did" unloads its live changes and
  reverts its commits.
- **Optional auto-commit.** A draft whose checks passed and which stayed live
  without a rollback for a set time can commit itself. Off by default.
- **Who is touching what.** `draft_status` lists the files other agents hold
  live, so an agent can avoid them before editing.
