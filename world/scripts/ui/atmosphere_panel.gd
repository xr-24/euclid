extends VBoxContainer
## Atmosphere editing for the current environment: sun, sky, light and fog. Every change previews
## live; Save keeps it, Discard returns to the saved look and Reset clears this environment's
## edits back to its package. Agents edit the same draft (rendering/atmosphere.gd).

const Atmosphere = preload("res://scripts/rendering/atmosphere.gd")

## field, label, minimum, maximum, step, format
const SLIDERS := {
	"Sun": [["sun_azimuth", "Direction", 0.0, 360.0, 1.0, "%d°"], ["sun_elevation", "Height", -30.0, 90.0, 0.5, "%.1f°"],
		["sun_energy", "Strength", 0.0, 8.0, 0.05, "%.2f"]],
	"Sky": [["sky_energy", "Brightness", 0.0, 4.0, 0.05, "%.2f"], ["stars", "Stars", 0.0, 2.0, 0.05, "%.2f"]],
	"Light": [["exposure", "Exposure", 0.2, 3.0, 0.01, "%.2f"], ["ambient", "Fill", 0.0, 3.0, 0.05, "%.2f"],
		["shadow_distance", "Shadow reach", 10.0, 250.0, 1.0, "%d m"]],
	"Fog": [["fog_density", "Density", 0.0, 0.08, 0.0005, "%.4f"], ["fog_direction", "Toward sun", -0.9, 0.9, 0.01, "%.2f"],
		["haze", "Haze", 0.0, 0.02, 0.0001, "%.4f"]],
}
const COLORS := {"Sun": [["sun_color", "Color"]], "Fog": [["fog_color", "Color"], ["haze_color", "Haze color"]]}

var _atmosphere: Atmosphere
var _zone := ""
var _sliders := {}
var _readouts := {}
var _formats := {}
var _colors := {}
var _sky := OptionButton.new()
var _notice := Label.new()
var _loading := false

func setup(atmosphere: Atmosphere, zone: String, close: Callable) -> void:
	_atmosphere = atmosphere
	_zone = zone
	add_theme_constant_override("separation", 8)
	var heading := HBoxContainer.new()
	add_child(heading)
	var title := Label.new()
	title.text = "Atmosphere"
	title.add_theme_font_size_override("font_size", 24)
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	heading.add_child(title)
	_button(heading, "Close", close)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)
	scroll.add_child(body)
	for section in ["Sun", "Sky", "Light", "Fog"]:
		var header := Label.new()
		header.text = section
		header.add_theme_font_size_override("font_size", 18)
		body.add_child(header)
		if section == "Sky":
			for sky in Atmosphere.skies():
				_sky.add_item("Painted gradient" if sky == "gradient" else str(sky).get_basename().replace("_", " "))
				_sky.set_item_metadata(_sky.item_count - 1, sky)
			_sky.item_selected.connect(func(index: int) -> void: _change("sky", _sky.get_item_metadata(index)))
			body.add_child(_sky)
		for spec in SLIDERS.get(section, []):
			_slider(body, spec)
		for spec in COLORS.get(section, []):
			_color(body, spec[0], spec[1])
	var actions := HBoxContainer.new()
	add_child(actions)
	_button(actions, "Save", func() -> void: _say(_atmosphere.finish(true)))
	_button(actions, "Discard", func() -> void: _say(_atmosphere.finish(false)))
	_button(actions, "Reset", func() -> void: _say(_atmosphere.preview(_zone, {"reset": true})))
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_notice)
	_atmosphere.changed.connect(_load)
	_load()

func _slider(parent: Control, spec: Array) -> void:
	var field: String = spec[0]
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = spec[1]
	label.custom_minimum_size.x = 120
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = spec[2]
	slider.max_value = spec[3]
	slider.step = spec[4]
	slider.size_flags_horizontal = SIZE_EXPAND_FILL
	slider.custom_minimum_size.y = 26
	row.add_child(slider)
	var readout := Label.new()
	readout.custom_minimum_size.x = 76
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(readout)
	_sliders[field] = slider
	_readouts[field] = readout
	_formats[field] = spec[5]
	slider.value_changed.connect(func(value: float) -> void:
		readout.text = _format(field, value)
		_change(field, value))

func _color(parent: Control, field: String, title: String) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = title
	label.custom_minimum_size.x = 120
	row.add_child(label)
	var picker := ColorPickerButton.new()
	picker.edit_alpha = false
	picker.custom_minimum_size = Vector2(0, 28)
	picker.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(picker)
	_colors[field] = picker
	picker.color_changed.connect(func(color: Color) -> void: _change(field, color.to_html(false)))

func _load() -> void:
	if not is_inside_tree():
		return
	_loading = true
	var values: Dictionary = _atmosphere.inspect(_zone).values
	for field in _sliders:
		var slider: HSlider = _sliders[field]
		slider.set_value_no_signal(float(values.get(field, slider.min_value)))
		(_readouts[field] as Label).text = _format(field, slider.value)
	for field in _colors:
		(_colors[field] as ColorPickerButton).color = Color.html(str(values.get(field, "ffffff")))
	for index in _sky.item_count:
		if _sky.get_item_metadata(index) == values.get("sky"):
			_sky.select(index)
	_loading = false

func _change(field: String, value: Variant) -> void:
	if _loading:
		return
	var result: Dictionary = _atmosphere.preview(_zone, {field: value})
	_notice.text = "" if result.ok else str(result.message)

func _say(result: Dictionary) -> void:
	_notice.text = "" if result.ok else str(result.message)

func _format(field: String, value: float) -> String:
	var format: String = _formats[field]
	return format % (roundi(value) if format.begins_with("%d") else value)

func _button(parent: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 34
	button.pressed.connect(action)
	parent.add_child(button)
	return button
