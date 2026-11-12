extends RefCounted
## Adapts the Workbench's version 1 appearance file to declared piece fields.

const Editor = preload("res://scripts/pieces/piece_editor.gd")
const Types = preload("res://scripts/pieces/piece_types.gd")
const PATH := "res://data/grid_appearance.json"
const DEFAULT := {"schema_version": 1, "floor_spacing": 2.0, "wall_height": 1.0}

var _committed := _read_committed()
var _draft := {}
var _editor: Editor
var _bindings := {}

func profile() -> Dictionary:
	var current: Dictionary = _draft.get("profile", _committed)
	return {"values": current.duplicate(), "preview": not _draft.is_empty()}

func attach(editor: Editor, bindings: Dictionary) -> void:
	_editor = editor
	_bindings = bindings
	_refresh()

func available() -> bool:
	return _editor != null and _bindings.values().any(func(binding: Dictionary) -> bool:
		return _editor.node_for(binding.id) != null)

func preview(candidate: Dictionary) -> Dictionary:
	var id: String = candidate.get("draft", "")
	var appearance: Variant = candidate.get("grid")
	if not available():
		return {"ok": false, "message": "Enter a Grid space to preview its scenery."}
	if id.is_empty() or not valid_profile(appearance):
		return {"ok": false, "message": "The Grid draft has invalid scenery settings."}
	if not _draft.is_empty() and _draft.id != id:
		return {"ok": false, "message": "Finish the current Grid preview first."}
	_draft = {"id": id, "profile": appearance.duplicate()}
	_refresh()
	return {"ok": true, "message": "Grid scenery reloaded. Close the panel to look around."}

func status(id: String) -> String:
	return "active" if _draft.get("id") == id and available() else ""

func finish(id: String, keep: bool) -> bool:
	if _draft.get("id") != id:
		return false
	if keep:
		_committed = _draft.profile
	_draft = {}
	_refresh()
	return true

func reload_committed() -> void:
	_committed = _read_committed()
	_refresh()

func _refresh() -> void:
	if _editor == null:
		return
	_editor.set_appearance(Callable() if _bindings.is_empty() else project.bind(_bindings, profile()))

## Committed appearance supplies defaults. A preview temporarily takes precedence over local
## values, and neither operation writes to the user's document.
static func project(records: Array, bindings: Dictionary, appearance: Dictionary) -> Array:
	if bindings.is_empty() or not appearance.has("values"):
		return records
	var result := records.duplicate()
	for index in result.size():
		var record: Dictionary = result[index]
		var updated := record.duplicate()
		for key in bindings:
			var binding: Dictionary = bindings[key]
			if binding.id != record.id or not appearance.values.has(key):
				continue
			var path: Array = binding.path
			var field: String = path[-1]
			var fields := updated
			if path.size() == 2:
				var nested: Variant = updated.get(path[0], {})
				if not nested is Dictionary:
					continue
				fields = nested.duplicate()
			if fields.has(field) and not appearance.preview:
				continue
			fields[field] = appearance.values[key]
			if path.size() == 2:
				updated[path[0]] = fields
		if record.has("children"):
			updated["children"] = project(record.children, bindings, appearance)
		if Types.valid(updated):
			result[index] = updated
	return result

static func _read_committed() -> Dictionary:
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return saved if valid_profile(saved) else DEFAULT.duplicate()

static func valid_profile(value: Variant) -> bool:
	return value is Dictionary and value.size() == 3 and value.get("schema_version") == 1 \
		and _number(value.get("floor_spacing"), 1.0, 8.0) and _number(value.get("wall_height"), 0.5, 1.5)

static func _number(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= minimum and value <= maximum
