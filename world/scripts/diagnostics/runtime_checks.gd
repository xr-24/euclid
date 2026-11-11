extends RefCounted
## Automated acceptance and screenshot flows. Keep test behavior out of the runtime controller.

static func smoke(world: Node3D) -> void:
	for zone in world.manifest.zones:
		world._load_zone(zone.id)
		assert(world.zone_root.get_child_count() > 5)
		assert(not world.interactables.is_empty())
		await world.get_tree().process_frame
	world._open_app("terminal")
	assert(world.overlay.visible)
	world._close_panel()
	assert(not world.overlay.visible)
	world._load_zone("villa")
	world.player.position = Vector3(4,0.1,2) # on the walk beside the reflecting pool
	world.player.rotation.y = 0.6
	world._write_state("user://smoke-state.json")
	world._load_zone("construct")
	world._read_state("user://smoke-state.json")
	assert(world.zone_id == "villa")
	assert(world.player.position.distance_to(Vector3(4,0.1,2)) < 0.01)
	assert(absf(world.player.rotation.y - 0.6) < 0.01)
	DirAccess.remove_absolute("user://smoke-state.json")
	for frame in range(15):
		await world.get_tree().physics_frame
	assert(world.player.position.y > -0.1)
	# Shift in place: the new zone replaces the old one around the world.player, who stays put.
	var before: Vector3 = world.player.position
	var old_root: Node3D = world.zone_root
	await world._shift("beach", 0.5)
	await world.get_tree().process_frame # the old zone is queued for deletion
	assert(world.zone_id == "beach" and not is_instance_valid(old_root) and world.zone_root.get_child_count() > 5)
	assert(not world.interactables.is_empty() and not world.shifting)
	assert(Vector2(world.player.position.x, world.player.position.z).distance_to(Vector2(before.x, before.z)) < 0.5)
	if not world.gateway_client.url.is_empty():
		if world.gateway_client.pending:
			await world.gateway_client.request.request_completed
		assert(world.gateway_connected, "Configured gateway must return a valid authenticated snapshot: HTTP %d transport %d" % [world.gateway_client.last_http_status,world.gateway_client.last_result])
		print("CONSTRUCT_GATEWAY_OK: authenticated snapshot received in Godot")
	print("CONSTRUCT_SMOKE_OK: three zones, anchors, collision, application return, saved location round trip, in-place shift")
	world.get_tree().quit()

static func capture(world: Node3D) -> void:
	var output := OS.get_environment("CONSTRUCT_CAPTURE_DIR")
	if output.is_empty():
		world.get_tree().quit(1)
		return
	# Extra viewpoints per zone: [suffix, eye position, point to look at].
	var views := {
		"villa": [["_pool", Vector3(3.4,0.1,-15), Vector3(0,0.6,22)], ["_portico", Vector3(-17.2,0.2,24), Vector3(-17,2.2,-22)],
			["_house", Vector3(9,0.1,-12), Vector3(-2,4.5,-36)], ["_view", Vector3(0,0.2,43.5), Vector3(0,-20,140)]],
		"beach": [["_shore", Vector3(-7,0,-10.5), Vector3(10,0.6,-26)], ["_surf", Vector3(2,0,-11.5), Vector3(0,-0.5,-17.5)], ["_back", Vector3(4,0,-11), Vector3(-6,1.2,8)], ["_wade", Vector3(1,-0.5,-17), Vector3(-4,-0.2,-40)]],
	}
	for zone in world.manifest.zones:
		world._load_zone(zone.id)
		world._close_panel()
		# Let global illumination, volumetric fog and temporal effects converge; on the shore, give
		# the simulated surf time to roll in from the wavemaker.
		for frame in range(90):
			await world.get_tree().process_frame
		if zone.id == "beach":
			await world.get_tree().create_timer(14.0).timeout
		print("CONSTRUCT_FPS %s %d" % [zone.id, Engine.get_frames_per_second()])
		await RenderingServer.frame_post_draw
		world.get_viewport().get_texture().get_image().save_png(output.path_join(str(zone.id) + ".png"))
		for view in views.get(zone.id, []):
			world.player.position = view[1]
			world.camera.global_position = world.player.position + Vector3(0,1.65,0)
			var target: Vector3 = view[2]
			var flat := Vector3(target.x - world.player.position.x, 0, target.z - world.player.position.z)
			world.player.rotation.y = atan2(-flat.x, -flat.z)
			world.camera.rotation.x = atan2(target.y - 1.65, flat.length())
			for frame in range(60):
				await world.get_tree().process_frame
			await RenderingServer.frame_post_draw
			world.get_viewport().get_texture().get_image().save_png(output.path_join(str(zone.id) + view[0] + ".png"))
	# The shift itself, mid-flight: villa to shore and back to the hub.
	for leg in [["villa", "beach", "shift_villa_beach"], ["beach", "construct", "shift_beach_hub"]]:
		world._load_zone(leg[0])
		for frame in range(60):
			await world.get_tree().process_frame
		var start := Time.get_ticks_msec()
		var worst := 0
		var tick := Time.get_ticks_usec()
		world._shift(leg[1])
		for moment in [0.6, 1.3, 2.4, 3.6, 4.4]:
			while (Time.get_ticks_msec() - start) / 1000.0 < moment:
				await world.get_tree().process_frame
				var now := Time.get_ticks_usec()
				worst = maxi(worst, now - tick)
				tick = now
			await RenderingServer.frame_post_draw
			world.get_viewport().get_texture().get_image().save_png(output.path_join("%s_%d.png" % [leg[2], int(moment * 10)]))
			await world.get_tree().process_frame
			tick = Time.get_ticks_usec() # screenshot frames are left out of the timing
		var longest := 0
		var last := Time.get_ticks_usec()
		while world.shifting:
			await world.get_tree().process_frame
			var now := Time.get_ticks_usec()
			longest = maxi(longest, now - last)
			last = now
		print("CONSTRUCT_SHIFT %s longest frame %.1f ms" % [leg[2], maxi(worst, longest) / 1000.0])
	world.wrist.raise_wrist("areas")
	await world.get_tree().create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	world.get_viewport().get_texture().get_image().save_png(output.path_join("wrist.png"))
	print("CONSTRUCT_CAPTURE_OK")
	world.get_tree().quit()
