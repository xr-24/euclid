extends MarginContainer
## F4 Workbench: a small IDE for Euclid's own source. Files open in tabs from the sidebar or
## Ctrl+P, and every edit stays a buffer until it is staged as a Git draft, checked, previewed
## and committed through the gateway.

signal close_requested
signal restart_requested
signal view_changed(file: String, tab: String)
signal commit_recorded(revision: String)
signal draft_reviewed(id: String, version: String)

const Client = preload("res://scripts/agents/workbench_client.gd")
const Look = preload("res://scripts/ui/terminal_theme.gd")
const Highlighters = preload("res://scripts/ui/code_highlighters.gd")
const CodeEditor = preload("res://scripts/ui/code_editor.gd")
const Effects = preload("res://scripts/ui/code_fx.gd")
const FindBar = preload("res://scripts/ui/find_bar.gd")
const QuickOpen = preload("res://scripts/ui/quick_open.gd")
const GlowLayer = preload("res://scripts/ui/glow_layer.gd")
const Diagnostics = preload("res://scripts/ui/workbench_diagnostics.gd")
const TerminalView = preload("res://scripts/ui/terminal_view.gd")
const AgentsPanel = preload("res://scripts/ui/agents_panel.gd")
const PREVIEW_ACTIONS := ["live", "check", "play", "stop", "apply", "discard", "restore"]

## Unstaged buffers are kept here between sessions. Diagnostics point it elsewhere so they never
## touch the user's own edits.
static var saved_buffers_path := "user://workbench-buffers.json"
static var font_size := Look.FONT_SIZE
static var _location := RegEx.create_from_string("res://([\\w./-]+?\\.(?:gd|gdshader|gdshaderinc|json|tscn)):(\\d+)")

var _client: Client
var _skin: Theme
var _body := VBoxContainer.new()
var _sidebar := VBoxContainer.new()
var _filter := LineEdit.new()
var _tree := Tree.new()
var _tree_items := {}
var _expanded := {"world/": true, "world/scripts/": true}
var _tree_updating := false
var _file_tabs := TabBar.new()
var _tabs_updating := false
var _editor_host := VBoxContainer.new()
var _empty := Label.new()
var _diff: CodeEditor
var _log: CodeEditor
var _revision_diff: CodeEditor
var _diagnostics := Diagnostics.new()
var _tabs := TabContainer.new()
var _find := FindBar.new()
var _quick_open := QuickOpen.new()
var _request := LineEdit.new()
var _status := Label.new()
var _cursor := Label.new()
var _chip := Label.new()
var _buttons := {}
var _catalog := PackedStringArray()
var _source := ""
## name -> {"hash", "original", "editor"}
var _buffers := {}
var _message := LineEdit.new()
var _busy := false
var _save_pending := false
var _state := {}
var _preview_behavior: Callable
var _finish_behavior: Callable
var _behavior_status: Callable
var _plugin_context: Callable
var _benchmark: Callable
var _live_output: Callable
var _view_ready := false
var _requested_review := ""
var _requested_tab := ""
var _drafts := OptionButton.new()
var _drafts_updating := false
var _drafts_signature := ""
var _history: CodeEditor
var _terminal: TerminalView
var _agents_panel: AgentsPanel
var _poll_ticks := 0

## Source locations named in a check log, as {"path": "world/...", "line": zero-based line}.
static func error_locations(log: String) -> Array:
	var found := []
	var seen := {}
	for hit in _location.search_all(log):
		var entry := {"path": "world/" + hit.get_string(1), "line": hit.get_string(2).to_int() - 1}
		var key := "%s:%d" % [entry.path, entry.line]
		if not seen.has(key):
			seen[key] = true
			found.append(entry)
	return found

## One entry in the draft picker: who holds the draft, its files and its state.
static func draft_label(entry: Dictionary) -> String:
	var holder: String = str(entry.get("owner", ""))
	var files: Array = entry.get("files", [])
	var count: String = "1 file" if files.size() == 1 else "%d files" % files.size()
	var label := "%s · %s · %s" % ["Your draft" if holder.is_empty() else holder, count, str(entry.get("status", ""))]
	if entry.get("behind_main", false):
		label += " · behind main"
	return label

## The Workbench journal as text, newest first.
static func history_text(entries: Array) -> String:
	if entries.is_empty():
		return "No Workbench history yet."
	var lines := PackedStringArray()
	for entry in entries:
		if not (entry is Dictionary):
			continue
		var at := str(entry.get("at", ""))
		var when: String = at.substr(5, 11).replace("T", " ") if at.length() >= 16 else at
		var event := str(entry.get("event", ""))
		var who := str(entry.get("owner", ""))
		var parts := PackedStringArray([when, "%-17s" % event, "you" if who.is_empty() else who])
		var id := str(entry.get("draft", ""))
		if not id.is_empty():
			parts.append(id.left(8))
		match event:
			"checked":
				parts.append("%s (%s)" % [str(entry.get("status", "")), str(entry.get("scope", "full"))])
			"committed", "reverted", "rebased":
				parts.append(str(entry.get("commit", "")).left(7))
		if entry.get("message") is String:
			parts.append(str(entry.message))
		var files: Variant = entry.get("files")
		if files is Array and not files.is_empty():
			parts.append(str(files[0]) if files.size() == 1 else "%s +%d" % [str(files[0]), files.size() - 1])
		if entry.get("error") is String:
			parts.append("— " + str(entry.error).get_slice("\n", 0))
		lines.append("  ".join(parts))
	return "\n".join(lines)

