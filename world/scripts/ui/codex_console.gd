extends VBoxContainer

signal submitted(prompt: String)
signal cli_requested
signal minimize_requested
signal layout_requested(expanded: bool)
signal voice_requested(enabled: bool)

const INK := Color("ded9d8")
const MUTED := Color("a29197")
const ACCENT := Color("ff776d")
var expanded := false
var _busy := false
var _history: RichTextLabel
var _entry: LineEdit
var _prompt: Label
var _resize: Button

static func frame_style() -> StyleBoxFlat:
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color("0d0b10")
	frame.border_color = Color("643941")
	frame.set_border_width_all(1)
	frame.set_corner_radius_all(6)
	frame.shadow_color = Color(0, 0, 0, 0.48)
	frame.shadow_size = 18
	frame.shadow_offset.y = 9
	return frame

func setup(lines: PackedStringArray, busy: bool, voice_enabled: bool) -> void:
	var mono := SystemFont.new()
	mono.font_names = ["Cascadia Mono", "Consolas", "DejaVu Sans Mono"]
	var skin := Theme.new()
	skin.default_font = mono
	skin.default_font_size = 16
	theme = skin
	add_theme_constant_override("separation", 0)

	var bar := HBoxContainer.new()
	bar.custom_minimum_size.y = 45
	bar.add_theme_constant_override("separation", 4)
	_inset(self, bar, 16, 0)
	var title := Label.new()
	title.text = "codex"
	title.add_theme_color_override("font_color", INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(title)
	_icon(bar, "↗", "Open native Codex CLI").pressed.connect(func() -> void: cli_requested.emit())
	var voice := _icon(bar, "♪", "Read replies aloud")
	voice.toggle_mode = true
	voice.button_pressed = voice_enabled
	voice.toggled.connect(func(enabled: bool) -> void: voice_requested.emit(enabled))
	_resize = _icon(bar, "□", "Expand terminal")
	_resize.pressed.connect(_toggle_size)
	_icon(bar, "−", "Minimize terminal (F2)").pressed.connect(func() -> void: minimize_requested.emit())
	_rule(self)

	_history = RichTextLabel.new()
	_history.custom_minimum_size.y = 120
	_history.scroll_following = true
	_history.selection_enabled = true
	_history.add_theme_constant_override("line_separation", 7)
	var viewport := _inset(self, _history, 20, 16)
	viewport.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rule(self)

	var input_row := HBoxContainer.new()
	input_row.custom_minimum_size.y = 49
	input_row.add_theme_constant_override("separation", 12)
	_inset(self, input_row, 20, 0)
	_prompt = Label.new()
	_prompt.add_theme_color_override("font_color", ACCENT)
	input_row.add_child(_prompt)
	_entry = LineEdit.new()
	_entry.max_length = 240
	_entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_entry.add_theme_color_override("font_color", INK)
	_entry.add_theme_color_override("caret_color", ACCENT)
	_entry.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	_entry.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_entry.text_submitted.connect(func(_text: String) -> void: _submit())
	input_row.add_child(_entry)
	update_display(lines, busy)
	focus_entry()

func focus_entry() -> void:
	_entry.grab_focus()

func update_display(lines: PackedStringArray, busy: bool) -> void:
	_busy = busy
	_prompt.text = "…" if busy else ">"
	_history.clear()
	for index in lines.size():
		var line := lines[index]
		_history.push_color(ACCENT if line.begins_with("> ") else INK)
		_history.add_text(line)
		_history.pop()
		if index < lines.size() - 1:
			_history.newline()

func _submit() -> void:
	var prompt := _entry.text.strip_edges()
	if _busy or prompt.is_empty():
		return
	_entry.clear()
	submitted.emit(prompt)

func _toggle_size() -> void:
	expanded = not expanded
	_resize.text = "▣" if expanded else "□"
	_resize.tooltip_text = "Restore terminal" if expanded else "Expand terminal"
	layout_requested.emit(expanded)

static func _inset(parent: Control, child: Control, horizontal: int, vertical: int) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", horizontal)
	margin.add_theme_constant_override("margin_right", horizontal)
	margin.add_theme_constant_override("margin_top", vertical)
	margin.add_theme_constant_override("margin_bottom", vertical)
	parent.add_child(margin)
	margin.add_child(child)
	return margin

static func _rule(parent: Control) -> void:
	var rule := ColorRect.new()
	rule.color = Color("392229")
	rule.custom_minimum_size.y = 1
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rule)

static func _icon(parent: Control, text: String, tooltip: String) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.flat = true
	button.custom_minimum_size = Vector2(34, 32)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.add_theme_color_override("font_color", MUTED)
	button.add_theme_color_override("font_pressed_color", ACCENT)
	button.add_theme_color_override("font_hover_color", INK)
	parent.add_child(button)
	return button
