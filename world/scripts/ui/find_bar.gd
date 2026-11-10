extends HBoxContainer
## Find, replace and go-to-line for whichever editor the panel points it at.
## Enter finds the next match, Shift+Enter the previous one, Escape returns to the editor.
const Look = preload("res://scripts/ui/terminal_theme.gd")

var editor: TextEdit
var _mode := "find"
var _label := Label.new()
var _query := LineEdit.new()
var _replacement := LineEdit.new()
var _count := Label.new()
var _match_case := Button.new()
var _replace_button: Button
var _replace_all_button: Button
var _navigation: Array[Button] = []

## Occurrences of a query in a document, optionally case-sensitive.
static func count_matches(text: String, query: String, match_case: bool) -> int:
	if query.is_empty():
		return 0
	return text.count(query) if match_case else text.countn(query)

func _init() -> void:
	add_theme_constant_override("separation", 6)
	visible = false
	_label.add_theme_color_override("font_color", Look.ACCENT)
	_label.custom_minimum_size.x = 58
	add_child(_label)
	_query.size_flags_horizontal = SIZE_EXPAND_FILL
	_query.text_changed.connect(func(_text: String) -> void: _refresh())
	_query.gui_input.connect(_on_field_input.bind(_query))
	add_child(_query)
	_replacement.size_flags_horizontal = SIZE_EXPAND_FILL
	_replacement.placeholder_text = "Replace with"
	_replacement.gui_input.connect(_on_field_input.bind(_replacement))
	add_child(_replacement)
	_match_case.text = "Aa"
	_match_case.toggle_mode = true
	_match_case.tooltip_text = "Match case"
	_match_case.toggled.connect(func(_on: bool) -> void: _refresh())
	add_child(_match_case)
	_count.add_theme_color_override("font_color", Look.MUTED)
	_count.custom_minimum_size.x = 96
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_count)
	_navigation.append(_button("↑", "Previous match (Shift+Enter)", func() -> void: find_next(true)))
	_navigation.append(_button("↓", "Next match (Enter)", func() -> void: find_next(false)))
	_replace_button = _button("Replace", "Replace this match", replace_one)
	_replace_all_button = _button("All", "Replace every match", replace_all)
	_button("×", "Close (Escape)", close)

func _button(text: String, tooltip: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.custom_minimum_size = Vector2(34, 30)
	button.pressed.connect(callback)
	add_child(button)
	return button

## Opens in "find", "replace" or "goto" mode against the given editor.
func open(mode: String, target: TextEdit) -> void:
	editor = target
	_mode = mode
	var going := mode == "goto"
	var replacing := mode == "replace" and editor.editable
	_label.text = {"find": "Find", "replace": "Replace", "goto": "Line"}.get(mode, "Find")
	_replacement.visible = replacing
	_replace_button.visible = replacing
	_replace_all_button.visible = replacing
	_match_case.visible = not going
	for button in _navigation:
		button.visible = not going
	_query.placeholder_text = "Line number (1–%d)" % editor.get_line_count() if going else "Search this file"
	if going:
		_query.text = ""
	elif editor.has_selection() and editor.get_selection_from_line() == editor.get_selection_to_line():
		_query.text = editor.get_selected_text()
	visible = true
	_query.grab_focus()
	_query.select_all()
	_refresh()

func close() -> void:
	visible = false
	if editor != null and is_instance_valid(editor):
		editor.set_search_text("")
		editor.queue_redraw()
		editor.grab_focus()

func find_next(backwards := false) -> void:
	if editor == null or _query.text.is_empty():
		return
	var flags := _flags() | (TextEdit.SEARCH_BACKWARDS if backwards else 0)
	var line := editor.get_caret_line()
	var column := editor.get_caret_column()
	if editor.has_selection():
		line = editor.get_selection_from_line() if backwards else editor.get_selection_to_line()
		column = editor.get_selection_from_column() if backwards else editor.get_selection_to_column()
	if backwards:
		column = maxi(column - 1, 0)
	var found := editor.search(_query.text, flags, line, column)
	if found.x < 0:
		_count.text = "no matches"
		return
	editor.select(found.y, found.x, found.y, found.x + _query.text.length())
	editor.center_viewport_to_caret()

func replace_one() -> void:
	if editor == null or not editor.editable or _query.text.is_empty():
		return
	var selected := editor.get_selected_text()
	var same := selected == _query.text if _match_case.button_pressed else selected.to_lower() == _query.text.to_lower()
	if editor.has_selection() and same:
		editor.insert_text_at_caret(_replacement.text)
	find_next()
	_refresh()

func replace_all() -> void:
	if editor == null or not editor.editable or _query.text.is_empty():
		return
	var replaced := 0
	editor.begin_complex_operation()
	for line in editor.get_line_count():
		var text := editor.get_line(line)
		var hits := count_matches(text, _query.text, _match_case.button_pressed)
		if hits == 0:
			continue
		var updated := text.replace(_query.text, _replacement.text) if _match_case.button_pressed \
			else text.replacen(_query.text, _replacement.text)
		editor.set_line(line, updated)
		replaced += hits
	editor.end_complex_operation()
	_refresh()
	_count.text = "replaced %d" % replaced

func _flags() -> int:
	return TextEdit.SEARCH_MATCH_CASE if _match_case.button_pressed else 0

func _refresh() -> void:
	if editor == null or not is_instance_valid(editor):
		return
	if _mode == "goto":
		_count.text = ""
		return
	editor.set_search_text(_query.text)
	editor.set_search_flags(_flags())
	editor.queue_redraw()
	var hits := count_matches(editor.text, _query.text, _match_case.button_pressed)
	_count.text = "" if _query.text.is_empty() else ("%d match%s" % [hits, "" if hits == 1 else "es"])

func _on_field_input(event: InputEvent, field: LineEdit) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return
	if key.keycode == KEY_ESCAPE:
		field.accept_event()
		close()
	elif key.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		field.accept_event()
		if _mode == "goto":
			var line := _query.text.strip_edges().to_int()
			if line > 0:
				close()
				if editor is CodeEdit and editor.has_method("go_to_line"):
					editor.call("go_to_line", line - 1)
				else:
					editor.set_caret_line(line - 1)
					editor.center_viewport_to_caret()
		elif field == _replacement:
			replace_one()
		else:
			find_next(key.shift_pressed)
