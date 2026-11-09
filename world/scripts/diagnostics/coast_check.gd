extends Node
## Normal game's coast, rendered without saves, desktop input or a visible window.
const Art = preload("res://scripts/world_art.gd")
var world: Node3D

func start(target: Node3D) -> void:
	world = target
	if RenderingServer.get_rendering_device() == null:
		push_error("Coast check requires a real Forward+ GPU")
		get_tree().quit(2)
		return
	world.overlay.hide()
	world.set_physics_process(false)
	world._load_zone("beach")
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var output := OS.get_environment("CONSTRUCT_WATER_CHECK_DIR")
	DirAccess.make_dir_recursive_absolute(output)
	var body: Dictionary = world.zone_root.get_meta("water").sims[0]
	var baseline := "--coast-baseline" in OS.get_cmdline_user_args()
	var debug := "--coast-debug" in OS.get_cmdline_user_args()
	var warmup := float(OS.get_environment("CONSTRUCT_COAST_WARMUP"))
	if not baseline and not debug:
		# Also check the pool mirror's visibility gating and zone-exit cleanup.
		world._load_zone("villa")
		world.camera.global_position = Vector3(3.4,1.75,19)
		world.camera.look_at(Vector3(0,0,10))
		await get_tree().create_timer(3.0).timeout
		var reflection: Node = world.zone_root.get_node("PoolReflection")
		assert(reflection.reflected_frames>0 and reflection.material.get_shader_parameter("pool_reflection_enabled"))
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(output.path_join("pool_current.png"))
		world.camera.look_at(world.camera.global_position+Vector3(10,5,0))
		for frame in 20: await get_tree().process_frame
		assert(not reflection.material.get_shader_parameter("pool_reflection_enabled"))
		world._load_zone("beach")
		body = world.zone_root.get_meta("water").sims[0]
	await get_tree().create_timer(10.0 if debug else maxf(18.0,warmup)).timeout
	var measurements := []
	var views := [
		["overview",Vector3(-18,7,-6),Vector3(3,-0.55,-35)],
		["shoreline",Vector3(2,1.65,-11.5),Vector3(0,-0.55,-21)],
		["box_edge",Vector3(-22,4,-43),Vector3(0,-0.55,-40)],
		["offshore",Vector3(0,2,-65),Vector3(0,-0.55,-110)]]
	if debug: views = [views[1]]
	for view in views:
		world.camera.global_position = view[1]
		world.camera.look_at(view[2])
		await get_tree().create_timer(1.0).timeout
		var frames: Array[float] = []
		var start_usec := Time.get_ticks_usec()
		var last := start_usec
		while Time.get_ticks_usec()-start_usec < 2000000:
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			frames.append((now-last)/1000.0)
			last = now
		frames.sort()
		measurements.append({"view":view[0],"mean_hidden_frame_ms":frames.reduce(func(a,b):return a+b,0.0)/frames.size(),
			"p95_hidden_frame_ms":frames[int(frames.size()*0.95)],"frames":frames.size()})
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(output.path_join(view[0]+".png"))
		if debug:
			var materials: Array = body.get("surfaces",[])
			for setting in [1,2,3,0]:
				for material in materials: material.set_shader_parameter("debug_surface",setting)
				for frame in 10: await get_tree().process_frame
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(output.path_join("debug_%d.png"%setting))
			for material in materials: material.set_shader_parameter("refraction_strength",0.0)
			for frame in 10: await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(output.path_join("no_refraction.png"))
			world.environment.ssr_enabled = false
			for frame in 20: await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(output.path_join("no_ssr.png"))
			for mesh in world.zone_root.find_children("*","MeshInstance3D",true,false):
				if mesh.material_override in materials: mesh.hide()
			for frame in 20: await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(output.path_join("dry_scene.png"))
	var surfaces: Array = body.get("surfaces",[])
	if not baseline:
		assert(body.get("profile","") == "shore" and surfaces.size() == 3)
		assert(int(body.sim.custom_cfg.mode) == 2)
		for material in surfaces:
			assert(material.shader.resource_path == "res://shaders/shore_water.gdshader")
			assert(absf(float(material.get_shader_parameter("wave_time"))-body.sim.sim_time)<0.1)
	# Save real fields for independent numerical inspection; readbacks follow all timings.
	var fields := {}
	for pair in [["state",body.sim.tex_state],["bottom",body.sim.tex_bottom],["derived",body.sim.tex_derived]]:
		var file := FileAccess.open(output.path_join(pair[0]+".rgba32f"),FileAccess.WRITE)
		var image: Image = pair[1].get_image()
		image.convert(Image.FORMAT_RGBAF)
		fields[pair[0]] = image.get_data().to_float32_array()
		file.store_buffer(image.get_data())
		file.close()
	var state: PackedFloat32Array = fields.state
	var bottom: PackedFloat32Array = fields.bottom
	var derived: PackedFloat32Array = fields.derived
	for scalar in state: assert(is_finite(scalar))
	var sum := 0.0
	var squared := 0.0
	var foam := 0.0
	var count := 0
	for along in range(60,body.n-60):
		for cross in range(80,300):
			var index: int = (along*body.n+cross)*4
			if state[index]-bottom[index]<0.02: continue
			sum += state[index]
			squared += state[index]*state[index]
			foam += derived[index+2]
			count += 1
	var wave_rms := sqrt(maxf(squared/maxi(count,1)-pow(sum/maxi(count,1),2),0.0))
	var foam_mean := foam/maxi(count,1)
	if not baseline:
		assert(count>1000 and foam_mean<0.10 and wave_rms>0.005 and wave_rms<0.4,
			"Open water must remain moving without a saturated foam box")
	var result := {"baseline":baseline,"surfaces":surfaces.size(),"simulation_time":body.sim.sim_time,
		"nan_cells":body.sim.dbg_nan_cells,"mode":body.sim.custom_cfg.mode,"samples":measurements,
		"offshore_foam_mean":foam_mean,"offshore_wave_rms_m":wave_rms,"finite_state":true,
		"device":RenderingServer.get_video_adapter_name(),"scope":"1440x900 hidden Vulkan frame timings; not desktop FPS"}
	var report := FileAccess.open(output.path_join("results.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify(result,"\t"))
	report.close()
	assert(body.sim.dbg_nan_cells == 0)
	print("CONSTRUCT_COAST_CHECK_OK "+JSON.stringify(result))
	get_tree().quit()

func _physics_process(delta: float) -> void:
	if is_instance_valid(world): Art.water_tick(world,delta)
