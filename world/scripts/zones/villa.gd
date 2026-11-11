extends RefCounted
## Villa Aurelia: a Getty-style Roman villa on a bluff above a Laguna Beach cove.
##
## Builds the zone from generated data: the architecture and hedges (villa_estate.glb, from
## scripts/blender/build_villa.py), the coast (villa_coast*.glb and its height field, from
## build_coast.py) and villa_layout.json, which says where beds, pools, fountains and lights go.
## What stands where is data too: statues and furniture in world/data/dressing/villa.json, the wild
## planting and rocks of the coast in world/data/vegetation/villa_coast.json. This file wires those
## together and plants the formal gardens, whose layout follows the architecture.

const Water = preload("res://scripts/simulation/water_system.gd")
const WorldArt = preload("res://scripts/world_art.gd")
const SceneDressing = preload("res://scripts/scene_dressing.gd")
const Props = preload("res://scripts/zones/authored_props.gd")
const Scatter = preload("res://scripts/scatter.gd")
const TerrainField = preload("res://scripts/terrain_field.gd")
const RenderLayers = preload("res://scripts/rendering/render_layers.gd")

const GEN := "res://assets/generated/"

static func available() -> bool:
	return ResourceLoader.exists(GEN + "villa_estate.glb") and FileAccess.file_exists(GEN + "villa_layout.json")

static func build(context: RefCounted) -> bool:
	if not available():
		return false
	var root: Node3D = context.build_root
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GEN + "villa_layout.json"))
	_architecture(root)
	var field := TerrainField.new()
	var has_coast := field.load_from(GEN + "villa_coast_height.json")
	var sea_y := float(field.info.get("sea_y", -80.0)) if has_coast else -80.0
	if has_coast:
		_coast(root, field)
	if "ocean" in context.package.water:
		_sea(root, sea_y)
	var pool := Water.build_pool_surface(root, layout) if "pool" in context.package.water else {}
	var water := {"sims": [] if pool.is_empty() else [pool], "floaters": [], "sources": []}
	if "still" in context.package.water:
		_still_water(root, layout)
	if "spouts" in context.package.water:
		_spouts(root, layout, water)
	_lights(root, layout)
	_gardens(root, layout)
	SceneDressing.apply(root, context.package.layers.dressing, {"marble": WorldArt.pbr("marble_rock_02", 1.4, Color(1.1, 1.07, 1.02)), "bronze": bronze()})
	if has_coast:
		Scatter.apply(root, context.package.layers.vegetation, field, keep_clear(layout))
	water["sea_level"] = sea_y
	root.set_meta("water", water)
	return true


# ---------------------------------------------------------------- architecture

