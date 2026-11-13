extends VBoxContainer
## The inspector draws the registered piece fields and sends the same commands as an agent.

const Registry = preload("res://scripts/workshop/command_registry.gd")
const Placement = preload("res://scripts/workshop/scene_placement.gd")
const PieceEditor = preload("res://scripts/pieces/piece_editor.gd")
const Library = preload("res://scripts/asset_library.gd")
const Types = preload("res://scripts/pieces/piece_types.gd")

var _editor: PieceEditor
var _list := OptionButton.new()
var _parent := OptionButton.new()
var _types := OptionButton.new()
var _fields := VBoxContainer.new()
var _notice := Label.new()
var _apply: Button
var _remove: Button
var _undo: Button
var _add: Button
var _selected := ""
var _placement: Array
var _field_controls := {}
var _revision := {}
var _rendered := false

func setup(editor: PieceEditor, placement: Array, selected: String, close: Callable) -> void:
	_editor = editor
	_placement = placement
	_selected = selected
	var heading := HBoxContainer.new()
	add_child(heading)
	var title := Label.new()
	title.text = "Pieces"
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	heading.add_child(title)
	_button(heading, "Close", close)
	_row("Piece", _list)
	_list.item_selected.connect(func(index: int) -> void: select_piece(_list.get_item_metadata(index)))
	_row("Add type", _types)
	for type in Types.types():
		_types.add_item(Types.types()[type].label)
		_types.set_item_metadata(_types.item_count - 1, type)
	_row("Parent", _parent)
	_add = _button(self, "Add piece", _create)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_fields.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(_fields)
	var actions := HBoxContainer.new()
	add_child(actions)
	_apply = _button(actions, "Apply", _edit)
	_remove = _button(actions, "Remove", _confirm_remove)
	_undo = _button(actions, "Undo piece", func() -> void: _run({"tool": "undo_piece"}))
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_notice)
	_editor.changed.connect(_refresh)
	_refresh()

func selected_piece() -> String:
	return _selected

func select_piece(id: String) -> void:
	_selected = id
	_rendered = false
	_refresh()

func _refresh() -> void:
	var result := _editor.execute({"tool": "list_pieces"})
	var parent: Variant = _parent.get_selected_metadata() if _parent.selected >= 0 else ""
	_list.clear()
	_list.add_item("Choose a piece")
	_list.set_item_metadata(0, "")
	_parent.clear()
	_parent.add_item("Environment")
	_parent.set_item_metadata(0, "")
	var levels := {"": 0}
	for item in _editor.summaries():
		var depth: int = levels[item.parent]
		levels[item.id] = depth + 1
		var label: String = "  ".repeat(depth) + item.name
		for menu in [_list, _parent]:
			menu.add_item(label)
			menu.set_item_metadata(menu.item_count - 1, item.id)
		if item.id == _selected:
			_list.select(_list.item_count - 1)
		if item.id == parent:
			_parent.select(_parent.item_count - 1)
	var record := _editor.record(_selected)
	record.erase("children")
	if record.is_empty():
		_selected = ""
	_apply.disabled = record.is_empty() or not _editor.can_edit()
	_remove.disabled = _apply.disabled
	_undo.disabled = not result.get("can_undo", false) or not _editor.can_edit()
	_add.disabled = not _editor.can_edit()
	if not _rendered or record != _revision:
		_rendered = true
		_revision = record
		_show_fields(record)

func _show_fields(record: Dictionary) -> void:
	for child in _fields.get_children():
		_fields.remove_child(child)
		child.queue_free()
	_field_controls.clear()
	if record.is_empty():
		return
	var fields := _editor.fields(record.type)
	for key in fields:
		if key in ["id", "type"] or (Types.types()[record.type].get("fixed_transform", false) and key in ["position", "rotation", "scale"]):
			continue
		_add_field(key, fields[key], record.get(key), _field_controls, _fields)

