extends VBoxContainer
## Palette and inspector for the same commands available to other tool clients.

signal agent_requested(prompt: String, placement: Array)

const EntityTypes = preload("res://scripts/workshop/entity_types.gd")
const Commands = preload("res://scripts/workshop/command_registry.gd")
const BehaviorInspector = preload("res://scripts/ui/behavior_inspector.gd")
const Placement = preload("res://scripts/workshop/scene_placement.gd")
const API_VERSION := 1

var _tools: RefCounted
var _spawn_at: Array
var _selected := ""
var _entities: OptionButton
var _fields := {}
var _numeric_fields := {}
var _form_baseline := {}
var _color: ColorPickerButton
var _color_label: Label
var _name: LineEdit
var _library: OptionButton
var _place_asset: Button
var _status: Label
var _apply: Button
var _delete: Button
var _restore_authored: Button
var _duplicate: Button
var _undo: Button
var _reset_shape: Button
var _behaviors: BehaviorInspector
var _prefabs: OptionButton
var _prefab_name: LineEdit
var _save_prefab: Button
var _place_prefab: Button
var _agent_input: LineEdit
var _agent_button: Button
var _registered_actions: MenuButton
var _action_catalog: Callable
var _run_action: Callable
var _action_entries: Array[Dictionary] = []

func setup(tools: RefCounted, spawn_at: Vector3, selected: String, catalog: Callable, run_action: Callable) -> bool:
	_tools = tools
	_spawn_at = Placement.coordinates(spawn_at)
	_selected = selected
	_action_catalog = catalog
	_run_action = run_action
	add_theme_constant_override("separation", 10)
	var spawn_row := HFlowContainer.new()
	add_child(spawn_row)
	for type in Commands.built_in_props():
		var definition: Dictionary = EntityTypes.TYPES[type]
		_button(spawn_row, definition.get("palette_label", "Spawn " + definition.label), _spawn.bind(type))
	var library_row := HBoxContainer.new()
	add_child(library_row)
	_library = OptionButton.new()
	_library.fit_to_longest_item = false
	_library.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	library_row.add_child(_library)
	_place_asset = _button(library_row, "Place asset", _place_selected_asset)
	_place_asset.size_flags_horizontal = Control.SIZE_SHRINK_END
	_library.item_selected.connect(func(index: int) -> void: _place_asset.disabled = index <= 0)
	_load_library()
	_entities = OptionButton.new()
	add_child(_entities)
	_entities.item_selected.connect(_select)
	_name = LineEdit.new()
	_name.max_length = Commands.field("prop_name").maxLength
	_name.placeholder_text = "Prop name"
	add_child(_name)
	var properties := GridContainer.new()
	properties.columns = 3
	add_child(properties)
	var bounds: AABB = _tools.bounds
	var position_step: float = Commands.field("position").multipleOfHint
	var specs := []
	for axis in 3:
		specs.append(["XYZ"[axis], bounds.position[axis], bounds.end[axis], position_step])
	for key in Commands.prop_fields(false):
		var rule := Commands.field(key)
		if rule.get("type") == "number":
			specs.append([rule.title, rule.minimum, rule.maximum, rule.multipleOfHint])
			_numeric_fields[key] = rule.title
	for spec in specs:
		var field := VBoxContainer.new()
		properties.add_child(field)
		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var label := Label.new()
		label.text = spec[0]
		field.add_child(label)
		var value := SpinBox.new()
		value.min_value = spec[1]
		value.max_value = spec[2]
		value.step = spec[3]
		field.add_child(value)
		_fields[spec[0]] = value
	var color_field := VBoxContainer.new()
	properties.add_child(color_field)
	color_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_color_label = Label.new()
	color_field.add_child(_color_label)
	_color = ColorPickerButton.new()
	_color.edit_alpha = false
	_color.custom_minimum_size.y = 30
	_color.tooltip_text = "Choose a color, then select Apply"
	_color.color_changed.connect(_show_color_code)
	color_field.add_child(_color)
	_show_color_code(_color.color)
	var actions := HFlowContainer.new()
	add_child(actions)
	var action_buttons := {}
	for definition in Commands.catalog():
		var ui: Dictionary = definition.get("palette", {})
		if ui.get("group") != "actions":
			continue
		var callback := Callable(self, ui.callback) if ui.has("callback") else _run.bind(definition.local, {})
		var button := _button(actions, ui.label, callback)
		if ui.has("role"):
			action_buttons[ui.role] = button
	_apply = action_buttons["apply"]
	_duplicate = action_buttons["duplicate"]
	_delete = action_buttons["delete"]
	_restore_authored = action_buttons["restore_authored"]
	_undo = action_buttons["undo"]
	_reset_shape = _button(actions, "Reset shape", func() -> void: _run("edit", {"changes": {"stretch": [1.0, 1.0, 1.0]}}))
	_reset_shape.visible = false
	_registered_actions = MenuButton.new()
	_registered_actions.text = "Workshop actions"
	actions.add_child(_registered_actions)
	_registered_actions.about_to_popup.connect(_refresh_actions)
	_registered_actions.get_popup().id_pressed.connect(_invoke_action)
	_behaviors = BehaviorInspector.new()
	add_child(_behaviors)
	_behaviors.submitted.connect(func(value: Variant) -> void: _run("set_behavior", {"behavior": value}))
	var save_row := HBoxContainer.new()
	add_child(save_row)
	_prefab_name = LineEdit.new()
	_prefab_name.placeholder_text = "Prefab name"
	_prefab_name.max_length = Commands.field("prefab_name").maxLength
	_prefab_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_row.add_child(_prefab_name)
	_save_prefab = _button(save_row, "Save prefab", _save_selected_prefab)
	_save_prefab.size_flags_horizontal = Control.SIZE_SHRINK_END
	var place_row := HBoxContainer.new()
	add_child(place_row)
	_prefabs = OptionButton.new()
	_prefabs.fit_to_longest_item = false
	_prefabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	place_row.add_child(_prefabs)
	_place_prefab = _button(place_row, "Place prefab", _place_selected_prefab)
	_place_prefab.size_flags_horizontal = Control.SIZE_SHRINK_END
	_prefabs.item_selected.connect(func(index: int) -> void: _place_prefab.disabled = index <= 0)
	var agent_row := HBoxContainer.new()
	add_child(agent_row)
	_agent_input = LineEdit.new()
	_agent_input.placeholder_text = "Make me an orange cone"
	_agent_input.max_length = 240
	_agent_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	agent_row.add_child(_agent_input)
	_agent_button = _button(agent_row, "Ask Codex", _send_agent_request)
	_agent_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	_agent_input.text_submitted.connect(func(_text: String) -> void: _send_agent_request())
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)
	_refresh()
	_refresh_prefabs()
	return true

