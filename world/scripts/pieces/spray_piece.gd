extends RefCounted
## An aimable jet for fountains and waterfalls. The direction is local to the piece.

static func build(record: Dictionary) -> Node3D:
	var direction: Array = record.get("spray_direction", [0, 1, 0])
	var node := GPUParticles3D.new()
	node.amount = int(record.get("amount", 220))
	node.lifetime = float(record.get("lifetime", 0.42))
	node.preprocess = minf(1.0, node.lifetime)
	node.local_coords = true
	var pm := ParticleProcessMaterial.new()
	var aim := Vector3(direction[0], direction[1], direction[2])
	pm.direction = aim.normalized() if not aim.is_zero_approx() else Vector3.UP
	pm.spread = float(record.get("spread", 2.5))
	var speed := float(record.get("speed", 2.28))
	pm.initial_velocity_min = speed * 0.97
	pm.initial_velocity_max = speed * 1.03
	pm.gravity = Vector3.DOWN * 9.8
	pm.scale_min = 0.6
	pm.scale_max = 1.0
	node.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.035, 0.07)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.85, 0.95, 1.0, 0.55)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	quad.material = mat
	node.draw_pass_1 = quad
	var reach := minf(250.0, maxf(2.0, speed * node.lifetime + 5.0 * node.lifetime ** 2))
	node.visibility_aabb = AABB(Vector3.ONE * -reach, Vector3.ONE * reach * 2.0)
	if record.has("landing"):
		var spot: Array = record.landing
		node.set_meta("water_source", Vector3(spot[0], spot[1], spot[2]))
	return node
