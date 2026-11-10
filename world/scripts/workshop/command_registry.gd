extends RefCounted
## Shared command definitions. Manifests name handlers on trusted runtime services.

const DIRECTORY := "res://data/commands"
const PLACEHOLDERS := {"target": "", "name": "", "template": "", "preserve_rig": false, "clip": null, "behavior": null, "changes": null}

static var _schema := _read("schema.json")
static var _patterns := {}
static var _commands := _load_commands()
static var _locals := _load_locals()
static var _snapshot := {"version": 1, "schema": _schema, "commands": _commands.values()}

static func snapshot() -> Dictionary:
	return _snapshot

static func command(name: Variant) -> Dictionary:
	return _commands.get(name, {})

static func local(name: String) -> Dictionary:
	return _locals.get(name, {})

static func catalog() -> Array:
	return _commands.values().duplicate(true)

static func field(name: String) -> Dictionary:
	return _schema.get("$defs", {}).get(name, {})

static func built_in_props() -> Array:
	var types := entity_types()
	return types.keys().filter(func(id: String) -> bool: return types[id].get("built_in", false))

static func entity_types() -> Dictionary:
	return _schema.get("entity_types", {})

static func action_properties() -> Array:
	return _schema.action_properties

static func prefab_properties() -> Array:
	return _schema.prefab_properties

static func prop_fields(authored: bool) -> Array:
	return _schema.get("authored_properties", []) if authored else field("prop_changes").properties.keys()

static func valid_field(name: String, value: Variant) -> bool:
	return _valid(value, field(name))

static func valid_plan(definition: Dictionary, plan: Dictionary) -> bool:
	var fields: Dictionary = definition.fields
	var required: Array = definition.required
	var args := {}
	for key in plan:
		var value: Variant = plan[key]
		if key in ["tool", "id", "expires_at"] or (key == "revision" and definition.has("catalog")):
			continue
		if key == "zone" and definition.get("scope") == "scene":
			if not valid_field("zone", value):
				return false
			continue
		if key == "changes" and value is Dictionary:
			value = value.duplicate()
			for field_name in value.keys():
				if value[field_name] == null:
					value.erase(field_name)
			if value.is_empty() and not required.has(key):
				continue
		elif (value == null or (PLACEHOLDERS.has(key) and value == PLACEHOLDERS[key])) and not required.has(key):
			continue
		if not fields.has(key) or not valid_field(fields[key], value):
			return false
		args[key] = value
	for key in required:
		if not args.has(key):
			return false
	return true

static func canonical_plan(plan: Dictionary) -> Dictionary:
	var definition := command(plan.get("tool"))
	var cleaned := plan.duplicate(true)
	for key in cleaned.keys():
		if key == "tool" or definition.required.has(key):
			continue
		if cleaned[key] == null or (PLACEHOLDERS.has(key) and cleaned[key] == PLACEHOLDERS[key]):
			cleaned.erase(key)
	return cleaned

static func _valid(value: Variant, rule: Dictionary) -> bool:
	if rule.has("$ref"):
		return valid_field(str(rule["$ref"]).get_file(), value)
	if rule.has("anyOf"):
		return rule.anyOf.any(func(option: Dictionary) -> bool: return _valid(value, option))
	if rule.has("enum") and value not in rule.enum:
		return false
	match rule.get("type"):
		"null": return value == null
		"boolean": return value is bool
		"string":
			return value is String and value.length() <= int(rule.get("maxLength", 0x7fffffff)) \
				and (not rule.has("pattern") or _matches(value, rule.pattern))
		"number":
			return (value is float or value is int) and is_finite(float(value)) \
				and value >= rule.get("minimum", -INF) and value <= rule.get("maximum", INF)
		"array":
			if not value is Array or value.size() < rule.get("minItems", 0) or value.size() > rule.get("maxItems", INF):
				return false
			var seen := {}
			for item in value:
				if not _valid(item, rule.items):
					return false
				if rule.has("uniqueBy"):
					var key: Variant = item.get(rule.uniqueBy)
					if seen.has(key):
						return false
					seen[key] = true
			return true
		"object":
			if not value is Dictionary or value.size() < rule.get("minProperties", 0):
				return false
			for key in rule.required:
				if not value.has(key):
					return false
			for key in value:
				if not rule.properties.has(key) or not _valid(value[key], rule.properties[key]):
					return false
			return true
	return false

static func _matches(value: String, pattern: String) -> bool:
	if not _patterns.has(pattern):
		_patterns[pattern] = RegEx.create_from_string(pattern)
	return _patterns[pattern].search(value) != null

static func _read(file: String) -> Dictionary:
	var content: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIRECTORY.path_join(file)))
	if content is Dictionary and content.get("version") == 1:
		return content
	push_error("Invalid command registry file: " + file)
	return {}

static func _load_commands() -> Dictionary:
	var entries := {}
	for file in DirAccess.get_files_at(DIRECTORY):
		if file == "schema.json" or file.get_extension() != "json":
			continue
		for definition in _read(file).get("commands", []):
			if not valid_definition(definition) or entries.has(definition.name):
				push_error("Invalid or duplicate command in " + file)
				continue
			entries[definition.name] = definition
	return entries

static func valid_definition(value: Variant) -> bool:
	if not value is Dictionary or not value.get("name") is String or not _matches(value.name, "^[a-z][a-z0-9_]*$") \
			or value.get("service") not in ["scene", "world", "animation", "assets", "development"] \
			or not value.get("handler") is String or value.handler.is_empty() \
			or value.get("effect") not in ["read", "write", "preview", "draft", "undo"] \
			or value.get("scope") not in ["scene", "session"] or value.get("undo") not in ["none", "scene", "prop"] \
			or not value.get("mutates_world") is bool or not value.get("fields") is Dictionary \
			or not value.get("required") is Array or not value.get("surfaces") is Array:
		return false
	for surface in value.surfaces:
		if surface not in ["palette", "f2", "mcp"]:
			return false
	for type in value.fields.values():
		if not type is String or field(type).is_empty():
			return false
	return value.required.all(func(key: Variant) -> bool: return value.fields.has(key))

static func _load_locals() -> Dictionary:
	var entries := {}
	for definition in _commands.values():
		if definition.has("local"):
			if entries.has(definition.local):
				push_error("Duplicate local command: " + str(definition.local))
				continue
			entries[definition.local] = definition
	return entries
