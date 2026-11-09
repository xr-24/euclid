extends VBoxContainer

signal close_requested
signal restart_requested

const Client = preload("res://scripts/agents/workbench_client.gd")
const Console = preload("res://scripts/ui/codex_console.gd")
const PREVIEW_ACTIONS := ["live", "check", "play", "stop", "apply", "discard", "restore"]
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
var _buffers := {}
var _message: LineEdit
var _busy := false
var _state := {}
var _preview_behavior: Callable
var _finish_behavior: Callable
var _behavior_status: Callable
var _plugin_context: Callable

func setup(url: String, token: String, capability: String, preview_behavior: Callable, finish_behavior: Callable,
		behavior_status: Callable, plugin_context: Callable) -> void:
	_preview_behavior = preview_behavior
	_finish_behavior = finish_behavior
	_behavior_status = behavior_status
	_plugin_context = plugin_context
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
	_buttons["close_file"] = _button(files_row, "Close file", _close_file)
	_buttons.close_file.tooltip_text = "Close the selected file and discard its unreviewed edits"

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
	_request.placeholder_text = "Describe a plugin or an edit to the open files"
	_request.max_length = 600
	_request.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_request.text_changed.connect(func(_text: String) -> void: _sync_controls())
	_request.text_submitted.connect(func(_text: String) -> void: _propose())
	prompt_row.add_child(_request)
	_buttons["propose"] = _button(prompt_row, "Ask Codex", _propose)
	_buttons["author"] = _button(prompt_row, "Create plugin", _author)
	_buttons.author.tooltip_text = "Draft a new behavior for entities in this Grid space"
	_buttons.propose.tooltip_text = "Codex can edit up to six open files. Use the file picker to open each one first."
	_buttons["stage"] = _button(prompt_row, "Review diff", _stage)

	var controls := HBoxContainer.new()
	add_child(controls)
	var labels := ["Preview live", "Run checks", "Play preview", "Stop preview", "Commit", "Discard", "Revert last"]
	for index in PREVIEW_ACTIONS.size():
		var action: String = PREVIEW_ACTIONS[index]
		_buttons[action] = _button(controls, labels[index], _command.bind(action))
	_buttons["restart"] = _button(controls, "Restart Euclid", func() -> void: restart_requested.emit())
	_message = LineEdit.new()
	_message.placeholder_text = "Commit message"
	_message.max_length = 100
	_message.text_changed.connect(func(_text: String) -> void: _sync_controls())
	add_child(_message)
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
	_remember_buffer()
	var file := _files.get_item_text(index)
	if _buffers.has(file):
		_show_file(file, _buffers[file])
	else:
		await _open_file(file)

func _open_file(file: String) -> void:
	_busy = true
	_sync_controls()
	var result := await _client.send("read", {"name": file})
	_busy = false
	if not result.has("error"):
		var original: String = result.text.replace("\r\n", "\n")
		_buffers[file] = {"hash": result.hash, "original": original, "text": original}
		_show_file(file, _buffers[file])
	else:
		_status.text = result.error
	_sync_controls()

func _show_file(file: String, buffer: Dictionary) -> void:
	_source = file
	_editor.text = buffer.text
	_tabs.current_tab = 0
	_status.text = "%d open file(s) · %d edited" % [_buffers.size(), _changed_files().size()]
	_sync_controls()

func _close_file() -> void:
	_buffers.erase(_source)
	_source = ""
	_files.select(0)
	_editor.clear()
	_status.text = "%d open file(s) · %d edited" % [_buffers.size(), _changed_files().size()]
	_sync_controls()

func show_error(message: String) -> void:
	_status.text = message

func _remember_buffer() -> void:
	if not _source.is_empty():
		_buffers[_source].text = _editor.text

func _changed_files() -> Array:
	var files := []
	for name in _buffers:
		var buffer: Dictionary = _buffers[name]
		var text: String = _editor.text if name == _source else buffer.text
		if text != buffer.original:
			files.append({"name": name, "hash": buffer.hash, "text": text})
	return files

func _propose() -> void:
	if _buttons.propose.disabled:
		return
	_remember_buffer()
	var files := []
	for name in _buffers:
		files.append({"name": name, "hash": _buffers[name].hash, "text": _buffers[name].text})
	if files.size() > 6:
		_status.text = "Codex can use six files per request. Close extra files before asking."
		return
	var arguments := {"files": files, "prompt": _request.text.strip_edges()}
	_busy = true
	_status.text = "Codex is preparing an edit…"
	_sync_controls()
	var result := await _client.send("propose", arguments)
	_busy = false
	if result.has("error"):
		_status.text = result.error
	else:
		for item in result.files:
			_buffers[item.name].text = item.text.replace("\r\n", "\n")
		_show_file(_source, _buffers[_source])
		_status.text = result.summary
	_sync_controls()

func _stage() -> void:
	if _buttons.stage.disabled:
		return
	await _command("stage", {"files": _changed_files()})

