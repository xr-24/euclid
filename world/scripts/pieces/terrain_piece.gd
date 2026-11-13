extends RefCounted

const Terrain = preload("res://scripts/pieces/terrain_node.gd")
const Data = preload("res://scripts/pieces/terrain_data.gd")

static func valid_storage(record: Dictionary) -> bool:
	var encoded: String = record.get("terrain_surface", "")
	var extra: String = record.get("terrain_paint_data", "")
	var ids: Array = record.get("terrain_materials", [])
	if not extra.is_empty() and ids.is_empty():
		return false
	for id in ids:
		if ids.count(id) != 1 or Terrain.builtin_slot(id) >= 0:
			return false
	return (encoded.is_empty() and extra.is_empty()) or Data.new().decode(encoded, extra, ids.size())

static func build(record: Dictionary) -> Node3D:
	var terrain := Terrain.new()
	terrain.setup(record)
	return terrain

static func update_fields(node: Node3D, before: Dictionary, record: Dictionary) -> bool:
	if before.terrain_size != record.terrain_size or before.get("cast_shadow") != record.get("cast_shadow"):
		return false
	return (node as Terrain).load_record(record)
