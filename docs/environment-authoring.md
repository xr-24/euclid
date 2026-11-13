# Environment authoring

**Euclid's rule: agents and the player get as much control over the engine and the world as
possible, from inside the game.** Anything a shipped environment can do, an agent or the player
can do too, with the same tools, in the build menu and through the agent command registry,
previewed, saved and undoable.

## Environment packages

The Grid, Open Ground, villa and shore all load from piece documents. The villa and shore
reference the existing generated geometry and water bakes. Their vegetation, lights, water,
scenery, furniture and collisions are declared in their packages.

## The model

- **Environments are documents.** An environment package (`world/data/zones/<id>/zone.json`)
  lists its sky and atmosphere, spawn and views, and a tree of **pieces**. Building it means
  loading that document; saving what an agent or the player made writes the same format. A
  code `builder` is no longer accepted in an environment package.
- **Pieces are small, general and combinable.** A piece is a record with an id, a type, a
  transform and its type's fields. Types are registered in `world/data/pieces/types.json`, each
  with a field schema and a trusted factory in `world/scripts/pieces/`. Nothing in the engine
  knows what a "pool" or a "house" is: a pool is a carved shape plus a water volume, a waterfall
  is rocks plus a flowing surface plus spray, a door is a shape plus a hinge behavior.
- **Commands are generic.** Agents and the build menu add, edit and remove any piece, with the
  fields its type declares. A new piece type appears in the planner schema, the editor and
  validation with no new command.
- **New abilities are plug-ins.** When the toolkit lacks something, the answer is a new piece
  type, behavior or material registered through the extension system, never a branch inside one
  environment's code.
- **Props use the piece document.** The workshop and Pieces panel share the physical prop
  factories. Existing spawned props are copied into the piece document with their IDs,
  bindings and available undo history. Older authored dressing overrides remain readable.

## Rules (checked by `scripts/open-engine.test.mjs`, part of `npm test`)

1. Shared code (everything in `world/scripts` outside `zones/` and `diagnostics/`) does not
   name a specific environment package. Behaviour an environment needs is data in its package.
2. Environment packages are documents. The checks reject a code `builder`.
3. Every piece in a package uses a registered piece type.

The debt file records today's exceptions with a reason each. The check fails when an exception
grows *or* shrinks without the file being updated, so fixes are locked in.

## Done

- **Props**: spawn, move, turn, resize and stretch (handles or fields), lock physics, prefabs,
  behaviors and animations, for Grid spaces and authored scenes (`workshop/world_tools.gd`).
- **Models**: search Poly Haven and Sketchfab and import a model by phrase or asset ID
  (`gateway/assets.mjs`, `spawn_asset`).
- **New environments** from an installed package as a template (`create_environment`).
- **Atmosphere**: sun direction, height (night below the horizon), colour and strength; sky
  (installed HDRI or painted gradient), its brightness and stars; exposure, fill light and
  shadow reach; fog density, colour and glow toward the sun; distance haze and its colour.
  `rendering/atmosphere.gd`, `ui/atmosphere_panel.gd` (Tab → Build → Atmosphere) and the
  `inspect_atmosphere`, `preview_atmosphere`, `save_atmosphere` and `discard_atmosphere` tools.
- **Environment documents** use the piece registry (`group`, `shape`, `light`, `model`) and
  the shared builder (`scripts/pieces/piece_builder.gd`). Open Ground and the Grid are built
  from pieces. The Grid uses a lattice plane with its own collision dimensions, invisible
  solid boundary boxes, and one `box_batch` for the fractured skyline.
- **Grid appearance** can be edited in **Pieces**. Select **Lattice floor** for line spacing
  and tint, or **Fractured skyline** for height, tint, and its local box transforms. Workbench
  scenery previews temporarily apply to those same pieces. The committed profile supplies
  the defaults for fields that have no local edit.
- **Live piece editing** is available in **Tab → Build → Pieces** and from the **B** palette.
  Choose a type and a parent to add a piece. Pick one from the list or click its collider in
  the scene, then edit the fields declared by its type. Use the move handles for translation
  and yaw, or **Q** and the white cube for uniform scaling. **Undo piece** reverses the most
  recent change, including a group removal.
- **Agent tools** use the same editor. Call `list_piece_types` for exact fields, defaults and
  installed library model IDs. `list_pieces` returns stable IDs and parent IDs. Pass a
  `target` to inspect one piece, or pass `next_offset` back as `offset` to page through the list.
  `add_piece` takes a type as `target`, optional `parent` and `piece_values`. `edit_piece` takes
  a piece ID as `target` and the fields to change in `piece_values`. `remove_piece` removes
  the target and its children. `undo_piece` uses the same history as the panel.
- **Saves** live in `user://environment-pieces-<id>.json` with the piece tree and its undo
  history. Creating an environment from a template copies its current piece tree into a new
  document. Legacy prop saves remain on disk for recovery. Authored prop and water appearance
  overrides retain their existing IDs.
