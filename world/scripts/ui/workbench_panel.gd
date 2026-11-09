extends VBoxContainer

signal close_requested

const Client = preload("res://scripts/agents/workbench_client.gd")
const Console = preload("res://scripts/ui/codex_console.gd")
const PREVIEW_ACTIONS := ["check", "play", "stop", "apply", "discard", "restore"]
var _client: Client
var _files: OptionButton
var _editor: CodeEdit
var _diff: TextEdit
var _log: TextEdit
var _tabs: TabContainer
var _request: LineEdit
var _status: Label
var _buttons := {}
var _source := ""
var _hash := ""
var _original := ""
var _busy := false
var _state := {}

func setup(url: String, token: String, capability: String) -> void:
	_client = Client.new()
	add_child(_client)
	_client.configure(url, token, capability)
	var mono := SystemFont.new()
	mono.font_names = ["Cascadia Mono", "Consolas", "DejaVu Sans Mono"]
	var skin := Theme.new()
	skin.default_font = mono
	skin.default_font_size = 16
	theme = skin
	add_theme_constant_override("separation", 8)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var title := HBoxContainer.new()
	add_child(title)
	var heading := Label.new()
	heading.text = "Workbench"
	heading.add_theme_font_size_override("font_size", 24)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_child(heading)
	_button(title, "×", func() -> void: close_requested.emit())

	var files_row := HBoxContainer.new()
	add_child(files_row)
	_files = OptionButton.new()
	_files.fit_to_longest_item = false
	_files.custom_minimum_size.y = 34
	_files.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_files.add_item("Choose a source file")
	_files.item_selected.connect(_select_file)
	files_row.add_child(_files)
	_buttons["reload"] = _button(files_row, "Reload", func() -> void: _open_file(_source))
	_buttons.reload.tooltip_text = "Reload the selected file from disk and reset the editor buffer"

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.custom_minimum_size.y = 220
	add_child(_tabs)
	_editor = CodeEdit.new()
	_editor.name = "Source"
	_editor.gutters_draw_line_numbers = true
	_editor.indent_use_spaces = false
	_editor.text_changed.connect(_sync_controls)
	_tabs.add_child(_editor)
	_diff = _output_tab("Diff")
	_log = _output_tab("Checks")

	var prompt_row := HBoxContainer.new()
	add_child(prompt_row)
	_request = LineEdit.new()
	_request.placeholder_text = "Describe an edit to this file"
	_request.max_length = 600
	_request.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_request.text_changed.connect(func(_text: String) -> void: _sync_controls())
	_request.text_submitted.connect(func(_text: String) -> void: _propose())
	prompt_row.add_child(_request)
	_buttons["propose"] = _button(prompt_row, "Ask Codex", _propose)
	_buttons["stage"] = _button(prompt_row, "Review diff", _stage)

	var controls := HBoxContainer.new()
	add_child(controls)
	var labels := ["Run checks", "Play preview", "Stop preview", "Apply", "Discard", "Restore last"]
	for index in PREVIEW_ACTIONS.size():
		var action: String = PREVIEW_ACTIONS[index]
		_buttons[action] = _button(controls, labels[index], _command.bind(action))
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.modulate = Console.INK
	add_child(_status)
	var timer := Timer.new()
	timer.wait_time = 2.0
	timer.timeout.connect(_poll)
	add_child(timer)
	timer.start()
	_load_catalog()