func setup(url: String, token: String, capability: String, preview_behavior: Callable, finish_behavior: Callable,
		behavior_status: Callable, plugin_context: Callable, saved_view := {}, benchmark := Callable(),
		live_output := Callable()) -> void:
	_preview_behavior = preview_behavior
	_finish_behavior = finish_behavior
	_behavior_status = behavior_status
	_plugin_context = plugin_context
	_benchmark = benchmark
	_live_output = live_output
	_client = Client.new()
	add_child(_client)
	_client.configure(url, token, capability)
	_skin = Look.make_theme(font_size)
	theme = _skin
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 8)
	add_child(_body)

	var title := HBoxContainer.new()
	title.add_theme_constant_override("separation", 10)
	_body.add_child(title)
	var heading := Label.new()
	heading.text = "◆ WORKBENCH"
	heading.add_theme_color_override("font_color", Look.ACCENT)
	heading.add_theme_font_size_override("font_size", 20)
	title.add_child(heading)
	_chip.add_theme_color_override("font_color", Look.MUTED)
	_chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_child(_chip)
	var fx := _button(title, "FX", func() -> void: pass)
	fx.toggle_mode = true
	fx.button_pressed = Effects.enabled
	fx.tooltip_text = "Text effects and glow"
	fx.toggled.connect(func(on: bool) -> void: Effects.enabled = on)
	_button(title, "×", func() -> void: close_requested.emit()).tooltip_text = "Close (F4)"

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 0
	_body.add_child(split)
	_sidebar.custom_minimum_size.x = 250
	_sidebar.add_theme_constant_override("separation", 6)
	split.add_child(_sidebar)
	_drafts.tooltip_text = "Open drafts. Pick one to review it, or your files to edit beside agents' drafts."
	_drafts.visible = false
	_drafts.item_selected.connect(_on_draft_selected)
	title.add_child(_drafts)
	title.move_child(_drafts, _chip.get_index() + 1)
	_filter.placeholder_text = "Filter files   Ctrl+P"
	_filter.text_changed.connect(func(_text: String) -> void: _build_tree())
	_sidebar.add_child(_filter)
	_tree.hide_root = true
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.item_selected.connect(_on_tree_selected)
	_tree.item_collapsed.connect(func(item: TreeItem) -> void:
		if _tree_updating:
			return
		var key: String = item.get_metadata(0)
		if item.collapsed:
			_expanded.erase(key)
		else:
			_expanded[key] = true)
	_sidebar.add_child(_tree)

	var main := VBoxContainer.new()
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 6)
	split.add_child(main)
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.custom_minimum_size.y = 220
	_tabs.tab_changed.connect(func(_index: int) -> void: _update_cursor())
	_tabs.tab_changed.connect(func(_index: int) -> void: _remember_view())
	main.add_child(_tabs)
	var source := VBoxContainer.new()
	source.name = "Source"
	source.add_theme_constant_override("separation", 0)
	_tabs.add_child(source)
	var file_row := HBoxContainer.new()
	source.add_child(file_row)
	_file_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_file_tabs.clip_tabs = true
	_file_tabs.tab_close_display_policy = TabBar.CLOSE_BUTTON_SHOW_ACTIVE_ONLY
	_file_tabs.tab_changed.connect(func(index: int) -> void:
		if not _tabs_updating:
			_select_file(_file_tabs.get_tab_metadata(index)))
	_file_tabs.tab_close_pressed.connect(_close_tab)
	file_row.add_child(_file_tabs)
	_buttons["reload"] = _button(file_row, "Reload", _reload)
	_buttons.reload.tooltip_text = "Reload the file from disk and discard its unreviewed edits"
	_buttons["close_file"] = _button(file_row, "Close", _close_file)
	_buttons.close_file.tooltip_text = "Close the file and discard its unreviewed edits (Ctrl+W)"
	_editor_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	source.add_child(_editor_host)
	_empty.text = "Choose a file from the sidebar, or press Ctrl+P.\n\nCtrl+F find · Ctrl+H replace · Ctrl+G go to line\nCtrl+/ comment · Alt+↑↓ move lines · Ctrl+Shift+D duplicate\nCtrl+Space complete · Ctrl+S keep edits · Ctrl+B sidebar"
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_empty.add_theme_color_override("font_color", Look.DIM)
	_editor_host.add_child(_empty)
	_diff = _output_tab("Diff", Highlighters.diff())
	_log = _output_tab("Checks", Highlighters.check_log())
	_log.gui_input.connect(_on_log_input)
	_revision_diff = _output_tab("Revision", Highlighters.diff())
	_tabs.set_tab_hidden(3, true)
	_diagnostics.setup(_benchmark_command.bind("benchmark"), _benchmark_command.bind("cancelbenchmark"))
	_tabs.add_child(_diagnostics)
	_history = _output_tab("History", Highlighters.check_log())
	_terminal = TerminalView.new()
	_terminal.name = "Terminal"
	_tabs.add_child(_terminal)
	_terminal.setup(url, token, capability)
	var agents_scroll := ScrollContainer.new()
	agents_scroll.name = "Agents"
	agents_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(agents_scroll)
	_agents_panel = AgentsPanel.new()
	_agents_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	agents_scroll.add_child(_agents_panel)
	_agents_panel.setup(url, token, capability)
	_tabs.tab_changed.connect(func(index: int) -> void:
		var shown := _tabs.get_tab_control(index)
		if shown == _history:
			_load_history()
		elif shown == _terminal:
			_terminal.start()
			_terminal.grab_focus.call_deferred()
		elif shown == agents_scroll:
			_agents_panel.refresh())
	main.add_child(_find)

	var prompt_row := HBoxContainer.new()
	_body.add_child(prompt_row)
	_request.placeholder_text = "Describe a plugin or an edit to the open files"
	_request.max_length = 600
	_request.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_request.text_changed.connect(func(_text: String) -> void: _sync_controls())
	_request.text_submitted.connect(func(_text: String) -> void:
		if _buttons.revise.visible:
			_revise()
		else:
			_propose())
	prompt_row.add_child(_request)
	_buttons["propose"] = _button(prompt_row, "Ask Codex", _propose)
	_buttons["author"] = _button(prompt_row, "Create plugin", _author)
	_buttons.author.tooltip_text = "Draft a new behavior for entities in this Grid space"
	_buttons.propose.tooltip_text = "Codex can edit up to six open files. Open each one first."
	_buttons["stage"] = _button(prompt_row, "Review diff", _stage)
	_buttons["revise"] = _button(prompt_row, "Revise draft", _revise)
	_buttons["previous"] = _button(prompt_row, "Restore previous", _command.bind("previous"))
	_buttons.previous.tooltip_text = "Restore the previous patch and run fresh checks before previewing"

	var controls := HBoxContainer.new()
	_body.add_child(controls)
	var labels := ["Preview live", "Run checks", "Play preview", "Stop preview", "Commit", "Discard", "Revert last"]
	for index in PREVIEW_ACTIONS.size():
		var action: String = PREVIEW_ACTIONS[index]
		_buttons[action] = _button(controls, labels[index], _command.bind(action))
	_buttons["rebase"] = _button(controls, "Rebase", _command.bind("rebase"))
	_buttons.rebase.tooltip_text = "Replay this draft onto the tip of the main branch, then run checks again"
	_buttons["restart"] = _button(controls, "Restart Euclid", func() -> void: restart_requested.emit())
	_message.placeholder_text = "Commit message"
	_message.max_length = 100
	_message.text_changed.connect(func(_text: String) -> void: _sync_controls())
	_body.add_child(_message)
	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 16)
	_body.add_child(status_row)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.add_theme_color_override("font_color", Look.INK)
	status_row.add_child(_status)
	_cursor.add_theme_color_override("font_color", Look.MUTED)
	status_row.add_child(_cursor)
	add_child(_quick_open)
	_quick_open.chosen.connect(_select_file)
	add_child(GlowLayer.new())
	var timer := Timer.new()
	timer.wait_time = 2.0
	timer.timeout.connect(_poll)
	add_child(timer)
	timer.start()
	var autosave := Timer.new()
	autosave.wait_time = 5.0
	autosave.timeout.connect(func() -> void:
		if _save_pending:
			_save_buffers(false))
	add_child(autosave)
	autosave.start()
	_load_catalog(saved_view)

