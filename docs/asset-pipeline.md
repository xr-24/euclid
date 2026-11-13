# Blender to Godot workflow

The suggested custom import pipeline is useful here. Keep scene creation and cleanup reproducible, then let Godot consume the exported result. Godot supports glTF and can also convert `.blend` files through Blender; an explicit `.glb` build keeps runtime assets usable without Blender installed. See the [Godot format documentation](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html).

## Realistic art pass (villa and shore)

Both zones use CC0 assets from [Poly Haven](https://polyhaven.com): HDRIs, scanned PBR texture sets and scanned models. The pipeline is reproducible and every step runs in a disposable background Blender:

1. `scripts/blender/fetch_polyhaven.py` downloads the assets listed at its top. HDRIs and texture sets go to `world/assets/thirdparty/polyhaven/`, and the raw scanned models to `.local/polyhaven/models/` (outside Git and Godot). Downloads are cached.
2. `scripts/blender/optimize_models.py` turns the raw scans, often 1–2 million triangles, into real-time GLBs within the per-asset budgets in `BUDGETS`. It splits each mesh by material, decimates trunks and rocks, and thins leaves by whole leaf so they keep their shape. Leaves become opaque and double-sided so they cast shadows. Origins are moved to the ground and textures resized. `models.json` records the triangle counts.
3. `scripts/blender/build_beach.py` builds the cove terrain (`world/assets/generated/shore_terrain.glb`). Its heights are authored in Godot coordinates, and `SEA_LEVEL` must match `world/scripts/simulation/water_system.gd`.
4. `scripts/blender/preview_models.py -- id ...` renders a textured preview of optimized models to `.local/model-previews/` for checking them by eye.

`world/assets/thirdparty/polyhaven/hdri/sun.json` records where the sun sits in each HDRI (equirectangular `u`, elevation). `world_art.gd` turns each sky so its sun sits at the zone's chosen azimuth, then aims the DirectionalLight there. `shaders/hdri_sky.gdshader` clamps the photographed sun out of the image-based lighting so shadows keep their contrast, and draws a matching sun disk on the background. Texture `.import` files keep normal maps in RGB (`compress/normal_map=2`), because the terrain and water shaders read all three channels. HDRIs use BC6H compression without mipmaps.

Materials are world-space triplanar `ORMMaterial3D`s built in `assets/asset_library.gd`, so the procedurally modeled villa needs no UVs. The villa meshes are matched by name (`COL_Ivory_limestone` and so on). The marble-tile and old olive meshes are hidden only when their replacements exist. The shore terrain and the water (`shore_terrain.gdshader`, `ocean.gdshader`) are custom shaders that shade from height, slope and scene depth.

## Simulated shoreline

`world/thirdparty/shorewaves/` vendors the solver from [Realistic Shoreline Waves](https://reboot16.itch.io/godot-rsw) (Reboot16, MIT; see its LICENSE.txt): `sim_controller.gd`, `scenario.gd`, the GLSL compute passes in `sim/`, and three helper textures. The local changes are listed at the top of `sim_controller.gd`: a `Kind.CUSTOM` scenario, GPU cleanup when the shore unloads, and quiet logging. `shaders/shore_water.gdshader` is adapted from the package's water shader. It maps the solver grid into the cove and hands over to `ocean.gdshader` with a complementary dither near the offshore and side edges.

`build_beach.py` bakes the solver's seabed from the same height function as the visible terrain. It writes `world/assets/generated/shore_sim_bottom.bin` and `shore_sim_state.bin` (608 × 608 RGBA float32) and `shore_sim.json` (grid, placement, sea level). The domain is 48.6 m square at 8 cm cells, and the wavemaker sits 39 m offshore over a flat 2.5 m bed. `simulation/water_system.gd` starts the solver only when a RenderingDevice is available (Forward+). The sand reads the solver's wetness and stranded-foam memory. The raw `.bin` and `.json` files are read with FileAccess, so add them to an export preset's non-resource filter when exporting.

## Construct / deconstruct shift

`shaders/construct_fx.gdshaderinc` holds the effect. The global shader parameters `construct_origin` and `construct_radius` (declared in `project.godot`) and a per-instance `construct_side` decide which surfaces survive, and which are reduced to the glowing lattice band. At zone build time, `rendering/zone_effects.gd` converts standard materials to `constructible.gdshaderinc` once and caches the result. `world.gd` animates their per-instance state during a shift (`_shift`); material resources are retained throughout. The custom shaders (ocean, shore water, terrain) include the effect directly. Anything else, such as text, is hidden for the duration.

## Included working example

Run `powershell -File scripts/build-assets.ps1`. It starts a disposable Blender process with factory settings, builds a limestone column, validates its 4.3 metre height, applies a triangulation modifier during export, and writes:

- `assets/source/villa_column.blend`: editable source, outside Godot's import tree.
- `world/assets/generated/villa_column.glb`: portable runtime asset with embedded material and stable metadata.

Godot imports the generated model. The villa places instances of it and adds an explicit collision shape. If the asset is absent, procedural columns keep the world runnable. The current column uses no downloaded textures or third-party models.

The script uses metres, a ground-level origin and Blender's Z-up coordinates; the glTF exporter performs the Y-up conversion. Application anchors are authored separately in world data so rebuilding geometry does not rewrite assignments.

## Blender MCP

Use Blender MCP for interactive modeling, inspection and refinement in the live app. The live addon was unreachable during initial setup, so the working example used the installed Blender 5.2 executable in a separate background process. This leaves any live project untouched.

Live MCP was subsequently restored by reopening Blender; the installed addon was current and auto-start was enabled. Connection status, scene inspection and Python execution were verified. A separate `Construct Art Review` scene holds the new courtyard; the original scene is retained.

`scripts/blender/build_villa.py` now builds the complete courtyard, exported as `assets/source/villa_courtyard.blend` and `world/assets/generated/villa_courtyard.glb`. The 72,128 triangles are grouped into 16 meshes by material and collision class. Runtime structural meshes use the `COL_` prefix, and Godot generates their collision surfaces. Marble and water shaders are applied in Godot.

For live modeling, work in a dedicated collection or scene, save an editable source asset, then move deterministic cleanup and export steps into the build script. Never run the example's scene deletion step in someone's live Blender; it is intended only for the disposable process.

## Extending the pipeline

For future rooms and furniture, validate dimensions, transforms, triangle budgets, material names, texture sizes and semantic anchor names before export. Keep collision and navigation separate from decorative geometry. Imported metadata can carry stable IDs, but scene metadata is data rather than executable instructions.

Avoid running arbitrary Python from downloaded theme packs. Review processing scripts that enter the build. Godot also offers [scene import customization](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/import_configuration.html), which can later handle consistent engine-side postprocessing.

## Villa Aurelia (Getty-style rework)

`scripts/blender/build_villa.py` builds the villa as a long peristyle garden on a hillside terrace (court 30 x 70 m, porticoes 4.5 m deep) and exports:

- `world/assets/generated/villa_estate.glb`: architecture and garden, joined by material. `COL_` meshes get trimesh collision in Godot; `ART_` meshes are visual only. Godot maps the material names (Limestone, Marble floor, Plaster, Fresco, Fresco frieze, Roof tiles, Timber, Gravel, Soil, Hedge, Pool basin, Window) to Poly Haven texture sets, and the frescoes to `fresco.gdshader`, a procedural Pompeian wall over `red_plaster_weathered`.
- `world/assets/generated/villa_hills.glb`: the surrounding hills (`hillside.gdshader`, grass and dry ground blended by slope and noise), falling steeply below the terrace to a distant sea.
- `world/assets/generated/villa_pool_bottom.bin`, `villa_pool_state.bin` and `villa_pool.json`: seabed and initial state for the reflecting pool's shallow-water solver.
- `world/assets/generated/villa_layout.json`: court, pool and bed rectangles, used to derive the villa package placements.

Extra Poly Haven assets fetched for it: textures `red_plaster_weathered`, `gravel_ground_01`, `forest_leaves_02`, `aerial_grass_rock`, `dry_ground_01`, `marble_01`, `white_plaster_02`, `dark_wooden_planks`; models `lion_head`, `horse_statue_01`, `jacaranda_tree`, `island_tree_01`, `searsia_lucida`, `shrub_01`, `shrub_03`, and for the shore's floating props `wine_barrel_01`, `wooden_crate_01` and `ocean_buoy`.

## Water interaction

The vendored solver gains two compute passes in `world/thirdparty/shorewaves/sim/`: `pass_poke.glsl` adds volume-neutral splashes and momentum at a point (wakes, entry splashes, fountain jets), and `pass_probe.glsl` reads water height, bed height and momentum back at up to eight points each frame. `simulation/water_system.gd` (`tick`) uses the readback for wading, swimming and buoyancy of floating rigid bodies.

## Asset library (placeable models)

Placeable models live in `world/assets/library/`, one folder per model, grouped by licence
(`cc-by/`, `cc-by-nc/`, `cc-by-nc-sa/`). `world/assets/library/README.md` explains the layout and
how to add a model. The pieces, each with one job:

- `scripts/assets/sketchfab.json`: which Sketchfab models are in the library, with real-world size,
  triangle budget, texture size and any orientation fix. Licence and author are not typed in here.
- `scripts/assets/fetch_sketchfab.py`: downloads them into `.local/sketchfab/raw/` (git-ignored)
  with the token from `SKETCHFAB_API_TOKEN` or `.local/sketchfab-key.txt`, records licence, author
  and page from the Sketchfab API, and refuses licences outside CC0/CC BY family.
- `scripts/blender/build_library.py` (shared helpers in `scripts/blender/mesh_tools.py`): reduces,
  rescales, re-centres and exports each model with an `asset.json`; `--preview` renders front and
  side views to `.local/library-previews/` for checking orientation.
- `scripts/assets/build_catalog.py`: writes `catalog.json` (every placeable model, Poly Haven ones
  included), `CREDITS.md` and a README per licence folder.
- `world/scripts/asset_library.gd`: loads the catalog; zones ask it for models by id.
- `world/scripts/scene_dressing.gd` and `world/data/dressing/*.json`: where models stand in a zone,
  as data. The villa's statuary is in `world/data/zones/villa/zone.json`.

Non-commercial models (`cc-by-nc*` folders) are fine while Euclid is free and not monetised.
Delete those folders and rebuild the catalog before selling it, monetising it or publishing it
under an open-source licence; the dressing skips models that are gone.

## Villa Aurelia and its coast (third pass)

The villa is now a whole estate on a bluff, built by small single-purpose scripts:

- `scripts/blender/arch_kit.py`: the geometry kit (boxes, walls with framed openings and painted
  skins, columns, hipped/shed/compluviate roofs, stairs with invisible collision ramps, curved
  theatre rows) and the join-by-material export.
- `scripts/blender/hedges.py`: clipped hedges from leaf cards over a dark core, with a generated
  leaf atlas (`hedge_leaves.png`, `hedge_leaves_n.png`); no external texture needed.
- `scripts/blender/build_villa.py`: the estate itself (outer peristyle, house with galleries, inner
  peristyle, atrium, hall of Herakles and library, east garden, herb terraces, theatre) and
  `villa_layout.json`, which tells the game where beds, pools, fountains, spouts and room lights are.
- `scripts/blender/coast_terrain.py` and `build_coast.py`: the Laguna-style coast (bluff, gullied
  sandstone cliff, cove beach, headlands, hills) as `villa_coast.glb` (walkable, 300 m round the
  villa), `villa_coast_far.glb` (horizon ring to 2 km) and the height field
  `villa_coast_height.bin/.json` used for placing plants and rocks.

In the game, the villa package in `world/data/zones/villa/zone.json` specifies the
generated geometry, water bakes, and placements. The coastal terrain shader shades the
bluff and tiled multimeshes render the wild planting and rocks. Statuary and garden
furnishings use the same model pieces as the in-world editor.

Extra Poly Haven assets for this pass: textures `cliff_side`, `rocky_terrain_02`, `sparse_grass`,
`coast_sand_01`, `old_mosaic_floor`, `marble_mosaic_tiles`, `sandstone_blocks_08`, `leafy_grass`;
models `crystalline_iceplant`, `cheiridopsis_succulent`, `flower_gazania`, `shrub_02`, `shrub_04`,
`wild_rooibos_bush`, `grass_medium_02`, `rock_face_01`, `rock_face_02`, `boulder_01`,
`coastal_cliff_01`, `coast_line_02`, `searsia_burchellii`, `wooden_bookshelf_worn`. Leaf-card
plants keep their cut-outs: `fetch_polyhaven.py` also fetches each model's alpha map and
`optimize_models.py` wires it in. Palms, cypresses, olive and lemon trees and agave come from
Sketchfab (CC BY) through the asset library (`scripts/assets/sketchfab.json`).
