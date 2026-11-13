extends RefCounted
## Headless smoke test of the running world: every zone builds, an app opens and closes, a saved
## location round-trips, and an in-place shift replaces the zone around the player.
## Run with `-- --smoke`. Uses a throwaway save and never the user's world state.

const Packages = preload("res://scripts/zones/zone_packages.gd")
const PieceBuilder = preload("res://scripts/pieces/piece_builder.gd")

static func run(world: Node3D) -> void:
	var tree := world.get_tree()
	await _check_grid_pieces(world, tree)
	await _check_prop_lock(world, tree)
	await _check_prop_lock(world, tree, true)
	await _check_piece_water(world, tree)
	for zone in world.manifest.zones:
		world._load_zone(zone.id)
		var package := Packages.definition(zone.id)
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
	assert(world.zone_id == "beach" and not is_instance_valid(old_root) and world.zone_root.get_node(PieceBuilder.LAYER).get_child_count() > 5)
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

static func _check_grid_pieces(world: Node3D, tree: SceneTree) -> void:
	var floor_body: StaticBody3D = world.pieces.node_for("floor")
	var slab := floor_body.get_node("Collision") as CollisionShape3D
	var surface := floor_body.get_node("Mesh") as MeshInstance3D
	var backdrop: MultiMeshInstance3D = world.pieces.node_for("backdrop").get_node("Boxes")
	assert(surface.mesh.size == Vector2(640, 640) and slab.shape.size == Vector3(128, 0.4, 128))
	assert(backdrop.multimesh.instance_count > 150)
	for direction in ["north", "south", "east", "west"]:
		var barrier: StaticBody3D = world.pieces.node_for("boundary-" + direction)
		assert(barrier.get_node_or_null("Mesh") == null and barrier.get_node("Collision").shape is BoxShape3D)

	var committed_spacing: float = surface.material_override.get_shader_parameter("floor_spacing")
	var committed_height := backdrop.scale.y
	var changed: Dictionary = await world._execute_world_tool({"tool": "edit_piece", "target": "floor",
		"piece_values": {"material": {"line_spacing": 5.5}}})
	assert(changed.ok and is_equal_approx(surface.material_override.get_shader_parameter("floor_spacing"), 5.5))
	var draft := "piece-appearance-smoke"
	var preview: Dictionary = await world._preview_live_change({"draft": draft, "grid": {
		"schema_version": 1, "floor_spacing": 4.0, "wall_height": 1.25}})
	assert(preview.ok and world._live_change_status(draft) == "active")
	assert(world.pieces.node_for("floor") == floor_body and floor_body.get_node("Collision") == slab)
	assert(is_equal_approx(surface.material_override.get_shader_parameter("floor_spacing"), 4.0) and is_equal_approx(backdrop.scale.y, 1.25))
	assert(world.pieces.record("floor").material.line_spacing == 5.5)
	assert(world._finish_live_change("discard", draft).live)
	assert(is_equal_approx(surface.material_override.get_shader_parameter("floor_spacing"), 5.5) and is_equal_approx(backdrop.scale.y, committed_height))
	assert(world.pieces.execute({"tool": "undo_piece"}).ok)
	assert(is_equal_approx(surface.material_override.get_shader_parameter("floor_spacing"), committed_spacing))

	world.player.position = Vector3(4, 0.05, 4)
	assert(world.pieces.execute({"tool": "edit_piece", "target": "floor", "piece_values": {"position": [0, 1, 0]}}).ok)
	await tree.physics_frame
	await tree.physics_frame
	var placement: Array = world._scene_spawn_position()
	assert(placement.size() == 3 and is_equal_approx(placement[1], 1.0), "Prop placement follows the moved floor.")
	assert(world.pieces.execute({"tool": "undo_piece"}).ok)
	print("CONSTRUCT_GRID_PIECES_OK")

static func _check_prop_lock(world: Node3D, tree: SceneTree, as_piece := false) -> void:
	world.set_physics_process(false)
	var tools = world.world_tools
	var spawned: Dictionary = tools.execute("spawn", {"type": "traffic_cone", "position": [0.65, 0.4, -2.6]})
	if as_piece:
		assert(tools.execute("delete", {"id": spawned.id}).ok)
		spawned = world.pieces.execute({"tool": "add_piece", "target": "prop", "piece_values": {"position": [0.65, 0.4, -2.6]}})
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

static func _check_piece_water(world: Node3D, tree: SceneTree) -> void:
	world._load_zone("open_ground")
	var water: Dictionary = await world._execute_world_tool({"tool": "add_piece", "target": "water",
		"piece_values": {"water_kind": "stream", "position": [6, 1, -8], "water_size": [4, 10], "flow_speed": 2}})
	assert(water.ok)
	var player: CharacterBody3D = world.player
	player.position = Vector3(6, 0.2, -8)
	await tree.physics_frame
	assert(is_equal_approx(world.zone_root.get_meta("water_surfaces")[0].surface.global_position.y, 1.0))
	assert(not world.scanner._water.inspect(water.id).is_empty())
	var planted: Dictionary = await world._execute_world_tool({"tool": "add_piece", "target": "scatter", "parent": "ground",
		"piece_values": {"count": 6, "position": [6, 0, -8], "scatter_size": [10, 10]}})
	assert(planted.ok and world.pieces.node_for(planted.id).get_meta("scatter_count") == 6)
	assert((await world._execute_world_tool({"tool": "undo_piece"})).ok)
	assert((await world._execute_world_tool({"tool": "undo_piece"})).ok)
	assert(world.zone_root.get_meta("water_surfaces").is_empty())