func _button(parent: Control, label: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(34, 32)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _output_tab(title: String, colors: SyntaxHighlighter) -> CodeEditor:
	var view := CodeEditor.new()
	view.name = title
	view.editable = false
	view.minimap_draw = false
	view.gutters_draw_fold_gutter = false
	view.syntax_highlighter = colors
	view.command_requested.connect(_on_editor_command)
	_tabs.add_child(view)
	return view

func _make_editor(file: String) -> CodeEditor:
	var editor := CodeEditor.new()
	editor.use_language_of(file)
	editor.visible = false
	editor.extra_words = _other_words.bind(file)
	editor.command_requested.connect(_on_editor_command)
	editor.text_changed.connect(_on_buffer_edited)
	editor.caret_changed.connect(_update_cursor)
	_editor_host.add_child(editor)
	return editor

func _current_editor() -> CodeEditor:
	return _buffers[_source].editor if _buffers.has(_source) else null

func _active_editor() -> CodeEditor:
	match _tabs.current_tab:
		1:
			return _diff
		2:
			return _log
		3:
			return _revision_diff
		4:
			return null
	return _current_editor()

func _other_words(except: String) -> PackedStringArray:
	var words := PackedStringArray()
	for name in _buffers:
		if name != except:
			words.append_array(_buffers[name].editor.document_words())
	return words

func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or not is_visible_in_tree():
		return
	var command := CodeEditor.command_for(key)
	if command in ["find", "replace", "goto", "quick_open", "toggle_sidebar", "save", "next_file", "previous_file",
			"close_file", "zoom_in", "zoom_out"]:
		get_viewport().set_input_as_handled()
		_on_editor_command(command)

func _on_editor_command(command: String) -> void:
	match command:
		"find", "replace", "goto":
			var target := _active_editor()
			if target != null:
				_find.open(command, target)
		"quick_open":
			if not _busy:
				_quick_open.open(_catalog, _skin)
		"toggle_sidebar":
			_sidebar.visible = not _sidebar.visible
		"save":
			_save_buffers(true)
		"close_file":
			if not _buttons.close_file.disabled:
				_close_file()
		"next_file", "previous_file":
			if _file_tabs.tab_count > 1:
				var step := 1 if command == "next_file" else -1
				_file_tabs.current_tab = posmod(_file_tabs.current_tab + step, _file_tabs.tab_count)
		"zoom_in", "zoom_out":
			font_size = clampi(font_size + (1 if command == "zoom_in" else -1), 11, 28)
			_skin.default_font_size = font_size

func _load_catalog(saved_view: Dictionary) -> void:
	_busy = true
	_sync_controls()
	var result := await _client.send("catalog")
	_catalog = PackedStringArray(result.get("files", []))
	_build_tree()
	_busy = false
	if result.has("error"):
		_status.text = result.error
		_sync_controls()
		return
	var file: String = saved_view.get("file", "")
	if _catalog.has(file):
		await _open_file(file)
	await _poll(true)
	var draft: Variant = _state.get("draft")
	if not _requested_tab.is_empty():
		show_tab(_requested_tab)
	elif not _requested_review.is_empty():
		show_review(_requested_review == "Checks")
	elif saved_view.get("tab") == "Diagnostics":
		_tabs.current_tab = 4
	elif draft is Dictionary:
		var tab: int = ["Source", "Diff", "Checks", "Revision"].find(saved_view.get("tab", ""))
		if tab < 0 or _tabs.is_tab_hidden(tab):
			tab = 2 if draft.status == "failed" else 1
		_tabs.current_tab = tab
	_view_ready = true
	_remember_view()

func _remember_view() -> void:
	if _view_ready:
		view_changed.emit(_source, _tabs.get_tab_title(_tabs.current_tab))

func _build_tree() -> void:
	_tree_updating = true
	_tree.clear()
	_tree_items.clear()
	var root := _tree.create_item()
	var folders := {}
	var filter := _filter.text.strip_edges()
	for path in _catalog:
		if not filter.is_empty() and QuickOpen.score(filter, path) < 0:
			continue
		var parts := path.split("/")
		var parent := root
		var key := ""
		for index in parts.size() - 1:
			key += parts[index] + "/"
			if not folders.has(key):
				var folder := _tree.create_item(parent)
				folder.set_text(0, parts[index])
				folder.set_metadata(0, key)
				folder.set_custom_color(0, Look.DIM)
				folder.collapsed = filter.is_empty() and not _expanded.has(key)
				folders[key] = folder
			parent = folders[key]
		var item := _tree.create_item(parent)
		item.set_metadata(0, path)
		item.set_tooltip_text(0, path)
		_tree_items[path] = item
	_mark_tree()
	_tree_updating = false

func _mark_tree() -> void:
	var edited := {}
	for item in _changed_files():
		edited[item.name] = true
	for path in _tree_items:
		var item: TreeItem = _tree_items[path]
		item.set_text(0, ("● " if edited.has(path) else "") + path.get_file())
		item.set_custom_color(0, Look.WARN if edited.has(path) else (Look.BRIGHT if path == _source else
			(Look.INK if _buffers.has(path) else Look.MUTED)))

func _on_tree_selected() -> void:
	if _tree_updating:
		return
	var item := _tree.get_selected()
	if item == null:
		return
	var key: String = item.get_metadata(0)
	if key.ends_with("/"):
		item.collapsed = not item.collapsed
		item.deselect(0)
		return
	if _tree_locked():
		_status.text = "Finish or discard the current draft before opening other files."
		return
	_select_file(key)

func _tree_locked() -> bool:
	return _busy or not str(_state.get("operation", "")).is_empty() or _state.get("draft") is Dictionary

func _select_file(file: String) -> void:
	if _busy or file.is_empty():
		return
	if _buffers.has(file):
		_show_file(file)
	elif _tree_locked():
		_status.text = "Finish or discard the current draft before opening other files."
	else:
		await _open_file(file)

func _reload() -> void:
	_forget_saved(_source)
	await _open_file(_source)

func _open_file(file: String) -> void:
	_busy = true
	_sync_controls()
	var result := await _client.send("read", {"name": file})
	_busy = false
	if result.has("error"):
		_status.text = result.error
		_sync_controls()
		return
	var original: String = result.text.replace("\r\n", "\n")
	var editor: CodeEditor = _buffers[file].editor if _buffers.has(file) else _make_editor(file)
	_buffers[file] = {"hash": result.hash, "original": original, "editor": editor}
	if _tab_index(file) < 0:
		_tabs_updating = true
		_file_tabs.add_tab(file.get_file())
		_file_tabs.set_tab_metadata(_file_tabs.tab_count - 1, file)
		_file_tabs.set_tab_tooltip(_file_tabs.tab_count - 1, file)
		_tabs_updating = false
	editor.load_text(original)
	_show_file(file)
	editor.grab_focus()
	var saved: Dictionary = _saved_buffers().get(file, {})
	if saved.get("hash") == result.hash and saved.get("text", original) != original:
		editor.replace_text(saved.text)
		_status.text = "Restored your unstaged edits to %s. Ctrl+Z returns to the file on disk." % file.get_file()
	_sync_controls()

func _tab_index(file: String) -> int:
	for index in _file_tabs.tab_count:
		if _file_tabs.get_tab_metadata(index) == file:
			return index
	return -1

func _show_file(file: String) -> void:
	_source = file
	for name in _buffers:
		_buffers[name].editor.visible = name == file
	_empty.visible = _buffers.is_empty() or not _buffers.has(file)
	_tabs_updating = true
	var index := _tab_index(file)
	if index >= 0:
		_file_tabs.current_tab = index
	_tabs_updating = false
	_tabs.current_tab = 0
	_status.text = "%s  ·  %d lines" % [file, _buffers[file].editor.get_line_count()]
	_mark_errors()
	_refresh_tabs()
	_update_cursor()
	_sync_controls()
	_remember_view()

func _close_tab(index: int) -> void:
	var file: String = _file_tabs.get_tab_metadata(index)
	if file == _source:
		_close_file()
	elif not _tree_locked():
		_close_buffer(file)
		_refresh_tabs()

func _close_file() -> void:
	if _source.is_empty():
		return
	var index := _tab_index(_source)
	_close_buffer(_source)
	_source = ""
	if _file_tabs.tab_count > 0:
		_show_file(_file_tabs.get_tab_metadata(clampi(index, 0, _file_tabs.tab_count - 1)))
	else:
		_empty.visible = true
		_status.text = "No open files."
		_update_cursor()
		_mark_tree()
		_sync_controls()
		_remember_view()

func _close_buffer(file: String) -> void:
	if not _buffers.has(file):
		return
	var editor: CodeEditor = _buffers[file].editor
	_buffers.erase(file)
	editor.queue_free()
	var index := _tab_index(file)
	if index >= 0:
		_tabs_updating = true
		_file_tabs.remove_tab(index)
		_tabs_updating = false
	_forget_saved(file)

func _clear_buffers() -> void:
	for file in _buffers.keys():
		_close_buffer(file)
	_source = ""
	_empty.visible = true
	if FileAccess.file_exists(saved_buffers_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(saved_buffers_path))

func _refresh_tabs() -> void:
	var edited := {}
	for item in _changed_files():
		edited[item.name] = true
	for index in _file_tabs.tab_count:
		var file: String = _file_tabs.get_tab_metadata(index)
		_file_tabs.set_tab_title(index, ("● " if edited.has(file) else "") + file.get_file())
	_mark_tree()

func _on_buffer_edited() -> void:
	_save_pending = true
	_refresh_tabs()
	_sync_controls()

func _update_cursor() -> void:
	var editor := _active_editor()
	if editor == null:
		_cursor.text = ""
		return
	var edited := _changed_files().size()
	_cursor.text = "Ln %d, Col %d  ·  %s  ·  %d open%s" % [editor.get_caret_line() + 1, editor.get_caret_column() + 1,
		Highlighters.display_name(editor.syntax_language) if editor != _log and editor != _diff else _tabs.get_tab_title(_tabs.current_tab),
		_buffers.size(), " · %d edited" % edited if edited > 0 else ""]

func show_error(message: String) -> void:
	_status.text = message

func _changed_files() -> Array:
	var files := []
	for name in _buffers:
		var buffer: Dictionary = _buffers[name]
		var text: String = buffer.editor.text
		if text != buffer.original:
			files.append({"name": name, "hash": buffer.hash, "text": text})
	return files

## Unstaged edits survive a restart in the user data folder, keyed to the file's hash on disk.
func _saved_buffers() -> Dictionary:
	if not FileAccess.file_exists(saved_buffers_path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(saved_buffers_path))
	return parsed if parsed is Dictionary else {}

func _save_buffers(announce: bool) -> void:
	_save_pending = false
	var saved := _saved_buffers()
	for name in _buffers:
		saved.erase(name)
	var changed := _changed_files()
	for item in changed:
		saved[item.name] = {"hash": item.hash, "text": item.text}
	var file := FileAccess.open(saved_buffers_path, FileAccess.WRITE)
	if file == null:
		if announce:
			_status.text = "Could not keep the edits locally: %s" % error_string(FileAccess.get_open_error())
		return
	file.store_string(JSON.stringify(saved))
	file.close()
	if announce:
		_status.text = "Kept %d edited file(s) on this PC. Review diff stages them as a Git draft." % changed.size()

func _forget_saved(file: String) -> void:
	var saved := _saved_buffers()
	if saved.erase(file):
		var stream := FileAccess.open(saved_buffers_path, FileAccess.WRITE)
		if stream != null:
			stream.store_string(JSON.stringify(saved))

func _propose() -> void:
	if _buttons.propose.disabled:
		return
	var files := []
	for name in _buffers:
		files.append({"name": name, "hash": _buffers[name].hash, "text": _buffers[name].editor.text})
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
			if _buffers.has(item.name):
				_buffers[item.name].editor.replace_text(item.text.replace("\r\n", "\n"))
		_show_file(_source)
		_status.text = result.summary + " Ctrl+Z undoes it."
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

func _revise() -> void:
	if not _buttons.revise.disabled:
		await _command("revise", {"prompt": _request.text.strip_edges()})

func _benchmark_command(action: String) -> void:
	if _busy or not _benchmark.is_valid():
		return
	var draft: Variant = _state.get("draft")
	var arguments := {}
	if action == "cancelbenchmark":
		arguments["id"] = _state.diagnostic_job.id
	elif draft is Dictionary:
		arguments = {"id": draft.id, "version": draft.version}
	_busy = true
	_sync_controls()
	var result: Dictionary = await _benchmark.call(action, arguments)
	_busy = false
	if result.has("error"):
		show_error(result.error)
		_sync_controls()
		return
	_show_state(result)

func _command(action: String, arguments := {}) -> void:
	if _busy:
		return
	var draft: Variant = _state.get("draft")
	if draft is Dictionary:
		arguments["id"] = draft.id
		arguments["version"] = draft.get("version", "")
		if action == "revise" and _live_output.is_valid():
			arguments["live_preview_output"] = _live_output.call(draft.id, arguments.version)
		if action == "discard" and draft.status == "revising":
			arguments["cancel_revision"] = true
		if action == "stop" and draft.get("subject") == "grid_palette" and _live_status() == "active":
			_finish_behavior.call("stop_palette", draft.id)
			_status.text = "Restored the working Grid palette. The checked draft is still available."
			_sync_controls()
			return
	if action == "apply":
		if _live_status() == "failed":
			show_error("The live preview failed. Revise the draft before committing.")
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
		"rebase":
			_tabs.current_tab = 1
			_status.text = "Rebased onto the main branch. Review the diff and run checks again."
			_sync_controls()
		"stage", "author":
			_tabs.current_tab = 1
		"live":
			_busy = true
			_sync_controls()
			var activated: Dictionary = await _preview_behavior.call(result.live)
			_busy = false
			_status.text = activated.message
			if not activated.ok and draft.get("subject") == "grid_palette":
				_tabs.current_tab = 4
			_sync_controls()
		"check":
			_tabs.current_tab = 2
		"revise":
			_request.clear()
			_tabs.current_tab = 2
			_sync_controls()
		"previous":
			_tabs.current_tab = 3
		"discard", "apply", "restore":
			# Cancelling a revision keeps the same draft. Another open draft may come into view instead.
			if action == "discard" and result.get("draft") is Dictionary and result.draft.id == arguments.get("id", ""):
				return
			var finished: Dictionary = _finish_behavior.call(action, arguments.get("id", ""))
			var subjects := {"shoreline": "shoreline look", "grid": "Grid scenery", "behavior": "behavior",
				"workshop_tool": "workshop action", "grid_palette": "Grid palette"}
			var live_subject: String = subjects.get(draft.get("subject"), "preview") if draft is Dictionary else "preview"
			var previous := _source
			_clear_buffers()
			_message.clear()
			if not previous.is_empty():
				await _open_file(previous)
			var short: String = result.get("commit", "").left(7)
			if action == "apply":
				commit_recorded.emit(result.commit)
			var activation: String = draft.get("activation", "") if draft is Dictionary else ""
			var applied := "Committed %s. Restart Euclid to load it here." % short
			if finished.get("live", false):
				applied = "Committed %s. The %s stays active." % [short, live_subject]
			elif activation == "gateway_restart":
				applied = "Committed %s." % short
			elif activation == "none":
				applied = "Committed %s. Nothing needs a restart." % short
			var messages := {"discard": "Discarded the Git draft.", "apply": applied,
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
	_catalog = PackedStringArray(result.get("files", []))
	_build_tree()

func _poll(force := false) -> void:
	if _busy or not is_visible_in_tree():
		return
	# Idle panels still look in now and then, so a draft a connected agent opens shows up.
	_poll_ticks += 1
	var open_drafts: Array = _state.get("drafts", [])
	var idle: bool = _state.get("draft") == null and _state.get("diagnostic_job") == null \
		and not _state.get("playing", false) and open_drafts.is_empty()
	if not force and idle and _poll_ticks % 5 != 0:
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
	if force or result != _state:
		_show_state(result)

## Shows a tab by its title, such as Terminal or Agents. Before the first load finishes, the
## request waits so the restored view does not replace it.
func show_tab(title: String) -> void:
	if not _view_ready:
		_requested_tab = title
	for index in _tabs.get_tab_count():
		if _tabs.get_tab_title(index) == title and not _tabs.is_tab_hidden(index):
			_tabs.current_tab = index
			return

func show_review(logs := false) -> void:
	if not _view_ready:
		_requested_review = "Checks" if logs else "Diff"
	_tabs.current_tab = 2 if logs else (1 if _tabs.is_tab_hidden(3) else 3)

func _show_state(result: Dictionary) -> void:
	var prior: Variant = _state.get("draft")
	_state = result
	_update_draft_picker(result)
	var draft: Variant = result.get("draft")
	if draft is Dictionary:
		draft_reviewed.emit(draft.id, draft.get("version", ""))
	var has_previous: bool = draft is Dictionary and draft.get("has_previous", false)
	if not has_previous and _tabs.current_tab == 3:
		_tabs.current_tab = 1
	_tabs.set_tab_hidden(3, not has_previous)
	var delta: String = draft.get("revision_diff", "") if has_previous else ""
	if _revision_diff.text != delta:
		_show_diff(_revision_diff, delta)
	if has_previous and prior is Dictionary and prior.status == "revising" and draft.status == "staged":
		_tabs.current_tab = 3
	if draft is Dictionary:
		if _diff.text != draft.diff:
			_show_diff(_diff, draft.diff)
		if _log.text != draft.log:
			# A growing log streams in; a replaced one scans in.
			var growing: bool = not _log.text.is_empty() and draft.log.begins_with(_log.text)
			_log.fx.show_text(draft.log, growing)
			_log.set_caret_line(_log.get_line_count() - 1)
			_mark_errors()
		var messages := {"authoring": "Codex is working in a separate source workspace.", "staged": "Review the Git diff before running the edited code.",
			"revising": "Codex is revising a copy of the active draft.",
			"checking": "Checking the disposable project…", "passed": "Checks passed. Play the preview or commit the draft."}
		var activation := {"live": "Live swap", "reload_grid": "Grid scenery reload",
			"reload_palette": "Grid palette reload", "restart": "Restart Euclid", "gateway_restart": "Gateway reload",
			"none": "No restart"}
		_status.text = "%s  ·  %s  ·  %s" % [draft.name, activation.get(draft.get("activation"), "Restart Euclid"),
			draft.error if draft.status == "failed" else messages[draft.status]]
		if draft.status == "staged":
			if draft.get("check_status") == "passed":
				_status.text = "Previous checks passed. Run checks again to preview or commit."
			elif not draft.get("summary", "").is_empty():
				_status.text = draft.summary + " Review the diff before previewing."
		if draft.get("behind_main", false) and draft.status in ["staged", "passed", "failed"]:
			_status.text = "The main branch moved past this draft. Rebase it, then run checks again."
		if not draft.get("revision_notice", "").is_empty():
			_status.text = draft.revision_notice
		elif result.get("playing", false) and draft.status != "revising":
			_status.text = "The preview is open in a separate Euclid window."
		elif _live_status() == "failed":
			_status.text = "Live preview failed. The previous version is active."
		elif _live_status() == "active" and draft.status != "checking":
			_status.text += " Live preview active."
		var chip_colors := {"failed": Look.ERROR, "passed": Look.GOOD, "checking": Look.WARN, "authoring": Look.WARN, "revising": Look.WARN}
		var holder: String = draft.get("owner", "")
		_chip.text = "draft · %s" % draft.status if holder.is_empty() else "draft · %s · %s" % [holder, draft.status]
		_chip.add_theme_color_override("font_color", chip_colors.get(draft.status, Look.ACCENT))
	else:
		if not _diff.text.is_empty():
			_diff.fx.show_text("")
		if not _log.text.is_empty():
			_log.fx.show_text("")
		_mark_errors()
		var revision: String = result.get("revision", "")
		_chip.text = "" if revision.is_empty() else "commit · " + revision.left(7)
		_chip.add_theme_color_override("font_color", Look.GOOD)
		var waiting: Array = result.get("drafts", [])
		if not waiting.is_empty():
			_status.text = "%d open %s. Pick one from the drafts list to review it." % [waiting.size(), "draft" if waiting.size() == 1 else "drafts"]
		elif _buffers.is_empty():
			_status.text = "Choose a source file to start."
	_sync_controls()
	if _tabs.get_current_tab_control() == _history:
		_load_history.call_deferred()

## Lists the open drafts. "Your files" shows the main checkout when the person has no draft of their own.
func _update_draft_picker(result: Dictionary) -> void:
	var entries: Array = result.get("drafts", [])
	var focus := str(result.get("focus", ""))
	var signature := "%s|%s" % [focus, JSON.stringify(entries)]
	if signature == _drafts_signature:
		return
	_drafts_signature = signature
	var own_draft := false
	for entry in entries:
		if entry is Dictionary and str(entry.get("owner", "")).is_empty():
			own_draft = true
	_drafts_updating = true
	_drafts.clear()
	if not own_draft:
		_drafts.add_item("Your files")
		_drafts.set_item_metadata(_drafts.item_count - 1, "")
	for entry in entries:
		if entry is Dictionary:
			_drafts.add_item(draft_label(entry))
			_drafts.set_item_metadata(_drafts.item_count - 1, str(entry.get("id", "")))
	_drafts.selected = -1
	for index in _drafts.item_count:
		if str(_drafts.get_item_metadata(index)) == focus:
			_drafts.selected = index
	_drafts.visible = not entries.is_empty()
	_drafts_updating = false

func _on_draft_selected(index: int) -> void:
	if _drafts_updating:
		return
	var id := str(_drafts.get_item_metadata(index))
	if _busy or id == str(_state.get("focus", "")):
		_drafts_signature = ""
		_update_draft_picker(_state)
		return
	_busy = true
	_sync_controls()
	var result := await _client.send("focus", {"id": id})
	_busy = false
	if result.has("error"):
		_status.text = result.error
		_drafts_signature = ""
		_update_draft_picker(_state)
		_sync_controls()
		return
	_show_state(result)
	_tabs.current_tab = 1 if result.get("draft") is Dictionary else 0

func _load_history() -> void:
	if _busy or _history == null:
		return
	_busy = true
	var result := await _client.send("history", {"limit": 60})
	_busy = false
	var text: String = str(result.error) if result.has("error") else history_text(result.get("entries", []))
	if _history.text != text:
		_history.fx.show_text(text)
	_sync_controls()

func _show_diff(editor: CodeEditor, text: String) -> void:
	editor.fx.show_text(text)
	for line in editor.get_line_count():
		var row := editor.get_line(line)
		if row.begins_with("+") and not row.begins_with("+++"):
			editor.set_line_background_color(line, Look.ADDED_BG)
		elif row.begins_with("-") and not row.begins_with("---"):
			editor.set_line_background_color(line, Look.REMOVED_BG)

func _mark_errors() -> void:
	var by_file := {}
	for entry in error_locations(_log.text):
		if not by_file.has(entry.path):
			by_file[entry.path] = []
		by_file[entry.path].append(entry.line)
	for name in _buffers:
		_buffers[name].editor.mark_errors(by_file.get(name, []))

func _on_log_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.double_click and click.button_index == MOUSE_BUTTON_LEFT:
		_open_log_location.call_deferred()

## Double-clicking a res:// location in the check log opens that file at the line.
func _open_log_location() -> void:
	var found := error_locations(_log.get_line(_log.get_caret_line()))
	if found.is_empty():
		return
	var entry: Dictionary = found[0]
	if not _catalog.has(entry.path) and not _buffers.has(entry.path):
		_status.text = "%s is outside the Workbench's editable files." % entry.path
		return
	await _select_file(entry.path)
	if _buffers.has(entry.path):
		_buffers[entry.path].editor.go_to_line(entry.line)

func _sync_controls() -> void:
	var draft: Variant = _state.get("draft")
	var staged := draft is Dictionary
	var playing: bool = _state.get("playing", false)
	var blocked := _busy or not str(_state.get("operation", "")).is_empty()
	var editing := not blocked and not staged and not _source.is_empty()
	_sidebar.modulate.a = 0.55 if blocked or staged else 1.0
	_buttons.reload.disabled = not editing
	_buttons.close_file.disabled = not editing
	for name in _buffers:
		_buffers[name].editor.editable = not blocked and not staged
	var revisable: bool = staged and draft.get("can_revise", false)
	_request.editable = not blocked and (not staged or revisable)
	_request.placeholder_text = "Describe a change to this draft" if revisable else "Describe a plugin or an edit to the open files"
	_buttons.revise.visible = revisable
	_buttons.revise.disabled = blocked or not revisable or _request.text.strip_edges().is_empty()
	_buttons.previous.visible = staged and draft.get("has_previous", false)
	_buttons.previous.disabled = blocked
	for action in ["propose", "author", "stage"]:
		_buttons[action].visible = not revisable
	_buttons.propose.disabled = not editing or _request.text.strip_edges().is_empty()
	_buttons.author.disabled = blocked or staged or _request.text.strip_edges().is_empty() or not _changed_files().is_empty()
	_buttons.stage.disabled = blocked or staged or _changed_files().is_empty()
	_buttons.check.disabled = blocked or not staged or draft.files.is_empty() or playing
	var live := _live_status()
	_buttons.live.text = "Preview Grid reload" if staged and draft.get("activation") == "reload_grid" else "Preview live"
	if staged and draft.get("subject") == "workshop_tool":
		_buttons.live.text = "Preview tool"
	if staged and draft.get("subject") == "grid_palette":
		_buttons.live.text = "Preview palette"
	_buttons.live.disabled = blocked or not staged or not draft.get("live", false) or live == "active" \
		or (draft.get("checked_preview", false) and draft.status != "passed")
	var passed: bool = staged and draft.status == "passed"
	_buttons.play.disabled = blocked or not passed or playing
	var palette_preview: bool = staged and draft.get("subject") == "grid_palette" and live == "active"
	_buttons.stop.disabled = blocked or (not playing and not palette_preview)
	_message.visible = passed
	_message.editable = not blocked
	_buttons.apply.disabled = blocked or not passed or live == "failed" or _message.text.strip_edges().is_empty()
	var operation: String = _state.get("operation", "")
	_buttons.discard.text = {"authoring": "Cancel authoring", "revising": "Cancel revision"}.get(operation, "Discard")
	_buttons.discard.disabled = _busy or not staged or (blocked and operation not in ["checking", "authoring", "revising"])
	_buttons.restore.disabled = blocked or staged or str(_state.get("revision", "")).is_empty()
	_buttons.restore.tooltip_text = str(_state.get("revision", ""))
	_buttons.restart.disabled = blocked or playing or live == "active"
	_buttons.rebase.visible = staged and draft.get("behind_main", false)
	_buttons.rebase.disabled = blocked or playing
	_drafts.disabled = _busy or str(_state.get("operation", "")) in ["authoring", "revising", "discarding"]
	var diagnostic_state := _state.duplicate()
	if staged and _live_output.is_valid():
		diagnostic_state["live_preview_log"] = _live_output.call(draft.id, draft.get("version", ""))
	_diagnostics.update(diagnostic_state, blocked or not _benchmark.is_valid())

func _live_status() -> String:
	var draft: Variant = _state.get("draft")
	return _behavior_status.call(draft.id) if draft is Dictionary else ""
