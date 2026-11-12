# Environment authoring

The goal: an agent, or the player, can make and change a whole environment without leaving
Euclid — find and import models, textures and skies, shape the ground, place and build things,
and set the light and weather — with the same tools in the build menu and in the agent command
registry, every change previewable, saved per environment and undoable.

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

## Next, in order

1. **Skies and textures from the web.** Extend the asset service from models to Poly Haven HDRIs
   (installed into the sky list, with their sun position measured into `sun.json`) and PBR
   texture sets. Same licence checks and cache as models.
2. **Materials on things.** Assign an installed PBR material, tint and tiling to a prop or
   surface; a material picker in the palette and a `set_material` tool.
3. **Blank environments and ground.** A plain template (open ground, sky, nothing else); a
   height-field terrain that can be raised, lowered, flattened and smoothed with a brush, and
   painted with materials; water bodies placed and sized (building on water edits).
4. **Building.** Walls, floors, stairs and roofs as stretchable, snappable primitives with
   materials, so structures can be made in place.
5. **Lights and planting.** Point and spot lights as props; scatter rules (what grows where,
   how dense) editable per environment.
6. **Time and weather.** Time of day driving the sun along a path, cloud cover, rain.
7. **Environments as packages.** Turn an edited environment into a package draft that passes
   the checks (including `check.ps1 -Performance`) and can be shared.

Each step adds data that is validated in one place (the shared command schema), applied by one
service, and offered both as a panel and as registered tools, like the atmosphere.
