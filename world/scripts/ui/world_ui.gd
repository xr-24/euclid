extends Node
## View-only UI: emits intent, never loads zones or writes saves.
signal zone_requested(zone: String)
signal quit_requested
signal resumed
signal graphics_requested
var graphics_label := "Balanced"
var zones: Array = []
var hud: Label
var hint: Label
var gateway_label: Label
var overlay: PanelContainer
var overlay_content: VBoxContainer
var underwater: ColorRect

func _ready() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var ui := Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(ui)
	hud = _ui_label(ui, Vector2(36, 30), 22)
	hud.modulate.a = 0.0
	gateway_label = _ui_label(ui, Vector2(36, 62), 13)
	gateway_label.visible = false
	hint = _ui_label(ui, Vector2(32, 850), 17)
	underwater = ColorRect.new()
	underwater.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	underwater.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var under_mat := ShaderMaterial.new()
	under_mat.shader = load("res://shaders/underwater.gdshader")
	underwater.material = under_mat
	underwater.visible = false
	ui.add_child(underwater)
	ui.move_child(underwater, 0)
	var crosshair := _ui_label(ui, Vector2.ZERO, 14)
	crosshair.text = "·"
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	overlay = PanelContainer.new()
	ui.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.offset_left = 80
	overlay.offset_top = 170
	overlay.offset_right = -80
	overlay.offset_bottom = -70
	var style := StyleBoxFlat.new()
	style.bg_color = Color("111d2c")
	style.content_margin_left = 38
	style.content_margin_top = 32
	style.content_margin_right = 38
	style.content_margin_bottom = 32
	style.corner_radius_top_left = 16
	style.corner_radius_top_right = 16
	style.corner_radius_bottom_left = 16
	style.corner_radius_bottom_right = 16
	overlay.add_theme_stylebox_override("panel", style)
	overlay_content = VBoxContainer.new()
	overlay_content.add_theme_constant_override("separation", 18)
	overlay.add_child(overlay_content)
	overlay.hide()
	show_menu()

func _ui_label(parent: Node, at: Vector2, font_size: int) -> Label:
	var label := Label.new()
	parent.add_child(label)
	label.position = at
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("f5f8ff"))
	label.add_theme_color_override("font_shadow_color", Color("142137"))
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _panel(title: String, description: String) -> void:
	overlay.offset_left = 520
	overlay.offset_top = 150
	overlay.offset_right = -520
	overlay.offset_bottom = -150
	for child in overlay_content.get_children():
		child.free()
	var heading := Label.new()
	heading.text = title
	heading.add_theme_font_size_override("font_size", 34)
	overlay_content.add_child(heading)
	if not description.is_empty():
		var text := Label.new()
		text.text = description
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_theme_font_size_override("font_size", 18)
		text.modulate.a = 0.75
		overlay_content.add_child(text)
	overlay.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _button(title: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size.y = 46
	button.add_theme_font_size_override("font_size", 20)
	button.pressed.connect(callback)
	overlay_content.add_child(button)

func show_menu() -> void:
	_panel("CONSTRUCT", "")
	_button("Resume", _resume)
	for i in zones.size():
		var zone: Dictionary = zones[i]
		_button("%d    %s" % [i + 1, zone.name], zone_requested.emit.bind(str(zone.id)))
	_button("Terminal", show_application.bind("terminal"))
	_button("Graphics: " + graphics_label, graphics_requested.emit)
	_button("Save and quit", quit_requested.emit)

func close_panel() -> void:
	overlay.hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func show_application(app_id: String) -> void:
	_panel("Terminal" if app_id == "terminal" else "Media", "Not connected yet.")
	overlay.offset_left = 0
	overlay.offset_top = 0
	overlay.offset_right = 0
	overlay.offset_bottom = 0
	_button("Back", close_panel)

func _resume() -> void:
	close_panel()
	resumed.emit()

func show_agent(title: String, summary: String) -> void:
	_panel(title, summary)
	_button("Back", close_panel)
