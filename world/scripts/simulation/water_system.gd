extends RefCounted
## Water construction and gameplay interaction. The GPU solver stays isolated in thirdparty/.
const Assets = preload("res://scripts/assets/asset_library.gd")
const Interactions = preload("res://scripts/simulation/water_interactions.gd")
const PoolReflection = preload("res://scripts/rendering/pool_reflection.gd")
const SEA_LEVEL := -0.55
const SIM_DIR := "res://thirdparty/shorewaves/"
const SIM_META := "res://assets/generated/shore_sim.json"

static func water_material(sea: bool) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = Assets.get_resource("res://shaders/ocean.gdshader")
	mat.set_shader_parameter("ripple_a", Assets.noise_texture(11, 0.012, true))
	mat.set_shader_parameter("ripple_b", Assets.noise_texture(23, 0.02, true))
	mat.set_shader_parameter("foam_noise", Assets.noise_texture(5, 0.02, false))
	if not sea: # a shallow, clear courtyard pool over dark stone
		mat.set_shader_parameter("swell", 0.0)
		mat.set_shader_parameter("ripple_scale", 1.6)
		mat.set_shader_parameter("ripple_strength", 0.25)
		mat.set_shader_parameter("clarity", 0.6)
		mat.set_shader_parameter("colour_depth", 0.6)
		mat.set_shader_parameter("shallow_color", Color("4f9c98"))
		mat.set_shader_parameter("deep_color", Color("123c44"))
		mat.set_shader_parameter("foam_amount", 0.0)
		mat.set_shader_parameter("refraction", 0.012)
	return mat


static func build_pool_surface(root: Node3D, layout: Dictionary) -> Dictionary:
	var p: Array = layout.pool
	var water_y := float(layout.water_y)
	var meta_path := "res://assets/generated/villa_pool.json"
	var body := {}
	if Assets.has_rd and FileAccess.file_exists(meta_path) and ResourceLoader.exists(SIM_DIR + "sim_controller.gd"):
		var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
		var n := int(meta.n)
		var dx := float(meta.dx)
		var origin := Vector2(meta.x0, meta.z0)
		var sim: Node = (Assets.get_resource(SIM_DIR + "sim_controller.gd") as GDScript).new()
		sim.kind = 4 # SimController.Kind.CUSTOM
		sim.custom_cfg = {"n": n, "dx": dx, "dt": 0.002, "sub": 16, "depth0": 0.5, "mode": 0.0, "closed_walls":true,
			"kappa": 0.012, "amp": 0.0, "period": 5.0, "solo_h": 0.05, "solo_x0": 1.0}
		sim.custom_initial = {
			"bottom": FileAccess.get_file_as_bytes("res://assets/generated/villa_pool_bottom.bin"),
			"state": FileAccess.get_file_as_bytes("res://assets/generated/villa_pool_state.bin"),
		}
		sim.name = "PoolSim"
		sim.verbose = OS.has_environment("CONSTRUCT_SIM_VERBOSE")
		root.add_child(sim)
		var water := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(float(p[1]) - float(p[0]) - 0.08, float(p[3]) - float(p[2]) - 0.08)
		plane.subdivide_width = 48
		plane.subdivide_depth = 560
		water.mesh = plane
		water.position = Vector3((float(p[0]) + float(p[1])) * 0.5, 0.0, (float(p[2]) + float(p[3])) * 0.5)
		water.custom_aabb = AABB(Vector3(-4, -2, -30), Vector3(8, 4, 60))
		water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var wmat := ShaderMaterial.new()
		wmat.shader = Assets.get_resource("res://shaders/shore_water.gdshader")
		wmat.set_shader_parameter("tx_state", sim.tex_state)
		wmat.set_shader_parameter("tx_bottom", sim.tex_bottom)
		wmat.set_shader_parameter("tx_derived", sim.tex_derived)
		wmat.set_shader_parameter("lace_tex", Assets.get_resource(SIM_DIR + "textures/voronoi_lace.png"))
		wmat.set_shader_parameter("flow_noise_tex", Assets.get_resource(SIM_DIR + "textures/flow_noise.png"))
		wmat.set_shader_parameter("DOMAIN_SIZE", n * dx)
		wmat.set_shader_parameter("GRID_RES", float(n))
		wmat.set_shader_parameter("sim_origin", origin)
		wmat.set_shader_parameter("sea_level", water_y)
		wmat.set_shader_parameter("absorption", Vector3(0.5, 0.16, 0.14))
		wmat.set_shader_parameter("scatter_color", Vector3(0.02, 0.09, 0.1))
		wmat.set_shader_parameter("detail_normal_strength", 0.025)
		wmat.set_shader_parameter("detail_normal_a", Assets.noise_texture(73,0.025,true,256))
		wmat.set_shader_parameter("detail_normal_b", Assets.noise_texture(97,0.037,true,256))
		wmat.set_shader_parameter("confined", true)
		wmat.set_shader_parameter("refraction_strength", 0.012)
		wmat.set_shader_parameter("foam_strength", 0.0)
		wmat.set_shader_parameter("base_roughness", 0.055)
		water.material_override = wmat
		root.add_child(water)
		var reflection := PoolReflection.new()
		reflection.name = "PoolReflection"
		reflection.configure(wmat,water,water_y)
		root.add_child(reflection)
		body = {"sim": sim, "origin": origin, "dx": dx, "n": n, "sea_level": water_y, "profile":"pool", "player_wet":false}
	else:
		var still := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(float(p[1]) - float(p[0]), float(p[3]) - float(p[2]))
		still.mesh = plane
		still.position = Vector3(0, water_y, (float(p[2]) + float(p[3])) * 0.5)
		still.material_override = water_material(false)
		root.add_child(still)
	return body


