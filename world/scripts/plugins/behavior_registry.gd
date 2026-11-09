extends RefCounted
## Project-owned plugin declarations and the settings shared by both tool clients.

const CATALOG := "res://data/behavior_plugins.json"
const SCRIPT_ROOT := "res://scripts/plugins/"
const MAX_SETTINGS := 6
var _plugins := {}

func _init() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
	if not data is Dictionary or data.get("schema_version") != 1 or not data.get("plugins") is Array:
		return
	for plugin in data.plugins:
		if _valid_definition(plugin) and not _plugins.has(plugin.id):
			_plugins[plugin.id] = plugin

func list(entity_type := "") -> Array[Dictionary]:
	var definitions: Array[Dictionary] = []
	for plugin in _plugins.values():
		if entity_type.is_empty() or plugin.entity_type == entity_type:
			definitions.append(plugin.duplicate(true))
	return definitions

func script_path(id: String) -> String:
	return SCRIPT_ROOT + id + ".gd" if _plugins.has(id) else ""

func configure(entity_type: String, request: Variant) -> Dictionary:
	if not valid_record(request) or not _plugins.has(request.id):
		return {}
	var plugin: Dictionary = _plugins[request.id]
	if plugin.entity_type != entity_type or not request.settings.keys().all(func(key: String) -> bool: return plugin.settings.has(key)):
		return {}
	var settings := {}
	for key in plugin.settings:
		var spec: Dictionary = plugin.settings[key]
		var value: float = request.settings.get(key, spec.default)
		if value < float(spec.minimum) or value > float(spec.maximum):
			return {}
		settings[key] = value
	return {"id": plugin.id, "settings": settings}

static func valid_record(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 2 or not _identifier(value.get("id")):
		return false
	var settings: Variant = value.get("settings")
	if not settings is Dictionary or settings.size() > MAX_SETTINGS:
		return false
	for key in settings:
		if not _identifier(key) or not _number(settings[key]):
			return false
	return true

static func _valid_definition(value: Variant) -> bool:
	if not value is Dictionary or not _identifier(value.get("id")) or not _identifier(value.get("entity_type")) \
			or not value.get("name") is String or not value.get("settings") is Dictionary or value.settings.size() > MAX_SETTINGS:
		return false
	for key in value.settings:
		var spec: Variant = value.settings[key]
		if not _identifier(key) or not spec is Dictionary or not spec.get("label") is String or not _number(spec.get("minimum")) \
				or not _number(spec.get("maximum")) or not _number(spec.get("default")) \
				or spec.minimum > spec.default or spec.default > spec.maximum:
			return false
	return true

static func _identifier(value: Variant) -> bool:
	return value is String and value.length() <= 40 and value.is_valid_identifier() and value == value.to_lower()

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and absf(float(value)) <= 10000.0
