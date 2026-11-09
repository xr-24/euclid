extends VBoxContainer
## Renders the numeric settings declared by a registered behavior.

signal submitted(behavior: Variant)

var _choices: OptionButton
var _fields: HBoxContainer
var _target: OptionButton
var _doors: Array = []
var _inputs := {}
var _saved := {}
var _definitions: Array = []

func _ready() -> void:
	var row := HBoxContainer.new()
	add_child(row)
	_choices = OptionButton.new()
	_choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_choices.item_selected.connect(_select)
	row.add_child(_choices)
	var apply := Button.new()
	apply.text = "Apply behavior"
	apply.pressed.connect(_submit)
	row.add_child(apply)
	_fields = HBoxContainer.new()
	add_child(_fields)
	_target = OptionButton.new()
	add_child(_target)
	hide()

func show_entity(definitions: Array, saved: Dictionary, doors := []) -> void:
	_definitions = definitions
	_saved = saved
	_doors = doors
	visible = not definitions.is_empty() or not saved.is_empty()
	_choices.clear()
	_choices.add_item("No behavior")
	var selected := 0
	for definition in definitions:
		_choices.add_item(definition.name)
		if definition.id == saved.get("id"):
			selected = _choices.item_count - 1
	_choices.select(selected)
	_select(selected)

func _select(index: int) -> void:
	_inputs.clear()
	_target.hide()
	for child in _fields.get_children():
		child.free()
	if index == 0:
		return
	var definition: Dictionary = _definitions[index - 1]
	if definition.output == "door_open":
		_target.clear()
		_target.add_item("Choose a linked door")
		var selected := 0
		for door in _doors:
			_target.add_item("%s  ·  %s" % [door.name, door.id.left(6)])
			var row := _target.item_count - 1
			_target.set_item_metadata(row, door.id)
			if door.id == _saved.get("target"):
				selected = row
		_target.select(selected)
		_target.show()
	for key in definition.settings:
		var spec: Dictionary = definition.settings[key]
		var label := Label.new()
		label.text = spec.label
		_fields.add_child(label)
		var input := SpinBox.new()
		input.min_value = spec.minimum
		input.max_value = spec.maximum
		input.step = 0.05
		input.value = _saved.settings.get(key, spec.default) if _saved.get("id") == definition.id else spec.default
		_fields.add_child(input)
		_inputs[key] = input

func _submit() -> void:
	if _choices.selected <= 0:
		submitted.emit(null)
		return
	var settings := {}
	for key in _inputs:
		settings[key] = _inputs[key].value
	var behavior := {"id": _definitions[_choices.selected - 1].id, "settings": settings}
	if _target.visible and _target.selected > 0:
		behavior["target"] = _target.get_selected_metadata()
	submitted.emit(behavior)