static func build_pool(root: Node3D, layout: Dictionary) -> Dictionary:
	var body := build_pool_surface(root, layout)
	var p: Array = layout.pool
	var water_y := float(layout.water_y)
	# The earlier villa builder supplies its own fixed fountain layout here.
	var sources := []
	for x in [-1.1, 1.1]:
		var base := Vector3(x, 0.06, float(p[2]) - 0.32)
		var ped := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.55, 0.62, 0.5)
		ped.mesh = box
		ped.position = base + Vector3(0, 0.31, 0)
		ped.material_override = Assets.pbr("marble_rock_02", 1.2, Color(1.07, 1.03, 0.96))
		root.add_child(ped)
		Assets.place(root, "lion_head", base + Vector3(0, 0.62, 0), 180.0, 0.48)
		var mouth := base + Vector3(0, 0.78, 0.2)
		root.add_child(_spout(mouth))
		var landing := mouth + Vector3(0, water_y - mouth.y, 0.62)
		sources.append(landing)
	var water_meta := {"sims": [body] if not body.is_empty() else [], "floaters": [], "sources": sources}
	root.set_meta("water", water_meta)
	return body

## A thin arcing jet of water from a fountain mouth.

static func _spout(at: Vector3) -> GPUParticles3D:
	var jet := GPUParticles3D.new()
	jet.position = at
	jet.amount = 220
	jet.lifetime = 0.42
	jet.preprocess = 1.0
	jet.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0.55, 1)
	pm.spread = 2.5
	pm.initial_velocity_min = 2.2
	pm.initial_velocity_max = 2.35
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
	jet.visibility_aabb = AABB(Vector3(-1, -2, -1), Vector3(2, 3, 3))
	return jet

