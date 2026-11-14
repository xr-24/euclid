extends RefCounted
## Named surface finishes for walls, floors, pools and paving (data/pieces/finishes.json). Any piece
## material may start from one with {"finish": name}; house fields also take a bare finish name.

const FILE := "res://data/pieces/finishes.json"

static var _data := _load()

static func all() -> Dictionary:
	return _data.get("finishes", {})

static func has(id: String) -> bool:
	return all().has(id)

## The piece material for a finish name or a piece material spec; {} for anything else. A spec's
## "finish" is replaced by that finish's material, with the spec's other fields laid over it.
static func spec(value: Variant) -> Dictionary:
	if value is String:
		var finish: Dictionary = all().get(value, {})
		return finish.get("material", {})
	if not value is Dictionary:
		return {}
	if not value.has("finish"):
		return value
	var resolved: Dictionary = spec(str(value.finish)).duplicate()
	for key: String in value:
		if key != "finish":
			resolved[key] = value[key]
	return resolved

static func _load() -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE))
	if not value is Dictionary or value.get("version") != 1:
		push_error("Invalid wall finishes: " + FILE)
		return {}
	return value
