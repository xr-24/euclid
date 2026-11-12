# Euclid

A first-person desktop prototype: applications have places, and agent work can have a visible presence. This repository starts with a normal Windows application, leaving Linux compositor work behind a separate boundary.

## Run it

Double-click **Start Euclid.cmd**. This starts the local gateway and opens the world in borderless fullscreen with a 1920×1080 launch size. Press **F4** in that session to open Workbench. On this machine Godot is already downloaded into `.tools/godot/`. Node 22 is already installed, and there are no npm dependencies to install.

For another Windows machine, install Node 22 or later, then run `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/setup.ps1` once. The setup script downloads the pinned Godot build from its official release and verifies its SHA512 checksum. It does not install Godot system-wide.

A successful launch from a clean Git checkout records that revision for recovery.
If Euclid fails to start, double-click **Start Euclid Recovery.cmd**. It runs the
last recorded revision in a separate checkout with separate saves and no gateway.
Allow about 2.25 GiB for the temporary art copy. Startup logs are under
`.local/recovery`.

| Control | Action |
| --- | --- |
| WASD and mouse | Move and look |
| Space | Jump; swim up in deep water |
| C | Dive while swimming |
| Hold left mouse | Aim the palm beam and drag the prop under the crosshair |
| Wheel while dragging | Rotate, resize, or change distance |
| Middle click while dragging | Cycle the wheel mode |
| Right click while dragging / aiming at a locked prop | Lock in place / unlock |
| 1, 2, 3 | Shift the world around you to The Grid, the villa or the shore |
| E while near and facing an object | Open an application preview, inspect an agent |
| E while near and facing an agent avatar | Open that agent’s conversation |
| Tab | Raise or lower the wrist computer |
| Q / E, or ← → (wrist up) | Previous / next wrist page |
| ↑ ↓ or mouse wheel, then Enter or left click (wrist up) | Select and confirm |
| Right click in a menu | Back |
| Escape | Lower the wrist or return from a panel; with neither up, raise the wrist on System |
| B | Open Grid or Scene tools at the crosshair |
| F2 | Open or minimize Agent Chat |
| F11 | Toggle fullscreen |
| F3 | Toggle live performance statistics |
| F4 | Open or close Workbench |

There is no menu screen. Press **Tab** and your left forearm comes up the way you would check a
watch, and the wrist computer projects a hologram above it. Its pages are **Areas** (shift to
any space, custom ones included), **Build** (open Grid or Scene tools, or describe what you want
and let Codex build it), **Agents** (send a quick command or open Agent Chat),
**Workbench** (source, terminal, agents and history) and **System** (fullscreen, graphics, and
save and quit, which asks you to confirm twice). You can keep walking and looking while it is up;
only typing holds you still. Opening any panel lowers it.

Drag the three-dot handle to move a desktop panel, or drag its edges and corners to resize it.
In Grid or Scene tools, click the color swatch and choose **Apply** to save the change.

**Build → Scan Object** opens a live inspector. Frame a prop or water surface
in the left pane while walking. The wrist renders the selected prop and shows
its editable properties. Scroll to a property, left-click, type a value, and
left-click or press Enter to apply. Water uses a material preview and saves
per-surface color, reflectivity, roughness, ripple and foam settings where supported.
Right-click returns to Build.

In **Open Ground**, open **Build → Terrain** or press **B → Terrain**. Pick **Raise**,
**Lower**, **Smooth**, **Flatten**, or **Paint**, then left-drag the brush ring across the
ground. Hold middle mouse to look and move. Flatten samples the height where you begin.
Paint blends dry earth, sand, and rock. Releasing the mouse saves one undoable stroke
and updates the walkable surface.

Let go of the palm beam to drop the prop where it is; it keeps the turn you gave it.
Right-click while holding it to place it and lock its physics there instead. Right-click a
locked prop to make it movable again, including while holding it. Unlocked props respond to gravity and can be pushed by
walking into them. Scripted props and structural surfaces retain their own motion rules.

