extends RefCounted
## Headless smoke test of the running world: every zone builds, an app opens and closes, a saved
## location round-trips, and an in-place shift replaces the zone around the player.
## Run with `-- --smoke`. Uses a throwaway save and never the user's world state.

static func run(world: Node3D) -> void:
	var tree := world.get_tree()
	for zone in world.manifest.zones:
		world._load_zone(zone.id)
		if zone.id == "construct":
			assert(world.zone_root.get_node_or_null("GridFloor") is StaticBody3D)
		else:
			assert(world.zone_root.get_child_count() > 5)
		assert(not world.interactables.is_empty())
		await tree.process_frame
	# The wrist computer is the menu: it rises with the arm, and any panel lowers it.
	var wrist = world.wrist
	wrist.raise_wrist("areas")
	assert(wrist.is_open and wrist.current().id == "areas" and wrist.rows().size() == world.manifest.zones.size())
	await tree.create_timer(0.8).timeout
	assert(wrist._layer.visible and wrist.open_t == 1.0)
	wrist.turn(-1)
	assert(wrist.current().id == "system")
	world._open_app("terminal")
	assert(world.overlay.visible and not wrist.is_open)
	world._close_panel()
	assert(not world.overlay.visible)
	world._load_zone("villa")
	world.player.position = Vector3(4, 0.1, 2) # on the walk beside the reflecting pool
	world.player.rotation.y = 0.6
	world._write_state("user://smoke-state.json")
	world._load_zone("construct")
	world._read_state("user://smoke-state.json")
	assert(world.zone_id == "villa")
	assert(world.player.position.distance_to(Vector3(4, 0.1, 2)) < 0.01)
	assert(absf(world.player.rotation.y - 0.6) < 0.01)
	DirAccess.remove_absolute("user://smoke-state.json")
	for frame in range(15):
		await tree.physics_frame
	assert(world.player.position.y > -0.1)
	# Shift in place: the new zone replaces the old one around the player, who stays put.
	var before: Vector3 = world.player.position
	var old_root: Node = world.zone_root
	await world._shift("beach", 0.5)
	await tree.process_frame # the old zone is queued for deletion
	assert(world.zone_id == "beach" and not is_instance_valid(old_root) and world.zone_root.get_child_count() > 5)
	assert(not world.interactables.is_empty() and not world.shifting)
	var after: Vector3 = world.player.position
	assert(Vector2(after.x, after.z).distance_to(Vector2(before.x, before.z)) < 0.5)
	if not str(world.gateway_url).is_empty():
		if world.request_pending:
			await world.request.request_completed
		assert(world.gateway_connected, "Configured gateway must return a valid authenticated snapshot")
		print("CONSTRUCT_GATEWAY_OK: authenticated snapshot received in Godot")
	print("CONSTRUCT_SMOKE_OK: three zones, anchors, collision, application return, saved location round trip, in-place shift")
	tree.quit()