static func build_surf(root: Node3D, terrain_mat: ShaderMaterial, ocean_materials: Array[ShaderMaterial]) -> Dictionary:
	if not Assets.has_rd or not FileAccess.file_exists(SIM_META) \
			or not ResourceLoader.exists(SIM_DIR + "sim_controller.gd"):
		return {}
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SIM_META))
	var n := int(meta.n)
	var dx := float(meta.dx)
	var size := n * dx
	var origin := Vector2(meta.x0, meta.z0)
	var sim: Node = (Assets.get_resource(SIM_DIR + "sim_controller.gd") as GDScript).new()
	sim.kind = 4 # SimController.Kind.CUSTOM
	sim.custom_cfg = {"n": n, "dx": dx, "dt": 0.0032, "sub": 12, "depth0": meta.depth0, "mode": 2.0,
		"kappa": 0.012, "amp": 0.14, "period": 6.0, "solo_h": 0.5, "solo_x0": 4.0}
	sim.custom_initial = {
		"bottom": FileAccess.get_file_as_bytes("res://assets/generated/shore_sim_bottom.bin"),
		"state": FileAccess.get_file_as_bytes("res://assets/generated/shore_sim_state.bin"),
	}
	sim.wave_amp = 0.14     # one dominant incoming swell, shared with the ocean surface
	sim.wave_period = 6.0   # seconds
	sim.name = "ShoreSim"
	sim.verbose = OS.has_environment("CONSTRUCT_SIM_VERBOSE")
	root.add_child(sim)

	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	plane.subdivide_width = n - 2 # one vertex per solver cell
	plane.subdivide_depth = n - 2
	water.mesh = plane
	water.position = Vector3(origin.x + size * 0.5, 0.0, origin.y + size * 0.5)
	water.custom_aabb = AABB(Vector3(-size, -10.0, -size), Vector3(size * 2.0, 20.0, size * 2.0))
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var wmat := ShaderMaterial.new()
	wmat.shader = Assets.get_resource("res://shaders/shore_water.gdshader")
	wmat.set_shader_parameter("tx_state", sim.tex_state)
	wmat.set_shader_parameter("tx_bottom", sim.tex_bottom)
	wmat.set_shader_parameter("tx_derived", sim.tex_derived)
	wmat.set_shader_parameter("lace_tex", Assets.get_resource(SIM_DIR + "textures/voronoi_lace.png"))
	wmat.set_shader_parameter("flow_noise_tex", Assets.get_resource(SIM_DIR + "textures/flow_noise.png"))
	wmat.set_shader_parameter("DOMAIN_SIZE", size)
	wmat.set_shader_parameter("GRID_RES", float(n))
	wmat.set_shader_parameter("sim_origin", origin)
	wmat.set_shader_parameter("sea_level", SEA_LEVEL)
	wmat.set_shader_parameter("detail_normal_strength", 0.08)
	wmat.set_shader_parameter("detail_normal_a", Assets.noise_texture(73,0.025,true,256))
	wmat.set_shader_parameter("detail_normal_b", Assets.noise_texture(97,0.037,true,256))
	wmat.set_shader_parameter("wave_amp",sim.wave_amp)
	wmat.set_shader_parameter("wave_period",sim.wave_period)
	wmat.set_shader_parameter("wave_depth",float(meta.depth0))
	wmat.set_shader_parameter("shore_edge_smoothing",true)
	wmat.set_shader_parameter("column_optics",true)
	# Screen-space offsets pull sky/foreground into deep water at grazing angles.
	# Keep the existing depth-based transparency/absorption without that unstable warp.
	wmat.set_shader_parameter("refraction_strength",0.0)
	water.material_override = wmat
	root.add_child(water)

	terrain_mat.set_shader_parameter("sim_enabled", true)
	terrain_mat.set_shader_parameter("sim_origin", origin)
	terrain_mat.set_shader_parameter("sim_size", size)
	terrain_mat.set_shader_parameter("tx_ground", sim.tex_ground)
	terrain_mat.set_shader_parameter("tx_state", sim.tex_state)
	terrain_mat.set_shader_parameter("tx_derived", sim.tex_derived)
	terrain_mat.set_shader_parameter("shore_contact_foam",true)
	terrain_mat.set_shader_parameter("lace_tex", Assets.get_resource(SIM_DIR + "textures/voronoi_lace.png"))
	terrain_mat.set_shader_parameter("caustics_tex", Assets.get_resource(SIM_DIR + "textures/caustics.png"))
	for ocean in ocean_materials:
		var horizon: bool = ocean.get_shader_parameter("has_lod_hole") == true
		if not horizon:
			# Match the detailed patch's edge sampling. A coarse plane crossing the cut
			# interpolates a different height and leaves a visible rectangular crack.
			for mesh in root.find_children("*","MeshInstance3D",true,false):
				if mesh.material_override == ocean:
					mesh.mesh = _ocean_ring(origin,size,n)
					mesh.position = Vector3.ZERO
		# A single shader and wave clock across all three meshes: same colour, height and normals.
		ocean.shader = wmat.shader
		for uniform in ["tx_state","tx_bottom","tx_derived","lace_tex","flow_noise_tex",
				"DOMAIN_SIZE","GRID_RES","sim_origin","sea_level","detail_normal_strength",
				"detail_normal_a","detail_normal_b","wave_amp","wave_period","wave_depth","shore_edge_smoothing","refraction_strength","column_optics"]:
			ocean.set_shader_parameter(uniform,wmat.get_shader_parameter(uniform))
		ocean.set_shader_parameter("surface_role",2 if horizon else 1)
	var surfaces: Array[ShaderMaterial] = [wmat]
	surfaces.append_array(ocean_materials)
	return {"sim": sim, "origin": origin, "dx": dx, "n": n, "sea_level": SEA_LEVEL,
		"profile":"shore", "player_wet":false, "surfaces":surfaces}

