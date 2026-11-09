extends RefCounted

const WALL_SHADER = preload("res://shaders/grid_wall.gdshader")

## Detached set dressing. The wall and its suspended fragments are outside collision.
static func build(root: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 71023
	var pieces: Array[Transform3D] = []
	for i in 74:
		var angle := TAU * i / 74.0
		var radius := rng.randf_range(86.0, 106.0)
		var height := rng.randf_range(40.0, 92.0)
		_piece(pieces, Vector3(sin(angle) * radius, height * 0.46, -cos(angle) * radius),
			Vector3(rng.randf_range(4.8, 8.1), height, rng.randf_range(2.5, 7.0)), -angle, rng.randf_range(-0.027, 0.027))
	for i in 61:
		var angle := TAU * i / 61.0
		# Open up the nearer ring to give the distant strata room in the arrival view.
		if absf(wrapf(angle + 0.22, -PI, PI)) < 0.17:
			continue
		var radius := rng.randf_range(64.0, 77.0)
		var height := rng.randf_range(17.0, 59.0)
		var base := Vector3(sin(angle) * radius, 0, -cos(angle) * radius)
		_piece(pieces, base + Vector3.UP * height * 0.44,
			Vector3(rng.randf_range(3.5, 7.1), height, rng.randf_range(1.8, 5.8)), -angle, rng.randf_range(-0.045, 0.045))
		if i % 3 == 0:
			_piece(pieces, base + Vector3.UP * (height + rng.randf_range(3.0, 9.0)),
				Vector3(rng.randf_range(1.2, 4.0), rng.randf_range(5.0, 19.0), 1.8), -angle + 0.2, rng.randf_range(-0.11, 0.11))
	for i in 22:
		var angle := rng.randf_range(-PI, PI)
		var radius := rng.randf_range(27.0, 63.0)
		_piece(pieces, Vector3(sin(angle) * radius, rng.randf_range(5.2, 29.0), -cos(angle) * radius),
			Vector3(rng.randf_range(0.6, 2.1), rng.randf_range(1.3, 9.0), rng.randf_range(0.6, 2.1)),
			rng.randf_range(-PI, PI), rng.randf_range(-0.2, 0.2))

	var material := ShaderMaterial.new()
	material.shader = WALL_SHADER
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	box.material = material
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.mesh = box
	batch.instance_count = pieces.size()
	for i in pieces.size():
		batch.set_instance_transform(i, pieces[i])
	var walls := MultiMeshInstance3D.new()
	walls.multimesh = batch
	walls.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(walls)

static func _piece(pieces: Array[Transform3D], at: Vector3, size: Vector3, yaw: float, tilt: float) -> void:
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.FORWARD, tilt)
	pieces.append(Transform3D(basis.scaled_local(size), at))
