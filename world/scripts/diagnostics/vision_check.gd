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
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var screen := world.get_viewport().get_texture().get_image()
	var mine := screen.get_pixel(screen.get_width() / 2, screen.get_height() / 2)
	var seen: Dictionary = await world.vision.capture("player", "", Vector3.ZERO, null, 70.0, "vision-check")
	if not seen.ok:
		return _fail(tree, "capture the player's view: %s" % seen.message)
	var image := Image.new()
	image.load_jpg_from_buffer(Marshalls.base64_to_raw(seen.image))
	image.save_jpg(output.path_join("player.jpg"))
	var theirs := image.get_pixel(image.get_width() / 2, image.get_height() / 2)
	# The environment's grading dims the red, so compare how strongly red dominates on each side.
	if _red(mine) < 0.08 or _red(theirs) > _red(mine) * 0.4:
		return _fail(tree, "the private panel should show on the player's screen (%s) and not to the agent (%s)" % [mine, theirs])
	var after := world.get_viewport().get_texture().get_image()
	var still := after.get_pixel(after.get_width() / 2, after.get_height() / 2)
	if _red(still) < 0.08:
		return _fail(tree, "the private panel should stay on the player's screen after the capture")
	var at: Vector3 = world.player.global_position + Vector3(4, 3, 4)
	var placed: Dictionary = world.vision.place("corner", at, [world.player.global_position.x, world.player.global_position.y, world.player.global_position.z], 60.0)
	var from_camera: Dictionary = await world.vision.capture("camera", "corner")
	if not placed.ok or not from_camera.ok:
		return _fail(tree, "placed camera: %s %s" % [placed.message, from_camera.message])
	image.load_jpg_from_buffer(Marshalls.base64_to_raw(from_camera.image))
	image.save_jpg(output.path_join("camera.jpg"))
	print("VISION_CHECK_OK: %d-byte view without the private panel; placed camera works" % Marshalls.base64_to_raw(seen.image).size())
	tree.quit(0)

static func _red(color: Color) -> float:
	return color.r - maxf(color.g, color.b)

static func _fail(tree: SceneTree, message: String) -> void:
	push_error("VISION_CHECK_FAILED: " + message)
	tree.quit(1)
