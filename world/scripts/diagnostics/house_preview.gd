extends SceneTree
## Renders a house piece from several views into PNG files, for reviewing house styles and plans.
## Run with a display (or xvfb-run): godot --path world --script res://scripts/diagnostics/house_preview.gd
## -- <output directory> [record JSON]

const House = preload("res://scripts/pieces/house_piece.gd")
const Shapes = preload("res://scripts/pieces/shape_piece.gd")
const Library = preload("res://scripts/asset_library.gd")

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var output := args[0] if args.size() > 0 else "user://house-preview"
	var record: Dictionary = {"id": "house", "type": "house", "style": "modern", "bedrooms": 2, "bathrooms": 1}
	if args.size() > 1:
		var parsed: Variant = JSON.parse_string(args[1])
		if parsed is Dictionary:
			record.merge(parsed, true)
	DirAccess.make_dir_recursive_absolute(output)
	Library.load_catalog()
	var world := Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("6f9bd1")
	sky_material.sky_horizon_color = Color("d9e3ea")
	sky_material.ground_horizon_color = Color("c9bba5")
	sky_material.ground_bottom_color = Color("8b7b66")
	sky.sky_material = sky_material
	settings.background_mode = Environment.BG_SKY
	settings.sky = sky
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	settings.ambient_light_energy = 0.45
	settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	settings.tonemap_exposure = 0.85
	environment.environment = settings
	world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -35, 0)
	sun.light_energy = 1.0
	sun.light_color = Color("fff1df")
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	world.add_child(sun)
	# The ground, with a hole where a terrain would be dug out for the house's pool.
	var cut := House.terrain_cut(record)
	var hole := Rect2(-0.01, -0.01, 0.02, 0.02)
	if not cut.is_empty():
		hole = Rect2(cut.center - cut.half, cut.half * 2.0)
	var extent := 60.0
	for part: Rect2 in [Rect2(-extent, -extent, extent * 2.0, hole.position.y + extent), Rect2(-extent, hole.end.y, extent * 2.0, extent - hole.end.y),
			Rect2(-extent, hole.position.y, hole.position.x + extent, hole.size.y), Rect2(hole.end.x, hole.position.y, extent - hole.end.x, hole.size.y)]:
		var ground := Shapes.build({"shape": "box", "size": [part.size.x, 0.2, part.size.y], "collision": false,
			"material": {"texture": "dry_ground_01", "texture_size": 3.0}})
		ground.position = Vector3(part.get_center().x, -0.1, part.get_center().y)
		world.add_child(ground)
	var house := House.build(record)
	world.add_child(house)
	print("HOUSE_PLAN ", JSON.stringify(House.plan(record)))
	var camera := Camera3D.new()
	camera.fov = 60
	world.add_child(camera)
	camera.make_current()
	await process_frame
	var plan := House.plan(record)
	var size := Vector2(plan.footprint[0], plan.footprint[1])
	var span := maxf(size.x, size.y) + (6.0 if record.get("pool", false) else 0.0)
	var reach := span
	var views := [
		["front", Vector3(-reach * 0.55, 1.7, -reach * 1.05), Vector3(0, 1.4, 0)],
		["back", Vector3(reach * 0.8, 2.2, reach * 0.95), Vector3(0, 1.2, 0)],
		["aerial", Vector3(-reach * 0.6, reach * 1.1, -reach * 0.9), Vector3(0, 0, 0)],
		["cutaway", Vector3(reach * 0.35, reach * 1.15, -reach * 0.75), Vector3(0, 0, 0.5)],
	]
	if not cut.is_empty():
		var centre: Vector2 = cut.center
		views.append(["pool", Vector3(centre.x, 0, centre.y) + Vector3(-6, 3.2, -6).rotated(Vector3.UP, 0.4), Vector3(centre.x, 0, centre.y)])
	var floor_y := float(record.get("foundation_height", 0.3))
	for room: Dictionary in plan.rooms:
		if room.kind in ["living", "kitchen", "bedroom", "bathroom"]:
			var rect: Array = room.rect
			var centre := Vector3((rect[0] + rect[2]) * 0.5, floor_y + 1.6, (rect[1] + rect[3]) * 0.5)
			var corner := Vector3(rect[2] - 0.5, floor_y + 0.5, rect[3] - 0.5)
			var eye := centre.lerp(Vector3(rect[0] + 0.5, floor_y + 1.6, rect[1] + 0.5), 0.55)
			views.append(["inside_" + str(room.name).to_snake_case(), eye, corner])
	for view: Array in views:
		var cutaway: bool = view[0] == "cutaway"
		(house.get_node("Roof") as Node3D).visible = not cutaway
		(house.get_node("Ceilings") as Node3D).visible = not cutaway
		camera.look_at_from_position(view[1], view[2])
		for frame in 4:
			await process_frame
		var image := root.get_viewport().get_texture().get_image()
		image.save_png(output.path_join(str(view[0]) + ".png"))
		print("HOUSE_VIEW ", view[0])
	quit()