func _author() -> void:
	if _buttons.author.disabled:
		return
	var context: Dictionary = _plugin_context.call()
	if context.is_empty():
		show_error("Enter a Grid space to author a plugin.")
		return
	_status.text = "Codex is drafting a plugin…"
	await _command("author", {"context": context, "prompt": _request.text.strip_edges()})

func _command(action: String, arguments := {}) -> void:
	if _busy:
		return
	var draft: Variant = _state.get("draft")
	if draft is Dictionary:
		arguments["id"] = draft.id
	if action == "apply":
		if _live_status() == "failed":
			show_error("The live preview failed. Discard this draft and revise the behavior.")
			return
		arguments["message"] = _message.text.strip_edges()
	elif action == "restore":
		arguments["revision"] = _state.get("revision", "")
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
		"stage", "author":
			_tabs.current_tab = 1
		"live":
			_busy = true
			_sync_controls()
			var activated: Dictionary = await _preview_behavior.call(result.live)
			_busy = false
			_status.text = activated.message
			_sync_controls()
		"check":
			_tabs.current_tab = 2
		"discard", "apply", "restore":
			var finished: Dictionary = _finish_behavior.call(action, arguments.get("id", ""))
			var live_subject := "shoreline look" if draft is Dictionary and draft.get("shoreline", false) else "behavior"
			_buffers.clear()
			_message.clear()
			if not _source.is_empty():
				var previous := _source
				_source = ""
				await _open_file(previous)
			var short: String = result.get("commit", "").left(7)
			var messages := {"discard": "Discarded the Git draft.",
				"apply": "Committed %s. The %s stays active." % [short, live_subject] if finished.live else "Committed %s. Restart Euclid to load it here." % short,
				"restore": "Created revert %s. Restart Euclid for changes outside live previews." % short}
			_status.text = messages[action]
			if not result.get("warning", "").is_empty():
				_status.text += " " + result.warning
			if not finished.get("warning", "").is_empty():
				_status.text += " " + finished.warning
			if action != "discard":
				await _refresh_catalog()
			_sync_controls()

func _refresh_catalog() -> void:
	_busy = true
	_sync_controls()
	var result := await _client.send("catalog")
	_busy = false
	if result.has("error"):
		return
	_files.clear()
	_files.add_item("Choose a source file")
	for file in result.get("files", []):
		_files.add_item(file)
		if file == _source:
			_files.select(_files.item_count - 1)

func _poll(force := false) -> void:
	if _busy or not is_visible_in_tree():
		return
	if not force and not _state.get("playing", false) and _state.get("operation", "") != "checking":
		if _live_status() == "failed":
			_status.text = "Live preview failed. The previous behavior is active."
			_sync_controls()
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
		var messages := {"staged": "Review the Git diff before running the edited code.",
			"checking": "Checking the disposable project…", "passed": "Checks passed. Play the preview or commit the draft."}
		_status.text = "%s  ·  %s" % [draft.name, draft.error if draft.status == "failed" else messages[draft.status]]
		if draft.status == "staged" and not draft.get("summary", "").is_empty():
			_status.text = draft.summary + " Review the diff before previewing."
		if result.get("playing", false):
			_status.text = "The preview is open in a separate Euclid window."
		elif _live_status() == "failed":
			_status.text = "Live preview failed. The previous behavior is active."
		elif _live_status() == "active" and draft.status != "checking":
			_status.text += " Live preview active."
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
	_buttons.close_file.disabled = not editing
	_editor.editable = editing
	_request.editable = not blocked and not staged
	_buttons.propose.disabled = not editing or _request.text.strip_edges().is_empty()
	_buttons.author.disabled = blocked or staged or _request.text.strip_edges().is_empty() or not _changed_files().is_empty()
	_buttons.stage.disabled = blocked or staged or _changed_files().is_empty()
	_buttons.check.disabled = blocked or not staged or playing
	var live := _live_status()
	_buttons.live.disabled = blocked or not staged or not draft.get("live", false) or live == "active" \
		or (draft.get("shoreline", false) and draft.status != "passed")
	var passed: bool = staged and draft.status == "passed"
	_buttons.play.disabled = blocked or not passed or playing
	_buttons.stop.disabled = blocked or not playing
	_message.visible = passed
	_message.editable = not blocked
	_buttons.apply.disabled = blocked or not passed or live == "failed" or _message.text.strip_edges().is_empty()
	_buttons.discard.disabled = _busy or not staged or (blocked and _state.get("operation") != "checking")
	_buttons.restore.disabled = blocked or staged or str(_state.get("revision", "")).is_empty()
	_buttons.restore.tooltip_text = str(_state.get("revision", ""))
	_buttons.restart.disabled = blocked or staged

func _live_status() -> String:
	var draft: Variant = _state.get("draft")
	return _behavior_status.call(draft.id) if draft is Dictionary else ""
