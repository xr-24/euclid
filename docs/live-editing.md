# Live editing: the next seams

Goal: a change to Euclid, made by an agent or by you, reaches the running world
as seamlessly as possible. It needs no restart, no manual loading and no
waiting, and it works for any file, not a list of editable properties. [Hot
loading](architecture.md#hot-loading) is the base this plan builds on. Each
item below names what is missing, what will change and how we know it works.

Status: **planned**, **building** or **done**, updated as each lands.

## 1. Agents learn what happened to their change (planned)

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

Verified by: gateway tests for the route and the draft state, plus the world's
hot check posting a report.

## 2. Live tweak, then keep (planned)

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

## 3. Two live drafts on the same file (planned)

Missing: when two live drafts change the same file, discarding the earlier one
put back the text it saw at load time, silently undoing the later one.

Change: each file keeps a stack of layers, one per live draft, over the
committed text:
- Discarding a draft removes only its layer.
- Committing a draft folds its layer into the base.
- The world always shows the top layer.

Verified by: the hot check loads two drafts on one file, discards the lower one
and keeps the upper one's text.

## 4. Assets without a restart (planned)

Missing: replacing a downloaded model, material or sky under the same ID kept
the old copy cached until a restart.

Change:
- Asset libraries clear a replaced asset from their caches.
- The environment rebuilds when something in it uses that asset.
- Scripts can declare `static func _hot_changed(paths)` to refresh any other
  cache when hot loading changes files.

Verified by: core tests for cache invalidation.

## 5. Faster commit checks (planned)

Missing: a commit's checks took about 6.5 minutes whatever the draft changed.

Change: checks are scoped by what the draft touches:
- A draft of world files skips the gateway tests unless it changes the command
  sets the gateway validates.
- Screenshots of every environment are taken only when a draft changes how
  something looks or is built: shaders, art, rendering, zones, pieces, scenes.

Verified by: gateway tests for the scope rules.

## 6. In-world edits into the project (planned)

Missing: props you place, pieces you edit and atmosphere you set live in your
user data. They do not ship with the project or show up in Git history.

Change:
- `save_environment` turns the current environment's in-world edits into a
  draft of the environment's own files in `world/data/zones/<id>/`: its pieces
  and its saved props.
- After review, the commit makes them part of the project for everyone.

Verified by: core tests for the export, plus a gateway test that the draft
contains the expected files.

## Smaller seams (planned)

- **Shader gate.** Changed shaders compile before they load. A shader that
  fails to compile is refused with its error, like a script that fails.
- **Rewind timeline.** The wrist computer's **Live** page lists the changes
  loaded live, newest first. Selecting one unloads it. The draft stays open, so
  **Load live** brings it back.
- **Environment packages and command sets.** These are now hot: a changed
  `zone.json` rebuilds the environment, and a changed command set reloads the
  command registry. Agents see the new tools on the world's next sync.
