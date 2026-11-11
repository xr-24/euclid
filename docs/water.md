# Water integration and visual regression

Euclid uses the MIT-licensed [Realistic Shoreline Waves](https://reboot16.itch.io/godot-rsw) GPU shallow-water solver. The enclosed pool has its own disturbance settings and solid-boundary treatment. The coast combines the local solver with a continuing offshore wave field.

The active villa builder in `scripts/zones/villa.gd` uses `Water.build_pool_surface` for the reflecting pool and places its fountains from the villa layout. `WorldArt` delegates the beach surface and per-frame water interactions to the same water module. The villa Blender exporter and the standalone `scripts/water_bake.py` command share the padded pool bake, so regenerating the villa also regenerates a grid that matches the entry ramp.

## Pool reflections

`scripts/rendering/pool_reflection.gd` provides an HDR planar reflection with temporal antialiasing. Both graphics profiles render the reflection at 960×540 in a 16:9 window. At other aspect ratios, the mirror keeps its 960-pixel width and adjusts its height. Balanced uses simpler meshes at a distance. The mirror camera reflects the active camera across the resting pool level and passes a projective texture to the water shader. The shared transition shader clips geometry below the water plane for the mirror camera, and the mirror excludes the pool's layer to prevent recursive reflections. The main viewport applies exposure and tone mapping once.

The reflection stops when the pool is outside the main camera's frustum, farther than 80 m, or the viewer is underwater. It is destroyed with its zone and releases the material's viewport texture. The mirror uses reduced post-processing and does not enable its own SDFGI/SSR/AO. Reflection visibility and cleanup across a villa-to-beach change are checked by the coastal harness. This is independent of the .NET/Crest preview.

## Coastal boundary and shoreline repair

The active coast now selects absorbing mode 2, a 14 cm incident amplitude and one shared wave clock. The surrounding ocean uses the same surface shader, wave phases, colour and normal inputs as the local solver patch. An annular mesh matches the patch's dense edge sampling instead of cutting through a coarse plane; the distant horizon remains a separate level ring with matching wave normals.

The old refraction offset used the full camera-space normal, shifting even flat water with camera pitch and pulling sky or foreground geometry into large cutout shapes. The shader now computes distortion relative to a flat normal and bounds its screen offset. Coastal distortion is disabled because screen-space disocclusions still produced artefacts at grazing angles; depth-based transparency, absorption, wave geometry, ripple normals and reflections remain. The confined pool retains a small distortion.

Coastal foam uses a depth-feathered contact mask and a small, noise-broken terrain contact band driven by the actual foam field. This softens the faceted water/ground intersection without changing terrain collision or hiding a numerical explosion. The water no longer writes into the scene depth used by adjacent water sections for refraction.

The shader explicitly uses the transparent pass and reconstructs scene positions in world space. Colour absorption uses the continuous local water column across the cove and extends that treatment 20 m beyond the grid before blending back to scene depth. This avoids a hard colour line where a grazing depth ray jumps from the near sand shelf to the distant seabed. Reflection and foam normals still follow the moving surface.

Run `python scripts/background-render.py --coast --output .local/coast-check` for the normal application's elevated, shoreline, boundary and offshore views. Add `--warmup 90` for the longer soak. It also checks pool reflection visibility/cleanup, three shared coastal surfaces, absorbing boundaries, a synchronized clock, finite GPU state, nonzero offshore waves and low offshore foam concentration. Readbacks happen after timing samples. `--debug` creates normal, optical-depth and foam diagnostic views; `--baseline` relaxes the new integration assertions for investigating an older setup.

The November 8 runtime validation measured a 3.74 cm scripted pool walking disturbance, with the sampled peak at Y −0.0826 m below the +0.060 m coping. Pool volume and mean height passed their existing tolerances. A 101.9-second coastal field remained finite with offshore height standard deviation 0.0883 m and mean foam concentration 0.0000655 (in the stated offshore test region). Raw results/captures are under `.local/coast-fix/`. These are test-route observations, not guarantees for every possible impact or sea state.

## Pool

The original 48 m basin exactly filled a 48 m solver domain. The two boundary stencil rows therefore cut into the basin, producing raised ends. The first diagnostic skipped those rows and missed the pillows. It also only checked that waves were not excessive; it did not require a visible walking response. The second pass addresses both gaps.

- `scripts/water_bake.py` creates a 640 x 640, 8 cm grid with dry padding around the entire basin. The bed includes the actual south-end 3.4 m entry ramp.
- Vertical coping is represented by solid cells rather than partially wet cells made by averaging wall and floor heights. The pool opts into a `CLOSED_BASIN` compute specialization that reflects matching physical cells across the boundary. Shared fluid faces use consistent stencils, including the second ghost layer.
- Closed faces explicitly transmit normal pressure while blocking water and foam transport. The pool uses a 2 ms timestep and a 2.5 m/s flow cap; coastal settings are separate.
- A pool-only GPU volume projection preserves the initial water inventory after integration. It removes small volume errors from positivity clamps at the shallow entry by scaling depths and depth-integrated momentum uniformly. It preserves motion and velocity rather than clamping wave crests flat. Filling, draining and overflow would require a different inventory policy. This correction performs no runtime CPU readback.
- This pool model has a fixed wet footprint: cells whose bed is at or above the resting water level are closed boundaries, including the dry upper entry ramp. It models small reflecting ripples, not overtopping or changing inundation of the ramp. The coastal solver retains its ordinary moving wet/dry shoreline.
- Recirculating fountains inject time-scaled momentum, not height. A height kernel cut off by a nearby wall would gradually add volume.
- Walking supplies a bounded momentum wake and a small volume-neutral bow ripple. The pool test now requires a measurable response, as well as an upper bound. Entry splashes remain bounded single impulses.
- Surface interpolation excludes dry neighbors and numerical wetting films. Dry vertices remain near water level instead of stretching up a bank or coping. The opaque terrain and per-fragment wet mask determine the visible waterline.

The pool still has real height-field motion and reflecting wakes. Its optical settings use restrained refraction, independent smooth ripple normals and no surf foam. These settings do not substitute for the simulated walking disturbance.

## Coast and offshore water

All coastal meshes now use `shore_water.gdshader`. The detailed solver patch and the surrounding ocean share shading, wave phase and a continuous height field. The local simulation blends into continuing offshore waves instead of flattening at a rectangular seam or selecting between surfaces with screen-space stippling.

`coastal_waves.gdshaderinc` is included by both the visible surface and `pass_boundary.glsl`. It defines one dominant incident swell and weaker components with a narrow directional spread. Both use the same dispersion approximation, phases, ramp-up and simulation clock. The cove selects the existing absorbing boundary mode to reduce reflected cross-waves from its outer sides.

The horizon excludes the near patch, carries the same analytical wave normals, and stays geometrically level because its coarse mesh cannot resolve short displacement. Near-patch displacement settles gradually toward its distant perimeter. The local GPU simulation remains finite; this is a hybrid surface, not a simulation of the entire sea. Gameplay probes still return the local solver height; a small visual/probe mismatch can remain in its blending strips.

Foam is used only as foam, never as a cellular bump map. Dry shore mesh vertices no longer rise to dry terrain heights, which previously stretched water into sheets near the simulation limits. Ground wetness and stranded foam still use the local solver.

## Background GPU checks

On Windows, run from the project root:

```powershell
python scripts/background-render.py --output .local/water-check
```

This uses a permanently invisible native parent and Godot's `--wid` embedding, with an always-updating 1440 x 900 SubViewport. It does not manipulate desktop input or open a visible game window. Python's standard library is sufficient for this host. The independent pool data bake uses NumPy, also available in Blender's bundled Python.

The test uses Forward+ on the real GPU and never reads or writes the normal world save. It warms the pool for eight seconds, captures both ends, drives a five-second walk, waits eight seconds, and warms the surf for eighteen seconds. Additional captures cover the shore sides, an elevated overview and offshore water. GPU texture readback is enabled only in this diagnostic mode. Entry impulse bounds are also covered by unit checks; the rendered route primarily verifies continuous wading.

The test requires: no sampled crest above coping, a nearly level resting pool, a walking disturbance between 3 mm and 8 cm, mean-level drift below 0.1 mm, full-grid volume drift below 0.01%, and finite coastal extrema. It includes the boundary rows and reports shallow-film extrema separately from water deeper than 2 cm. Height extrema are sampled; volume integrates every grid cell to avoid aliasing moving ripples. These checks are not a guarantee of every transient or exact conservation. JSON, logs, raw resting pool state and screenshots are local artifacts.

`scripts/check.ps1` additionally checks tick-rate invariance, bounded impulses, dry padding, ramp alignment, module contracts, gameplay smoke and the gateway. The asset builder calls the same pool bake function, so rebuilding the villa preserves the fix.

## Validation limits

The first water pass's screenshots and sampled extrema were insufficient: they missed the pool ends and did not establish that a wake was visible. The second pass adds those explicit checks and a shared coastal surface. Earlier `.local/water-before`, `.local/water-after` and `.local/water-final` reports describe the superseded first pass.

Hidden GPU captures establish rendering and numerical behavior, not desktop FPS. The visible `scripts/benchmark.ps1` run is deferred to respect the background-only workflow. No new 60 FPS claim is made for this water revision. Height fields also do not simulate overturning wave volumes, spray or droplets.

For a later offshore upgrade, [GodotOceanWaves](https://github.com/2Retr0/GodotOceanWaves) is an MIT-licensed FFT ocean rendering reference. It has not been integrated or benchmarked in Euclid and would still need a deliberate connection to the local shore and pool systems.
