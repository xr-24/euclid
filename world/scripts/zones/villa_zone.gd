extends RefCounted
## Getty-inspired villa geometry, materials and planting.
const Assets = preload("res://scripts/assets/asset_library.gd")
const Water = preload("res://scripts/simulation/water_system.gd")

static func build(context: RefCounted) -> bool:
	var path := "res://assets/generated/villa_estate.glb"
	if not ResourceLoader.exists(path) or not FileAccess.file_exists("res://assets/generated/villa_layout.json"):
		return false
	var root: Node3D = context.build_root
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/generated/villa_layout.json"))
	var estate := (Assets.get_resource(path) as PackedScene).instantiate() as Node3D
	root.add_child(estate)
	var mats := {
		"limestone": Assets.pbr("marble_rock_02", 3.0, Color(1.07, 1.03, 0.96), Color("d8c8a8")),
		"marble_floor": Assets.pbr("marble_01", 3.0, Color(1.06, 1.04, 1.0), Color("ddd5c6")),
		"plaster": Assets.pbr("white_plaster_02", 3.0, Color(1.04, 0.97, 0.86), Color("e2d6c0")),
		"roof_tiles": Assets.pbr("clay_roof_tiles_02", 2.0, Color(1.0, 0.92, 0.86), Color("8a3b22")),
		"timber": Assets.pbr("dark_wooden_planks", 2.5, Color(0.85, 0.72, 0.6), Color("3a2414")),
		"gravel": Assets.pbr("gravel_ground_01", 3.0, Color(1.08, 1.02, 0.92), Color("b8a888")),
		"soil": Assets.pbr("brown_mud_leaves_01", 1.5, Color.WHITE, Color("3a2a1a")),
		"hedge": Assets.pbr("forest_leaves_02", 0.9, Color(0.4, 0.62, 0.3), Color("2f4a22")),
		"pool_basin": Assets.pbr("granite_tile", 1.2, Color(0.32, 0.38, 0.4), Color("1d2628")),
		"fresco": _fresco(false),
		"fresco_frieze": _fresco(true),
	}
	var window := StandardMaterial3D.new()
	window.albedo_color = Color(0.03, 0.035, 0.04)
	window.roughness = 0.12
	window.metallic = 0.4
	mats["window"] = window
	for child in estate.find_children("*", "MeshInstance3D"):
		var mesh_node := child as MeshInstance3D
		var key := str(mesh_node.name).to_lower().trim_prefix("col_").trim_prefix("art_")
		if mats.has(key):
			mesh_node.material_override = mats[key]
		if mesh_node.name.begins_with("COL_"):
			Assets.add_mesh_collision(mesh_node)
	# The hills it stands among, and the Pacific far below to the south.
	var hills := (Assets.get_resource("res://assets/generated/villa_hills.glb") as PackedScene).instantiate() as Node3D
	root.add_child(hills)
	var hill_mat := ShaderMaterial.new()
	hill_mat.shader = Assets.get_resource("res://shaders/hillside.gdshader")
	var grass := Assets.texture_set("aerial_grass_rock")
	var dirt := Assets.texture_set("dry_ground_01")
	if not grass.is_empty() and not dirt.is_empty():
		for pair in [["grass", grass], ["dirt", dirt]]:
			hill_mat.set_shader_parameter(pair[0] + "_albedo", pair[1].albedo)
			hill_mat.set_shader_parameter(pair[0] + "_normal", pair[1].normal)
			hill_mat.set_shader_parameter(pair[0] + "_orm", pair[1].orm)
	hill_mat.set_shader_parameter("macro_noise", Assets.noise_texture(9, 0.01, false, 256))
	var hill_mesh: Mesh = null
	for child in hills.find_children("*", "MeshInstance3D"):
		(child as MeshInstance3D).material_override = hill_mat
		Assets.add_mesh_collision(child as MeshInstance3D)
		hill_mesh = (child as MeshInstance3D).mesh
	var hill_tri := hill_mesh.generate_triangle_mesh() if hill_mesh else null
	var sea := MeshInstance3D.new()
	var sea_plane := PlaneMesh.new()
	sea_plane.size = Vector2(5000, 3000)
	sea_plane.subdivide_width = 40
	sea_plane.subdivide_depth = 40
	sea.mesh = sea_plane
	sea.position = Vector3(0, float(layout.sea_y), 1700)
	sea.material_override = Water.water_material(true)
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(sea)
	Water.build_pool(root, layout)
	_plant_villa(root, layout, hill_tri)
	root.set_meta("spawn", {"position": Vector3(0, 0.05, 37.0), "yaw": 0.0})
	return true

static func _fresco(frieze: bool) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = Assets.get_resource("res://shaders/fresco.gdshader")
	var plaster := Assets.texture_set("red_plaster_weathered")
	if not plaster.is_empty():
		mat.set_shader_parameter("plaster_albedo", plaster.albedo)
		mat.set_shader_parameter("plaster_normal", plaster.normal)
	mat.set_shader_parameter("frieze", frieze)
	mat.set_shader_parameter("period", 70.0 / 24.0)
	mat.set_shader_parameter("offset", -30.0 - 70.0 / 48.0)
	return mat