static func _architecture(root: Node3D) -> void:
	var estate := (WorldArt.res(GEN + "villa_estate.glb") as PackedScene).instantiate() as Node3D
	root.add_child(estate)
	var mats := {
		"limestone": WorldArt.pbr("marble_rock_02", 3.0, Color(1.07, 1.03, 0.96), Color("d8c8a8")),
		"marble_floor": WorldArt.pbr("marble_01", 3.0, Color(1.06, 1.04, 1.0), Color("ddd5c6")),
		"plaster": WorldArt.pbr("white_plaster_02", 3.0, Color(1.04, 0.97, 0.86), Color("e2d6c0")),
		"roof_tiles": WorldArt.pbr("clay_roof_tiles_02", 2.0, Color(1.0, 0.92, 0.86), Color("8a3b22")),
		"timber": WorldArt.pbr("dark_wooden_planks", 2.5, Color(0.85, 0.72, 0.6), Color("3a2414")),
		"gravel": WorldArt.pbr("gravel_ground_01", 3.0, Color(1.08, 1.02, 0.92), Color("b8a888")),
		"soil": WorldArt.pbr("brown_mud_leaves_01", 1.5, Color.WHITE, Color("3a2a1a")),
		"lawn": WorldArt.pbr("leafy_grass", 2.5, Color(0.9, 1.0, 0.8), Color("4a6a2a")),
		"pool_basin": WorldArt.pbr("granite_tile", 1.2, Color(0.32, 0.38, 0.4), Color("1d2628")),
		"mosaic_floor": WorldArt.pbr("old_mosaic_floor", 2.2, Color(1.05, 1.0, 0.94), Color("b8a080")),
		"mosaic_wall": WorldArt.pbr("marble_mosaic_tiles", 1.0, Color(0.85, 0.95, 1.05), Color("6b8aa0")),
		"rubble": WorldArt.pbr("sandstone_blocks_08", 3.0, Color(1.05, 0.98, 0.88), Color("b09878")),
		"fresco": fresco(false),
		"fresco_frieze": fresco(true),
		"hedge_core": _hedge_core(),
		"hedge_leaves": _hedge_leaves(),
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
		# The leaf cards are the costliest thing in the villa: over a million alpha-tested
		# triangles. The opaque core inside them casts the clipped hedges' shadows and stands in
		# for them in reflections, so the cards are drawn once, in the main view only.
		if key == "hedge_leaves":
			mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mesh_node.layers = RenderLayers.REFLECTION_HIDDEN
		if key == "hedge_core":
			mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if mesh_node.name.begins_with("COL_"):
			mesh_node.create_trimesh_collision()
		if key == "invisible":  # stair ramps: walked on, never seen
			mesh_node.visible = false

## Pompeian red wall painting (see shaders/fresco.gdshader); the frieze variant runs above columns.
static func fresco(frieze: bool) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = WorldArt.res("res://shaders/fresco.gdshader")
	var plaster := WorldArt.texture_set("red_plaster_weathered")
	if not plaster.is_empty():
		mat.set_shader_parameter("plaster_albedo", plaster.albedo)
		mat.set_shader_parameter("plaster_normal", plaster.normal)
	mat.set_shader_parameter("frieze", frieze)
	mat.set_shader_parameter("period", 70.0 / 24.0)
	mat.set_shader_parameter("offset", -30.0 - 70.0 / 48.0)
	return mat

static func bronze() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.3, 0.17)
	mat.metallic = 0.85
	mat.roughness = 0.38
	return mat

## The inside of a hedge, glimpsed between the leaf cards: the leaf atlas again, opaque and darker,
## so gaps read as deeper foliage rather than a box.
static func _hedge_core() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.5, 0.42)
	if ResourceLoader.exists(GEN + "hedge_leaves.png"):
		mat.albedo_texture = WorldArt.res(GEN + "hedge_leaves.png")
		mat.uv1_triplanar = true
		mat.uv1_scale = Vector3(3.0, 3.0, 3.0)
	mat.roughness = 0.9
	return mat

static func _hedge_leaves() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	if ResourceLoader.exists(GEN + "hedge_leaves.png"):
		mat.albedo_texture = WorldArt.res(GEN + "hedge_leaves.png")
	mat.albedo_color = Color(1.0, 1.05, 0.95)
	if ResourceLoader.exists(GEN + "hedge_leaves_n.png"):
		mat.normal_enabled = true
		mat.normal_texture = WorldArt.res(GEN + "hedge_leaves_n.png")
		mat.normal_scale = 0.7
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.45
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.62
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return mat


# ---------------------------------------------------------------- coast and sea

static func _coast(root: Node3D, field: RefCounted) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = WorldArt.res("res://shaders/coast_terrain.gdshader")
	for pair in [["grass", "sparse_grass"], ["dirt", "rocky_terrain_02"], ["cliff", "cliff_side"], ["sand", "coast_sand_01"]]:
		var set := WorldArt.texture_set(pair[1])
		if set.is_empty():
			continue
		mat.set_shader_parameter(pair[0] + "_albedo", set.albedo)
		mat.set_shader_parameter(pair[0] + "_normal", set.normal)
		mat.set_shader_parameter(pair[0] + "_orm", set.orm)
	mat.set_shader_parameter("macro_noise", WorldArt.noise_texture(9, 0.01, false, 256))
	mat.set_shader_parameter("sea_level", float(field.info.get("sea_y", -80.0)))
	mat.set_shader_parameter("beach_top", float(field.info.get("beach_back_y", -78.4)) + 0.8)
	for file in ["villa_coast.glb", "villa_coast_far.glb"]:
		if not ResourceLoader.exists(GEN + file):
			continue
		var land := (WorldArt.res(GEN + file) as PackedScene).instantiate() as Node3D
		root.add_child(land)
		for child in land.find_children("*", "MeshInstance3D"):
			var mi := child as MeshInstance3D
			mi.material_override = mat
			if mi.name.begins_with("COL_"):
				mi.create_trimesh_collision()

