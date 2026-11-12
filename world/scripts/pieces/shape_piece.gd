extends RefCounted
## A solid primitive with a material: box, sphere, cylinder, capsule or a flat plane.
## Round shapes use size X as the diameter and size Y as the height.

const PieceMaterial = preload("res://scripts/pieces/piece_material.gd")
const PLANE_THICKNESS := 0.02

static func build(record: Dictionary) -> Node3D:
	var value: Array = record.size
	var size := Vector3(float(value[0]), float(value[1]), float(value[2]))
	var kind := str(record.shape)
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	mesh.mesh = _mesh(kind, size)
	mesh.material_override = PieceMaterial.make(record.get("material", {}))
	if not record.get("cast_shadow", true):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if not record.get("collision", true):
		var plain := Node3D.new()
		plain.add_child(mesh)
		return plain
	var body := StaticBody3D.new()
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	shape.name = "Collision"
	shape.shape = _collider(kind, size, mesh.mesh)
	if kind == "plane":
		shape.position.y = -PLANE_THICKNESS * 0.5
	body.add_child(shape)
	return body

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
			var slab := BoxShape3D.new()
			slab.size = Vector3(size.x, PLANE_THICKNESS, size.z)
			return slab
	var box := BoxShape3D.new()
	box.size = size
	return box
