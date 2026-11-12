extends RefCounted

## The projection's hair and signal trails, as one skinned mesh of ribbons. Each ribbon is a
## centreline with a half-width in UV2.x and its direction in NORMAL; the filament shader turns it
## to face the camera, so a strand never thins to an edge or crosses into an X.
##
## Hair grows from roots spread over the scalp (an ellipsoid fitted to the head of the body's
## points: the face looks toward +Z), is combed down over the skull under gravity from a centre
## part, and gathers into locks toward the tips. The front hairline gets a short fringe.
const HEAD_CENTER := Vector3(0.0, 0.815, 0.078)
const HEAD_RADII := Vector3(0.094, 0.127, 0.107)
const LOCKS := 34
const STRANDS_PER_LOCK := 5
const STEPS := 14

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
	for lock in LOCKS:
		var root := _scalp_direction(lock, rng)
		var guide := _comb(root, rng.randf_range(0.04, 0.08), _hair_length(root, rng), rng.randf() * TAU, rng)
		for strand in STRANDS_PER_LOCK:
			# Neighbouring roots a centimetre or so apart, drawn back into the lock toward the tips.
			var nudge := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * 0.16
			var start := (root + nudge).normalized()
			if not _on_scalp(start):
				start = root
			var own := _comb(start, rng.randf_range(0.02, 0.1),
				_hair_length(root, rng) * rng.randf_range(0.9, 1.04), rng.randf() * TAU, rng)
			var path := PackedVector3Array()
			for point in own.size():
				var t := float(point) / (own.size() - 1)
				path.append(own[point].lerp(guide[point] + (own[0] - guide[0]) * (1.0 - t), 0.55 * t * t))
			var radius := rng.randf_range(0.0008, 0.0021)
			var brightness := rng.randf_range(0.28, 0.85)
			if (lock * STRANDS_PER_LOCK + strand) % 13 == 0:
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
	var steps := points.size() - 1
	for i in steps:
		var a := points[i]
		var b := points[i + 1]
		var along := (b - a).normalized()
		var start := float(i) / steps
		var end := float(i + 1) / steps
		var width_a := radius * lerpf(1.0, 0.14, start * start)
		var width_b := radius * lerpf(1.0, 0.14, end * end)
		_vertex(surface, a, along, Vector2(0, start), width_a, kind)
		_vertex(surface, a, along, Vector2(1, start), width_a, kind)
		_vertex(surface, b, along, Vector2(1, end), width_b, kind)
		_vertex(surface, a, along, Vector2(0, start), width_a, kind)
		_vertex(surface, b, along, Vector2(1, end), width_b, kind)
		_vertex(surface, b, along, Vector2(0, end), width_b, kind)

## A root direction on the scalp, from a Fibonacci spiral over the head, skipping the face, the
## ears and the neck.
static func _scalp_direction(index: int, rng: RandomNumberGenerator) -> Vector3:
	var count := LOCKS * 3
	var k := index * 3 + rng.randi_range(0, 2)
	for attempt in 400:
		var y := 1.0 - (float(k % count) + 0.5) / count * 1.6
		var ring := sqrt(maxf(0.0, 1.0 - y * y))
		var angle := k * 2.39996323
		var direction := Vector3(cos(angle) * ring, y, sin(angle) * ring)
		if _on_scalp(direction):
			return direction
		k += 7
	return Vector3.UP

static func _on_scalp(direction: Vector3) -> bool:
	if direction.z > 0.3 and direction.y < 0.5: # forehead and face
		return false
	if absf(direction.x) > 0.75 and direction.y < 0.15 and direction.z > -0.25: # ears
		return false
	return direction.y > -0.35 or direction.z < -0.45 # down to the nape at the back

static func _hair_length(root: Vector3, rng: RandomNumberGenerator) -> float:
	if root.z > 0.35: # the fringe stops above the brows
		return rng.randf_range(0.04, 0.06)
	return rng.randf_range(0.26, 0.34) * lerpf(1.0, 0.85, clampf(root.z, 0.0, 1.0))

## Combs one strand from a root direction: along the scalp away from the centre part, bending
## down under gravity, kept just outside the skull by lift (a share of the head's size, which gives
## the hair its volume), then falling free below the head with a slight outward flare and wave.
static func _comb(root: Vector3, lift: float, length: float, phase: float, rng: RandomNumberGenerator) -> PackedVector3Array:
	var shell := HEAD_RADII * (1.0 + lift)
	var at := HEAD_CENTER + root * HEAD_RADII * 1.01
	var side := signf(root.x) if absf(root.x) > 0.02 else (1.0 if rng.randf() < 0.5 else -1.0)
	var heading := Vector3(side * 0.9, -0.4, -0.35 if root.z < 0.35 else 0.5)
	var path := PackedVector3Array([at])
	var step := length / STEPS
	var wave := rng.randf_range(0.002, 0.006)
	for point in STEPS:
		var t := float(point + 1) / STEPS
		heading = (heading + Vector3.DOWN * (0.35 + t)).normalized()
		var next := at + heading * step
		var local := (next - HEAD_CENTER) / shell
		if local.length() < 1.0:
			next = HEAD_CENTER + local.normalized() * shell
		if next.y < HEAD_CENTER.y - HEAD_RADII.y * 0.4:
			var outward := Vector3(next.x - HEAD_CENTER.x, 0.0, next.z - HEAD_CENTER.z).normalized()
			next += outward * step * 0.12
		var across := heading.cross(Vector3.UP).normalized()
		next += across * sin(t * 9.0 + phase) * wave * t
		heading = (next - at).normalized()
		at = next
		path.append(at)
	return path

static func _vertex(surface: SurfaceTool, point: Vector3, along: Vector3, uv: Vector2, half_width: float, kind: Color) -> void:
	surface.set_uv(uv)
	surface.set_uv2(Vector2(half_width, 0.0))
	surface.set_normal(along)
	surface.set_color(kind)
	surface.add_vertex(point)