static func _sea(root: Node3D, sea_y: float) -> void:
	var sea := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(6000, 4000)
	plane.subdivide_width = 60
	plane.subdivide_depth = 60
	sea.mesh = plane
	sea.position = Vector3(0, sea_y, 1900)
	sea.material_override = WorldArt.water_material(true)
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(sea)


# ---------------------------------------------------------------- water features

## Shallow still pools (atrium impluvium, inner peristyle, wall fountain) and round fountains.
static func _still_water(root: Node3D, layout: Dictionary) -> void:
	for pool in layout.get("pools", []):
		var r: Array = pool.rect
		_water_plane(root, Rect2(float(r[0]), float(r[2]), float(r[1]) - float(r[0]), float(r[3]) - float(r[2])), float(pool.y))
	for f in layout.get("fountains", []):
		var disc := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = float(f.radius)
		cyl.bottom_radius = float(f.radius)
		cyl.height = 0.02
		cyl.radial_segments = 48
		disc.mesh = cyl
		disc.position = Vector3(f.centre[0], float(f.y), f.centre[1])
		disc.material_override = WorldArt.water_material(false)
		disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(disc)
		var j: Array = f.jet
		root.add_child(_jet(Vector3(j[0], j[1], j[2]), Vector3.UP, 2.6, 0.9, 360))

static func _water_plane(root: Node3D, rect: Rect2, y: float) -> void:
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = rect.size
	plane.subdivide_width = int(rect.size.x * 2)
	plane.subdivide_depth = int(rect.size.y * 2)
	mi.mesh = plane
	mi.position = Vector3(rect.get_center().x, y, rect.get_center().y)
	mi.material_override = WorldArt.water_material(false)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)

## Bronze lion heads spouting into the water: free-standing on short pedestals at the reflecting
## pool, or set into a wall. Jets landing in a simulated pool keep it rippling.
static func _spouts(root: Node3D, layout: Dictionary, water: Dictionary) -> void:
	for s in layout.get("spouts", []):
		var at := Vector3(s.at[0], s.at[1], s.at[2])
		var yaw := float(s.get("yaw", 0.0))
		var facing := Vector3(sin(deg_to_rad(yaw)), 0, cos(deg_to_rad(yaw)))
		var head_at := at
		if s.get("pedestal", false):
			var ped := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(0.55, 0.62, 0.5)
			ped.mesh = box
			ped.position = at + Vector3(0, 0.31, 0)
			ped.material_override = WorldArt.pbr("marble_rock_02", 1.2, Color(1.07, 1.03, 0.96))
			root.add_child(ped)
			WorldArt.static_box(root, ped.position, box.size)
			head_at = at + Vector3(0, 0.62, 0)
		WorldArt.place(root, "lion_head", head_at, yaw + 180.0, 0.48)
		var mouth := head_at + Vector3(0, 0.16, 0) + facing * 0.2
		root.add_child(_jet(mouth, (facing + Vector3(0, 0.55, 0)).normalized(), 2.28, 0.42, 220))
		water.sources.append(mouth + facing * 0.62 + Vector3(0, float(s.get("water_y", 0.0)) - mouth.y, 0))

