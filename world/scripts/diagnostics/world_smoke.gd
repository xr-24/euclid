extends RefCounted
## Headless smoke test of the running world: every zone builds, an app opens and closes, a saved
## location round-trips, and an in-place shift replaces the zone around the player.
## Run with `-- --smoke`. Uses a throwaway save and never the user's world state.

const Packages = preload("res://scripts/zones/zone_packages.gd")
const PieceBuilder = preload("res://scripts/pieces/piece_builder.gd")

static func run(world: Node3D) -> void:
	var tree := world.get_tree()
	await _check_prop_lock(world, tree)
	for zone in world.manifest.zones:
		world._load_zone(zone.id)
		var package := Packages.definition(zone.id)
		if zone.id == "construct":
			assert(world.zone_root.get_node_or_null("GridFloor") is StaticBody3D)
		elif package.has("builder"):
			assert(world.zone_root.get_child_count() > 5)
		for piece: Dictionary in package.get("pieces", []):
			var node: Node = world.zone_root.get_node_or_null(PieceBuilder.LAYER + "/Piece_" + str(piece.id))
			assert(node != null and node.get_meta("piece_type") == piece.type)
		var anchors: Array = world.manifest.anchors.filter(func(anchor: Dictionary) -> bool: return anchor.zone == zone.id)
		assert(world.interactables.size() == anchors.size())
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
	print("CONSTRUCT_SMOKE_OK: installed zones, anchors, collision, application return, saved location round trip, in-place shift")
	tree.quit()

static func _check_prop_lock(world: Node3D, tree: SceneTree) -> void:
	world.set_physics_process(false)
	var tools = world.world_tools
	var spawned: Dictionary = tools.execute("spawn", {"type": "traffic_cone", "position": [0.65, 0.4, -2.6]})
	assert(spawned.ok)
	var body: RigidBody3D = tools.scene_node(spawned.id)
	var grab := InputEventMouseButton.new()
	grab.button_index = MOUSE_BUTTON_LEFT
	grab.pressed = true
	var toggle := InputEventMouseButton.new()
	toggle.button_index = MOUSE_BUTTON_RIGHT
	toggle.pressed = true
	var player: CharacterBody3D = world.player
	var camera: Camera3D = world.camera
	var grabber = world.grabber
	var hands = world.player_avatar.hands
	player.position = Vector3.ZERO
	for grab_locked_prop in [true, false]:
		for frame in 2:
			await tree.physics_frame
		camera.look_at(tools.scene_node(spawned.id).global_position + Vector3.UP * 0.35)
		grabber.handle(grab)
		grabber.tick(1.0 / 60.0, player, camera, tools, hands, true)
		grabber.handle(toggle)
		grabber.tick(1.0 / 60.0, player, camera, tools, hands, true)
		assert(tools.scene_node(spawned.id).freeze and grabber.hint() == "Locked")
		assert(tools.scene_node(spawned.id) == body, "Locking keeps the rendered prop in place.")
		for frame in 2:
			await tree.physics_frame
		if grab_locked_prop:
			grabber.handle(grab)
			grabber.tick(1.0 / 60.0, player, camera, tools, hands, true)
		grabber.handle(toggle)
		grabber.tick(1.0 / 60.0, player, camera, tools, hands, true)
		assert(not tools.scene_node(spawned.id).freeze and grabber.hint() == "Unlocked")
		assert(tools.scene_node(spawned.id) == body, "Unlocking keeps the rendered prop in place.")
	assert(tools.execute("delete", {"id": spawned.id}).ok)
	grabber.cancel()
	world.set_physics_process(true)
