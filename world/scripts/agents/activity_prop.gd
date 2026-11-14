extends Node3D
## A holographic prop an agent conjures while it works (a book while reading, a keyboard while
## editing, ...). Specs live in data/agents/activity_motions.json under "props": the shape, the
## bones it floats between, an offset in the body's frame (+X left, +Y up, +Z forward), what it
## faces (a bone or a direction) and its size. It materializes in and dissolves away.

const SHADER = preload("res://shaders/agent_prop.gdshader")
const PATTERNS := {"panel": 0, "book": 1, "keyboard": 2, "terminal": 3, "lens": 4, "orb": 5}
## Seconds to materialize or dissolve.
const RISE := 0.45

var key := ""
var leaving := false
var _spec := {}
var _rig: Skeleton3D
var _anchors: Array[int] = []
var _face_bone := -1
var _face := Vector3.FORWARD
var _level := 0.0
var _materials: Array[ShaderMaterial] = []
var _spin: Node3D

static func create(name_key: String, spec: Dictionary, rig: Skeleton3D, tint: Color, accent: Color):
	var prop = new()
	prop.name = "Prop"
	prop.key = name_key
	prop._spec = spec
	prop._rig = rig
	prop._build(tint, accent)
	return prop

func _build(tint: Color, accent: Color) -> void:
	for bone in _spec.get("between", []):
		var index := _rig.find_bone(str(bone))
		if index >= 0:
			_anchors.append(index)
	var face: Variant = _spec.get("face", "")
	if face is String and not face.is_empty():
		_face_bone = _rig.find_bone(face)
	elif face is Array and face.size() == 3:
		_face = Vector3(face[0], face[1], face[2]).normalized()
	var size_value: Array = _spec.get("size", [0.25, 0.18])
	var size := Vector2(float(size_value[0]), float(size_value[1]))
	var shape := str(_spec.get("shape", "panel"))
	var seed := randf() * 50.0
	match shape:
		"book":
			# Two pages open toward the reader, hinged down the middle.
			for side in [-1.0, 1.0]:
				var hinge := Node3D.new()
				hinge.rotation.y = side * -0.32
				add_child(hinge)
				var page := _quad(Vector2(size.x * 0.5, size.y), "book", tint, accent, seed + side)
				page.position.x = side * size.x * 0.25
				hinge.add_child(page)
		"lens":
			var ring := MeshInstance3D.new()
			var torus := TorusMesh.new()
			torus.inner_radius = size.x * 0.42
			torus.outer_radius = size.x * 0.5
			torus.rings = 24
			torus.ring_segments = 6
			ring.mesh = torus
			ring.rotation.x = PI * 0.5
			ring.material_override = _material("orb", tint, accent, seed)
			add_child(ring)
			add_child(_quad(size * 0.92, "lens", tint, accent, seed))
		"orb":
			_spin = Node3D.new()
			add_child(_spin)
			var ball := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = size.x * 0.5
			sphere.height = size.x
			sphere.radial_segments = 20
			sphere.rings = 10
			ball.mesh = sphere
			ball.material_override = _material("orb", tint, accent, seed)
			_spin.add_child(ball)
			var orbit := MeshInstance3D.new()
			var band := TorusMesh.new()
			band.inner_radius = size.x * 0.72
			band.outer_radius = size.x * 0.76
			band.rings = 32
			band.ring_segments = 4
			orbit.mesh = band
			orbit.rotation = Vector3(0.5, 0.0, 0.3)
			orbit.material_override = _material("orb", tint, accent, seed + 1.0)
			_spin.add_child(orbit)
		_:
			add_child(_quad(size, shape, tint, accent, seed))
	_place()
	_apply()

func _quad(size: Vector2, shape: String, tint: Color, accent: Color, seed: float) -> MeshInstance3D:
	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = size
	quad.mesh = mesh
	quad.material_override = _material(shape, tint, accent, seed)
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return quad

func _material(shape: String, tint: Color, accent: Color, seed: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("tint", tint)
	material.set_shader_parameter("accent", accent)
	material.set_shader_parameter("pattern", PATTERNS.get(shape, 0))
	material.set_shader_parameter("seed", seed)
	_materials.append(material)
	return material

## Dissolve, then free.
func leave() -> void:
	leaving = true

## Jump to fully shown (previews).
func settle() -> void:
	_level = 1.0
	_apply()

func _process(delta: float) -> void:
	_level = move_toward(_level, 0.0 if leaving else 1.0, delta / RISE)
	_apply()
	if leaving and _level <= 0.0:
		queue_free()
		return
	if _spin:
		_spin.rotate_y(delta * 0.9)
	_place()

func _apply() -> void:
	for material in _materials:
		material.set_shader_parameter("materialize", _level)

func _place() -> void:
	if _anchors.is_empty():
		return
	var at := Vector3.ZERO
	for index in _anchors:
		at += _rig.get_bone_global_pose(index).origin
	at /= _anchors.size()
	var offset: Array = _spec.get("offset", [0, 0, 0])
	at += Vector3(offset[0], offset[1], offset[2])
	var facing := _face
	if _face_bone >= 0:
		facing = (_rig.get_bone_global_pose(_face_bone).origin - at).normalized()
	var up := Vector3.UP if absf(facing.dot(Vector3.UP)) < 0.95 else Vector3.BACK
	transform = _rig.transform * Transform3D(Basis.looking_at(facing, up, true), at)