## A thin arcing jet of water.
static func _jet(at: Vector3, direction: Vector3, speed: float, lifetime: float, amount: int) -> GPUParticles3D:
	var jet := GPUParticles3D.new()
	jet.position = at
	jet.amount = amount
	jet.lifetime = lifetime
	jet.preprocess = 1.0
	jet.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = direction
	pm.spread = 2.5
	pm.initial_velocity_min = speed * 0.97
	pm.initial_velocity_max = speed * 1.03
	pm.gravity = Vector3(0, -9.8, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.0
	jet.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.035, 0.07)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.85, 0.95, 1.0, 0.55)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	quad.material = mat
	jet.draw_pass_1 = quad
	jet.visibility_aabb = AABB(Vector3(-2, -2, -2), Vector3(4, 5, 4))
	return jet

## Warm, shadowless lamps in the rooms of the house, standing in for daylight bounced in through
## the doors.
static func _lights(root: Node3D, layout: Dictionary) -> void:
	for l in layout.get("lights", []):
		var light := OmniLight3D.new()
		light.position = Vector3(l.position[0], l.position[1], l.position[2])
		light.light_color = Color(l.color[0], l.color[1], l.color[2])
		light.light_energy = float(l.energy)
		light.omni_range = float(l.range)
		light.omni_attenuation = 1.4
		light.shadow_enabled = false
		light.light_bake_mode = Light3D.BAKE_DYNAMIC
		root.add_child(light)


# ---------------------------------------------------------------- formal gardens

## Planting that follows the architecture: trees and shrubs in the hedged beds of each garden,
## herbs and fruit trees in rows on the terraces, potted plants along the porticoes.
static func _gardens(root: Node3D, layout: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1999
	var rows := {}  # herb rows, instanced in bulk: id -> [Transform3D]
	var beds: Array = layout.get("beds", [])
	for index in beds.size():
		var bed: Dictionary = beds[index]
		var key := "garden_bed_%d" % index
		var r: Array = bed.rect
		var x0 := float(r[0]); var x1 := float(r[1]); var z0 := float(r[2]); var z1 := float(r[3])
		var y := float(bed.y)
		var cx := (x0 + x1) * 0.5
		var cz := (z0 + z1) * 0.5
		match str(bed.zone):
			"outer":  # olives toward the ends, shrubs between, the middle left for statuary
				for end in 2:
					var zt := z0 + 6.5 if end == 0 else z1 - 6.5
					var olive := "old_olive_tree" if rng.randf() < 0.5 else "olive_tree_portugal"
					_tree(root, key + "_olive_%d" % end, olive, Vector3(cx + rng.randf_range(-0.8, 0.8), y, zt), rng, 0.85, 1.0, "island_tree_01")
				for k in 5:
					var zs := lerpf(z0 + 2.0, z1 - 2.0, (k + 0.5) / 5.0)
					if absf(zs - cz) < 2.0:
						continue
					_garden_prop(root, key + "_shrub_%d" % k, "searsia_lucida" if k % 2 else "shrub_01",
						Vector3(cx + rng.randf_range(-1.5, 1.5), y, zs), rng.randf_range(0, 360), rng.randf_range(0.45, 0.6))
			"inner":  # lemon trees on a lawn
				var slots := [z0 + 3.0, cz, z1 - 3.0]
				for slot in slots.size():
					_tree(root, key + "_lemon_%d" % slot, "lemon_tree", Vector3(cx, y, slots[slot]), rng, 0.9, 1.1, "tree_small_02")
			"east":  # a shade tree in each bed, flowers round it
				_tree(root, key + "_jacaranda", "jacaranda_tree", Vector3(cx, y, cz), rng, 0.38, 0.45, "island_tree_02")
				for k in 6:
					_garden_prop(root, key + "_flower_%d" % k, "flower_gazania",
						Vector3(rng.randf_range(x0 + 0.8, x1 - 0.8), y, rng.randf_range(z0 + 0.8, z1 - 0.8)),
						rng.randf_range(0, 360), rng.randf_range(0.8, 1.2))
			_:  # herb terraces: rows of low shrubs, fruit trees down the middle of the upper beds
				var herbs := ["shrub_04", "wild_rooibos_bush", "flower_gazania", "cheiridopsis_succulent"]
				var kind: String = herbs[(int(cx) + int(cz)) % herbs.size()]
				var row := z0 + 0.8
				while row < z1 - 0.6:
					var x := x0 + 0.7
					while x < x1 - 0.5:
						var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.7, 1.0))
						if not rows.has(kind):
							rows[kind] = []
						rows[kind].append(Transform3D(basis, Vector3(x + rng.randf_range(-0.15, 0.15), y, row)))
						x += 1.6
					row += 2.2
				if str(bed.zone) != "herb1":
					var fruit := "lemon_tree" if str(bed.zone) == "herb2" else "olive_tree_portugal"
					_tree(root, key + "_fruit_tree", fruit, Vector3(cx, y, cz), rng, 0.9, 1.05, "island_tree_01")
	for kind in rows:
		Scatter.instance_many(root, kind, rows[kind], 90.0, false)
	# Potted plants along the side porticoes, clear of the doors and statues.
	for side in [-1.0, 1.0]:
		var slots := [-24.0, -1.0, 18.0, 32.0]
		for slot in slots.size():
			var z: float = slots[slot]
			var key := "%s_portico_planter_%d" % ["west" if side < 0 else "east", slot]
			_garden_prop(root, key, "potted_plant_01" if int(z) % 4 else "potted_plant_02",
				Vector3(side * 19.0, float(layout.stylobate), z), rng.randf_range(0, 360))

