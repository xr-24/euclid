extends RefCounted

const Store = preload("res://scripts/persistence/world_state_store.gd")
const LIMIT := 12
var _path: String
var _records: Array = []
var _readable := true

func _init(path: String) -> void:
	_path = path
	if path.is_empty() or not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	var data: Variant = JSON.parse_string(file.get_as_text()) if file and file.get_length() < 16384 else null
	if not data is Dictionary or data.get("schema_version") != 1 or not data.get("environments") is Array or data.environments.size() > LIMIT:
		_readable = false
		return
	var ids := {}
	var names := {}
	for record in data.environments:
		if not record is Dictionary or not _valid_name(record.get("name")) or not _valid_id(record.get("id")):
			_readable = false
			return
		if ids.has(record.id) or names.has(record.name.to_lower()):
			_readable = false
			return
		ids[record.id] = true
		names[record.name.to_lower()] = true
	_records = data.environments

func environments() -> Array:
	var zones := []
	for record in _records:
		zones.append(_zone(record))
	return zones

func create(title: Variant, catalog: Array) -> Dictionary:
	if not _readable:
		return {"ok": false, "message": "The environment save could not be read."}
	var name: String = title.strip_edges() if title is String else ""
	if not _valid_name(name):
		return {"ok": false, "message": "Choose a name with 1 to 48 printable characters."}
	if _records.size() >= LIMIT:
		return {"ok": false, "message": "The environment library is full."}
	for zone in catalog:
		if zone.name.to_lower() == name.to_lower():
			return {"ok": false, "message": "An environment already has that name."}
	var record := {"id": "space-" + Crypto.new().generate_random_bytes(8).hex_encode(), "name": name}
	var next := _records + [record]
	if not _path.is_empty() and Store.write_json(_path, {"schema_version": 1, "environments": next}) != OK:
		return {"ok": false, "message": "The new environment could not be saved."}
	_records = next
	return {"ok": true, "zone": _zone(record), "message": "Created %s from the Grid template." % name}

static func _zone(record: Dictionary) -> Dictionary:
	return {"id": record.id, "name": record.name, "template": "grid",
		"subtitle": "A new Grid space", "description": "A saved custom space using the luminous Grid template.", "color": "071217"}

static func _valid_name(value: Variant) -> bool:
	if not value is String or value.strip_edges().is_empty() or value.length() > 48:
		return false
	for i in value.length():
		if value.unicode_at(i) < 32 or value.unicode_at(i) == 127:
			return false
	return true

static func _valid_id(value: Variant) -> bool:
	return value is String and value.begins_with("space-") and value.length() == 22 and value.substr(6).is_valid_hex_number()
