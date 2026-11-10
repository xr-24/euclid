extends RefCounted
## Catalog and activation for data-only workshop plugins.

const DIRECTORY := "res://data/workshop_tools"
const Commands = preload("res://scripts/workshop/command_registry.gd")
const Placement = preload("res://scripts/workshop/scene_placement.gd")
const UNDO := "grid_undo_edit"
const LIMIT := 24

var _installed := {}
var _preview := {}

func _init() -> void:
	reload_committed()

func reload_committed() -> void:
	_installed.clear()
	var files := DirAccess.get_files_at(DIRECTORY) if DirAccess.dir_exists_absolute(DIRECTORY) else PackedStringArray()
	for file in files:
		if file.get_extension() != "json":
			continue
		var definition: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIRECTORY.path_join(file)))
		if valid_definition(definition) and definition.id == file.get_basename():
			_installed[_name(definition)] = definition

func preview(candidate: Dictionary, zone: String, workshop: RefCounted) -> Dictionary:
	var definition: Variant = candidate.get("workshop_tool")
	var draft: String = candidate.get("draft", "")
	if not valid_definition(definition) or draft.is_empty():
		return {"ok": false, "message": "The workshop action definition is invalid."}
	if definition.zone != zone or workshop == null:
		return {"ok": false, "message": "Return to the Grid space where this action was authored."}
	if not _preview.is_empty() and _preview.draft != draft:
		return {"ok": false, "message": "Finish the current workshop action preview first."}
	if _available(zone).size() >= LIMIT and not _available(zone).has(_name(definition)):
		return {"ok": false, "message": "This Grid space has reached its workshop action limit."}
	var valid: Dictionary = workshop.validate_action(definition.targets)
	if not valid.ok:
		return {"ok": false, "message": valid.error}
	_preview = {"draft": draft, "definition": definition.duplicate(true)}
	return {"ok": true, "message": "%s is available in Grid tools and to Codex. Running it creates an undoable Grid edit." % definition.label}

func finish(draft: String, keep: bool) -> bool:
	if _preview.get("draft") != draft:
		return false
	if keep:
		var definition: Dictionary = _preview.definition
		_installed[_name(definition)] = definition
	_preview = {}
	return true

func status(draft: String) -> String:
	return "active" if _preview.get("draft") == draft else ""

func catalog(zone: String) -> Array[Dictionary]:
	var entries: Array[Dictionary] = [_descriptor(UNDO, "Undo Grid edit", "Undo the last Grid edit, including a workshop action.", zone.sha256_text())]
	var available := _available(zone)
	var names := available.keys()
	names.sort()
	for name in names.slice(0, LIMIT):
		var definition: Dictionary = available[name]
		entries.append(_descriptor(name, definition.label, definition.description, JSON.stringify(definition).sha256_text()))
	return entries

func execute(zone: String, name: String, revision: String, workshop: RefCounted) -> Dictionary:
	for entry in catalog(zone):
		if entry.name != name or entry.revision != revision:
			continue
		if name == UNDO:
			var undone: Dictionary = workshop.execute("undo")
			return {"ok": undone.ok, "message": "Grid edit undone." if undone.ok else undone.error}
		var definition: Dictionary = _available(zone)[name]
		var result: Dictionary = workshop.run_action(definition.targets)
		return {"ok": result.ok, "message": "%s complete." % definition.label if result.ok else result.error}
	return {"ok": false, "message": "That workshop action changed or is no longer available. List the current tools."}

func _available(zone: String) -> Dictionary:
	var available := {}
	for name in _installed:
		if _installed[name].zone == zone:
			available[name] = _installed[name]
	if not _preview.is_empty():
		var definition: Dictionary = _preview.definition
		var name := _name(definition)
		available.erase(name)
		if definition.zone == zone:
			available[name] = definition
	return available

static func _name(definition: Dictionary) -> String:
	return "grid_action_" + definition.id

static func _descriptor(name: String, label: String, description: String, revision: String) -> Dictionary:
	return {"name": name, "label": label, "description": description, "revision": revision}

static func valid_definition(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 6 or value.get("schema_version") != 1 \
			or not _identifier(value.get("id"), "^[a-z][a-z0-9_]{0,31}$") \
			or not _identifier(value.get("zone"), "^[a-z0-9-]{1,64}$") \
			or not _label(value.get("label"), 48) or not _label(value.get("description"), 180) \
			or not value.get("targets") is Array or value.targets.is_empty() or value.targets.size() > 12:
		return false
	var ids := {}
	for target in value.targets:
		if not target is Dictionary or target.size() != 3 or not _identifier(target.get("id"), "^[a-f0-9]{32}$") \
				or ids.has(target.id) or not target.get("close_door") is bool or not target.get("changes") is Dictionary \
				or (target.changes.is_empty() and not target.close_door):
			return false
		for key in target.changes:
			if not _valid_field(key, target.changes[key]):
				return false
		ids[target.id] = true
	return true

static func _valid_field(key: String, value: Variant) -> bool:
	if key not in Commands.action_properties():
		return false
	return Placement.valid_coordinates(Placement.GRID, value) if key == "position" else Commands.valid_field(key, value)

static func _identifier(value: Variant, pattern: String) -> bool:
	return value is String and RegEx.create_from_string(pattern).search(value) != null

static func _label(value: Variant, limit: int) -> bool:
	return value is String and not value.strip_edges().is_empty() and value.length() <= limit \
		and RegEx.create_from_string("[\\x00-\\x1f\\x7f]").search(value) == null
