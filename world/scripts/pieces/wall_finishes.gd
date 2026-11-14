extends RefCounted
## Named wall finishes (data/pieces/wall_finishes.json). A house's walls rules, backsplash and
## material overrides may name a finish instead of spelling out a piece material.

const FILE := "res://data/pieces/wall_finishes.json"

static var _data := _load()

static func all() -> Dictionary:
	return _data.get("finishes", {})

static func has(id: String) -> bool:
	return all().has(id)

## The piece material for a finish id or a piece material spec; {} for anything else.
static func spec(value: Variant) -> Dictionary:
	if value is Dictionary:
		return value
	if value is String:
		var finish: Dictionary = all().get(value, {})
		return finish.get("material", {})
	return {}

static func _load() -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE))
	if not value is Dictionary or value.get("version") != 1:
		push_error("Invalid wall finishes: " + FILE)
		return {}
	return value
