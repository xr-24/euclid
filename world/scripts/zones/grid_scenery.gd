extends RefCounted
## Owns the replaceable scenery while the zone, physics and workshop stay attached.

const Grid = preload("res://scripts/zones/grid_zone.gd")
const WorldArt = preload("res://scripts/world_art.gd")
const PATH := "res://data/grid_appearance.json"
const DEFAULT := {"schema_version": 1, "floor_spacing": 2.0, "wall_height": 1.0}

var _committed := _read_committed()
var _draft := {}
var _zone: Node3D

func profile() -> Dictionary:
	# The builder gets a value snapshot before a worker starts.
	var current: Dictionary = _draft.get("profile", _committed)
	return current.duplicate()

func attach(zone: Node3D) -> void:
	_zone = zone if zone.has_node("GridScenery") else null
	if available() and _zone.get_node("GridScenery").get_meta("appearance") != profile():
		_replace()

func available() -> bool:
	return is_instance_valid(_zone)

func preview(candidate: Dictionary) -> Dictionary:
	var id: String = candidate.get("draft", "")
	var appearance: Variant = candidate.get("grid")
	if not available():
		return {"ok": false, "message": "Enter a Grid space to preview its scenery."}
	if id.is_empty() or not valid_profile(appearance):
		return {"ok": false, "message": "The Grid draft has invalid scenery settings."}
	if not _draft.is_empty() and _draft.id != id:
		return {"ok": false, "message": "Finish the current Grid preview first."}
	_draft = {"id": id, "profile": appearance.duplicate()}
	_replace()
	return {"ok": true, "message": "Grid scenery reloaded. Close the panel to look around."}

func status(id: String) -> String:
	return "active" if _draft.get("id") == id and available() else ""

func finish(id: String, keep: bool) -> bool:
	if _draft.get("id") != id:
		return false
	if keep:
		_committed = _draft.profile
	_draft = {}
	if not keep:
		_replace()
	return true

func reload_committed() -> void:
	_committed = _read_committed()
	_replace()

func _replace() -> void:
	if not available():
		return
	var previous := _zone.get_node("GridScenery")
	var next := Grid.scenery(profile())
	WorldArt.make_constructible(next)
	var floor_visual := previous.get_node("FloorVisual") as MeshInstance3D
	var side: Variant = floor_visual.get_instance_shader_parameter("construct_side")
	if side is float and side != 0.0:
		WorldArt.set_side(next, side)
	_zone.remove_child(previous)
	_zone.add_child(next)
	previous.queue_free()

static func _read_committed() -> Dictionary:
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return saved if valid_profile(saved) else DEFAULT.duplicate()

static func valid_profile(value: Variant) -> bool:
	return value is Dictionary and value.size() == 3 and value.get("schema_version") == 1 \
		and _number(value.get("floor_spacing"), 1.0, 8.0) and _number(value.get("wall_height"), 0.5, 1.5)

static func _number(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= minimum and value <= maximum
