extends RefCounted
## Named entity snapshots shared by the Grid and custom spaces.

const EntityTypes = preload("res://scripts/workshop/entity_types.gd")
const Store = preload("res://scripts/persistence/world_state_store.gd")
const PROPERTIES := ["type", "yaw", "scale", "color", "asset_id", "animation"]
const LIMIT := 64
const MAX_BYTES := 3 * 1024 * 1024

var _path: String
var _records := {}
var _readable := true

func _init(path: String) -> void:
	_path = path
	if path.is_empty() or not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	var data: Variant = JSON.parse_string(file.get_as_text()) if file and file.get_length() <= MAX_BYTES else null
	if not data is Dictionary or data.get("schema_version") != 1 or not data.get("prefabs") is Array or data.prefabs.size() > LIMIT:
		_readable = false
		return
	var loaded := {}
	var names := {}
	for record in data.prefabs:
		if not _valid_record(record) or loaded.has(record.id) or names.has(record.name.to_lower()):
			_readable = false
			return
		loaded[record.id] = record
		names[record.name.to_lower()] = true
	_records = loaded

func list() -> Dictionary:
	if not _readable:
		return _error("The prefab library could not be read.")
	var prefabs: Array[Dictionary] = []
	for record in _records.values():
		prefabs.append({"id": record.id, "name": record.name, "type": record.properties.type,
			"animated": record.properties.has("animation")})
	return {"ok": true, "prefabs": prefabs}

func save(title: Variant, entity: Dictionary) -> Dictionary:
	if not _readable:
		return _error("The prefab library could not be read.")
	var name: String = title.strip_edges() if title is String else ""
	if not _valid_name(name):
		return _error("Choose a prefab name with 1 to 48 printable characters.")
	if _records.size() >= LIMIT:
		return _error("The prefab library is full.")
	for record in _records.values():
		if record.name.nocasecmp_to(name) == 0:
			return _error("A prefab already has that name.")
	var properties := {}
	for key in PROPERTIES:
		if entity.has(key):
			properties[key] = entity[key]
	if not EntityTypes.valid_properties(properties):
		return _error("This entity cannot be saved as a prefab.")
	var id := Crypto.new().generate_random_bytes(16).hex_encode()
	var record := {"id": id, "name": name, "properties": properties.duplicate(true)}
	if not _path.is_empty() and Store.write_json(_path, {"schema_version": 1, "prefabs": _records.values() + [record]}) != OK:
		return _error("The prefab could not be saved.")
	_records[id] = record
	return {"ok": true, "prefab_id": id, "name": name}

func get_prefab(id: Variant) -> Dictionary:
	if not _readable:
		return _error("The prefab library could not be read.")
	if not id is String or not _records.has(id):
		return _error("Choose a prefab from the library.")
	return {"ok": true, "prefab": _records[id].duplicate(true)}

static func _valid_record(record: Variant) -> bool:
	if not record is Dictionary or record.size() != 3 or not _valid_name(record.get("name")):
		return false
	var id: Variant = record.get("id")
	var properties: Variant = record.get("properties")
	return id is String and id.length() == 32 and id.is_valid_hex_number() \
		and properties is Dictionary and properties.keys().all(func(key: String) -> bool: return key in PROPERTIES) \
		and EntityTypes.valid_properties(properties)

static func _valid_name(value: Variant) -> bool:
	if not value is String or value.strip_edges().is_empty() or value.length() > 48:
		return false
	for index in value.length():
		if value.unicode_at(index) < 32 or value.unicode_at(index) == 127:
			return false
	return true

static func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
