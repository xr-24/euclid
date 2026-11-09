extends RefCounted

## Two crossed ribbons keep each fibre visible when viewed from the side.
static func build(body: ArrayMesh) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_custom_format(0, SurfaceTool.CUSTOM_RGB_FLOAT)
	surface.set_custom_format(1, SurfaceTool.CUSTOM_RGB_FLOAT)
	var arrays := body.surface_get_arrays(0)
	var body_points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var poses := body.surface_get_blend_shape_arrays(0)
	var normalized := body.blend_shape_mode == Mesh.BLEND_SHAPE_MODE_NORMALIZED
	var crown := Vector3(-0.02, 0.93, 0.028)
	var crown_index := 0
	var nearest := INF
	for index in body_points.size():
		var distance := body_points[index].distance_squared_to(crown)
		if distance < nearest:
			nearest = distance
			crown_index = index
	_set_attachment(surface, arrays, poses, crown_index, normalized)
	var rng := RandomNumberGenerator.new()
	rng.seed = 61837
	for i in 132:
		var angle := TAU * i / 132.0 + rng.randf_range(-0.05, 0.05)
		var radial := Vector3(cos(angle), 0.0, sin(angle))
		var tangent := Vector3(-radial.z, 0.0, radial.x)
		var fringe := smoothstep(0.28, 0.96, radial.z)
		var spread := rng.randf_range(0.91, 1.21)
		var length := rng.randf_range(0.34, 0.49) - fringe * rng.randf_range(0.08, 0.19)
		var root := Vector3(rng.randf_range(-0.048, 0.006), rng.randf_range(0.958, 0.984), 0.028)
		var sweep := rng.randf_range(0.011, 0.047) * (1.0 - 0.42 * fringe)
		var wave := rng.randf_range(0.006, 0.022)
		var phase := rng.randf() * TAU
		var path := PackedVector3Array()
		for point in 13:
			var t := point / 12.0
			var curl := sin(t * 8.6 + phase) * wave * t * t
			var shell := sin(minf(t * 2.1, 1.0) * PI * 0.5) * (0.103 + fringe * 0.016) * spread * (1.0 - t * 0.08)
			var at := root + radial * (shell + curl) + tangent * (sweep * t + sin(t * 6.1 + phase) * wave * t)
			at.z = root.z + (at.z - root.z) * 1.14
			at.x += fringe * pow(t, 1.4) * 0.043
			at.y -= length * t
			path.append(at)
		var radius := rng.randf_range(0.0008, 0.0023)
		var brightness := rng.randf_range(0.28, 0.85)
		if i % 13 == 0:
			radius *= 1.44
			brightness = 0.96
		_strand(surface, path, radius, Color(1.0, rng.randf(), brightness))
	# Corruption trails originate at actual body samples, including the limbs.
	for i in 128:
		var index := rng.randi_range(0, body_points.size() - 1)
		var at := body_points[index]
		_set_attachment(surface, arrays, poses, index, normalized)
		var span := rng.randf_range(0.05, 0.37)
		_strand(surface, PackedVector3Array([at, at + Vector3.UP * span]),
			rng.randf_range(0.0007, 0.0018), Color(0.0, rng.randf(), rng.randf_range(0.22, 0.7)))
	_set_attachment(surface, arrays, poses, crown_index, normalized)
	for i in 25:
		var x := rng.randf_range(-0.165, 0.165)
		var z := rng.randf_range(-0.115, 0.115)
		var top := rng.randf_range(1.13, 1.58)
		var bottom := rng.randf_range(0.49, 0.94)
		_strand(surface, PackedVector3Array([Vector3(x, bottom, z), Vector3(x, top, z)]),
			rng.randf_range(0.00075, 0.0017), Color(0.0, rng.randf_range(0.0, 0.49), rng.randf_range(0.55, 0.94)))
	surface.index()
	return surface.commit()

static func _set_attachment(surface: SurfaceTool, arrays: Array, poses: Array, index: int, normalized: bool) -> void:
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	surface.set_bones(bones.slice(index * 4, index * 4 + 4))
	surface.set_weights(weights.slice(index * 4, index * 4 + 4))
	for channel in poses.size():
		var offset: Vector3 = poses[channel][Mesh.ARRAY_VERTEX][index]
		if normalized:
			offset -= arrays[Mesh.ARRAY_VERTEX][index]
		surface.set_custom(channel, Color(offset.x, offset.y, offset.z))

static func _strand(surface: SurfaceTool, points: PackedVector3Array, radius: float, kind: Color) -> void:
	const AXES := [Vector3.RIGHT, Vector3.BACK]
	var steps := points.size() - 1
	for i in steps:
		var a := points[i]
		var b := points[i + 1]
		var start := float(i) / steps
		var end := float(i + 1) / steps
		var width_a := radius * lerpf(1.0, 0.14, start * start)
		var width_b := radius * lerpf(1.0, 0.14, end * end)
		for axis in AXES:
			var left_a: Vector3 = a - axis * width_a
			var right_a: Vector3 = a + axis * width_a
			var left_b: Vector3 = b - axis * width_b
			var right_b: Vector3 = b + axis * width_b
			_vertex(surface, left_a, Vector2(0, start), kind)
			_vertex(surface, right_a, Vector2(1, start), kind)
			_vertex(surface, right_b, Vector2(1, end), kind)
			_vertex(surface, left_a, Vector2(0, start), kind)
			_vertex(surface, right_b, Vector2(1, end), kind)
			_vertex(surface, left_b, Vector2(0, end), kind)

static func _vertex(surface: SurfaceTool, point: Vector3, uv: Vector2, kind: Color) -> void:
	surface.set_uv(uv)
	surface.set_color(kind)
	surface.add_vertex(point)
