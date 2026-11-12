extends RefCounted
## A solid primitive with a material: box, sphere, cylinder, capsule or a flat plane.
## Round shapes use size X as the diameter and size Y as the height.

const PieceMaterial = preload("res://scripts/pieces/piece_material.gd")
const Effects = preload("res://scripts/rendering/zone_effects.gd")
const PLANE_THICKNESS := 0.02

static func build(record: Dictionary) -> Node3D:
	var size := _size(record.size)
	var kind := str(record.shape)
	var solid: bool = record.get("collision", true)
	var root := StaticBody3D.new() as Node3D if solid else Node3D.new()
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	mesh.mesh = _mesh(kind, size)
	_apply_look(mesh, record)
	if record.get("render", true):
		root.add_child(mesh)
	if solid:
		var shape := CollisionShape3D.new()
		shape.name = "Collision"
		if record.has("collision_size"):
			shape.shape = _box(_size(record.collision_size))
		else:
			shape.shape = _collider(kind, size, mesh.mesh)
		if kind == "plane":
			var slab := shape.shape as BoxShape3D
			shape.position.y = -slab.size.y * 0.5
		root.add_child(shape)
	if mesh.get_parent() == null:
		mesh.free()
	return root

static func update_fields(node: Node3D, old: Dictionary, record: Dictionary) -> bool:
	for key in ["shape", "size", "collision", "collision_size", "render"]:
		if old.get(key) != record.get(key):
			return false
	var mesh := node.get_node_or_null("Mesh") as MeshInstance3D
	if mesh:
		_apply_look(mesh, record)
		Effects.make_constructible(mesh, false)
	return true

static func _apply_look(mesh: MeshInstance3D, record: Dictionary) -> void:
	mesh.material_override = PieceMaterial.make(record.get("material", {}))
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if record.get("cast_shadow", true) \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

static func _size(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))

static func _mesh(kind: String, size: Vector3) -> Mesh:
	match kind:
		"sphere":
			var sphere := SphereMesh.new()
			sphere.radius = size.x * 0.5
			sphere.height = size.y
			return sphere
		"cylinder":
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = size.x * 0.5
			cylinder.bottom_radius = size.x * 0.5
			cylinder.height = size.y
			return cylinder
		"capsule":
			var capsule := CapsuleMesh.new()
			capsule.radius = size.x * 0.5
			capsule.height = maxf(size.y, size.x)
			return capsule
		"plane":
			var plane := PlaneMesh.new()
			plane.size = Vector2(size.x, size.z)
			return plane
	var box := BoxMesh.new()
	box.size = size
	return box

static func _collider(kind: String, size: Vector3, mesh: Mesh) -> Shape3D:
	match kind:
		"sphere":
			if is_equal_approx(size.x, size.y):
				var sphere := SphereShape3D.new()
				sphere.radius = size.x * 0.5
				return sphere
			return mesh.create_convex_shape()
		"cylinder":
			var cylinder := CylinderShape3D.new()
			cylinder.radius = size.x * 0.5
			cylinder.height = size.y
			return cylinder
		"capsule":
			var capsule := CapsuleShape3D.new()
			capsule.radius = size.x * 0.5
			capsule.height = maxf(size.y, size.x)
			return capsule
		"plane":
			return _box(Vector3(size.x, PLANE_THICKNESS, size.z))
	return _box(size)

static func _box(size: Vector3) -> BoxShape3D:
	var box := BoxShape3D.new()
	box.size = size
	return box
