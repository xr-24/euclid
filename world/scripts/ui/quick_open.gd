extends PopupPanel
## Ctrl+P file finder: type part of a path, pick with the arrow keys and Enter.
signal chosen(path: String)

const Look = preload("res://scripts/ui/terminal_theme.gd")
const SHOWN := 60

var files := PackedStringArray()
var _query := LineEdit.new()
var _results := ItemList.new()

## A fuzzy match score, or -1. Characters must appear in order. A match inside the file name
## beats one spread across folders, whole-substring matches and word starts score higher, and
## shorter paths win ties.
static func score(query: String, path: String) -> int:
	if query.is_empty():
		return 1
	var needle := query.to_lower().replace(" ", "")
	var hay := path.to_lower()
	var name_start := hay.rfind("/") + 1
	var best := _walk(needle, hay, name_start)
	if best >= 0:
		best += 40
	else:
		best = _walk(needle, hay, 0)
		if best < 0:
			return -1
	var exact := hay.find(needle)
	if exact >= 0:
		best += 30 + (30 if exact >= name_start else 0)
	return maxi(best * 4 - path.length(), 1)

static func _walk(needle: String, hay: String, from: int) -> int:
	var at := from
	var total := 0
	var run := 0
	for index in needle.length():
		var found := hay.find(needle[index], at)
		if found < 0:
			return -1
		run = run + 1 if found == at and index > 0 else 0
		total += 10 + run * 6
		if found == 0 or hay[found - 1] in ["/", "_", "-", "."]:
			total += 6
		at = found + 1
	return total

func _init() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	add_child(column)
	_query.placeholder_text = "Go to file…"
	_query.text_changed.connect(func(_text: String) -> void: _refresh())
	_query.gui_input.connect(_on_query_input)
	_query.text_submitted.connect(func(_text: String) -> void: _choose())
	column.add_child(_query)
	_results.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_results.custom_minimum_size = Vector2(620, 360)
	_results.item_activated.connect(func(_index: int) -> void: _choose())
	column.add_child(_results)

func open(paths: PackedStringArray, owner_theme: Theme) -> void:
	files = paths
	theme = owner_theme
	_query.text = ""
	_refresh()
	popup_centered(Vector2i(660, 430))
	_query.grab_focus()

func _refresh() -> void:
	var ranked := []
	for path in files:
		var value := score(_query.text, path)
		if value > 0:
			ranked.append([value, path])
	ranked.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0] or (a[0] == b[0] and a[1] < b[1]))
	_results.clear()
	for entry in ranked.slice(0, SHOWN):
		var path: String = entry[1]
		var index := _results.add_item(path.get_file() + "    " + path.get_base_dir())
		_results.set_item_metadata(index, path)
	if _results.item_count > 0:
		_results.select(0)

func _choose() -> void:
	var picked := _results.get_selected_items()
	if picked.is_empty():
		return
	var path: String = _results.get_item_metadata(picked[0])
	hide()
	chosen.emit(path)

func _on_query_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or _results.item_count == 0:
		return
	var step := 0
	if key.keycode == KEY_DOWN:
		step = 1
	elif key.keycode == KEY_UP:
		step = -1
	if step == 0:
		return
	var picked := _results.get_selected_items()
	var current := picked[0] if not picked.is_empty() else 0
	var next := clampi(current + step, 0, _results.item_count - 1)
	_results.select(next)
	_results.ensure_current_is_visible()
	_query.accept_event()
