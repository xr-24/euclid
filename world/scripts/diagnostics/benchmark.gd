extends RefCounted
## Fixed-view, uncapped GPU benchmark. Never reads or writes the player's save.

static func run(world: Node3D) -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Performance measurements require a rendered window, not --headless")
		world.get_tree().quit(2)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	world.overlay.hide()
	var viewport := world.get_viewport()
	var rid := viewport.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	var output := OS.get_environment("CONSTRUCT_BENCHMARK_DIR")
	if output.is_empty():
		output = ProjectSettings.globalize_path("res://../.local/benchmarks")
	DirAccess.make_dir_recursive_absolute(output)
	var results := {"schema_version": 1, "renderer": RenderingServer.get_current_rendering_method(),
		"device": RenderingServer.get_video_adapter_name(), "resolution": [viewport.size.x, viewport.size.y], "vsync": false, "samples": []}
	results["run_id"] = OS.get_environment("CONSTRUCT_BENCHMARK_RUN_ID")
	var graphics = load("res://scripts/rendering/graphics_settings.gd")
	results["profile"] = graphics.current
	var zone := OS.get_environment("CONSTRUCT_BENCHMARK_ZONE")
	if zone.is_empty():
		zone = "villa"
	world._load_zone(zone)
	# Save the authored settings so every isolation starts from the same baseline.
	var env: Environment = world.environment
	var baseline := {"sdfgi_enabled": env.sdfgi_enabled, "ssil_enabled": env.ssil_enabled,
		"ssr_enabled": env.ssr_enabled, "volumetric_fog_enabled": env.volumetric_fog_enabled}
	var suite := OS.get_environment("CONSTRUCT_BENCHMARK_SUITE")
	var variants := ["default", "no_ssil", "no_ssr", "no_gi", "no_sim", "gi_stagger"] if suite == "isolate" else ["default", "taa_only", "shadow_4k", "balanced"] if suite == "quality" else ["default"]
	var original_msaa := viewport.msaa_3d
	var original_shadow_size: int = graphics.PROFILES[graphics.current].shadow_size
	for variant in variants:
		for key in baseline:
			env.set(key, baseline[key])
		viewport.msaa_3d = original_msaa
		RenderingServer.directional_shadow_atlas_set_size(original_shadow_size, true)
		RenderingServer.environment_set_sdfgi_frames_to_converge(RenderingServer.ENV_SDFGI_CONVERGE_IN_10_FRAMES)
		if variant == "no_ssil": env.ssil_enabled = false
		if variant == "no_ssr": env.ssr_enabled = false
		if variant == "no_gi": env.sdfgi_enabled = false
		if variant == "gi_stagger": RenderingServer.environment_set_sdfgi_frames_to_converge(RenderingServer.ENV_SDFGI_CONVERGE_IN_30_FRAMES)
		if variant in ["taa_only", "balanced"]: viewport.msaa_3d = Viewport.MSAA_DISABLED
		if variant in ["shadow_4k", "balanced"]: RenderingServer.directional_shadow_atlas_set_size(4096, true)
		for sim in world.zone_root.find_children("*", "Node", true, false):
			if sim is SimController: sim.set_process(variant != "no_sim")
		var views := [["arrival", world.player.position, Vector3(0,1.0,-25)],
			["pool", Vector3(3.4,0.1,-15), Vector3(0,0.6,22)],
			["portico", Vector3(-17.2,0.2,24), Vector3(-17,2.2,-22)]] if suite not in ["isolate", "quality"] and zone == "villa" else [["arrival", world.player.position, Vector3(0,1,-25)]]
		for view in views:
			world.player.position = view[1]
			world.player.velocity = Vector3.ZERO
			world.player.rotation.y = atan2(-(view[2].x - view[1].x), -(view[2].z - view[1].z))
			world.camera.rotation.x = atan2(view[2].y - (view[1].y + 1.65), Vector2(view[2].x-view[1].x,view[2].z-view[1].z).length())
			await world.get_tree().create_timer(3.0).timeout
			var frames: Array[float] = []
			var gpu: Array[float] = []
			var cpu: Array[float] = []
			var draws := 0.0
			var primitives := 0.0
			var start := Time.get_ticks_usec()
			var last := start
			while Time.get_ticks_usec() - start < 6000000:
				await world.get_tree().process_frame
				var now := Time.get_ticks_usec()
				frames.append((now-last)/1000.0)
				last = now
				gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
				cpu.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0)
				draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
				primitives += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
			frames.sort()
			var sample := {"variant": variant, "zone":zone, "view": view[0], "frames":frames.size(),
				"fps":1000.0/(frames.reduce(func(a,b):return a+b,0.0)/frames.size()),
				"p95_ms":frames[int(frames.size()*0.95)], "p99_ms":frames[int(frames.size()*0.99)],
				"gpu_ms":gpu.reduce(func(a,b):return a+b,0.0)/gpu.size(),
				"cpu_process_ms":cpu.reduce(func(a,b):return a+b,0.0)/cpu.size(),
				"draw_calls":draws/frames.size(), "primitives":primitives/frames.size()}
			results.samples.append(sample)
			print("CONSTRUCT_BENCHMARK " + JSON.stringify(sample))
			if variant == "default":
				await RenderingServer.frame_post_draw
				viewport.get_texture().get_image().save_png(output.path_join(zone + "_" + str(view[0]) + ".png"))
	var file := FileAccess.open(output.path_join("results.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(results,"\t"))
	file.close()
	world.get_tree().quit()
