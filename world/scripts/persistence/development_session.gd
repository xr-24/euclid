extends RefCounted
## Local presentation state. Git draft versions and check results live in the gateway.

const Store = preload("res://scripts/persistence/world_state_store.gd")
const TABS := ["Source", "Diff", "Checks", "Revision"]
const MAX_LINES := 300
const MAX_PROMPTS := 100
const MAX_LINE_LENGTH := 2048
const MAX_PROMPT_LENGTH := 240
const MAX_BYTES := 4 * 1024 * 1024

var lines := PackedStringArray()
var prompts := PackedStringArray()
var file := ""
var tab := ""
var _path: String

func _init(path: String) -> void:
	_path = path
	var stream := FileAccess.open(path, FileAccess.READ)
	if stream == null or stream.get_length() > MAX_BYTES:
		return
	var state: Variant = JSON.parse_string(stream.get_as_text())
	if not state is Dictionary or state.get("schema_version") != 1:
		return
	lines = _strings(state.get("lines"), MAX_LINES, MAX_LINE_LENGTH)
	prompts = _strings(state.get("prompts"), MAX_PROMPTS, MAX_PROMPT_LENGTH)
	var view: Variant = state.get("view")
	if view is Dictionary:
		if view.get("file") is String:
			file = view.file.left(256)
		if view.get("tab") in TABS:
			tab = view.tab

func save_console(entries: PackedStringArray, submitted: PackedStringArray) -> void:
	lines = _strings(Array(entries), MAX_LINES, MAX_LINE_LENGTH)
	prompts = _strings(Array(submitted), MAX_PROMPTS, MAX_PROMPT_LENGTH)
	_save()

func save_view(selected_file: String, selected_tab: String) -> void:
	if selected_file == file and selected_tab == tab:
		return
	file = selected_file
	tab = selected_tab
	_save()

func _save() -> void:
	Store.write_json(_path, {"schema_version": 1, "lines": Array(lines), "prompts": Array(prompts),
		"view": {"file": file, "tab": tab}})

static func _strings(values: Variant, count: int, length: int) -> PackedStringArray:
	var result := PackedStringArray()
	if values is Array:
		for index in range(maxi(0, values.size() - count), values.size()):
			if values[index] is String:
				result.append(values[index].left(length))
	return result
