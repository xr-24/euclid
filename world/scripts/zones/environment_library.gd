extends RefCounted

const Store = preload("res://scripts/persistence/world_state_store.gd")
const Packages = preload("res://scripts/zones/zone_packages.gd")
const PieceDocument = preload("res://scripts/persistence/piece_document.gd")
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
		if record.has("package") and not Packages.has(record.package):
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

func create(title: Variant, catalog: Array, template := "") -> Dictionary:
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
	var package := "construct"
	if not template.is_empty():
		var sources := catalog.filter(func(zone: Dictionary) -> bool: return zone.id == template)
		if sources.is_empty():
			return {"ok": false, "message": "Choose a template from the current environment catalog."}
		package = sources[0].get("package", "construct" if sources[0].get("template") == "grid" else template)
	if not Packages.has(package):
		return {"ok": false, "message": "The source environment package is unavailable."}
	var record := {"id": "space-" + Crypto.new().generate_random_bytes(8).hex_encode(), "name": name}
	if package != "construct":
		record["package"] = package
	var next := _records + [record]
	if not _path.is_empty():
		var directory := _path.get_base_dir()
		var source := directory.path_join(PieceDocument.filename(package if template.is_empty() else template))
		var seed := PieceDocument.new(source, Packages.definition(package).get("pieces", []))
		if not seed.error.is_empty():
			return {"ok": false, "message": seed.error}
		var document_path := directory.path_join(PieceDocument.filename(record.id))
		var document := PieceDocument.new(document_path, [])
		if not document.save(seed.pieces, []):
			return {"ok": false, "message": "The new environment piece document could not be saved."}
		if Store.write_json(_path, {"schema_version": 1, "environments": next}) != OK:
			DirAccess.remove_absolute(document_path)
			return {"ok": false, "message": "The new environment could not be saved."}
	_records = next
	return {"ok": true, "zone": _zone(record), "message": "Created %s from the %s package." % [name, package]}

static func _zone(record: Dictionary) -> Dictionary:
	var package: String = record.get("package", "construct")
	var definition := Packages.definition(package)
	return {"id": record.id, "name": record.name, "template": "grid" if definition.capabilities.get("workshop", false) else package,
		"package": package, "subtitle": "A custom environment",
		"description": "A saved custom space using the %s package." % package, "color": definition.get("color", "071217")}

static func _valid_name(value: Variant) -> bool:
	if not value is String or value.strip_edges().is_empty() or value.length() > 48:
		return false
	for i in value.length():
		if value.unicode_at(i) < 32 or value.unicode_at(i) == 127:
			return false
	return true

static func _valid_id(value: Variant) -> bool:
	return value is String and value.begins_with("space-") and value.length() == 22 and value.substr(6).is_valid_hex_number()
