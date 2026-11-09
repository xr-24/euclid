extends RefCounted
## Project-owned plugin declarations and the settings shared by both tool clients.

const CATALOG := "res://data/behavior_plugins.json"
const PACKAGES := "res://data/behavior_plugins"
const SCRIPT_ROOT := "res://scripts/plugins/"
const MAX_SETTINGS := 6
var _plugins := {}

func _init() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
	if data is Dictionary and data.get("schema_version") == 1 and data.get("plugins") is Array:
		for plugin in data.plugins:
			register(plugin)
	if DirAccess.dir_exists_absolute(PACKAGES):
		for file in DirAccess.get_files_at(PACKAGES):
			if file.get_extension() != "json" or not _identifier(file.get_basename()):
				continue
			var definition: Variant = JSON.parse_string(FileAccess.get_file_as_string(PACKAGES.path_join(file)))
			if definition is Dictionary and definition.get("id") == file.get_basename():
				register(definition)

func register(definition: Variant) -> bool:
	if not _valid_definition(definition) or _plugins.has(definition.id):
		return false
	var plugin: Dictionary = definition.duplicate(true)
	plugin["output"] = plugin.get("output", "emission")
	_plugins[plugin.id] = plugin
	return true

func remove(id: String) -> void:
	_plugins.erase(id)

func definition(id: String) -> Dictionary:
	return _plugins.get(id, {}).duplicate(true)

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
	var configured := {"id": plugin.id, "settings": settings}
	if plugin.output == "door_open" and request.has("target"):
		configured["target"] = request.target
	return configured

static func valid_record(value: Variant) -> bool:
	if not value is Dictionary or not _identifier(value.get("id")) or value.size() != (3 if value.has("target") else 2):
		return false
	if value.has("target") and (not value.target is String or value.target.length() != 32 or not value.target.is_valid_hex_number()):
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
	var output: Variant = value.get("output", "emission")
	if output == "door_open" and value.entity_type != "pressure_plate":
		return false
	if output == "emission" and value.entity_type not in ["pressure_plate", "traffic_cone"]:
		return false
	if output not in ["emission", "door_open"] or value.name.strip_edges().is_empty() or value.name.length() > 48:
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
