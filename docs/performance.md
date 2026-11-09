# Villa performance pass

The first optimization pass targets the default 1440 x 900 window on the NVIDIA GeForce RTX 3060. The villa's materials, geometry, planting, lighting and water simulation are retained. The primary savings come from removing overlapping antialiasing and reducing the directional shadow atlas from 8192 to 4096.

## Measured results

Each fixed view warms up for three seconds and samples six seconds of uncapped frame intervals. VSync is disabled only for the benchmark. Screenshots are taken after sampling, outside the timing interval. Results below compare the original settings with the default Balanced profile.

| Villa view | Original FPS | Balanced FPS | Original p95 frame ms | Balanced p95 frame ms |
| --- | ---: | ---: | ---: | ---: |
| Arrival | 59.1 | 84.7 | 18.58 | 13.38 |
| Pool | 53.7 | 80.8 | 19.81 | 13.75 |
| Portico | 60.3 | 87.5 | 17.78 | 12.63 |

All three measured views meet the 60 FPS average and 16.67 ms p95 budgets. The user-reported 47 FPS was not reproduced exactly; the fixed-view baseline was 54–60 FPS. These results describe this machine, these viewpoints and a warmed-up window. They do not establish an absolute minimum during movement, zone shifts, startup, shader compilation or future content.

A secondary Balanced run at 1920 x 1080 measured 71.7 FPS at arrival, 68.6 at the pool and 71.3 in the portico; the corresponding p95 times were 15.32, 15.86 and 14.93 ms. That run also passed both budgets. Its artifacts are under `.local/benchmarks/balanced-1080p/`.

The arrival isolation test measured approximately 57.5 FPS with the original settings, 74.3 with TAA alone, 69.4 with the smaller shadow atlas alone, and 88.1 with both. Run-to-run variation accounts for differences from the full-view results. These isolated measurements identify the rendering cost; extracting modules by itself is not credited with the FPS gain.

## What changed

- Balanced retains TAA, uses no MSAA, and uses a 4096 directional shadow atlas. Cinematic restores the original combination. The smaller atlas trades some fine shadow detail for headroom; compare it in the portico before changing defaults again.
- Identical PBR requests and converted transition materials share immutable resources. Revisited zones reuse triangle collision shapes instead of rebuilding them. This primarily reduces allocation and construction work; no separate startup-speed gain is claimed.
- Resource lookup is synchronized when environment loading on the main thread overlaps a worker build. Build state belongs to each detached build context.
- F3 displays FPS, approximate frame duration, GPU viewport time and draw calls. It samples twice per second while visible and stops querying while hidden.

The GPU viewport timing is useful for rendering comparisons but does not account for every engine or compute operation. The reported main-process timing includes engine work and waiting; it is not a measurement of GDScript execution alone. See Godot's [render timing API](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html#class-renderingserver-method-viewport-get-measured-render-time-gpu) and [profiling guidance](https://docs.godotengine.org/en/stable/tutorials/performance/cpu_optimization.html).

## Reproduce and enforce the budget

Run from the project folder:

```powershell
powershell -File scripts/benchmark.ps1 -Quality balanced -MinimumFps 60 -MaximumP95Ms 16.67
powershell -File scripts/benchmark.ps1 -Quality cinematic
```

Use `-Width 1920 -Height 1080` to test a larger window, `-Zone beach` for a shore arrival sample, or `-OutputDirectory` to keep a named run. Run one GPU benchmark at a time. The script opens a real rendered window; headless mode is rejected for performance measurement. It exits with an error if an optional budget is missed.

JSON results, logs and screenshots are written under `.local/benchmarks/`. The original reference run is `before/results.json`, and the measured Balanced run is `final-balanced/results.json`. They are machine-local artifacts and excluded from Git. The tests, benchmark code and this report remain in the repository.

## Next performance gates

Add a repeatable moving-camera route and long transition samples before claiming a minimum FPS across the whole experience. If future content exceeds the budget, inspect GPU timing, draw calls, shadows and overdraw before reducing art globally. Large scenery meshes may benefit from spatial subdivision and distant repeated props from MultiMesh or LOD; those require their own measurements and were not added speculatively in this pass. The pool's square solver grid contains substantial dry space, so a rectangular compute domain is a future option if profiling shows simulation cost becoming significant.
