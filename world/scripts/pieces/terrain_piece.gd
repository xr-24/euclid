extends RefCounted

const Terrain = preload("res://scripts/pieces/terrain_node.gd")
const Data = preload("res://scripts/pieces/terrain_data.gd")

static func valid_storage(record: Dictionary) -> bool:
	var encoded: String = record.get("terrain_surface", "")
	return encoded.is_empty() or Data.new().decode(encoded)

static func build(record: Dictionary) -> Node3D:
	var terrain := Terrain.new()
	terrain.setup(record)
	return terrain

static func update_fields(node: Node3D, before: Dictionary, record: Dictionary) -> bool:
	if before.terrain_size != record.terrain_size or before.get("cast_shadow") != record.get("cast_shadow"):
		return false
	return (node as Terrain).load_surface(record.get("terrain_surface", ""))
