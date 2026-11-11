extends MarginContainer
## F2 Codex uplink: a terminal-styled conversation with the world agent. Output types in,
## ↑/↓ recall earlier prompts, and the prompt line has the shared glowing block caret.

signal submitted(prompt: String)
signal cli_requested
signal minimize_requested
signal layout_requested(expanded: bool)
signal voice_requested(enabled: bool)
signal development_requested(action: String)

const Look = preload("res://scripts/ui/terminal_theme.gd")
const Effects = preload("res://scripts/ui/code_fx.gd")
const GlowLayer = preload("res://scripts/ui/glow_layer.gd")
const INK := Look.INK
const MUTED := Look.MUTED
const ACCENT := Look.ACCENT
const TYPE_RATE := 900.0
const HISTORY_LIMIT := 100

## Submitted prompts for ↑/↓ recall. The main world restores and saves these.
static var prompts := PackedStringArray()

var expanded := false
var _busy := false
var _body := VBoxContainer.new()
var _history: RichTextLabel
var _entry: LineEdit
var _prompt: Label
var _resize: Button
var _draft_row: HBoxContainer
var _draft_strip: MarginContainer
var _preview_draft: Button
var _discard_draft: Button
var _recall := -1
var _draft_text := ""
var _shown := 0.0

static func frame_style() -> StyleBoxFlat:
	return Look.frame_style()

func setup(lines: PackedStringArray, busy: bool, voice_enabled: bool) -> void:
	theme = Look.make_theme()
	add_child(_body)
	_body.add_theme_constant_override("separation", 0)

	var bar := HBoxContainer.new()
	bar.custom_minimum_size.y = 45
	bar.add_theme_constant_override("separation", 4)
	_inset(_body, bar, 16, 0)
	var title := Label.new()
	title.text = "◆ codex uplink"
	title.add_theme_color_override("font_color", ACCENT)
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
	_rule(_body)

	_history = RichTextLabel.new()
	_history.custom_minimum_size.y = 120
	_history.scroll_following = true
	_history.selection_enabled = true
	_history.context_menu_enabled = true
	_history.add_theme_constant_override("line_separation", 7)
	_history.add_theme_color_override("default_color", INK)
	_history.add_theme_color_override("selection_color", Color(ACCENT, 0.22))
	var viewport := _inset(_body, _history, 20, 16)
	viewport.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rule(_body)
	_draft_row = HBoxContainer.new()
	_draft_row.add_theme_constant_override("separation", 8)
	_draft_strip = _inset(_body, _draft_row, 16, 4)
	_draft_strip.hide()
	_draft_button("Review draft", "review")
	_preview_draft = _draft_button("Preview live", "live")
	_discard_draft = _draft_button("Discard", "discard")

	var input_row := HBoxContainer.new()
	input_row.custom_minimum_size.y = 49
	input_row.add_theme_constant_override("separation", 12)
	_inset(_body, input_row, 20, 0)
	_prompt = Label.new()
	_prompt.add_theme_color_override("font_color", ACCENT)
	input_row.add_child(_prompt)
	_entry = LineEdit.new()
	_entry.max_length = 4096
	_entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_entry.add_theme_color_override("font_color", Look.BRIGHT)
	_entry.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	_entry.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_entry.text_submitted.connect(func(_text: String) -> void: _submit())
	_entry.gui_input.connect(_on_entry_input)
	input_row.add_child(_entry)
	var caret := Effects.new()
	caret.block_caret = true
	caret.attach(_entry)
	add_child(GlowLayer.new(1.6))
	update_display(lines, busy)
	_shown = _history.get_total_character_count()
	focus_entry()

func focus_entry() -> void:
	_entry.grab_focus()

func update_development(draft: Dictionary, can_preview: bool, live: bool) -> void:
	_draft_strip.visible = not draft.is_empty()
	var status: String = draft.get("status", "")
	_discard_draft.text = "Cancel revision" if status == "revising" else ("Cancel" if status == "authoring" else "Discard")
	if draft.get("agent_source", false):
		var can_check: bool = status in ["staged", "failed"] and draft.get("has_patch", false)
		var playing: bool = draft.get("playing", false)
		var palette: bool = draft.get("subject") == "grid_palette"
		_preview_draft.disabled = not can_preview or playing or live or (not can_check and status != "passed")
		_preview_draft.text = "Run checks" if can_check else ("Preview palette" if palette else "Preview build")
		if playing:
			_preview_draft.text = "Preview open"
		elif live:
			_preview_draft.text = "Preview active"
		return
	_preview_draft.disabled = not can_preview or draft.get("status") != "passed" or live
	var label := "Preview Grid reload" if draft.get("activation") == "reload_grid" else "Preview live"
	if draft.get("subject") == "workshop_tool":
		label = "Preview tool"
	_preview_draft.text = "Preview active" if live else label

func _draft_button(label: String, action: String) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size.y = 32
	button.pressed.connect(func() -> void: development_requested.emit(action))
	_draft_row.add_child(button)
	return button

func update_display(lines: PackedStringArray, busy: bool) -> void:
	_busy = busy
	_prompt.text = "…" if busy else ">"
	var before := _history.get_total_character_count()
	_history.clear()
	for index in lines.size():
		var line := lines[index]
		_history.push_color(ACCENT if line.begins_with("> ") else INK)
		_history.add_text(line)
		_history.pop()
		if index < lines.size() - 1:
			_history.newline()
	var total := _history.get_total_character_count()
	# New output types in from where the old text ended; a shorter history shows at once.
	if Effects.enabled and total > before and before > 0:
		_shown = minf(_shown, before)
		_history.visible_characters = int(_shown)
	else:
		_shown = total
		_history.visible_characters = -1

func _process(delta: float) -> void:
	if _history == null or _history.visible_characters < 0:
		return
	var total := _history.get_total_character_count()
	_shown = minf(_shown + delta * TYPE_RATE, total)
	_history.visible_characters = -1 if _shown >= total else int(_shown)

func _submit() -> void:
	var prompt := _entry.text.strip_edges()
	if _busy or prompt.is_empty():
		return
	if prompts.is_empty() or prompts[prompts.size() - 1] != prompt:
		prompts.append(prompt)
		if prompts.size() > HISTORY_LIMIT:
			prompts.remove_at(0)
	_recall = -1
	_entry.clear()
	submitted.emit(prompt)

func _on_entry_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or prompts.is_empty():
		return
	if key.keycode != KEY_UP and key.keycode != KEY_DOWN:
		return
	_entry.accept_event()
	if _recall < 0:
		if key.keycode == KEY_DOWN:
			return
		_draft_text = _entry.text
		_recall = prompts.size()
	_recall += -1 if key.keycode == KEY_UP else 1
	_recall = maxi(_recall, 0)
	if _recall >= prompts.size():
		_recall = -1
		_entry.text = _draft_text
	else:
		_entry.text = prompts[_recall]
	_entry.caret_column = _entry.text.length()

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
	rule.color = Look.LINE
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
