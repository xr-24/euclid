extends RefCounted
const Packages = preload("res://scripts/zones/zone_packages.gd")
## Fixed-view, uncapped GPU benchmark. Never reads or writes the player's save.
## Suites: default (every view), quality (antialiasing and shadow atlas), isolate (screen-space
## effects) and costs, which turns one part of the scene or one renderer feature off at a time on
## the first two views, so the difference from default is that part's cost. looks renders the
## first two views with and without the cheaper settings, saving a screenshot of each.
const LOOKS := ["default", "hedge_shadows", "mirror_sun_shadows"]
const COSTS := ["default", "no_mirror", "no_sun_shadow", "no_fog", "no_gi", "no_ssr", "no_ssil", "no_ssao",
	"no_glow", "no_vegetation", "no_props", "no_hedges", "no_lights", "no_player", "no_sim"]

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
		"ssr_enabled": env.ssr_enabled, "volumetric_fog_enabled": env.volumetric_fog_enabled,
		"ssao_enabled": env.ssao_enabled, "glow_enabled": env.glow_enabled}
	var sun_shadow: bool = world.sun.shadow_enabled
	var suite := OS.get_environment("CONSTRUCT_BENCHMARK_SUITE")
	var variants := ["default", "no_ssil", "no_ssr", "no_gi", "no_sim", "gi_stagger"] if suite == "isolate" else ["default", "taa_only", "shadow_4k", "balanced"] if suite == "quality" else ["default"]
	if suite == "costs":
		variants = COSTS
	elif suite == "looks":
		variants = LOOKS
	results["suite"] = suite if not suite.is_empty() else "default"
	var mirror: SubViewport = world.zone_root.find_child("PoolMirrorViewport", true, false)
	if mirror:
		RenderingServer.viewport_set_measure_render_time(mirror.get_viewport_rid(), true)
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
		world.sun.shadow_enabled = sun_shadow and variant != "no_sun_shadow"
		if variant == "no_fog": env.volumetric_fog_enabled = false
		if variant == "no_ssao": env.ssao_enabled = false
		if variant == "no_glow": env.glow_enabled = false
		var hidden := _hide(world, variant)
		var views := Packages.views(zone, "benchmark")
		if suite in ["isolate", "quality"]:
			views = views.slice(0, 1)
		elif suite in ["costs", "looks"]:
			views = views.slice(0, 2)
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
			var objects := 0.0
			var render_cpu := 0.0
			var physics := 0.0
			var mirror_gpu := 0.0
			var mirror_cpu := 0.0
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
				objects += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
				render_cpu += RenderingServer.viewport_get_measured_render_time_cpu(rid) + RenderingServer.get_frame_setup_time_cpu()
				physics += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
				if mirror and mirror.render_target_update_mode == SubViewport.UPDATE_ALWAYS:
					mirror_gpu += RenderingServer.viewport_get_measured_render_time_gpu(mirror.get_viewport_rid())
					mirror_cpu += RenderingServer.viewport_get_measured_render_time_cpu(mirror.get_viewport_rid())
			frames.sort()
			var sample := {"variant": variant, "zone":zone, "view": view[0], "frames":frames.size(),
				"fps":1000.0/(frames.reduce(func(a,b):return a+b,0.0)/frames.size()),
				"p95_ms":frames[int(frames.size()*0.95)], "p99_ms":frames[int(frames.size()*0.99)],
				"gpu_ms":gpu.reduce(func(a,b):return a+b,0.0)/gpu.size(),
				"cpu_process_ms":cpu.reduce(func(a,b):return a+b,0.0)/cpu.size(),
				"draw_calls":draws/frames.size(), "primitives":primitives/frames.size(), "objects":objects/frames.size(),
				"render_cpu_ms":render_cpu/frames.size(), "physics_ms":physics/frames.size(),
				"mirror_gpu_ms":mirror_gpu/frames.size(), "mirror_cpu_ms":mirror_cpu/frames.size()}
			results.samples.append(sample)
			print("CONSTRUCT_BENCHMARK " + JSON.stringify(sample))
			if variant == "default" or suite == "looks":
				await RenderingServer.frame_post_draw
				var suffix: String = "" if variant == "default" else "_" + str(variant)
				viewport.get_texture().get_image().save_png(output.path_join(zone + "_" + str(view[0]) + suffix + ".png"))
		for node in hidden:
			if node is GeometryInstance3D and variant == "hedge_shadows":
				(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			else:
				node.visible = true
		if mirror:
			mirror.get_parent().set_process(true)
			mirror.get_parent().set("use_scene_sun", false)
	world.sun.shadow_enabled = sun_shadow
	var file := FileAccess.open(output.path_join("results.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(results,"\t"))
	file.close()
	world.get_tree().quit()

## Hides one part of the scene for a costs variant and returns what it hid. no_mirror stops the
## pool's mirror camera instead.
static func _hide(world: Node3D, variant: String) -> Array[Node3D]:
	var hidden: Array[Node3D] = []
	var root: Node3D = world.zone_root
	if variant == "mirror_sun_shadows":
		var reflection := root.find_child("PoolReflection", true, false)
		if reflection:
			reflection.set("use_scene_sun", true)
		return hidden
	if variant == "hedge_shadows": # the leaf cards cast shadows again; returned so they can be reset
		for node in root.find_children("*", "MeshInstance3D", true, false):
			if str(node.name).to_lower().contains("hedge_leaves"):
				(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
				hidden.append(node)
		return hidden
	if variant == "no_mirror":
		var reflection := root.find_child("PoolReflection", true, false)
		if reflection:
			reflection.set_process(false)
			var mirror: SubViewport = reflection.find_child("PoolMirrorViewport", true, false)
			mirror.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return hidden
	var candidates: Array[Node3D] = []
	match variant:
		"no_player":
			candidates.append(world.player_avatar)
			candidates.append(world.player_avatar.hands)
		"no_vegetation":
			for node in root.find_children("*", "MultiMeshInstance3D", true, false):
				candidates.append(node)
		"no_props": # statues, furniture, garden trees and planters: every editable placed prop
			var entries: Dictionary = root.get_meta("authored_dressing", {})
			for entry in entries.values():
				if is_instance_valid(entry.node):
					candidates.append(entry.node)
		"no_hedges":
			for node in root.find_children("*", "MeshInstance3D", true, false):
				if str(node.name).to_lower().contains("hedge"):
					candidates.append(node)
		"no_lights":
			for node in root.find_children("*", "Light3D", true, false):
				candidates.append(node)
	for node in candidates:
		if node.visible:
			node.visible = false
			hidden.append(node)
	return hidden