func capture_view() -> Dictionary:
	var fields := {}
	for key in _fields:
		var input: SpinBox = _fields[key]
		fields[key] = {"value": input.value, "text": input.get_line_edit().text}
	var point := Vector3.INF if _spawn_at.is_empty() else Vector3(_spawn_at[0], _spawn_at[1], _spawn_at[2])
	return {"selected": _selected, "spawn_at": point, "name": _name.text,
		"fields": fields, "color": _color.color, "behavior": _behaviors.capture_view(),
		"library": _library.get_selected_metadata() if _library.selected > 0 else "",
		"prefab": _prefabs.get_selected_metadata() if _prefabs.selected > 0 else "",
		"prefab_name": _prefab_name.text, "prompt": _agent_input.text}

func restore_view(view: Dictionary) -> bool:
	if view.get("selected", "") == _selected:
		var fields: Dictionary = view.get("fields", {})
		for key in fields:
			if _fields.has(key):
				var input: SpinBox = _fields[key]
				input.value = fields[key].value
				input.get_line_edit().text = fields[key].text
		_color.color = view.get("color", _color.color)
		_show_color_code(_color.color)
		_name.text = view.get("name", _name.text)
		_behaviors.restore_view(view.get("behavior", {}))
	for index in range(1, _library.item_count):
		if _library.get_item_metadata(index) == view.get("library"):
			_library.select(index)
			_place_asset.disabled = false
			break
	_refresh_prefabs(view.get("prefab", ""))
	_prefab_name.text = view.get("prefab_name", "")
	_agent_input.text = view.get("prompt", "")
	return true

