extends RefCounted
## Cove geometry, scanned props and surf integration.
const Assets = preload("res://scripts/assets/asset_library.gd")
const Water = preload("res://scripts/simulation/water_system.gd")
const Props = preload("res://scripts/zones/authored_props.gd")
const SEA_LEVEL := Water.SEA_LEVEL
const SCOPE := "beach"

static func has_shore() -> bool:
	return ResourceLoader.exists("res://assets/generated/shore_terrain.glb") and not Assets.texture_set("aerial_beach_01").is_empty()

static func build(context: RefCounted) -> bool:
	if not has_shore():
		return false
	var root: Node3D = context.build_root
	var terrain := (Assets.get_resource("res://assets/generated/shore_terrain.glb") as PackedScene).instantiate() as Node3D
	root.add_child(terrain)
	var ground_mesh: Mesh = null
	var mat := ShaderMaterial.new()
	mat.shader = Assets.get_resource("res://shaders/shore_terrain.gdshader")
	var dry := Assets.texture_set("aerial_beach_01")
	var wet := Assets.texture_set("damp_beach_sand")
	var rock := Assets.texture_set("coast_sand_rocks_02")
	for pair in [["dry", dry], ["wet", wet], ["rock", rock if not rock.is_empty() else wet]]:
		mat.set_shader_parameter(pair[0] + "_albedo", pair[1].albedo)
		mat.set_shader_parameter(pair[0] + "_normal", pair[1].normal)
		mat.set_shader_parameter(pair[0] + "_orm", pair[1].orm)
	mat.set_shader_parameter("macro_noise", Assets.noise_texture(3, 0.008, false, 256))
	mat.set_shader_parameter("sea_level", SEA_LEVEL)
	for child in terrain.find_children("*", "MeshInstance3D"):
		var mesh_node := child as MeshInstance3D
		mesh_node.material_override = mat
		Assets.add_mesh_collision(mesh_node)
		ground_mesh = mesh_node.mesh
	var ground := ground_mesh.generate_triangle_mesh() if ground_mesh else null
	var h := func(x: float, z: float) -> float: return Assets.ground_height(ground, x, z)

	# The sea: a dense patch near the beach for the swell, a coarse ring out to the horizon.
	var ocean_materials: Array[ShaderMaterial] = []
	for spec in [[Vector2(260, 200), Vector3(0, SEA_LEVEL, -70), 200], [Vector2(3000, 3000), Vector3(0, SEA_LEVEL, -1300), 24]]:
		var sea := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = spec[0]
		plane.subdivide_width = spec[2]
		plane.subdivide_depth = spec[2]
		sea.mesh = plane
		sea.position = spec[1]
		sea.material_override = Water.water_material(true)
		if spec[2] == 24:
			var horizon := sea.material_override as ShaderMaterial
			horizon.set_shader_parameter("has_lod_hole", true)
			horizon.set_shader_parameter("lod_hole", Vector4(-129.5,-169.5,129.5,29.5))
			horizon.set_shader_parameter("swell",0.0)
		sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ocean_materials.append(sea.material_override)
		root.add_child(sea)
	# Simulated surf: the shoreline solver takes over the cove's shallows.
	var surf := Water.build_surf(root, mat, ocean_materials)
	# The cove is open to walk and swim in; far-off invisible walls keep you in the world.
	for wall in [[Vector3(0, 10, -95), Vector3(160, 40, 2)], [Vector3(0, 10, 50), Vector3(160, 40, 2)],
			[Vector3(-75, 10, -20), Vector3(2, 40, 150)], [Vector3(75, 10, -20), Vector3(2, 40, 150)]]:
		Assets.add_static_box(root, wall[0], wall[1])
	# Flotsam riding the surf: it bobs on the simulated surface and drifts with the currents.
	var floaters: Array[RigidBody3D] = []
	for spec in [["inshore_barrel", "Inshore barrel", "wine_barrel_01", Vector3(-3.0, 0.0, -21.0), 0.9, 60.0],
			["crate", "Floating crate", "wooden_crate_01", Vector3(4.5, 0.0, -19.5), 0.6, 25.0],
			["offshore_barrel", "Offshore barrel", "wine_barrel_01", Vector3(1.5, 0.0, -26.0), 0.9, 60.0],
			["buoy", "Cove buoy", "ocean_buoy", Vector3(-9.0, 0.0, -34.0), 2.2, 180.0]]:
		var floater := Water.create_floater(root, spec[2], spec[3] + Vector3(0, SEA_LEVEL, 0), spec[4], spec[5])
		if floater:
			floaters.append(floater)
			Props.register(root, Props.stable_id(SCOPE, spec[0]), floater, spec[2], 0.0, {"label": spec[1]})
	root.set_meta("water", {"sea_level": SEA_LEVEL, "sims": [surf] if not surf.is_empty() else [], "floaters": floaters})

	# Windswept trees framing the beach, just outside the walkable area, and on the dunes.
	Props.place(root, SCOPE, "west_beach_tree", "island_tree_03", Vector3(-15.5, h.call(-15.5, 1.5) - 0.1, 1.5), 75.0, 0.0, 1.5)
	Props.place(root, SCOPE, "east_beach_tree", "island_tree_02", Vector3(17.5, h.call(17.5, 7.0) - 0.1, 7.0), 200.0, 0.0, 1.3)
	Props.place(root, SCOPE, "east_cove_tree", "island_tree_03", Vector3(24.0, h.call(24.0, -6.0) - 0.15, -6.0), 250.0, 0.0, 1.2)
	Props.place(root, SCOPE, "west_dune_tree", "island_tree_02", Vector3(-9.0, h.call(-9.0, 19.0) - 0.15, 19.0), 40.0, 0.0, 1.4)
	Props.place(root, SCOPE, "east_dune_tree", "island_tree_03", Vector3(6.5, h.call(6.5, 21.5) - 0.15, 21.5), 130.0, 0.0, 1.6)
	Props.place(root, SCOPE, "west_headland_tree", "island_tree_02", Vector3(-27.0, h.call(-27.0, 4.0) - 0.2, 4.0), 300.0, 0.0, 1.5)
	# Rocks at the waterline and on the headland toes.
	Props.place(root, SCOPE, "west_shore_rocks", "coast_rocks_05", Vector3(-8.5, h.call(-8.5, -16.5) - 0.35, -16.5), 30.0)
	Props.place(root, SCOPE, "east_shore_rocks", "coast_rocks_05", Vector3(12.5, h.call(12.5, -14.0) - 0.3, -14.0), 160.0, 0.0, 0.7)
	Props.place(root, SCOPE, "west_headland_rocks", "coast_land_rocks_03", Vector3(-21.0, h.call(-21.0, -13.0) - 0.4, -13.0), 110.0)
	Props.place(root, SCOPE, "east_headland_rocks", "coast_land_rocks_03", Vector3(22.0, h.call(22.0, -11.0) - 0.4, -11.0), 300.0, 0.0, 1.2)
	Props.place(root, SCOPE, "beach_pebbles", "sand_rocks_small_01", Vector3(-9.0, h.call(-9.0, -10.5) - 0.12, -10.5), 10.0)
	# A weathered pier running out into the cove.
	var pier := Assets.place(root, "modular_wooden_pier", Vector3(9.0, SEA_LEVEL - 2.6, -26.0), 180.0)
	if pier:
		pier.name = "Pier"
		for part in pier.find_children("*", "MeshInstance3D", true, false):
			Assets.add_mesh_collision(part as MeshInstance3D)
		Props.register(root, Props.stable_id(SCOPE, "pier"), pier, "modular_wooden_pier", 180.0,
			{"label": "Wooden pier", "placement_surface": true})
	# Scanned rock outcrops scattered over both headlands give the bluffs real crags.
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for side in [-1.0, 1.0]:
		for n in 14:
			var x: float = side * rng.randf_range(22.0, 44.0)
			var z := rng.randf_range(-40.0, 10.0)
			var id := "coast_land_rocks_03" if n % 3 else "coast_rocks_05"
			var key := "headland_%s_%d" % ["west" if side < 0 else "east", n]
			_place_on_ground(root, ground, key, id, x, z, rng.randf_range(0, 360), rng.randf_range(0.9, 1.6))
	# Shells and a lantern for the evening.
	var shells := [Vector3(-3.5, 0, -10.2), Vector3(4.2, 0, -11.0), Vector3(1.0, 0, -11.6)]
	for index in shells.size():
		var spot: Vector3 = shells[index]
		Props.place(root, SCOPE, "shell_%d" % index, "lambis_shell", Vector3(spot.x, h.call(spot.x, spot.z), spot.z), rng.randf_range(0, 360))
	var lantern := Assets.place(root, "wooden_lantern_01", Vector3(-1.4, h.call(-1.4, -3.4), -3.4), 20.0)
	if lantern:
		var flame := OmniLight3D.new()
		flame.position = Vector3(0, 0.25, 0)
		flame.light_color = Color("ffa24a")
		flame.light_energy = 1.2
		flame.omni_range = 3.5
		flame.shadow_enabled = true
		lantern.add_child(flame)
		Props.register(root, Props.stable_id(SCOPE, "lantern"), lantern, "wooden_lantern_01", 20.0, {"label": "Beach lantern"})
	return true

static func _place_on_ground(root: Node3D, tri: TriangleMesh, key: String, id: String, x: float, z: float, yaw_deg: float, scale: float) -> void:
	if tri == null or not tri.has_method("intersect_ray"):
		return
	var hit: Dictionary = tri.call("intersect_ray", Vector3(x, 80, z), Vector3.DOWN)
	if hit.is_empty() or hit.normal.y < 0.8:
		return
	var rock := Assets.place(root, id, hit.position, 0.0, 0.0, scale)
	if rock == null:
		return
	var height := Assets.bounds(rock).size.y * scale
	var tilt := Quaternion(Vector3.UP, (hit.normal as Vector3).normalized())
	rock.basis = Basis(tilt) * Basis(Vector3.UP, deg_to_rad(yaw_deg)).scaled(Vector3.ONE * scale)
	rock.position = hit.position - hit.normal * height * 0.4
	Props.register(root, Props.stable_id(SCOPE, key), rock, id, yaw_deg)