- **Terrain** is a registered piece. Open Ground starts with one, and any editable environment
  can add one through **Pieces**. Open **Build → Terrain** for five brushes and a three-material
  palette. Left-drag to brush and hold middle mouse to look and move. Flatten uses the height
  at the start of the stroke. Release saves the stroke and updates collision. Esc cancels a
  stroke in progress. **Undo** uses the same saved history as the piece editor.
- **Agent terrain tools** share that data and history. Use `inspect_terrain` to find the piece,
  see its paint materials, or sample elevations. `terrain_brush` takes the piece ID, a brush,
  and an array of world-space `[x,y,z]` points. Each call saves one stroke.
- **Live terrain materials** come from Poly Haven. In the Terrain panel choose **Paint → Import…**,
  search, and choose a result to make it the active brush. The gateway verifies the 1K color,
  OpenGL normal, and packed occlusion/roughness/metallic maps before caching them. Godot loads the
  complete map set without a restart. Each terrain can use five imported materials alongside its
  built-in palette. Material IDs, paint, and undo persist with the terrain. Agents use
  `search_materials` and `import_material`, then pass the material ID to `terrain_brush`.

- **Vegetation scatter** uses the registered piece editor and agent commands. Choose a model,
  patch size, count, spacing and seed. A scatter attached directly to sculptable terrain follows
  that surface. Scatter supports slope filters, exclusions, collision and render distance.
- **Live sky imports** are available under **Atmosphere → Sky → Import…**. Imported 2K panoramas
  preview immediately and remain available offline. Use `search_skies`, `import_sky`, and
  `preview_atmosphere` for the same workflow through agent tools.
- **Water pieces** include pools, round basins, streams, oceans and spray. Place water over
  existing basin or stream geometry. The shipped reflecting pool and shore retain their GPU
  solvers through baked-water pieces. Generated terrain and water bakes are prepared offline.
- **Villa and shore** use those pieces along with editable models, shapes, lights and buoyant
  props. Their Blender-generated meshes remain reusable model assets.

- **Houses** (`house`) are whole homes planned from rooms. Give `bedrooms`, `bathrooms`,
  `layout` (`open` or `closed`), `style` (`modern`, `desert`, `farmhouse`) and optionally
  `floor_area`, or list exact `rooms` (`kind` and `rect` `[x0, z0, x1, z1]` along wall
  centrelines; rooms may form an L or other rectilinear shape). `scripts/pieces/house_layout.gd`
  turns that into walls: exterior and interior thicknesses from the style, no walls between
  shared rooms in an open plan, a door from each bedroom, bath or office to the hall (or the
  nearest shared room), one front entrance, a glazed patio door from the living room, and
  windows sized by room kind (full-height glazing in living rooms, casements in bedrooms,
  high frosted windows in baths). `house_piece.gd` builds the foundation, floors per room,
  painted wall linings, framed doors and windows with handles, ceilings with downlights, the
  roof (flat with eaves, parapet with vigas, or gable), entrance steps and lights, a gravel
  apron, stepping stones and a patio deck; `house_furniture.gd` furnishes each room against
  walls free of openings, using real models where installed: `world/data/pieces/house_furnishings.json` lists, per furniture slot and style, the library models to try (fitted to the slot, never enlarged) before falling back to a simple stand-in, and `scripts/build-furniture.ps1` downloads and prepares the CC0 Poly Haven ones. `pool: true` swaps the deck for a stone terrace with an in-ground
  pool; parented to a terrain, the house digs the basin. Styles live in
  `world/data/pieces/house_styles.json` (finishes, roof, proportions); `materials` on the
  piece overrides any finish. Static surfaces are merged per material when built, so a house
  draws in a few dozen calls. Preview any record outside the game with
  `xvfb-run godot --rendering-method gl_compatibility --path world --script
  res://scripts/diagnostics/house_preview.gd -- <output dir> '<record JSON>'`.
- **Building plans** support multiple rooms within a rectangular footprint. Specify
  `partitions` as wall segments with `start` and `end` in local `[x,z]` metres,
  plus optional `openings`. Opening `offset` is measured along the wall from its
  midpoint. Use `wall_openings` for exterior opening lists. Each opening can be a
  hinged or sliding door or window, or an open passage (`archway`). The older
  `openings` field still supplies each side without an explicit list.
- **Pool with basin** (`pool_basin`) adds the floor, lining, rim and water as one
  piece. When parented to sculptable terrain it defaults to `basin_mode: excavated`;
  environment-level placement defaults to `raised`. Excavation is derived from the
  piece. Removing it or undoing the edit reveals the original terrain and its saved brushwork.
- **Video screens** use YouTube links by default and accept local imports. Set
  `youtube_url` with `add_piece` or `edit_piece`. Agents can use
  `control_video_screen` for playback and playlist navigation. For local sources,
  call `list_local_videos` to discover IDs after the player imports files. FFmpeg
  conversions run separately from the game. Shared agent views hide the video image.
- **Time and weather** live in **Build → Atmosphere**. Set a fixed hour or let the day
  cycle, then adjust cloud cover and rain. The same preview, save and discard tools
  accept `time_mode`, `time_of_day`, `day_length`, `cloud_cover` and `rain`.

## Next

- **Sharing.** Turn an edited environment into a package that passes the checks, including
  `check.ps1 -Performance`.
