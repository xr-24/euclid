extends Node
## Rendered water regression: controlled walk/splash and GPU height readback. No normal save IO.
var world: Node3D
var output := ""
var drive := {}
var peak := -INF
var results := {}
var resting_pool: Image
var wake_change := 0.0

func start(target: Node3D) -> void:
	world = target
	if RenderingServer.get_rendering_device() == null:
		push_error("Water checks require Forward+ and a GPU")
		get_tree().quit(2)
		return
	process_physics_priority = -100
	output = OS.get_environment("CONSTRUCT_WATER_CHECK_DIR")
	if output.is_empty(): output = ProjectSettings.globalize_path("res://../.local/water-check")
	DirAccess.make_dir_recursive_absolute(output)
	world.overlay.hide()
	world._load_zone("villa")
	_view(Vector3(3.4,0.1,19),Vector3(0,0,10))
	await get_tree().create_timer(8.0).timeout
	var pool := _body()
	results["rest"] = _stats(pool)
	resting_pool = pool.sim.tex_state.get_image()
	var raw := FileAccess.open(output.path_join("pool_rest.rgba32f"),FileAccess.WRITE)
	raw.store_buffer(resting_pool.get_data())
	raw.close()
	await _capture("pool_rest")
	var reflection: Node = world.zone_root.get_node_or_null("PoolReflection")
	assert(reflection != null and reflection.reflected_frames > 0)
	results["reflection_frames"] = reflection.reflected_frames
	var mirror_image: Image = reflection.viewport.get_texture().get_image()
	mirror_image.convert(Image.FORMAT_RGB8)
	mirror_image.save_png(output.path_join("pool_mirror.png"))
	reflection.set_process(false)
	reflection.material.set_shader_parameter("pool_reflection_enabled",false)
	await _capture("pool_reflections_off")
	reflection.set_process(true)
	_view(Vector3(3.2,0.1,-18.5),Vector3(0,-0.12,-17.5))
	await _capture("pool_north_end")
	_view(Vector3(3.2,0.1,28.5),Vector3(0,-0.12,27.5))
	await _capture("pool_south_end")
	_view(Vector3(3.4,0.1,19),Vector3(0,0,10))
	drive = {"start":Time.get_ticks_msec(), "a":Vector3(0.6,-0.60,23), "b":Vector3(0.6,-0.60,16), "seconds":5.0, "first":true}
	for i in 5:
		await get_tree().create_timer(1.0).timeout
		var measured := _stats(pool)
		peak = maxf(peak, measured.max_surface)
		wake_change = maxf(wake_change,_wake_difference(pool))
		print("WATER_SAMPLE " + JSON.stringify(measured))
	results["wake_peak"] = peak
	results["wake_change_m"] = wake_change
	await _capture("pool_walk")
	drive.clear()
	world.player.position = Vector3(3.4,0.1,19)
	world.player.velocity = Vector3.ZERO
	await get_tree().create_timer(8.0).timeout
	results["settled"] = _stats(pool)
	raw = FileAccess.open(output.path_join("pool_settled.rgba32f"),FileAccess.WRITE)
	raw.store_buffer(pool.sim.tex_state.get_image().get_data())
	raw.close()
	await _capture("pool_settled")
	world._load_zone("beach")
	_view(Vector3(2,0,-11.5),Vector3(0,-0.5,-25))
	await get_tree().create_timer(18.0).timeout
	var shore := _body()
	results["shore"] = _stats(shore)
	await _capture("shore")
	for spec in [["shore_side",Vector3(22,1,-17),Vector3(0,-0.55,-35)],
		["shore_overview",Vector3(0,13,-3),Vector3(0,-0.55,-45)],
		["offshore",Vector3(0,2,-65),Vector3(0,-0.55,-110)]]:
		_view(spec[1],spec[2])
		await get_tree().create_timer(0.5).timeout
		await _capture(spec[0])
	# Freeze the field to compare geometry-derived normals with the detail ripple layer.
	shore.sim.set_process(false)
	for mesh in world.zone_root.find_children("*","MeshInstance3D",true,false):
		var material = mesh.material_override
		if material is ShaderMaterial and material.shader.resource_path == "res://shaders/shore_water.gdshader":
			material.set_shader_parameter("detail_normal_strength",0.0)
	await _capture("shore_no_detail")
	_view(Vector3(10,2,-49),Vector3(0,-0.55,-100))
	await get_tree().create_timer(1.0).timeout
	await _capture("open_water")
	var passed: bool = peak < 0.06 and absf(results.settled.mean_surface-results.rest.mean_surface) < 0.0001 \
		and absf(results.settled.volume_m3/results.rest.volume_m3-1.0) < 0.0001 \
		and results.rest.bulk_max_surface < -0.09 and results.rest.max_surface < 0.06 \
		and wake_change > 0.003 and wake_change < 0.08 \
		and is_finite(results.shore.max_surface) and is_finite(results.shore.min_surface)
	results["passed"] = passed
	var file := FileAccess.open(output.path_join("results.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(results,"\t"))
	file.close()
	print("CONSTRUCT_WATER_CHECK " + JSON.stringify(results))
	if passed: print("CONSTRUCT_WATER_CHECK_OK")
	else: push_error("Water check failed: pillow, invisible/excessive wake, drift, overtopping, or non-finite state")
	get_tree().quit(0 if passed else 1)

func _physics_process(_delta: float) -> void:
	if drive.is_empty(): return
	var t := clampf((Time.get_ticks_msec()-drive.start)/1000.0/drive.seconds,0.0,1.0)
	world.player.position = (drive.a as Vector3).lerp(drive.b,t)
	world.player.velocity = (drive.b-drive.a)/drive.seconds
	if drive.first:
		world.player.velocity.y = -3.0
		drive.first = false

func _body() -> Dictionary:
	return world.zone_root.get_meta("water").sims[0]

func _view(at: Vector3, target: Vector3) -> void:
	world.player.position = at
	world.player.velocity = Vector3.ZERO
	var flat := Vector2(target.x-at.x,target.z-at.z)
	world.player.rotation.y = atan2(-flat.x,-flat.y)
	world.camera.rotation.x = atan2(target.y-at.y-1.65,flat.length())

func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	world.get_viewport().get_texture().get_image().save_png(output.path_join(name+".png"))

func _stats(body: Dictionary) -> Dictionary:
	var image: Image = body.sim.tex_state.get_image()
	var bottom: Image = body.sim.tex_bottom.get_image()
	var maximum := -INF
	var bulk_maximum := -INF
	var peak_depth := 0.0
	var peak_position := Vector2.ZERO
	var minimum := INF
	var volume := 0.0
	var total := 0.0
	var count := 0
	# Volume must integrate every cell. Sparse samples alias a moving short wake and
	# can falsely report volume growth even when the full conservative field is stable.
	var state_floats := image.get_data().to_float32_array()
	var bed_floats := bottom.get_data().to_float32_array()
	for index in range(0,state_floats.size(),4):
		volume += maxf(state_floats[index]-bed_floats[index],0.0)*body.dx*body.dx
	# Include boundary rows and wet cells over raised beds: these were the missed pool pillows.
	for y in range(0,body.n,2):
		for x in range(0,body.n,2):
			var bed := bottom.get_pixel(x,y).r
			var value := image.get_pixel(x,y).r
			if value-bed < 0.001: continue
			if value+body.sea_level > maximum:
				maximum = value+body.sea_level
				peak_depth = value-bed
				peak_position = body.origin+Vector2(y+0.5,x+0.5)*body.dx
			if value-bed > 0.02: bulk_maximum = maxf(bulk_maximum,value+body.sea_level)
			minimum = minf(minimum,value+body.sea_level)
			total += value+body.sea_level
			count += 1
	return {"max_surface":maximum,"bulk_max_surface":bulk_maximum,"peak_depth":peak_depth,
		"peak_x":peak_position.x,"peak_z":peak_position.y,"min_surface":minimum,
		"mean_surface":total/maxi(count,1),"volume_m3":volume,"samples":count}

func _wake_difference(body: Dictionary) -> float:
	var image: Image = body.sim.tex_state.get_image()
	var maximum := 0.0
	for z in range(175,313,2): # route neighborhood, world z 14..25 m
		var world_z := float(z)*0.08
		var i := clampi(int((world_z-body.origin.y)/body.dx),0,body.n-1)
		for x in range(-18,19,2):
			var j := clampi(int((float(x)*0.08-body.origin.x)/body.dx),0,body.n-1)
			maximum = maxf(maximum,absf(image.get_pixel(i,j).r-resting_pool.get_pixel(i,j).r))
	return maximum