static func _ocean_ring(origin: Vector2, size: float, n: int) -> ArrayMesh:
	var inner := [origin+Vector2(0.5,0.5),origin+Vector2(size-0.5,0.5),
		origin+Vector2(size-0.5,size-0.5),origin+Vector2(0.5,size-0.5)]
	var outer := [Vector2(-130,-170),Vector2(130,-170),Vector2(130,30),Vector2(-130,30)]
	var rings := [0.0,0.03,0.08,0.18,0.4,1.0]
	var count := 4*(n-1)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for blend in rings:
		for edge in 4:
			for i in n-1:
				var fraction := float(i)/float(n-1)
				var a: Vector2 = inner[edge].lerp(inner[(edge+1)%4],fraction)
				var b: Vector2 = outer[edge].lerp(outer[(edge+1)%4],fraction)
				var point := a.lerp(b,blend)
				vertices.append(Vector3(point.x,0,point.y))
				normals.append(Vector3.UP)
	for ring in rings.size()-1:
		for i in count:
			var a := ring*count+i
			var b := ring*count+(i+1)%count
			indices.append_array(PackedInt32Array([a,a+count,b,b,a+count,b+count]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

static func create_floater(root: Node3D, id: String, at: Vector3, height: float, mass: float) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.mass = mass
	body.position = at
	body.linear_damp = 0.05
	body.angular_damp = 0.6
	body.continuous_cd = true
	root.add_child(body)
	var model := Assets.place(body, id, Vector3.ZERO, 0.0, height)
	if model == null:
		body.free()
		return null
	var box := Assets.bounds(model)
	var size := box.size * model.scale
	model.position = -Vector3(0, size.y * 0.5, 0)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size * 0.9
	shape.shape = box_shape
	body.add_child(shape)
	body.set_meta("float_height", size.y)
	return body

static func _sim_cell(body: Dictionary, p: Vector3) -> Vector2:
	# Solver axes: x = cross-shore (world z), y = alongshore (world x).
	return Vector2((p.z - body.origin.y) / body.dx, (p.x - body.origin.x) / body.dx)

## Called every physics frame: reads the zone's water (simulated where possible) at the player and
## at floating props, applies buoyancy and drag to the props, and pushes the player's wake and
## splashes back into the simulation. Returns the water surface height at the player.

static func tick(root: Node3D, player: CharacterBody3D, delta: float) -> Dictionary:
	if root == null or not root.has_meta("water"):
		return {"has": false, "level": -INF}
	var w: Dictionary = root.get_meta("water")
	w["time"] = float(w.get("time",0.0))+delta
	var result := {"has": w.has("sea_level"), "level": w.get("sea_level", -INF)}
	var floaters: Array = w.get("floaters", [])
	var points: Array[Vector3] = [player.global_position]
	for f in floaters:
		points.append((f as Node3D).global_position)
	var levels := []
	var flows := []
	for p in points:
		levels.append(w.get("sea_level", -INF))
		flows.append(Vector3.ZERO)
	for body in w.get("sims", []):
		var sim: Node = body.sim
		if not is_instance_valid(sim):
			continue
		for surface in body.get("surfaces",[]):
			surface.set_shader_parameter("wave_time",sim.sim_time)
		var cells := PackedVector2Array()
		for p in points:
			cells.append(_sim_cell(body, p))
		sim.probe_cells = cells
		var vals: PackedFloat32Array = sim.probe_values
		for k in points.size():
			var c := cells[k]
			if c.x < 0.0 or c.y < 0.0 or c.x >= body.n or c.y >= body.n or vals.size() < (k + 1) * 4:
				continue
			var h := vals[k * 4] - vals[k * 4 + 1]
			levels[k] = body.sea_level + vals[k * 4] if h > 0.004 else -INF
			flows[k] = Vector3(vals[k * 4 + 3], 0.0, vals[k * 4 + 2]) / maxf(h, 0.05)
		# The player stirs the water: a wake along the walking direction, a splash on entry.
		var c0 := cells[0]
		var in_water: bool = levels[0] > player.global_position.y + 0.02
		if in_water and c0.x >= 0.0 and c0.y >= 0.0 and c0.x < body.n and c0.y < body.n:
			var v := player.velocity
			var profile: String = body.get("profile","shore")
			var radius: float = Interactions.PROFILES[profile].wake_radius / body.dx
			if Vector2(v.x, v.z).length() > 0.2:
				var impulse := Interactions.wake(v,delta,profile)
				sim.poke(c0.x, c0.y, radius, Interactions.wake_height(v,delta,profile), impulse.x, impulse.y)
			if not body.get("player_wet", false) and v.y < -2.0:
				sim.poke(c0.x, c0.y, radius * 1.5, Interactions.splash(v.y,profile), 0.0, 0.0)
		body["player_wet"] = in_water
		# Fountain jets landing in the water keep a gentle ripple running across it.
		for src in w.get("sources", []):
			var cs := _sim_cell(body, src)
			if cs.x >= 0.0 and cs.y >= 0.0 and cs.x < body.n and cs.y < body.n:
				var impulse := Interactions.fountain(w.time,delta,src.x*3.0)
				sim.poke(cs.x, cs.y, 0.18 / body.dx, impulse.x, impulse.y, 0.0)
	result = {"has": levels[0] > -INF, "level": levels[0]}
	for k in floaters.size():
		_float(floaters[k], levels[k + 1], flows[k + 1])
	return result

static func _float(body: RigidBody3D, level: float, flow: Vector3) -> void:
	if level == -INF:
		return
	var height: float = body.get_meta("float_height", 1.0)
	var submerged := clampf((level - (body.global_position.y - height * 0.5)) / height, 0.0, 1.0)
	if submerged <= 0.0:
		return
	# Floats about half submerged; water drags it toward the local current and damps bobbing.
	body.apply_central_force(Vector3.UP * body.mass * 9.8 * 2.0 * submerged)
	var drag := (flow - body.linear_velocity) * Vector3(1.0, 0.6, 1.0)
	body.apply_central_force(drag * body.mass * 1.8 * submerged)
	body.apply_torque(-body.angular_velocity * body.mass * 0.4 * submerged)
