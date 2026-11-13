extends RefCounted
## Seeded vegetation and rock placement using the same batched renderer as authored landscapes.

const Scatter = preload("res://scripts/scatter.gd")
const Terrain = preload("res://scripts/pieces/terrain_node.gd")
const TerrainField = preload("res://scripts/terrain_field.gd")

class LevelSurface:
	extends RefCounted

	func contains(_x: float, _z: float) -> bool:
		return true

	func height(_x: float, _z: float) -> float:
		return 0.0

	func normal(_x: float, _z: float) -> Vector3:
		return Vector3.UP

class SculptedSurface:
	extends RefCounted

	var terrain: Terrain
	var to_terrain: Transform3D
	var to_patch: Transform3D

	func _init(target: Terrain, transform: Transform3D) -> void:
		terrain = target
		to_terrain = transform
		to_patch = transform.affine_inverse()

	func contains(x: float, z: float) -> bool:
		var p := to_terrain * Vector3(x, 0, z)
		return terrain.contains_point(Vector2(p.x, p.z))

	func height(x: float, z: float) -> float:
		var p := to_terrain * Vector3(x, 0, z)
		p.y = terrain.surface_height(Vector2(p.x, p.z))
		return (to_patch * p).y

	func normal(x: float, z: float) -> Vector3:
		const DISTANCE := 0.3
		return Vector3(height(x - DISTANCE, z) - height(x + DISTANCE, z), 2.0 * DISTANCE,
			height(x, z - DISTANCE) - height(x, z + DISTANCE)).normalized()

static func build(record: Dictionary) -> Node3D:
	var root := Node3D.new()
	if not record.get("follow_terrain", true):
		plant(root, record)
	return root

static func plant(root: Node3D, record: Dictionary) -> void:
	for child in root.get_children():
		if not child.has_meta("piece_id"):
			child.free()
	var rule := record.duplicate()
	rule["asset"] = record.asset_id
	var area: Array = record.scatter_size
	rule["region"] = record.get("region", [-area[0] * 0.5, area[0] * 0.5, -area[1] * 0.5, area[1] * 0.5])
	rule["scale"] = record.get("plant_scale", [0.8, 1.2])
	var field: RefCounted = LevelSurface.new()
	var parent := root.get_parent() as Terrain
	if parent != null and record.get("follow_terrain", true):
		field = SculptedSurface.new(parent, root.transform)
	var field_id: String = record.get("heightfield", "")
	if not field_id.is_empty():
		var landscape := TerrainField.new()
		if not landscape.load_from("res://assets/generated/" + field_id + ".json"):
			return
		field = landscape
	var exclusions := []
	for rect: Array in record.get("exclusions", []):
		exclusions.append(Rect2(rect[0], rect[1], rect[2], rect[3]))
	var count := Scatter.plant(root, rule, field, exclusions, int(record.get("seed", 1)))
	root.set_meta("scatter_count", count)

static func placed(node: Node3D, _before: Dictionary, record: Dictionary) -> bool:
	if not record.get("follow_terrain", true):
		return false
	plant(node, record)
	return true
