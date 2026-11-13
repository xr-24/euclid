extends RefCounted
## Per-environment piece documents. A failed write leaves the live scene and undo intact.

const Types = preload("res://scripts/pieces/piece_types.gd")
const Store = preload("res://scripts/persistence/world_state_store.gd")
const SceneStore = preload("res://scripts/persistence/scene_edit_store.gd")
const MAX_BYTES := 8 * 1024 * 1024

var pieces: Array
var history: Array[Dictionary] = []
var error := ""
var _path: String
var _base_revision: int
var _scene_props_imported := false

static func path_for(zone: String, temporary: bool) -> String:
	return "" if temporary else "user://".path_join(filename(zone))

static func filename(zone: String) -> String:
	return "environment-pieces-%s.json" % zone

func _init(path: String, defaults: Array, base_revision := 0, replacements: Array = []) -> void:
	_path = path
	_base_revision = base_revision
	pieces = defaults.duplicate(true)
	if _path.is_empty() or not FileAccess.file_exists(_path):
		return
	var file := FileAccess.open(_path, FileAccess.READ)
	var saved: Variant = JSON.parse_string(file.get_as_text()) if file and file.get_length() <= MAX_BYTES else null
	if not saved is Dictionary or saved.get("schema_version") != 1 or not Types.valid_tree(saved.get("pieces")):
		error = "The environment piece document could not be read."
		return
	_scene_props_imported = saved.get("scene_props_imported", false) == true
	var saved_revision: Variant = saved.get("base_revision", 0)
	if not valid_revision(saved_revision):
		error = "The environment piece document has an invalid base revision."
		return
	var upgrade: bool = saved_revision < base_revision
	_base_revision = maxi(int(saved_revision), base_revision)
	pieces = _add_defaults(saved.pieces, defaults, replacements) if upgrade else saved.pieces
	if not Types.valid_tree(pieces):
		pieces = defaults.duplicate(true)
		error = "The environment piece document could not be upgraded."
		return
	var undo: Variant = saved.get("undo")
	if undo is Array and undo.size() <= SceneStore.MAX_UNDO and undo.all(
			func(entry: Variant) -> bool: return entry is Dictionary and Types.valid_tree(entry.get("pieces"))):
		for entry: Dictionary in undo:
			var tree: Array = _add_defaults(entry.pieces, defaults, replacements) if upgrade else entry.pieces
			if not Types.valid_tree(tree):
				history.clear()
				break
			var edit: Dictionary = {"pieces": tree, "time": float(entry.get("time", 0.0)) if entry.get("time") is float else 0.0}
			if _valid_door_heights(entry.get("door_heights")):
				edit["door_heights"] = entry.door_heights
			history.append(edit)

func save(next: Array, undo: Array[Dictionary]) -> bool:
	if not error.is_empty() or not Types.valid_tree(next):
		return false
	var journal := SceneStore.trimmed(undo)
	if not _path.is_empty():
		var text := JSON.stringify({"schema_version": 1, "base_revision": _base_revision, "pieces": next, "undo": journal, "scene_props_imported": _scene_props_imported})
		if text.to_utf8_buffer().size() > MAX_BYTES or Store.write_text(_path, text) != OK:
			return false
	pieces = next
	history = journal
	return true

func import_scene_props(records: Array, legacy_edits: Array[Dictionary]) -> bool:
	if _scene_props_imported:
		return true
	var ids := {}
	_collect_ids(pieces, ids)
	var next: Array = pieces.duplicate()
	var previous: Array[Dictionary] = []
	for entry in legacy_edits:
		previous.append({"pieces": pieces + entry.records, "door_heights": entry.door_heights, "time": entry.time})
	var existing_history := history.duplicate()
	for record: Dictionary in records:
		if ids.has(record.id):
			return false
		next.append(record)
	# A prior piece undo should leave the imported props in place.
	for entry in existing_history:
		previous.append(entry.merged({"pieces": entry.pieces + records}, true))
	_scene_props_imported = true
	if save(next, previous):
		return true
	_scene_props_imported = false
	return false

static func _valid_door_heights(value: Variant) -> bool:
	if not value is Dictionary or value.size() > SceneStore.MAX_ENTITIES:
		return false
	for id in value:
		var height: Variant = value[id]
		if not SceneStore.valid_id(id) or not (height is float or height is int) or not is_finite(float(height)) or height < 0 or height > 10:
			return false
	return true

static func valid_revision(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= 0 and value <= 10000 and value == floorf(value)

static func _add_defaults(saved: Array, defaults: Array, replacements: Array) -> Array:
	var ids := {}
	_collect_ids(saved, ids)
	var next := saved.duplicate()
	for record: Dictionary in defaults:
		if not ids.has(record.id):
			next.append(record.duplicate(true))
		elif not replacements.is_empty():
			var index := next.find_custom(func(item: Dictionary) -> bool: return item.id == record.id)
			if index >= 0 and replacements.has(next[index]):
				next[index] = record.duplicate(true)
	return next

static func _collect_ids(tree: Array, ids: Dictionary) -> void:
	for record: Dictionary in tree:
		ids[record.id] = true
		_collect_ids(record.get("children", []), ids)
