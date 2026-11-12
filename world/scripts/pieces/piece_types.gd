extends RefCounted
## Registered piece types. Each declares its fields in data/pieces/types.json and names a trusted
## factory in scripts/pieces/. Records choose a registered type, never a script path.

const Commands = preload("res://scripts/workshop/command_registry.gd")
const PATH := "res://data/pieces/types.json"
const MAX_PIECES := 4096
const MAX_DEPTH := 16
const FACTORY_DIRECTORY := "res://scripts/pieces/"

static var _data := _load()
static var _factories := {}
static var _factory_mutex := Mutex.new()

static func types() -> Dictionary:
	return _data.types

static func common() -> Dictionary:
	return _data.common

static func has(type: Variant) -> bool:
	return type is String and _data.types.has(type)

## One piece's own fields (its children are checked by valid_tree).
static func valid(record: Variant) -> bool:
	if not record is Dictionary or not has(record.get("type")):
		return false
	var definition: Dictionary = _data.types[record.type]
	var fields: Dictionary = definition.fields
	for key in ["id", "type"] + definition.required:
		if not record.has(key):
			return false
	for key in record:
		if key == "children":
			continue
		var rule: Variant = _data.common.get(key, fields.get(key))
		if not rule is Dictionary or not Commands.valid_value(record[key], rule):
			return false
	return true

## A list of pieces and all their children: valid records, unique ids, bounded size and depth.
static func valid_tree(pieces: Variant) -> bool:
	return _valid_level(pieces, {}, [0], 0)

static func factory(type: String) -> GDScript:
	_factory_mutex.lock()
	if not _factories.has(type):
		var loaded := load(str(_data.types[type]["script"])) as GDScript
		_factories[type] = loaded if loaded != null and loaded.has_script_method("build") else null
	var factory_script: GDScript = _factories[type]
	_factory_mutex.unlock()
	return factory_script

static func _valid_level(pieces: Variant, ids: Dictionary, count: Array, depth: int) -> bool:
	if not pieces is Array or depth > MAX_DEPTH:
		return false
	for piece: Variant in pieces:
		count[0] += 1
		if count[0] > MAX_PIECES or not valid(piece) or ids.has(piece.id):
			return false
		ids[piece.id] = true
		if piece.has("children") and not _valid_level(piece.children, ids, count, depth + 1):
			return false
	return true

static func _load() -> Dictionary:
	var empty := {"common": {}, "types": {}}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not value is Dictionary or value.get("version") != 1 or not value.get("common") is Dictionary \
			or not value.get("types") is Dictionary:
		push_error("Invalid piece types: " + PATH)
		return empty
	var rejected := []
	for id: Variant in value.types:
		var definition: Variant = value.types[id]
		if not id is String or not definition is Dictionary or not definition.get("fields") is Dictionary \
				or not definition.get("required") is Array or not definition.get("script") is String \
				or not str(definition["script"]).begins_with(FACTORY_DIRECTORY) or ".." in str(definition["script"]) \
				or str(definition["script"]).get_extension() != "gd" \
				or not definition.required.all(func(key: Variant) -> bool: return definition.fields.has(key)):
			push_error("Invalid piece type: " + str(id))
			rejected.append(id)
	for id: Variant in rejected:
		value.types.erase(id)
	return value
