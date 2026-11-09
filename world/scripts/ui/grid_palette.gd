extends VBoxContainer
## Palette and inspector for the same commands available to other tool clients.

signal agent_requested(prompt: String, placement: Array)

const EntityTypes = preload("res://scripts/workshop/entity_types.gd")
const BehaviorInspector = preload("res://scripts/ui/behavior_inspector.gd")

var _tools: RefCounted
var _spawn_at: Array
var _selected := ""
var _entities: OptionButton
var _fields := {}
var _color: ColorPickerButton
var _status: Label
var _apply: Button
var _delete: Button
var _duplicate: Button
var _undo: Button
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

func setup(tools: RefCounted, spawn_at: Vector3, selected: String, catalog: Callable, run_action: Callable) -> void:
	_tools = tools
	_spawn_at = [spawn_at.x, spawn_at.y, spawn_at.z]
	_selected = selected
	_action_catalog = catalog
	_run_action = run_action
	add_theme_constant_override("separation", 10)
	var spawn_row := HBoxContainer.new()
	add_child(spawn_row)
	_button(spawn_row, "Spawn orange cone", _spawn.bind("traffic_cone"))
	_button(spawn_row, "Spawn plate", _spawn.bind("pressure_plate"))
	_button(spawn_row, "Spawn door", _spawn.bind("sliding_door"))
	_entities = OptionButton.new()
	add_child(_entities)
	_entities.item_selected.connect(_select)
	var properties := GridContainer.new()
	properties.columns = 3
	add_child(properties)
	for spec in [["X", -60.0, 60.0, 0.05], ["Y", 0.0, 12.0, 0.05], ["Z", -60.0, 60.0, 0.05],
			["Yaw", -360.0, 360.0, 1.0], ["Scale", 0.25, 4.0, 0.05]]:
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
	var color_label := Label.new()
	color_label.text = "Color"
	color_field.add_child(color_label)
	_color = ColorPickerButton.new()
	_color.edit_alpha = false
	_color.custom_minimum_size.y = 30
	color_field.add_child(_color)
	var actions := HBoxContainer.new()
	add_child(actions)
	_apply = _button(actions, "Apply", _apply_changes)
	_duplicate = _button(actions, "Duplicate", _duplicate_entity)
	_delete = _button(actions, "Delete", _run.bind("delete", {}))
	_undo = _button(actions, "Undo", _run.bind("undo", {}))
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
	_prefab_name.max_length = 48
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

func _send_agent_request() -> void:
	var prompt := _agent_input.text.strip_edges()
	if prompt.is_empty() or _agent_button.disabled:
		return
	_agent_button.disabled = true
	_status.text = "Codex is planning a Grid edit…"
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
	_run("spawn", {"type": type, "position": _spawn_at})

func _save_selected_prefab() -> void:
	var result: Dictionary = _tools.execute("save_prefab", {"id": _selected, "name": _prefab_name.text})
	if not result.ok:
		_status.text = result.error
		return
	_prefab_name.clear()
	_refresh_prefabs(result.prefab_id)
	_status.text = "Saved %s to the prefab library." % result.name

func _place_selected_prefab() -> void:
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

func _apply_changes() -> void:
	var point := []
	for axis in ["X", "Y", "Z"]:
		point.append(_fields[axis].value)
	_run("edit", {"changes": {"position": point, "yaw": _fields.Yaw.value,
		"scale": _fields.Scale.value, "color": _color.color.to_html(false)}})

func _duplicate_entity() -> void:
	var result: Dictionary = _tools.execute("inspect", {"id": _selected})
	if not result.ok:
		_status.text = result.error
		return
	var entity: Dictionary = result.entity
	var position: Array = entity.position.duplicate()
	var offset: float = 0.8 * entity.scale
	position[0] += offset if position[0] + offset <= 60.0 else -offset
	var args := {"type": entity.type, "position": position, "yaw": entity.yaw,
		"scale": entity.scale, "color": entity.color}
	if entity.has("asset_id"):
		args["asset_id"] = entity.asset_id
	if entity.has("animation"):
		args["animation"] = entity.animation
	if entity.has("behavior"):
		args["behavior"] = entity.behavior
	_run("spawn", args)

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
	var messages := {"spawn": "Entity created.", "spawn_prefab": "Prefab placed.",
		"edit": "Properties saved.", "set_behavior": "Behavior saved.", "delete": "Entity deleted.", "undo": "Edit undone."}
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
			_entities.add_item("%s  ·  %s" % [EntityTypes.label(record), record.id.left(6)])
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
	_apply.disabled = not result.ok
	_duplicate.disabled = not result.ok
	_delete.disabled = not result.ok
	_save_prefab.disabled = not result.ok
	_color.disabled = not result.ok
	for field in _fields.values():
		field.editable = result.ok
	if not result.ok:
		_behaviors.show_entity([], {})
		return
	var record: Dictionary = result.entity
	var doors: Array = []
	if record.type == "pressure_plate":
		doors = _tools.execute("list_entities").get("entities", []).filter(func(item: Dictionary) -> bool: return item.type == "sliding_door")
	_behaviors.show_entity(_tools.execute("list_behaviors", {"id": _selected}).get("behaviors", []), record.get("behavior", {}), doors)
	_fields.X.value = record.position[0]
	_fields.Y.value = record.position[1]
	_fields.Z.value = record.position[2]
	_fields.Yaw.value = record.yaw
	_fields.Scale.value = record.scale
	_color.color = Color.html(record.color)
