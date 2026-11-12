# Environment authoring

**Euclid's rule: agents and the player get as much control over the engine and the world as
possible, from inside the game.** Anything a shipped environment can do, an agent or the player
can do too, with the same tools, in the build menu and through the agent command registry,
previewed, saved and undoable.

## Why features kept getting hardcoded

Each shipped environment is a GDScript builder (`zones/villa.gd` is 400 lines) that makes its
own pool, hedges and lights. When a scene needs something new, the cheapest change is another
builder function, and agents can never reach it because agents only have registered commands.
The fix is structural: the shipped environments must be made from the same parts agents use.

## The model

- **Environments are documents.** An environment package (`world/data/zones/<id>/zone.json`)
  lists its sky and atmosphere, spawn and views, and a tree of **pieces**. Building it means
  loading that document; saving what an agent or the player made writes the same format. A
  code `builder` is legacy and is being retired package by package.
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
- **Props become pieces.** Today's props (`workshop/entity_types.gd`) are pieces with a physics
  body. Their factories move into the piece registry so there is one record system, not two.

## Rules (checked by `scripts/open-engine.test.mjs`, part of `npm test`)

1. Shared code (everything in `world/scripts` outside `zones/` and `diagnostics/`) does not
   name a specific environment package. Behaviour an environment needs is data in its package.
2. New environment packages are documents: no code `builder`. The packages that still have one
   are listed in `scripts/open-engine-debt.json` and the list may only shrink.
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
  document. Existing prop saves and package files use their own storage.

## Next, in order

1. **Terrain, ground materials and planting.** A height-field piece that can be sculpted with a
   brush and painted with materials; Poly Haven PBR textures and HDRI skies through the asset
   service (skies land in the atmosphere sky list); scatter pieces (what grows where, how dense).
2. **Water as a piece.** Pools, ponds and basins from a shape, using the existing water looks;
   a flowing surface for streams and waterfalls; spray emitters.
3. **One record system.** Move the prop factories (cone, box, door, model) into the piece
   registry; props become pieces with a body.
4. **Villa and Shore as documents.** Their builders become pieces. The villa looking the same
   from its document is the test that the toolkit is general enough.
5. **Building.** Floors, walls, stairs and roofs from a plan, with openings that take working
   doors and windows (hinge and slide behaviors).
6. **Screens.** A video surface piece (local video first; web video needs a browser engine).
7. **Time and weather.** Time of day driving the sun, cloud cover, rain.
8. **Sharing.** Turn an edited environment into a package that passes the checks (including
    `check.ps1 -Performance`).