The Grid, a villa and a beach share the same space. Press 1–3 (or pick a zone on the wrist computer's Areas page) and the world is rewritten around you in place. A sphere expands from your eyes, the old zone unravels into a blue lattice with streams of 1s and 0s pouring down it, and the new zone climbs up out of the same lattice while the sky, sun and atmosphere blend across. There are no portals. Zones are built on a worker thread and global illumination re-settles while the effect still covers the change, so a shift neither freezes the game nor flashes at the end. If the spot you are standing on would leave you inside a hill or out in deep water in the new zone, you arrive at its usual starting point instead. The villa, Villa Aurelia, is modelled on the Getty Villa and stands on a sandstone bluff about 80 m above a sandy cove on a Laguna Beach-style coast, with rocky headlands either side, coastal sage scrub and ice plant on the bluffs and rolling hills behind. You arrive in the outer peristyle: a long garden court with fluted limestone colonnades under coffered ceilings, Pompeian red frescoes, clipped box hedges (built leaf by leaf), olive trees, a reflecting pool fed by bronze lion-head fountains and an open south end looking out over the sea. North of it is the house: an entrance hall between two sculpture galleries, an inner peristyle with a long narrow pool and bronzes, an atrium open to the sky over its rain pool, the hall of Herakles, and the library, where the study terminal and the example worker now sit. Doors lead on to a walled east garden with a round fountain and a lion-head wall fountain, terraced herb and fruit gardens stepping down toward the bluff, and an outdoor theatre facing the house's west door. The reflecting pool runs its own shallow-water simulation, so the fountains keep a ripple moving down it and you can wade in from the ramp at its south end. The shore is a sheltered cove at golden hour, with wind-rippled sand that darkens and turns glossy toward the waterline, real simulated surf (a GPU shallow-water solver: waves shoal over the seabed, break, run up the sand and drain back, leaving wet sand and foam lines that dry over time) that you can walk and swim out into; you leave a wake and splash, and barrels, a crate and a buoy float and drift on it, rocky headlands, windswept trees and a weathered pier. Materials and most models are CC0 scans from [Poly Haven](https://polyhaven.com) (see `world/assets/thirdparty/polyhaven/CREDITS.md`). The villa's statues, busts and sarcophagi are museum and artist scans from Sketchfab under Creative Commons licences; they live in a licence-sorted asset library with generated credits (`world/assets/library/`, credits in `world/assets/library/CREDITS.md`), and where they stand is plain data in `world/data/dressing/villa.json`. Some of them are non-commercial only; see `world/assets/library/README.md` before selling or open-sourcing Euclid. Each zone has its own HDRI sky with a matched sun, and Forward+ adds SDFGI bounce light, SSR, SSAO/SSIL, volumetric fog and AgX tonemapping. The surf uses the MIT-licensed [Realistic Shoreline Waves](https://reboot16.itch.io/godot-rsw) solver by Reboot16, vendored in `world/thirdparty/shorewaves`. It needs Forward+ with a GPU; otherwise the shore falls back to the shader ocean. The Grid is a dark digital workshop. Other zones fall back to blockout geometry if their art is missing. Location, zone and viewing direction save automatically and restore on restart. Application identities and anchor assignments live in `world/data/world.json` independently of scene geometry.

## Build in The Grid

Press **1** to enter The Grid. Aim at the floor and press **B**, then choose **Spawn orange cone**. If you're aiming into the distance, the palette places it a few metres ahead. Aim at an existing cone before pressing **B** to select it, or pick it from the entity list. Change its position, yaw, scale or color, then press **Apply**. Duplicate, delete and undo are in the same palette.

While the palette is open, the selected prop has handles you can drag in the world. Press
**Q** (or **Handles** in the panel) to switch between two sets:

- **Move**: the red, green and blue arrows move it along X, Y and Z, the white ball slides it
  over the ground and the yellow ring turns it.
- **Shape**: a cube-tipped handle on each face stretches the prop from that side along its own
  axes, keeping the opposite face where it is; the white cube resizes it evenly. **Reset shape**
  in the palette undoes the stretch.

Hold **Ctrl** while dragging to snap (25 cm, 15°, 0.1× or a tenth of the stretch), and press
**Escape** mid-drag to put it back. Click another prop in the world to select it, and hold the
middle mouse button to look around. Each drag is one undo step, and the fields update to match.
Agents can stretch props too, with the `stretch` property.

Entity edits save to `grid-entities.json` alongside the existing location save. Each scene keeps up to 64 undo steps across restarts.

To edit environment pieces, choose **Pieces** from the **B** palette or the wrist’s **Build**
page. Pick **Open Ground** from **Areas** for an environment built from pieces. Add a shape,
light, group or model, select it from the list and use **Apply** to save changes. You can move
and rotate it with the world handles, and **Undo piece** reverses the last edit. See the
[environment authoring guide](docs/environment-authoring.md) for the matching agent tools.

To reuse an entity in another Grid space, select it with **B**, enter a name, and
click **Save prefab**. In any Grid space, pick it from the library and click
**Place prefab**. Each copy has its own position and edits. The prefab keeps
the source model, orientation, scale, color, and any saved animation. Imported
models still use the local model cache.

In **F2**, with a single cone in the space, try **Save the cone as a prefab
named Signal Cone**, then **Place the Signal Cone prefab**. The native CLI
discovers `list_entities`, `list_prefabs`, `save_prefab`, and `spawn_prefab`.
The local prefab library holds up to 64 named snapshots. Grid undo reverses
placement and edits to an instance.

To try the local agent, launch Euclid normally, open Grid tools and enter **Make me a bright orange traffic cone**. Press **Ask Codex** and keep the palette open. Euclid uses the installed Codex CLI with ChatGPT sign-in. Run `codex login` first if needed. If the launcher cannot find the native executable, set `EUCLID_CODEX_BIN` to its full path.

Codex can propose one cone with a color and scale. Euclid places it at the crosshair location captured when the palette opened and selects it in the inspector after saving. The same **Undo** button reverses a player or Codex edit.

## Agent Chat

Press **F2**, or choose **Message** on the wrist’s Agents page. Use **+** to open a conversation with a local worker or an agent registered in Workbench. Use the conversation tabs to switch between open chats. Codex and Claude take requests through their local CLI workers. Registered agents receive messages in their inbox. The arrow on the Codex tab opens the interactive Codex CLI in a native Windows terminal.

An avatar appears when you first contact its agent in a running session. Codex is red, Claude is orange, and cloud agents have a blue gradient. Aim at a nearby avatar and press **E** to open its conversation.

Local agents can use Euclid’s world tools to find or change environments. Try **Take me to the Roman villa**, **Follow me**, or **Stay here**. **Quick Command** on the wrist also supports the direct world planner for short Codex requests.

Created environments appear under **Custom spaces** and keep separate entity saves. The Grid is the default template. The hovering avatars follow across environments and space themselves apart. **Stay here** parks the addressed local agent in its current environment for the session. The musical note toggles spoken world-tool results through an installed English system voice.

## Choose the agent

Codex is the default agent. Set `EUCLID_AGENT=claude` before starting the
gateway to use Claude Code for planning and source drafts, or set
`EUCLID_AGENT_PLAN` and `EUCLID_AGENT_AUTHOR` separately. See the
[agent adapter guide](docs/agents.md).

## Extend Euclid through shared definitions

`world/data/commands` declares the built-in capabilities used by MCP, F2,
the palette, and scene editing. The same schemas supply property validation,
inspector ranges, entity defaults, and prefab properties. Registered workshop
actions and behavior attachments appear in the live command catalog.
See the [command registry guide](docs/command-registry.md).

`world/data/zones/<id>/zone.json` declares each environment's reviewed builder,
spawn, bounds, lighting, content layers, water features, editing capabilities,
and named views. New package folders are discovered on startup. Custom spaces
can reference any installed environment package. See the
[environment package guide](docs/zone-packages.md).

## Edit props in the villa and at the beach

Press **B** while aiming at solid ground in either scene. Choose an installed
model and select **Place asset**, or place a prefab from the shared library.
Aim at a prop and press **B** to select it. You can also select it by
name in the palette. **Apply** saves its name, position, rotation, scale, and
color for placed props. You can also move, rotate, resize, rename, or **Hide**
authored props. These include the villa’s statues, planters and garden trees,
the beach’s pier, lantern, shoreline scenery and floating props, and the
workstations. Parts such as a plinth, collision, or a workstation’s app prompt
follow the prop. Select a hidden item in the list to **Restore defaults**. The
palette and agent commands share each scene’s undo history across restarts.

In **F2**, try **Place an antique ceramic vase here and call it Garden vase**,
**Rotate the wooden pier to 135 degrees**, or **Undo the last scene edit**.
The native CLI can discover the installed library with `list_scene_assets`
and prop IDs with `list_entities`. It can call `restore_dressing` on an authored
prop. Prop mutations require the active environment ID. Floating props keep
simulating after edits. Their position fields set the release point, and the
agent tools also report their current position.

## Live models

In any environment, press **F2** and ask **Spawn a piece of pizza**.
Codex derives a search phrase, searches Sketchfab and Poly Haven, chooses an actual
result, and starts a background import. Euclid downloads the prepared GLB and
loads it while the world is running. The object appears a few metres in front
of the position where the import began. Changing environments during preparation
keeps the model cached for a later spawn.

Aim at the object and press **B** to select it. The same position, rotation,
scale, color, duplicate, delete and undo controls work for imported models.
Models and entity records survive restarting Euclid. **List imported assets**
in F2 shows the source, author and license credits.

The native Codex CLI discovers `search_assets`, `import_asset`, `asset_status`,
`list_assets` and `spawn_entity` through Euclid's MCP server. Search returns real
provider IDs. Import starts an asynchronous job, and `asset_status` reports when
the model is ready for `spawn_entity`. Optional spawn arguments include position
and scale. These tools work with the running world's session and report a spawn
after the world applies and saves it.

Sketchfab uses `SKETCHFAB_API_TOKEN` or the existing ignored key file
`.local/sketchfab-key.txt` (also accepts `.local/sketchfab_token.txt`). The key
stays in the gateway. Provider metadata and original license credits are retained
with every prepared asset. Poly Haven imports include **Powered by Poly Haven**.
The gateway and terminal discover native Codex installations from PATH, npm's
native package, and the Codex desktop installation. `EUCLID_CODEX_BIN` overrides
that discovery.

Preparation runs in disposable background Blender, using `BLENDER_BIN` when set
or the installed Windows Blender. Static props are reduced to roughly 30,000
triangles and 1024-pixel textures, with a one-metre longest edge and a floor-level
origin. Spawn scale ranges from 0.25 to 4. Collision uses a bounding box. Downloads
are limited to 64 MB and two concurrent imports. Native provider files and
prepared models are cached under `.local/runtime-assets/`; the renderer's copies
live under `user://runtime-assets/`. World saves contain asset IDs and transforms,
and never remote scripts or paths. Background import logs stay in the ignored
cache directories.

## Live behaviors

Spawn a cone in The Grid. Select it with **B**, choose **Proximity pulse**, and
click **Apply behavior**. Adjust **Radius (m)** in the same inspector. In **F2**
with a single cone, try **Make the cone pulse when I come within five metres**.
The native agent tools `list_behaviors` and `set_behavior` use the same settings.
Behavior changes support Grid undo, and prefabs keep their behavior settings.

To change the code while the cone is in the world, launch **Start Euclid
Workbench.cmd**, press **F4**, and open
`world/scripts/plugins/proximity_pulse.gd`. Ask Codex to **Change `PULSE_HZ`
from 1.0 to 2.0**. Choose **Review diff**, then **Preview live**. Close the
panel and approach the cone. **Discard** restores the previous code, and
**Run checks → Commit** keeps the previewed version and records it in Git.

### Create a pressure-plate plugin

Place a **Spawn plate** and **Spawn door** from **B** in the same Grid space.
Leave a little room between them. In **F4**, enter **Make this pressure plate
open the sliding door while I stand on it** and click **Create plugin**. Codex
uses the scene's entity IDs and drafts both the GDScript and its manifest.

Review the diff and choose **Preview live**. Step onto the plate, then step off.
Select the plate with **B** to adjust its trigger radius or door speed during the
preview. **Discard** removes the new registration and test link. **Run checks →
Commit** keeps the plugin and saves the link in this Grid space. For reuse, save
the plate as a prefab or attach the new behavior to another plate and pick a door
in its inspector. Prefabs carry the behavior settings and let you choose a local
target after placement.

Live preview accepts one registered behavior edit or one new plugin package.
The preview compiles and probes the code before activating it. The developer-mode
plugin runs inside Euclid with your local account's permissions.

## Live animation

Press **F2** and ask **Preview a four-second loop where the companion raises
her left forearm and tilts her head**. Close the console to watch the loop.
Ask for a revision, then say **Save this animation** or **Discard this preview**.
Only saving writes the clip. Discarding restores the motion that was playing
before the draft. Leaving a Grid space discards its prop preview.

In The Grid, try **Preview the pizza slice gently floating and spinning** after
spawning one. Saved prop clips are part of the entity save and support Grid
undo. Saved companion motion follows the companion between environments.

Ask for a **rigged** model when importing a character, such as **Import and
spawn the rigged Sphere Bot from Sketchfab**. Rigged imports have separate
cache IDs and retain one skinned skeleton and any source clips. Models without
a rig support whole-object translation and rotation. Rigged props also support
named joint rotations. Props use a collision box that follows the object's
transform.

The native CLI exposes `inspect_animation`, `preview_animation`,
`save_animation` and `discard_animation`. Inspect a target to find its exact
ID, supported channels, current clip and joint names. Author a closed loop of
1–30 seconds with keyframes at zero and at the end. The companion supports
either named joints or its original Lift and Drift pose channels in a clip.
The native `import_asset` tool accepts `preserve_rig: true` and returns the
separate rigged asset ID for `spawn_entity`.

### Player rig

Open **Tab → Build → Player Rig**. The shell and joint swatches recolor both
the world-space body and the first-person arms. **Walk bob** adjusts the
amount of hand motion while walking.

Choose a hand pose, then select **Wrist** or a finger joint. Scrub the timeline,
enter an offset or rotation, and use **Set key**. Edits are additive to the
built-in pose. A loop has up to 10 keys per track, with linked start and end
values. Use **Play** to see the loop, **Save** to keep the rig across sessions,
or **Discard** to restore the last saved rig. Saved clips play when their
corresponding hand pose is active.

F2 and local world MCP agents can use `inspect_player_rig`, `preview_player_rig`,
`save_player_rig`, and `discard_player_rig` to edit the same draft.

## Atmosphere

Open **Tab → Build → Atmosphere** to change the current environment's sun (direction, height,
color, strength), sky (an installed HDRI or a painted gradient, its brightness and stars),
light (exposure, fill, shadow reach) and fog (density, color, glow toward the sun, haze).
Changes show live; **Save** keeps them for this environment, **Discard** returns to the saved
look and **Reset** goes back to the environment's own settings. Put the sun below the horizon
for night; stars come out as it sets.

Agents use the same draft through `inspect_atmosphere`, `preview_atmosphere`,
`save_atmosphere` and `discard_atmosphere`, for example **Make it dusk with a few stars and a
light warm haze**. Edits are saved per environment in `atmosphere.json` beside the other saves,
so an environment's package still supplies the defaults. The plan for authoring whole
environments from inside Euclid is in [environment authoring](docs/environment-authoring.md).

## Develop from inside Euclid

See the [in-Euclid development roadmap](docs/development-roadmap.md) for the current status and remaining milestones.

### Workbench editor

**F4** opens Euclid's source editor in your running session. Pick a file in the sidebar or
press **Ctrl+P** and type part of its name. Each open file has a tab with its own undo
history and scroll position. **●** marks unstaged edits. The editor has a minimap, code
folding, word completion, and highlighting for GDScript, shaders, JSON, and occurrences
of the word under the cursor.

| Keys | Action |
| --- | --- |
| Ctrl+P | Go to file |
| Ctrl+F / Ctrl+H | Find / replace in this file (Enter next, Shift+Enter previous) |
| Ctrl+G | Go to line |
| Ctrl+/ or Ctrl+K | Toggle line comments |
| Alt+↑ / Alt+↓ | Move lines |
| Ctrl+Shift+D / Ctrl+Shift+K | Duplicate / delete lines |
| Ctrl+D | Add a cursor at the next occurrence |
| Ctrl+Space | Complete a word (also offered while you type) |
| Ctrl+Tab / Ctrl+Shift+Tab | Next / previous file tab |
| Ctrl+W | Close the file tab and discard its unstaged edits |
| Ctrl+S | Keep unstaged edits on this PC so they survive a restart |
| Ctrl+= / Ctrl+- | Text size |
| Ctrl+B | Show or hide the sidebar |

**Ask Codex** in F4 applies each proposal as one undoable step in each affected file.
Unstaged edits save locally about every five seconds and restore when you reopen the
same file at the same on-disk version. **Ctrl+S** saves immediately. To drop a restored
edit, press **Ctrl+Z**, then **Ctrl+S**.

The **Diff** and **Checks** tabs have their own highlighting. Double-click a `res://…:line`
location in **Checks** to jump to a matching open source file. While a draft is active,
use **Diff** to review its changed or added lines. The **FX** button toggles Workbench's
typing and deletion effects, caret trail, file reveal, and panel glow.

### Ask from the beach

Go to the beach and press **F2**. Ask
**Make the shoreline foam softer**. Codex drafts an edit to the shoreline
appearance file and starts the Workbench checks. **Review draft** opens the
diff and logs. When checks pass, **Preview live** applies the look to the
current surf and wet sand. Close the panel to look around. **Discard** restores
the previous look. Open the draft and **Commit** to keep the previewed settings.

This live edit covers foam strength and edge softness on simulated surf. It
uses the same Git draft, check, and revert commands as the rest of Workbench.

### Ask from The Grid

Press **F2** and ask **Spread the Grid floor lines farther
apart** or **Make the distant Grid walls taller**. After checks pass, **Preview
Grid reload** replaces the scenery in place. Your position, agent, and placed
objects stay in the world. These settings apply to the shared Grid template.

You can also ask for a new behavior plugin for existing objects. For example,
place a pressure plate and sliding door, then ask **Write a plugin that opens the
door while I stand on the plate**. The same review, preview, and discard actions
are available after checks pass.

To give Codex a new tool, place a sliding door and a cone, then ask in F2
**Build a workshop tool that closes this door and resets the cone to its current
position and color**. **Preview tool** registers the checked action in this Grid
space. Move the cone, then ask F2 to run the action by name or open **B → Workshop
actions**. The native CLI can discover it through `list_workshop_tools` and
invoke it through `run_workshop_tool`.

A reset is one Grid edit. Use **Undo** in the palette or ask F2 to undo the last
Grid edit. **Discard** removes the previewed action and leaves its invocations
in the ordinary undo history. **Commit** installs the action in this Grid space
for future sessions.

### Edit source in Workbench

For an agent-authored code change, ask in **F2**. For
example, ask **Add undoable group duplication to the Grid palette and write a
regression test**. Codex searches and edits a separate source workspace. When
the draft is ready, **Review draft** opens its diff in F4. **Run checks** starts
the isolated checks, then **Preview build** opens the checked build with its
own saves. Commit through F4 if you want to install it.

To iterate on that draft, ask F2 **Fix the failing check** or **Adjust this
preview**, or describe the change with **Revise draft** in F4. Codex starts
from the existing patch and receives the latest check output. F4's
**Revision** tab shows what changed since the previous version, while **Diff**
shows the full patch. **Restore previous** swaps the two versions. Run fresh
checks after either action before previewing or committing.

After a restart, open **F4** to return to the active draft, last selected file,
and review tab. **Checks** keeps the last completed result for that patch. A
failed draft can be revised from **F2** using that result. If the gateway
restarted too, run checks again before previewing or committing a previously
passing draft.

### Measure villa performance in Euclid

Open **F4 → Diagnostics → Benchmark villa** or ask **F2** to **Run the villa
benchmark**. Euclid minimizes while a separate rendered window measures the
arrival, pool and portico at 1920×1080 Balanced. Use a clean Git checkout for
a baseline. With a checked draft, Euclid measures its pinned baseline and
reviewed patch in sequence. Close any open preview before running the benchmark.

Ask F2 for **the saved villa benchmark results** or reopen **Diagnostics** to
see frame times, the 60 FPS and 16.67 ms p95 budgets, and the change per view.
**Open captures and logs** opens the saved screenshots, run logs and raw
measurements. Results follow the measured draft version. Codex can use
matching desktop results when authoring or revising source.
Diagnostics also shows output and errors from the current draft's playable
preview. Codex can use that output when revising the patch.

### Live-preview the Grid palette

In The Grid, try asking F2 to **Add a Reset rotation button to the Grid palette**.
For a draft that changes only the palette script, review the patch in F4 and
run checks. Choose **Preview palette**, close Workbench, and press **B** to
use it in the current world. The selection, placement, and unapplied fields
carry over from the palette you left.

**Stop preview** restores the working palette and keeps the checked draft
available. **Discard** removes the draft and **Commit** keeps a successful
preview active. A candidate that fails to load or reports a script error
restores the working panel, and F4 **Diagnostics** shows the error. A new
draft version requires fresh checks and its own preview. World edits made
through the palette still use ordinary Grid undo.

The source workspace supports one active task and up to 24 changed Godot
source or test files. The checks and preview run code from the reviewed draft
with your local account permissions.

Press **F4** and open existing Godot
scripts, shaders, the main scene, or project data files. Open each file you want
Codex to see. For example, open `world/scripts/workshop/entity_types.gd` and
`world/scripts/ui/grid_palette.gd`, then ask Codex to make the default traffic
cone teal and update the spawn button to match. You can also edit either file
directly and switch between open buffers.

**Review diff** creates a separate Git worktree for the draft. **Run checks**
tests it in a disposable project and shows its logs. The first check keeps a
2 GiB copy of the local art and import cache under `.local/workbench`. Later
checks link to it and copy only what changed. A draft that changes only gateway
code skips the Godot core and smoke tests, and a documentation draft runs
nothing. **Play preview** opens that build with separate saves. Enter a
message and choose **Commit** to add the reviewed changes to the local branch.
The main checkout must be clean and still on the draft's starting commit. If
it moved, **Rebase** replays the draft onto the new tip; run checks again
before committing. **Discard** removes the draft. **Revert last** adds a revert
commit when the last Workbench commit is at the branch tip.

Connected agents can hold drafts at the same time as you. When any are open, a
drafts list appears beside the Workbench title. Pick a draft to review it, or
**Your files** to keep editing beside it. An agent's new draft does not replace
the one you are looking at. The **History** tab lists recent drafts, checks,
commits, discards and reverts, with the agent that made each.

The **Terminal** tab runs PowerShell in the repository root. The gateway keeps
the shell, so it is still there after **Restart Euclid**, but it ends when the
gateway restarts. Ctrl+Shift+V pastes and the mouse wheel scrolls history.

The **Agents** tab connects cloud agents. Deploy the relay in `relay/` to your
Cloudflare account once, paste its address, and add agents with their
permissions. It shows when each agent was last active and its recent calls, and
disconnects any of them. See [cloud agents](docs/agents.md#cloud-agents).

**Restart Euclid** saves your current environment, position, and view, then
relaunches Euclid from the updated source. The window briefly closes during the
restart. Workbench identifies whether a draft supports a live swap, a Grid
scenery reload, a gateway reload, or a restart. Preview a live change before committing to keep
it active in the running world.

The F4 editor supports up to six existing text files, 64 KiB per file and 128 KiB total.
The local baseline tracks source, build tools, and asset metadata. Large binary
art under `world/assets`, Blender sources, and the standalone experiments are
local inputs. Keep those files with a checkout you want to run. Preview projects
copy the local runtime art and run with your local account's permissions.

## Try the agent event bridge

While Euclid is open, run `npm run agent:example` in this folder. Travel to the villa and inspect **Example worker**. A real Node process checks the world manifest and submits the result. This is an adapter example, not a Codex or Claude session. It makes no model calls and spends no API credits. Status is event-driven; the worker appears offline after 30 seconds without a report, while its last result remains available.

The gateway runs at `127.0.0.1:4317`. The launcher passes its credentials to Godot through the process environment. Credentials, gateway state, logs and previews are stored in `.local/`, which Git ignores. The credential rotates whenever the gateway restarts; reopen the world through the launcher after restarting the gateway.

Run `powershell -File scripts/stop-gateway.ps1` to stop the background gateway. Closing the world leaves the gateway running so adapters can finish independently.

## Edit and build

The runtime now separates content builders, asset resources, rendering, transitions, water, player movement, UI, agent transport and persistence. See [the module map and content workflow](docs/architecture.md) before adding new features.

Graphics default to **Balanced**, which retains the existing visual effects and simulation while removing redundant antialiasing and using a smaller shadow atlas. **Graphics** on the wrist computer's System page switches to **Cinematic**, which restores the previous settings. This preference is saved separately from your world position. The first measured villa pass improved the three fixed default-window views from 54–60 FPS to 81–88 FPS; see [measurements and limits](docs/performance.md).

- `powershell -File scripts/start.ps1 -Editor` opens Godot with the gateway configuration.
- `powershell -File scripts/start.ps1 -NoGateway` runs just the world.
- `powershell -File scripts/start.ps1 -Windowed` starts Euclid in a window.
- `powershell -File scripts/start.ps1 -Compatibility` uses OpenGL for graphics troubleshooting.
- `powershell -File scripts/start.ps1 -Quality balanced` overrides the graphics preference for that launch. In the villa, Balanced uses simpler distant meshes, lighter shadows, and FSR 2 to reconstruct the 3D view at window resolution. Cinematic renders at native resolution.
- `powershell -File scripts/check.ps1` runs the content/save/ownership checks, world smoke test and gateway tests.
- `python scripts/background-render.py --text-tools --output .local/text-tools-check` captures Workbench and F2 on the GPU with a read-only gateway stand-in. The output directory holds the captures, log, and any fixture editor buffers.
- `python scripts/background-render.py --output .local/water-check` checks pool motion and coastal rendering on the GPU without a visible window or desktop input. See [water validation](docs/water.md) for its scope.
- `python scripts/background-render.py --coast --warmup 90 --output .local/coast-check` checks the normal game's coastal boundary/foam over a longer run, plus pool reflection visibility and cleanup. The normal water now uses the bounded pool settings and a shared offshore wave surface; the pool also reflects the surrounding villa.
- `powershell -File scripts/benchmark.ps1 -MinimumFps 60 -MaximumP95Ms 16.67` measures the three villa views in a real rendered window and fails if either budget is missed.
- `powershell -File scripts/build-assets.ps1` regenerates the villa column, courtyard and shore terrain in isolated background Blender processes. It also downloads the Poly Haven assets (cached), reduces the scanned models to real-time budgets and imports everything into Godot. Add `-NoDownload` to rebuild offline. Set `BLENDER_BIN` for another installation.
- `.tools\godot\Godot_v4.7.2-stable_win64_console.exe --path world -- --capture` with `CONSTRUCT_CAPTURE_DIR` set renders preview screenshots of every zone plus extra villa and shore viewpoints.
- `npm test` checks authentication, unsupported events, task transitions, concurrent duplicate delivery, payload limits, and restart persistence.
- `.tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path world -- --smoke` checks all three zones, anchors, collision, application return and saved-location restoration without touching your normal save.

Euclid keeps the original save directory after the rename. Godot saves your location under `%APPDATA%\Godot\app_userdata\Construct\world-state.json`. Close the world and rename that file to reset your location.

## Linux workspace

A fresh **Construct-Ubuntu** WSL 2 environment is installed at `F:\Construct\Ubuntu\ext4.vhdx`. Start it with `wsl -d Construct-Ubuntu`. The ordinary account is `level`; use `wsl -d Construct-Ubuntu -u root` for administration. No password has been set for the ordinary account. The original broken `Ubuntu` registration is retained, and the global default distribution is unchanged.

The installation image and checksum are in `F:\Construct\downloads`. This environment is for Linux builds and nested graphics experiments. WSLg does not prove that a full replacement Linux login session will work; that requires later testing in a Linux VM or on Linux hardware.

C/C++ compilers, CMake, Ninja, Git, Python virtual-environment support, and Wayland/EGL/Vulkan development libraries are installed. `scripts/linux-deps.sh` records the repeatable package setup. The source project remains in this Windows folder; use the Linux filesystem for future compositor build directories.

## Working with agents in the world

- Press **F2** for world commands, tasks, and messages. Use `/task local-codex Check the Grid for duplicate props and report what you find` to start a local Codex CLI session. Use `local-claude` for Claude Code. Sign in to the corresponding CLI first. A task can run multiple tools and leaves its result in F2. Workbench drafts still require player review in **F4**.
- Use `/task muse <request>` for a connected agent named `muse`, or `/task * <request>` to let a connected agent claim it. Issue each connected agent its own credential in **F4 → Agents**. Agents use `claim_task`, `task_progress`, and `finish_task` over that MCP connection. `claim_task` can wait briefly for work. They can use `send_message` with `to: "you"` to reach the player.
- Use `@muse <message>` or `/msg <agent> <message>` to send a message. Addressing a local worker with `@local-codex` or `@local-claude` starts a task. Use `/inbox [agent]` to reread messages, `/journal` for recent events, and `/cancel <task-id> <reason>` to cancel a task. Connected agents can check its status in their inbox. F2 displays task IDs and refreshes while open. Recently active agents appear near the environment's arrival point.
- Use `/share-view <agent>` to share a still of the running world for five minutes. The agent retrieves it with `look_at_world`. Euclid hides the console and terminal surfaces for that frame. On Windows, full Workbench checks attempt to capture isolated Grid, villa, and beach views. Agents can see available views in `draft_status` and retrieve one with `view_check_capture`.
- Press **E** at the Grid or villa terminal to open the local shell window. The Grid workstation shows the latest frame from its terminal window. The beach media station opens local images. **Escape** or **Return to world** closes the app view.

## What comes next

1. Validate the cloud relay with a real hosted agent and test reconnect and task recovery through a gateway restart.
2. Add task and conversation navigation to F2, then route push-to-talk requests through the same task and message layer.
3. Test native Linux application surfaces, keyboard and pointer forwarding, and return-to-world behavior in a nested compositor.

See [the architecture notes](docs/architecture.md), [the Blender workflow](docs/asset-pipeline.md), and [water tuning and rendered checks](docs/water.md).
