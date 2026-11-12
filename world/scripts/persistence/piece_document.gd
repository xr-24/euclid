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

static func path_for(zone: String, temporary: bool) -> String:
	return "" if temporary else "user://".path_join(filename(zone))

static func filename(zone: String) -> String:
	return "environment-pieces-%s.json" % zone

func _init(path: String, defaults: Array) -> void:
	_path = path
	pieces = defaults.duplicate(true)
	if _path.is_empty() or not FileAccess.file_exists(_path):
		return
	var file := FileAccess.open(_path, FileAccess.READ)
	var saved: Variant = JSON.parse_string(file.get_as_text()) if file and file.get_length() <= MAX_BYTES else null
	if not saved is Dictionary or saved.get("schema_version") != 1 or not Types.valid_tree(saved.get("pieces")):
		error = "The environment piece document could not be read."
		return
	pieces = saved.pieces
	var undo: Variant = saved.get("undo")
	if undo is Array and undo.size() <= SceneStore.MAX_UNDO and undo.all(
			func(entry: Variant) -> bool: return entry is Dictionary and Types.valid_tree(entry.get("pieces"))):
		history.assign(undo)

func save(next: Array, undo: Array[Dictionary]) -> bool:
	if not error.is_empty() or not Types.valid_tree(next):
		return false
	var journal := SceneStore.trimmed(undo)
	if not _path.is_empty():
		var text := JSON.stringify({"schema_version": 1, "pieces": next, "undo": journal})
		if text.to_utf8_buffer().size() > MAX_BYTES or Store.write_text(_path, text) != OK:
			return false
	pieces = next
	history = journal
	return true