func _send_agent_request() -> void:
	var prompt := _agent_input.text.strip_edges()
	if prompt.is_empty() or _agent_button.disabled:
		return
	if not _can_place():
		return
	_agent_button.disabled = true
	_status.text = "Codex is planning a scene edit…"
	agent_requested.emit(prompt, _spawn_at.duplicate())

func finish_agent_request(result: Dictionary) -> void:
	_agent_button.disabled = false
	if not result.get("ok", false):
		_status.text = str(result.error)
		return
	_selected = result.id
	_refresh()
	_status.text = "Codex created a traffic cone. You can edit it or undo."

func _button(parent: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 36
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _spawn(type := "traffic_cone") -> void:
	if _can_place():
		_run("spawn", {"type": type, "position": _spawn_at})

func _load_library() -> void:
	_library.add_item("Choose an installed prop")
	var result: Dictionary = _tools.execute("list_scene_assets")
	for entry in result.get("assets", []):
		_library.add_item(entry.name)
		var index := _library.item_count - 1
		_library.set_item_metadata(index, entry.id)
		_library.get_popup().set_item_tooltip(index, entry.license)
	_library.select(0)
	_place_asset.disabled = true

func _place_selected_asset() -> void:
	if _can_place():
		_run("spawn", {"type": "library_model", "asset_id": _library.get_selected_metadata(), "position": _spawn_at})

func _can_place() -> bool:
	if _spawn_at.is_empty():
		_status.text = "Aim at solid ground and reopen the palette to place a prop."
		return false
	return true

func _save_selected_prefab() -> void:
	var result: Dictionary = _tools.execute("save_prefab", {"id": _selected, "name": _prefab_name.text})
	if not result.ok:
		_status.text = result.error
		return
	_prefab_name.clear()
	_refresh_prefabs(result.prefab_id)
	_status.text = "Saved %s to the prefab library." % result.name

func _place_selected_prefab() -> void:
	if _can_place():
		_run("spawn_prefab", {"prefab_id": _prefabs.get_selected_metadata(), "position": _spawn_at})

func _refresh_prefabs(selected := "") -> void:
	_prefabs.clear()
	_prefabs.add_item("Choose a prefab")
	var result: Dictionary = _tools.execute("list_prefabs")
	var index := 0
	for prefab in result.get("prefabs", []):
		_prefabs.add_item(prefab.name)
		var row := _prefabs.item_count - 1
		_prefabs.set_item_metadata(row, prefab.id)
		if prefab.id == selected:
			index = row
	_prefabs.select(index)
	_place_prefab.disabled = index == 0
	if not result.ok:
		_status.text = result.error

func _form_values() -> Dictionary:
	var point := []
	for axis in ["X", "Y", "Z"]:
		point.append(_fields[axis].value)
	var changes := {"position": point, "name": _name.text}
	for key in _numeric_fields:
		changes[key] = _fields[_numeric_fields[key]].value
	if not _color.disabled:
		changes["color"] = _color.color.to_html(false)
	return changes

func _apply_changes() -> void:
	var changes := _form_values()
	for key in _form_baseline:
		if changes.get(key) == _form_baseline[key]:
			changes.erase(key)
	if changes.is_empty():
		_status.text = "No property changes."
		return
	_run("edit", {"changes": changes})

func _run(tool: String, args: Dictionary) -> void:
	var request := args.duplicate()
	request["id"] = _selected
	var result: Dictionary = _tools.execute(tool, request)
	if not result.ok:
		_status.text = result.error
		return
	if not result.id.is_empty():
		_selected = result.id if not result.entity.is_empty() else ""
	_refresh()
	var messages := {"spawn": "Entity created.", "spawn_prefab": "Prefab placed.", "duplicate": "Entity duplicated.",
		"edit": "Properties saved.", "set_behavior": "Behavior saved.", "delete": "Entity deleted.", "undo": "Edit undone.",
		"restore_dressing": "Authored placement restored."}
	if tool == "delete" and result.entity.get("hidden", false):
		messages["delete"] = "Authored prop hidden."
	_status.text = "Behavior preview updated." if result.get("preview", false) else messages[tool]

func _refresh() -> void:
	_refresh_actions()
	_entities.clear()
	_entities.add_item("Select an entity")
	_entities.set_item_metadata(0, "")
	var result: Dictionary = _tools.execute("list")
	var index := 0
	if result.ok:
		for record in result.entities:
			var prefix := "Hidden · " if record.get("hidden", false) else ""
			_entities.add_item("%s%s  ·  %s" % [prefix, EntityTypes.label(record), record.id.left(6)])
			var row := _entities.item_count - 1
			_entities.set_item_metadata(row, record.id)
			if record.id == _selected:
				index = row
	_undo.disabled = not result.get("can_undo", false)
	_entities.select(index)
	_select(index)
	if not result.ok:
		_status.text = result.error

func _refresh_actions() -> void:
	_action_entries.clear()
	var popup := _registered_actions.get_popup()
	popup.clear()
	for entry in _action_catalog.call():
		if entry.name == "grid_undo_edit":
			continue
		popup.add_item(entry.label, _action_entries.size())
		popup.set_item_tooltip(_action_entries.size(), entry.description)
		_action_entries.append(entry)
	_registered_actions.visible = not _action_entries.is_empty()

func _invoke_action(index: int) -> void:
	if index >= 0 and index < _action_entries.size():
		var result: Dictionary = _run_action.call(_action_entries[index])
		_refresh()
		_status.text = result.message

func _select(index: int) -> void:
	_selected = _entities.get_item_metadata(index)
	var result: Dictionary = _tools.execute("inspect", {"id": _selected})
	var record: Dictionary = result.get("entity", {})
	var authored: bool = record.get("authored", false)
	var editable: bool = result.ok and not record.get("hidden", false)
	_apply.disabled = not editable
	_duplicate.disabled = not editable or authored
	_duplicate.visible = not authored
	_delete.disabled = not editable
	_delete.text = "Hide" if authored else "Delete"
	_restore_authored.visible = authored and record.get("overridden", false)
	var stretch: Variant = record.get("stretch", [1.0, 1.0, 1.0])
	_reset_shape.visible = editable and stretch is Array and stretch != [1.0, 1.0, 1.0] and stretch != [1, 1, 1]
	_save_prefab.disabled = not editable or authored
	var supports_color := "color" in Commands.prop_fields(authored)
	_color.disabled = not editable or not supports_color
	(_color.get_parent() as Control).visible = supports_color
	_name.editable = editable
	_name.text = record.get("name", "")
	for field in _fields.values():
		field.editable = editable
	if not result.ok:
		_behaviors.show_entity([], {})
		return
	var doors: Array = []
	if "door_open" in EntityTypes.TYPES.get(record.type, {}).get("behavior_outputs", []):
		doors = _tools.execute("list_entities").get("entities", []).filter(func(item: Dictionary) -> bool:
			return EntityTypes.TYPES.get(item.type, {}).get("factory") == "door")
	_behaviors.show_entity(_tools.execute("list_behaviors", {"id": _selected}).get("behaviors", []), record.get("behavior", {}), doors)
	_fields.X.value = record.position[0]
	_fields.Y.value = record.position[1]
	_fields.Z.value = record.position[2]
	for key in _numeric_fields:
		_fields[_numeric_fields[key]].value = record[key]
	_color.color = Color.html(record.color)
	_show_color_code(_color.color)
	_form_baseline = _form_values()

## The prop being edited, for the in-world handles (transform_gizmo.gd).
func selected_entity() -> String:
	return _selected

## Selects a prop picked in the world, or reloads its fields after it was moved there.
func select_entity(id: String) -> void:
	_selected = id
	_refresh()

func _show_color_code(color: Color) -> void:
	_color_label.text = "Color  #%s" % color.to_html(false).to_upper()