static func _garden_prop(root: Node3D, key: String, asset: String, at: Vector3, yaw: float, scale := 1.0) -> void:
	var model := WorldArt.place(root, asset, at, yaw, 0.0, scale)
	if model:
		Props.register(root, Props.stable_id("villa", key), model, asset, yaw)

## A garden tree from the library, falling back to a Poly Haven one; with a trunk collider.
static func _tree(root: Node3D, key: String, asset: String, at: Vector3, rng: RandomNumberGenerator, s0: float, s1: float, fallback: String) -> void:
	var yaw := rng.randf_range(0, 360)
	var tree := WorldArt.place(root, asset, at, yaw, 0.0, rng.randf_range(s0, s1))
	if tree == null:
		asset = fallback
		yaw = rng.randf_range(0, 360)
		tree = WorldArt.place(root, asset, at, yaw, 0.0, rng.randf_range(0.8, 0.95))
	if tree:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.25
		cyl.height = 2.0
		shape.shape = cyl
		body.add_child(shape)
		body.position = Vector3.UP / tree.scale.y
		body.scale = Vector3.ONE / tree.scale.y
		tree.add_child(body)
		Props.register(root, Props.stable_id("villa", key), tree, asset, yaw)

## Areas the coast's wild planting must leave alone: the buildings, gardens and terraces.
static func keep_clear(layout: Dictionary) -> Array:
	var out := []
	var h: Array = layout.get("house", [-32, 32, -82, -34.5])
	out.append(Rect2(float(h[0]) - 1.0, float(h[2]) - 1.0, float(h[1]) - float(h[0]) + 2.0, float(h[3]) - float(h[2]) + 2.0))
	out.append(Rect2(-21.5, -35.0, 43.0, 83.5))  # outer peristyle and belvedere
	var eg: Array = layout.get("east_garden", [32, 55, -76, -40])
	out.append(Rect2(float(eg[0]) - 0.5, float(eg[2]) - 0.8, float(eg[1]) - float(eg[0]) + 1.6, float(eg[3]) - float(eg[2]) + 1.6))
	for t in layout.get("terraces", []):
		out.append(Rect2(float(t[0]) - 0.5, float(t[2]) - 0.5, float(t[1]) - float(t[0]) + 1.6, float(t[3]) - float(t[2]) + 1.0))
	if layout.has("theatre"):
		var th: Dictionary = layout.theatre
		var r := float(th.radii[1]) + 1.5
		out.append(Rect2(float(th.centre[0]) - r, float(th.centre[1]) - r, r + 4.0, 2.0 * r))
	out.append(Rect2(-36.0, -59.0, 4.0, 6.0))  # steps at the west door
	return out
