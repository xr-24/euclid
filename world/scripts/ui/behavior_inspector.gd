extends VBoxContainer
## Renders the numeric settings declared by a registered behavior.

signal submitted(behavior: Variant)

var _choices: OptionButton
var _fields: HBoxContainer
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
	hide()

func show_entity(definitions: Array, saved: Dictionary) -> void:
	_definitions = definitions
	_saved = saved
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
	for child in _fields.get_children():
		child.free()
	if index == 0:
		return
	var definition: Dictionary = _definitions[index - 1]
	for key in definition.settings:
		var spec: Dictionary = definition.settings[key]
		var label := Label.new()
		label.text = spec.label
		_fields.add_child(label)
		var input := SpinBox.new()
		input.min_value = spec.minimum
		input.max_value = spec.maximum
		input.step = 0.1
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
	submitted.emit({"id": _definitions[_choices.selected - 1].id, "settings": settings})