## The long reflecting pool runs its own shallow-water solver: still and mirror-like until something
## disturbs it. Two bronze lion-head fountains at its north end keep a gentle ripple running down
## its length, and anyone wading in leaves a wake.

static func _plant_villa(root: Node3D, layout: Dictionary, hill_tri: TriangleMesh) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1999
	var p: Array = layout.pool
	# Olive-like trees and shrub rows in the hedged beds.
	for bed in layout.beds:
		var cx := (float(bed[0]) + float(bed[1])) * 0.5
		var z0 := float(bed[2])
		var z1 := float(bed[3])
		for zt in [z0 + 6.5, z1 - 6.5]:
			Assets.place(root, "island_tree_01", Vector3(cx + rng.randf_range(-0.8, 0.8), 0.03, zt), rng.randf_range(0, 360), 0.0, rng.randf_range(0.8, 0.95))
		for k in 5:
			var zs := lerpf(z0 + 2.0, z1 - 2.0, (k + 0.5) / 5.0)
			if absf(zs - (z0 + z1) * 0.5) < 2.0:
				continue
			Assets.place(root, "searsia_lucida" if k % 2 else "shrub_01", Vector3(cx + rng.randf_range(-1.5, 1.5), 0.03, zs), rng.randf_range(0, 360), 0.0, rng.randf_range(0.45, 0.6))
	# Herms carrying marble busts along both sides of the pool.
	for side in [-1.0, 1.0]:
		for k in 5:
			var at := Vector3(side * (float(p[1]) + 1.25), 0.0, lerpf(float(p[2]) + 4.0, float(p[3]) - 4.0, k / 4.0))
			var herm := MeshInstance3D.new()
			var shaft := BoxMesh.new()
			shaft.size = Vector3(0.42, 1.25, 0.42)
			herm.mesh = shaft
			herm.position = at + Vector3(0, 0.625, 0)
			herm.material_override = Assets.pbr("marble_rock_02", 1.4, Color(1.1, 1.07, 1.02))
			root.add_child(herm)
			Assets.add_static_box(root, herm.position, shaft.size)
			Assets.place(root, "marble_bust_01", at + Vector3(0, 1.25, 0), 90.0 if side < 0 else 270.0, 0.62)
	# A marble horse on a pedestal at the open south end, framed against the sea.
	var court: Array = layout.court
	var plinth := MeshInstance3D.new()
	var pbox := BoxMesh.new()
	pbox.size = Vector3(1.4, 1.1, 0.9)
	plinth.mesh = pbox
	plinth.position = Vector3(0, float(layout.stylobate) + 0.55, float(court[3]) + 2.6)
	plinth.material_override = Assets.pbr("marble_rock_02", 1.4, Color(1.07, 1.03, 0.96))
	root.add_child(plinth)
	Assets.add_static_box(root, plinth.position, pbox.size)
	Assets.place(root, "horse_statue_01", plinth.position + Vector3(0, 0.55, 0), 90.0, 1.5)
	# Potted plants along the portico walls.
	for side in [-1.0, 1.0]:
		for z in [-24.0, -10.0, 4.0, 18.0, 32.0]:
			Assets.place(root, "potted_plant_01" if int(z) % 4 else "potted_plant_02", Vector3(side * 19.0, float(layout.stylobate), z), rng.randf_range(0, 360))
	# Jacarandas over the walls and trees scattered down the hills toward the sea.
	for spot in [Vector3(-31, 0, -8), Vector3(32, 0, 14), Vector3(-30, 0, 30), Vector3(29, 0, -26)]:
		Assets.place(root, "jacaranda_tree", Vector3(spot.x, Assets.ground_height(hill_tri, spot.x, spot.z) - 0.2, spot.z), rng.randf_range(0, 360), 0.0, rng.randf_range(0.5, 0.62))
	var placed := 0
	var tries := 0
	while placed < 64 and tries < 1500:
		tries += 1
		var x := rng.randf_range(-150.0, 150.0)
		var z := rng.randf_range(-170.0, 190.0)
		if absf(x) < 42.0 and z > -70.0 and z < 58.0:
			continue
		if hill_tri == null or not hill_tri.has_method("intersect_ray"):
			break
		var hit: Dictionary = hill_tri.call("intersect_ray", Vector3(x, 200, z), Vector3.DOWN)
		if hit.is_empty() or hit.normal.y < 0.82 or hit.position.y < float(layout.sea_y) + 4.0:
			continue
		var id: String = ["island_tree_02", "shrub_03", "island_tree_03", "searsia_lucida", "shrub_01", "tree_small_02"][placed % 6]
		var size := rng.randf_range(0.7, 1.1) if id.begins_with("shrub") else rng.randf_range(1.2, 2.0)
		Assets.place(root, id, hit.position - Vector3(0, 0.25, 0), rng.randf_range(0, 360), 0.0, size)
		placed += 1
