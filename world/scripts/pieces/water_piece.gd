extends RefCounted
## A finite pool or stream, or the ocean surface around a landscape.

const Water = preload("res://scripts/simulation/water_system.gd")
const Shapes = preload("res://scripts/pieces/shape_piece.gd")
const TerrainData = preload("res://scripts/pieces/terrain_data.gd")
const Finish = preload("res://scripts/pieces/piece_material.gd")
const RIM := 0.24
const FREEBOARD := 0.10

const Reflection = preload("res://scripts/rendering/pool_reflection.gd")

static func valid_record(record: Dictionary) -> bool:
	var rotation: Array = record.get("rotation", [0, 0, 0])
	return is_zero_approx(rotation[0]) and is_zero_approx(rotation[2])

static func valid_parent(record: Dictionary, parent: Dictionary) -> bool:
	if record.basin_mode != "excavated":
		return true
	if parent.get("type") != "terrain":
		return false
	var cut := terrain_cut(record)
	var size: Array = parent.terrain_size
	var half := Vector2(size[0], size[1]) * 0.5
	var margin := maxf(size[0], size[1]) / TerrainData.CELLS
	for sign_x in [-1.0, 1.0]:
		for sign_z in [-1.0, 1.0]:
			var corner: Vector2 = cut.center + (cut.half * Vector2(sign_x, sign_z)).rotated(cut.angle)
			if absf(corner.x) + margin > half.x or absf(corner.y) + margin > half.y:
				return false
	return true

static func terrain_cut(record: Dictionary) -> Dictionary:
	if record.get("basin_mode") != "excavated":
		return {}
	var size := Vector2(record.water_size[0], record.water_size[1])
	var at: Array = record.get("position", [0, 0, 0])
	var scale: Array = record.get("scale", [1, 1, 1])
	var yaw: Array = record.get("rotation", [0, 0, 0])
	var depth := float(record.get("basin_depth", 1.45))
	return {"center": Vector2(at[0], at[2]), "half": (size * 0.5 + Vector2.ONE * RIM) * Vector2(scale[0], scale[2]),
		"angle": deg_to_rad(yaw[1]), "bottom": float(at[1]) - (depth + 0.025) * float(scale[1])}

static func build(record: Dictionary) -> Node3D:
	var node := Node3D.new()
	var dimensions: Array = record.water_size
	var size := Vector2(dimensions[0], dimensions[1])
	var kind: String = record.water_kind
	var material := Water.water_material(kind == "ocean")
	var mesh := MeshInstance3D.new()
	if record.has("basin_mode"):
		var rim := _build_basin(node, size, record)
		mesh.position.y = rim - FREEBOARD
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
		mirror.configure(material, mesh, mesh.position.y)
		mirror.name = "PoolReflection"
		node.add_child(mirror)
	node.set_meta("water_piece", {"surface": mesh, "size": size, "kind": kind,
		"id": record.get("water_id", record.id), "label": record.get("name", kind.capitalize())})
	return node

static func _build_basin(node: Node3D, size: Vector2, record: Dictionary) -> float:
	var depth := float(record.get("basin_depth", 1.45))
	var raised: bool = record.basin_mode == "raised"
	var rim := depth if raised else 0.0
	var lip := 0.34
	var material := Finish.make(record.get("basin_material", {"color": "8d9fa6", "roughness": 0.6}))
	_box(node, Vector3(0, rim - depth - 0.07, 0), Vector3(size.x + RIM * 2.0, 0.14, size.y + RIM * 2.0), material)
	for side in [-1.0, 1.0]:
		_box(node, Vector3(side * (size.x + RIM) * 0.5, rim - depth * 0.5, 0), Vector3(RIM, depth, size.y + RIM * 2.0), material)
		_box(node, Vector3(0, rim - depth * 0.5, side * (size.y + RIM) * 0.5), Vector3(size.x, depth, RIM), material)
		if not raised:
			_box(node, Vector3(side * (size.x + RIM + lip) * 0.5, rim - 0.05, 0),
				Vector3(RIM + lip, 0.10, size.y + (RIM + lip) * 2.0), material)
			_box(node, Vector3(0, rim - 0.05, side * (size.y + RIM + lip) * 0.5),
				Vector3(size.x, 0.10, RIM + lip), material)
	return rim

static func _box(node: Node3D, position: Vector3, size: Vector3, material: Material) -> void:
	var wall := Shapes.build({"shape": "box", "size": [size.x, size.y, size.z]})
	wall.position = position
	(wall.get_node("Mesh") as MeshInstance3D).material_override = material
	node.add_child(wall)
