extends VBoxContainer

const Terrain = preload("res://scripts/pieces/terrain_node.gd")
const Editor = preload("res://scripts/pieces/piece_editor.gd")
const Cache = preload("res://scripts/assets/runtime_materials.gd")
const MaterialClient = preload("res://scripts/agents/material_client.gd")

var mode := "raise"
var _radius := HSlider.new()
var _strength := HSlider.new()
var _materials := OptionButton.new()
var _status := Label.new()
var _undo: Button
var _paint_row := HBoxContainer.new()
var _client: MaterialClient

func setup(editor: Editor, close: Callable, undo: Callable, client: MaterialClient) -> void:
	_client = client
	add_theme_constant_override("separation", 9)
	var heading := HBoxContainer.new()
	add_child(heading)
	var title := Label.new()
	title.text = "Terrain"
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	heading.add_child(title)
	_button(heading, "Close", close)
	var brushes := HFlowContainer.new()
	add_child(brushes)
	var group := ButtonGroup.new()
	for name in ["raise", "lower", "smooth", "flatten", "paint"]:
		var button := _button(brushes, name.capitalize(), _select.bind(name))
		button.toggle_mode = true
		button.button_group = group
		button.set_pressed_no_signal(name == mode)
		if name == "flatten":
			button.tooltip_text = "Match the height where the stroke begins."
	_slider("Radius", _radius, 4, 60, 12, " m")
	_slider("Strength", _strength, 10, 100, 55, "%")
	_materials.fit_to_longest_item = false
	_materials.size_flags_horizontal = SIZE_EXPAND_FILL
	_paint_row.add_child(_materials)
	_button(_paint_row, "Import…", _browse)
	add_child(_paint_row)
	_paint_row.hide()
	_client.installed.connect(_refresh_materials)
	_refresh_materials()
	var hint := Label.new()
	hint.text = "Left drag to edit. Middle drag to look."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)
	_undo = _button(self, "Undo", func() -> void:
		show_status(undo.call().message))
	_undo.tooltip_text = "Undo the latest piece edit or terrain stroke."
	editor.changed.connect(_refresh_undo.bind(editor))
	_refresh_undo(editor)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)
	show_status("Aim at terrain.")

func radius() -> float:
	return _radius.value

func strength() -> float:
	return _strength.value * 0.01

func material_id() -> String:
	return _materials.get_selected_metadata()

func show_status(message: String) -> void:
	_status.text = message

func _refresh_undo(editor: Editor) -> void:
	_undo.disabled = not editor.execute({"tool": "list_pieces"}).get("can_undo", false)

func _select(next: String) -> void:
	mode = next
	_paint_row.visible = mode == "paint"

func _refresh_materials() -> void:
	var selected := material_id() if _materials.selected >= 0 else "earth"
	_materials.clear()
	for item: Dictionary in Terrain.palette() + Cache.installed():
		_materials.add_item(item.name)
		_materials.set_item_metadata(_materials.item_count - 1, item.id)
		if item.id == selected:
			_materials.select(_materials.item_count - 1)

func _browse() -> void:
	var browser := preload("res://scripts/ui/poly_haven_browser.gd").new()
	add_child(browser)
	browser.setup("material", "materials", _client.search, _client.import_material)
	browser.chosen.connect(func(id: String, title: String) -> void:
		_refresh_materials()
		for index in _materials.item_count:
			if _materials.get_item_metadata(index) == id:
				_materials.select(index)
				break
		show_status("%s is ready to paint." % title))
	browser.popup_centered(Vector2i(450, 330))

func _slider(title: String, slider: HSlider, low: float, high: float, initial: float, suffix: String) -> void:
	var row := HBoxContainer.new()
	add_child(row)
	var label := Label.new()
	label.text = title
	label.custom_minimum_size.x = 82
	row.add_child(label)
	slider.min_value = low
	slider.max_value = high
	slider.step = 1
	slider.value = initial
	slider.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(slider)
	var value := Label.new()
	value.custom_minimum_size.x = 56
	value.text = str(int(initial)) + suffix
	row.add_child(value)
	slider.value_changed.connect(func(amount: float) -> void: value.text = str(int(amount)) + suffix)

static func _button(parent: Control, title: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.pressed.connect(action)
	parent.add_child(button)
	return button
