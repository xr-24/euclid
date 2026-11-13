extends VBoxContainer
## The inspector draws the registered piece fields and sends the same commands as an agent.

const Registry = preload("res://scripts/workshop/command_registry.gd")
const Placement = preload("res://scripts/workshop/scene_placement.gd")
const PieceEditor = preload("res://scripts/pieces/piece_editor.gd")
const Videos = preload("res://scripts/assets/video_library.gd")
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
var _video_importing := false
var _facing := 0.0

func setup(editor: PieceEditor, placement: Array, selected: String, close: Callable, facing := 0.0) -> void:
	_editor = editor
	_placement = placement
	_facing = facing
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

func _video_options(key: String, value: Variant, inputs: Dictionary, parent: Control) -> void:
	var options := OptionButton.new()
	options.fit_to_longest_item = false
	_fill_videos(options, value)
	var row := _row("Video", options, parent)
	_button(row, "Import…", _browse_video.bind(options))
	inputs[key] = {"control": options, "type": "string", "allow_empty": true, "initial": _read(options)}

func _browse_video(options: OptionButton) -> void:
	if _video_importing:
		return
	var chooser := FileDialog.new()
	chooser.title = "Import local video"
	chooser.access = FileDialog.ACCESS_FILESYSTEM
	chooser.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	chooser.filters = PackedStringArray(["*.ogv,*.mp4,*.m4v,*.mov,*.webm,*.mkv ; Video"])
	add_child(chooser)
	chooser.file_selected.connect(_import_video.bind(options))
	chooser.file_selected.connect(func(_path: String) -> void: chooser.queue_free())
	chooser.canceled.connect(chooser.queue_free)
	chooser.popup_centered_ratio(0.65)

func _import_video(path: String, options: OptionButton) -> void:
	_video_importing = true
	_notice.text = "Importing video…"
	var result := {}
	var task := WorkerThreadPool.add_task(func() -> void: result.merge(Videos.import_local(path)), false, "Import local video")
	while not WorkerThreadPool.is_task_completed(task):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	_video_importing = false
	if not result.ok:
		_notice.text = result.message
		return
	if is_instance_valid(options):
		_fill_videos(options, result.id)
	_notice.text = "Video imported. Apply to show it on this screen."

func _fill_videos(options: OptionButton, selected: Variant) -> void:
	options.clear()
	options.add_item("No video")
	options.set_item_metadata(0, "")
	for item: Dictionary in Videos.installed():
		options.add_item(item.name)
		var index := options.item_count - 1
		options.set_item_metadata(index, item.id)
		if item.id == selected:
			options.select(index)
	if selected is String and not selected.is_empty() and options.selected == 0:
		options.add_item("Video unavailable")
		options.set_item_metadata(options.item_count - 1, selected)
		options.select(options.item_count - 1)

func _add_field(key: String, field: Dictionary, value: Variant, inputs: Dictionary, parent: Control) -> void:
	if field.has("$ref"):
		field = Registry.field(str(field["$ref"]).get_file())
	if field.get("catalog") == "local_video":
		_video_options(key, value, inputs, parent)
		return
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
	var definition: Dictionary = Types.types()[type]
	var missing: Array = definition.required.filter(func(key: String) -> bool:
		return not definition.get("defaults", {}).has(key))
	if missing.is_empty():
		if definition.has("placement_yaw") and parent.is_empty() and not _placement.is_empty():
			var at := _placement.duplicate()
			at[1] += float(definition.get("placement_lift", 0.0))
			plan["piece_values"] = {"position": at, "rotation": [0, wrapf(_facing + float(definition.placement_yaw), -180.0, 180.0), 0]}
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
		if value == null or (value is String and value.is_empty() and not field.get("allow_empty", false)):
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
