extends RefCounted
## Rendered captures of every zone, its named capture views, two shifts in flight and the wrist computer.
## Run with `-- --capture` and CONSTRUCT_CAPTURE_DIR set. Frames are written as PNG files.
const Packages = preload("res://scripts/zones/zone_packages.gd")

static func run(world: Node3D) -> void:
	var tree := world.get_tree()
	var output := OS.get_environment("CONSTRUCT_CAPTURE_DIR")
	if output.is_empty():
		tree.quit(1)
		return
	for zone in world.manifest.zones:
		world._load_zone(zone.id)
		world._close_panel()
		# Let global illumination, volumetric fog and temporal effects converge; on the shore, give
		# the simulated surf time to roll in from the wavemaker.
		for frame in range(90):
			await tree.process_frame
		var warmup: float = Packages.definition(zone.id).capture_warmup
		if warmup > 0.0:
			await tree.create_timer(warmup).timeout
		print("CONSTRUCT_FPS %s %d" % [zone.id, Engine.get_frames_per_second()])
		await _save_frame(world, output.path_join(str(zone.id) + ".png"))
		for view in Packages.views(zone.id, "capture"):
			var player: CharacterBody3D = world.player
			var camera: Camera3D = world.camera
			player.position = view[1]
			camera.global_position = player.position + Vector3(0, 1.65, 0)
			var target: Vector3 = view[2]
			var flat := Vector3(target.x - player.position.x, 0, target.z - player.position.z)
			player.rotation.y = atan2(-flat.x, -flat.z)
			camera.rotation.x = atan2(target.y - 1.65, flat.length())
			for frame in range(60):
				await tree.process_frame
			await _save_frame(world, output.path_join(str(zone.id) + "_" + view[0] + ".png"))
	# The shift itself, mid-flight: villa to shore and back to the hub.
	for leg in [["villa", "beach", "shift_villa_beach"], ["beach", "construct", "shift_beach_hub"]]:
		world._load_zone(leg[0])
		for frame in range(60):
			await tree.process_frame
		var start := Time.get_ticks_msec()
		var worst := 0
		var tick := Time.get_ticks_usec()
		world._shift(leg[1])
		for moment in [0.6, 1.3, 2.4, 3.6, 4.4]:
			while (Time.get_ticks_msec() - start) / 1000.0 < moment:
				await tree.process_frame
				var now := Time.get_ticks_usec()
				worst = maxi(worst, now - tick)
				tick = now
			await _save_frame(world, output.path_join("%s_%d.png" % [leg[2], int(moment * 10)]))
			await tree.process_frame
			tick = Time.get_ticks_usec() # screenshot frames are left out of the timing
		var longest := 0
		var last := Time.get_ticks_usec()
		while world.shifting:
			await tree.process_frame
			var now := Time.get_ticks_usec()
			longest = maxi(longest, now - last)
			last = now
		print("CONSTRUCT_SHIFT %s longest frame %.1f ms" % [leg[2], maxi(worst, longest) / 1000.0])
	world.wrist.raise_wrist("areas")
	await tree.create_timer(0.8).timeout
	await _save_frame(world, output.path_join("wrist.png"))
	print("CONSTRUCT_CAPTURE_OK")
	tree.quit()

static func _save_frame(world: Node3D, path: String) -> void:
	await RenderingServer.frame_post_draw
	world.get_viewport().get_texture().get_image().save_png(path)
