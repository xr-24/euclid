extends RefCounted

const Building = preload("res://scripts/pieces/building_piece.gd")
const Finish = preload("res://scripts/pieces/piece_material.gd")

static func build(record: Dictionary) -> Node3D:
	return Building.build_steps(record.stair_plan, Finish.make(record.get("material", {"color": "6d7380"})))
