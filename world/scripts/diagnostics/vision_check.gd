extends RefCounted
## Agent vision in a rendered world: a view through the player's eyes leaves out private surfaces
## (a red panel in the private group, right in front of the camera) while the player's own screen
## still shows it, and a placed camera renders too. Run with a renderer: -- --vision-check <dir>.
## Saves player.jpg and camera.jpg there and prints VISION_CHECK_OK.

static func run(world: Node3D) -> void:
	var tree := world.get_tree()
	var args := OS.get_cmdline_user_args()
	var output := args[args.find("--vision-check") + 1] if args.find("--vision-check") + 1 < args.size() else "user://vision"
	DirAccess.make_dir_recursive_absolute(output)
	for frame in 30:
		await tree.process_frame
	# Before and after a red panel in the private group appears right in front of the camera: the
	# player's screen changes, the agent's view does not. Comparing each with itself works in any
	# environment's colors.
	var screen_before := _centre(world.get_viewport().get_texture().get_image())
	var first: Dictionary = await world.vision.capture("player", "", Vector3.ZERO, null, 70.0, "vision-check")
	if not first.ok:
		return _fail(tree, "capture the player's view: %s" % first.message)
	var panel := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.6, 0.6)
	panel.mesh = quad
	var red := StandardMaterial3D.new()
	red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	red.albedo_color = Color(1, 0, 0)
	red.cull_mode = BaseMaterial3D.CULL_DISABLED
	panel.material_override = red
	panel.add_to_group("private_world_surfaces")
	world.add_child(panel)
	var eye: Camera3D = world.camera
	panel.global_transform = eye.global_transform.translated_local(Vector3(0, 0, -0.5))
	for frame in 4:
		await RenderingServer.frame_post_draw
	var screen_after := _centre(world.get_viewport().get_texture().get_image())
	var seen: Dictionary = await world.vision.capture("player", "", Vector3.ZERO, null, 70.0, "vision-check")
	if not seen.ok:
		return _fail(tree, "capture the player's view: %s" % seen.message)
	var image := Image.new()
	image.load_jpg_from_buffer(Marshalls.base64_to_raw(seen.image))
	image.save_jpg(output.path_join("player.jpg"))
	var before := Image.new()
	before.load_jpg_from_buffer(Marshalls.base64_to_raw(first.image))
	var agent_change := _distance(_centre(before), _centre(image))
	var player_change := _distance(screen_before, screen_after)
	if player_change < 0.15 or agent_change > 0.08:
		return _fail(tree, "the private panel should change the player's screen (%.2f) and not the agent's view (%.2f)" % [player_change, agent_change])
	panel.free()
	var at: Vector3 = world.player.global_position + Vector3(4, 3, 4)
	var placed: Dictionary = world.vision.place("corner", at, [world.player.global_position.x, world.player.global_position.y, world.player.global_position.z], 60.0)
	var from_camera: Dictionary = await world.vision.capture("camera", "corner")
	if not placed.ok or not from_camera.ok:
		return _fail(tree, "placed camera: %s %s" % [placed.message, from_camera.message])
	image.load_jpg_from_buffer(Marshalls.base64_to_raw(from_camera.image))
	image.save_jpg(output.path_join("camera.jpg"))
	var cost: float = await load("res://scripts/extensions/hot_load.gd").render_ms(5)
	# The compatibility renderer does not measure render time; Forward+ does.
	if cost == 0.0:
		return _fail(tree, "render time should be measured or reported as unavailable, not zero")
	print("VISION_CHECK_OK: render time %.2f ms; %d-byte view without the private panel; placed camera works" % [cost, Marshalls.base64_to_raw(seen.image).size()])
	tree.quit(0)

static func _centre(image: Image) -> Color:
	return image.get_pixel(image.get_width() / 2, image.get_height() / 2)

static func _distance(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()

static func _fail(tree: SceneTree, message: String) -> void:
	push_error("VISION_CHECK_FAILED: " + message)
	tree.quit(1)