func _add_field(key: String, field: Dictionary, value: Variant, inputs: Dictionary, parent: Control) -> void:
	if field.has("$ref"):
		field = Registry.field(str(field["$ref"]).get_file())
	if field.get("type") == "object":
		var label := Label.new()
		label.text = key.capitalize()
		parent.add_child(label)
		var group := {}
		for property in field.properties:
			_add_field(property, field.properties[property], value.get(property) if value is Dictionary else null, group, parent)
		inputs[key] = {"children": group}
		return
	var control: Control
	if field.get("catalog") == "vegetation":
		var choices := OptionButton.new()
		choices.fit_to_longest_item = false
		choices.add_item("Choose a plant or rock")
		for id: String in Library.ids():
			var item := Library.info(id)
			if item.category not in ["plant", "tree", "rock"] or not Library.has(id):
				continue
			choices.add_item(item.get("title", id))
			choices.set_item_metadata(choices.item_count - 1, id)
			if id == value:
				choices.select(choices.item_count - 1)
		control = choices
	elif field.has("enum") or field.get("type") == "boolean":
		var options := OptionButton.new()
		if value == null:
			options.add_item("Default")
		for choice in field.get("enum", [true, false]):
			options.add_item(str(choice).capitalize())
			options.set_item_metadata(options.item_count - 1, choice)
			if choice == value:
				options.select(options.item_count - 1)
		control = options
	elif field.get("type") == "array" and field.get("items", {}).get("type") == "object":
		var text := TextEdit.new()
		text.custom_minimum_size.y = 112
		if value is Array:
			var lines := PackedStringArray()
			for item in value:
				lines.append("  " + JSON.stringify(item))
			text.text = "[\n" + ",\n".join(lines) + "\n]"
		control = text
	else:
		var text := LineEdit.new()
		text.text = _display_value(value, field)
		if field.get("type") == "array":
			text.placeholder_text = "[x, y, z]"
		control = text
	var row := _row(key.capitalize(), control, parent)
	row.tooltip_text = field.get("description", "")
	inputs[key] = {"control": control, "type": field.get("type", ""), "initial": _read(control)}

static func _display_value(value: Variant, field: Dictionary) -> String:
	if value == null:
		return ""
	if value is String:
		return value
	if value is Array and field.get("items", {}).get("type") == "number":
		var parts := PackedStringArray()
		for number in value:
			parts.append(String.num(float(number), 4))
		return "[" + ", ".join(parts) + "]"
	return JSON.stringify(value)

func _create() -> void:
	var type: String = _types.get_selected_metadata()
	var plan := {"tool": "add_piece", "target": type}
	var parent: String = _parent.get_selected_metadata()
	if not parent.is_empty():
		plan["parent"] = parent
	var missing: Array = Types.types()[type].required.filter(func(key: String) -> bool:
		return not Types.types()[type].get("defaults", {}).has(key))
	if missing.is_empty():
		_run(plan, true)
		return
	# Gather required fields with no default before writing a piece.
	var dialog := ConfirmationDialog.new()
	dialog.title = "Add " + str(Types.types()[type].label)
	var rows := VBoxContainer.new()
	dialog.add_child(rows)
	var entries := {}
	var fields := _editor.fields(type)
	for key in missing:
		_add_field(key, fields[key], null, entries, rows)
	dialog.confirmed.connect(func() -> void:
		var result := _changes(entries)
		if result.has("error"):
			_notice.text = result.error
			return
		plan["piece_values"] = result.values
		_run(plan, true))
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()

func _edit() -> void:
	var result := _changes(_field_controls)
	if result.has("error"):
		_notice.text = result.error
		return
	_run({"tool": "edit_piece", "target": _selected, "piece_values": result.values})

func _confirm_remove() -> void:
	var id := _selected
	var dialog := ConfirmationDialog.new()
	dialog.title = "Remove piece"
	dialog.dialog_text = "Remove this piece and its children?"
	dialog.confirmed.connect(func() -> void: _run({"tool": "remove_piece", "target": id}))
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()

func _run(plan: Dictionary, select_added := false) -> void:
	var result := _editor.execute(plan, _placement)
	_notice.text = result.message
	if result.ok and select_added:
		select_piece(result.id)

static func _changes(inputs: Dictionary) -> Dictionary:
	var values := {}
	for key in inputs:
		var field: Dictionary = inputs[key]
		if field.has("children"):
			var nested := _changes(field.children)
			if nested.has("error"):
				return nested
			if not nested.values.is_empty():
				values[key] = nested.values
			continue
		var value: Variant = _read(field.control)
		if value == field.initial:
			continue
		if value == null or (value is String and value.is_empty()):
			return {"error": "Enter a value for %s." % key.capitalize()}
		if field.type in ["array", "number"]:
			value = JSON.parse_string(value)
			if value == null:
				return {"error": "Check the format of %s." % key.capitalize()}
		values[key] = value
	return {"values": values}

static func _read(control: Control) -> Variant:
	if control is OptionButton:
		return control.get_selected_metadata()
	if control is TextEdit:
		return control.text.strip_edges()
	return (control as LineEdit).text.strip_edges()

func _row(text: String, input: Control, parent: Control = null) -> HBoxContainer:
	var row := HBoxContainer.new()
	(parent if parent else self).add_child(row)
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = 112
	row.add_child(label)
	input.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(input)
	return row

static func _button(parent: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)
	return button