func _button(parent: Control, label: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(34, 32)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _output_tab(title: String) -> TextEdit:
	var view := TextEdit.new()
	view.name = title
	view.editable = false
	view.add_theme_color_override("font_readonly_color", Console.INK)
	_tabs.add_child(view)
	return view

func _load_catalog() -> void:
	_busy = true
	_sync_controls()
	var result := await _client.send("catalog")
	for file in result.get("files", []):
		_files.add_item(file)
	_busy = false
	if result.has("error"):
		_status.text = result.error
		_sync_controls()
		return
	await _poll(true)
	if _state.get("draft") is Dictionary:
		_tabs.current_tab = 1

func _select_file(index: int) -> void:
	if _busy or index < 1:
		return
	if not _source.is_empty() and _editor.text != _original:
		for row in range(1, _files.item_count):
			if _files.get_item_text(row) == _source:
				_files.select(row)
				break
		_status.text = "Review the current edit or undo it before switching files."
		return
	await _open_file(_files.get_item_text(index))

func _open_file(file: String) -> void:
	_busy = true
	_sync_controls()
	var result := await _client.send("read", {"name": file})
	_busy = false
	if not result.has("error"):
		_source = file
		_hash = result.hash
		_original = result.text.replace("\r\n", "\n")
		_editor.text = _original
		_tabs.current_tab = 0
		_status.text = "Edit the source or ask Codex for a draft."
	else:
		_status.text = result.error
	_sync_controls()

func _source_args() -> Dictionary:
	return {"name": _source, "hash": _hash, "text": _editor.text}

func _propose() -> void:
	if _buttons.propose.disabled:
		return
	var arguments := _source_args()
	arguments["prompt"] = _request.text.strip_edges()
	_busy = true
	_status.text = "Codex is preparing an edit…"
	_sync_controls()
	var result := await _client.send("propose", arguments)
	_busy = false
	if result.has("error"):
		_status.text = result.error
	else:
		_editor.text = result.text.replace("\r\n", "\n")
		_tabs.current_tab = 0
		_status.text = result.summary
	_sync_controls()

func _stage() -> void:
	if _buttons.stage.disabled:
		return
	await _command("stage", _source_args())

func _command(action: String, arguments := {}) -> void:
	if _busy:
		return
	var draft: Variant = _state.get("draft")
	if draft is Dictionary:
		arguments["id"] = draft.id
	_busy = true
	_sync_controls()
	var result := await _client.send(action, arguments)
	_busy = false
	if result.has("error"):
		_status.text = result.error
		_sync_controls()
		return
	_show_state(result)
	match action:
		"stage":
			_tabs.current_tab = 1
		"check":
			_tabs.current_tab = 2
		"discard", "apply", "restore":
			if not _source.is_empty():
				await _open_file(_source)
			var messages := {"discard": "Discarded the staged edit.",
				"apply": "Applied to the project. Reopen Euclid to load the updated source.",
				"restore": "Restored the previous file. Reopen Euclid to load it."}
			_status.text = messages[action]

func _poll(force := false) -> void:
	if _busy or not is_visible_in_tree() or (not force and not _state.get("playing", false) and _state.get("operation", "") != "checking"):
		return
	_busy = true
	var result := await _client.send("state")
	_busy = false
	if result.has("error"):
		_status.text = result.error
		_sync_controls()
		return
	_show_state(result)

func _show_state(result: Dictionary) -> void:
	_state = result
	var draft: Variant = result.get("draft")
	if draft is Dictionary:
		if _diff.text != draft.diff:
			_show_diff(draft.diff)
		if _log.text != draft.log:
			_log.text = draft.log
			_log.set_caret_line(_log.get_line_count() - 1)
		var messages := {"staged": "Review the diff before running the edited code in a disposable project.",
			"checking": "Checking the disposable project…", "passed": "Checks passed. You can play the preview or apply the edit."}
		_status.text = "%s  ·  %s" % [draft.name, draft.error if draft.status == "failed" else messages[draft.status]]
		if result.get("playing", false):
			_status.text = "The preview is open in a separate Euclid window."
	else:
		_diff.text = ""
		_log.text = ""
		_status.text = "Choose a source file to start."
	_sync_controls()

func _show_diff(text: String) -> void:
	_diff.text = text
	for line in _diff.get_line_count():
		var row := _diff.get_line(line)
		if row.begins_with("+") and not row.begins_with("+++"):
			_diff.set_line_background_color(line, Color("17332b"))
		elif row.begins_with("-") and not row.begins_with("---"):
			_diff.set_line_background_color(line, Color("392129"))

func _sync_controls() -> void:
	var draft: Variant = _state.get("draft")
	var staged := draft is Dictionary
	var playing: bool = _state.get("playing", false)
	var blocked := _busy or not str(_state.get("operation", "")).is_empty()
	var editing := not blocked and not staged and not _source.is_empty()
	_files.disabled = blocked or staged
	_buttons.reload.disabled = not editing
	_editor.editable = editing
	_request.editable = editing
	_buttons.propose.disabled = not editing or _request.text.strip_edges().is_empty()
	_buttons.stage.disabled = not editing or _editor.text == _original
	_buttons.check.disabled = blocked or not staged or playing
	var passed: bool = staged and draft.status == "passed"
	_buttons.play.disabled = blocked or not passed or playing
	_buttons.stop.disabled = blocked or not playing
	_buttons.apply.disabled = blocked or not passed
	_buttons.discard.disabled = _busy or not staged or (blocked and _state.get("operation") != "checking")
	_buttons.restore.disabled = blocked or staged or str(_state.get("revision", "")).is_empty()
	_buttons.restore.tooltip_text = str(_state.get("revision", ""))
