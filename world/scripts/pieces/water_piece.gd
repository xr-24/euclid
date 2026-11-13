extends RefCounted
## A finite pool or stream, or the ocean surface around a landscape.

const Water = preload("res://scripts/simulation/water_system.gd")
const Reflection = preload("res://scripts/rendering/pool_reflection.gd")

static func build(record: Dictionary) -> Node3D:
	var node := Node3D.new()
	var dimensions: Array = record.water_size
	var size := Vector2(dimensions[0], dimensions[1])
	var kind: String = record.water_kind
	var material := Water.water_material(kind == "ocean")
	var mesh := MeshInstance3D.new()
	if kind == "round":
		var disc := CylinderMesh.new()
		disc.top_radius = size.x * 0.5
		disc.bottom_radius = disc.top_radius
		disc.height = 0.02
		disc.radial_segments = 48
		mesh.mesh = disc
		size.y = size.x
	else:
		var plane := PlaneMesh.new()
		plane.size = size
		plane.subdivide_width = int(record.get("detail", mini(160, int(size.x * 2))))
		plane.subdivide_depth = int(record.get("detail", mini(160, int(size.y * 2))))
		mesh.mesh = plane
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.material_override = material
	node.add_child(mesh)
	if kind == "stream":
		material.set_shader_parameter("surface_flow", Vector2(0, float(record.get("flow_speed", 0.8))))
	for key in record.get("water_look", {}):
		var value: Variant = record.water_look[key]
		material.set_shader_parameter(key, Color.html(value) if value is String else value)
	if record.get("mirror", false) and kind != "ocean":
		var mirror := Reflection.new()
		mirror.configure(material, mesh, 0.0)
		mirror.name = "PoolReflection"
		node.add_child(mirror)
	node.set_meta("water_piece", {"surface": mesh, "size": size, "kind": kind,
		"id": record.get("water_id", record.id), "label": record.get("name", kind.capitalize())})
	return node
