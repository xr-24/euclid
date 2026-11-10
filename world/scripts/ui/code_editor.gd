extends CodeEdit
## Workbench source editor: language setup, word completion and common editing commands.
## Commands it cannot finish alone (find, quick open, closing a tab) go to the owning panel.
signal command_requested(command: String)

const Look = preload("res://scripts/ui/terminal_theme.gd")
const Highlighters = preload("res://scripts/ui/code_highlighters.gd")
const Effects = preload("res://scripts/ui/code_fx.gd")
const MAX_SUGGESTIONS := 400

static var _word_pattern := RegEx.create_from_string("[A-Za-z_][A-Za-z0-9_]{2,}")

var syntax_language := "text"
var fx: Effects
## Returns more completion words, such as identifiers from the panel's other open files.
var extra_words := Callable()
var _errors: Array[int] = []
var _words := PackedStringArray()
var _words_stale := true
var _suggest := Timer.new()
var _last_length := 0
var _last_line := 0

## Adds or removes a line comment on every non-blank line. Lines that are all commented are
## uncommented; otherwise the token goes at the shallowest indentation.
static func toggle_comment_lines(lines: PackedStringArray, token: String) -> PackedStringArray:
	var indent := -1
	var commented := true
	for text in lines:
		var body := text.strip_edges(true, false)
		if body.is_empty():
			continue
		var lead := text.length() - body.length()
		indent = lead if indent < 0 else mini(indent, lead)
		if not body.begins_with(token):
			commented = false
	var result := PackedStringArray()
	for text in lines:
		if indent < 0 or text.strip_edges().is_empty():
			result.append(text)
		elif commented:
			var at := text.find(token)
			var cut := token.length() + (1 if text.substr(at + token.length(), 1) == " " else 0)
			result.append(text.substr(0, at) + text.substr(at + cut))
		else:
			result.append(text.substr(0, indent) + token + " " + text.substr(indent))
	return result

func _init() -> void:
	size_flags_horizontal = SIZE_EXPAND_FILL
	size_flags_vertical = SIZE_EXPAND_FILL
	wrap_mode = TextEdit.LINE_WRAPPING_NONE
	gutters_draw_line_numbers = true
	gutters_draw_fold_gutter = true
	line_folding = true
	highlight_current_line = true
	highlight_all_occurrences = true
	minimap_draw = true
	minimap_width = 84
	scroll_smooth = true
	scroll_past_end_of_file = true
	caret_blink = false
	auto_brace_completion_enabled = true
	auto_brace_completion_highlight_matching = true
	indent_automatic = true
	code_completion_enabled = true
	_suggest.one_shot = true
	_suggest.wait_time = 0.18
	_suggest.timeout.connect(func() -> void:
		if has_focus():
			request_code_completion())
	add_child(_suggest, false, Node.INTERNAL_MODE_FRONT)
	code_completion_requested.connect(_complete)
	text_changed.connect(_on_text_changed)
	fx = Effects.new()
	fx.attach(self)

func use_language_of(path: String) -> void:
	syntax_language = Highlighters.language_for(path)
	syntax_highlighter = Highlighters.for_language(syntax_language)
	indent_use_spaces = syntax_language == "json"
	indent_size = 2 if syntax_language == "json" else 4
	clear_comment_delimiters()
	clear_string_delimiters()
	match syntax_language:
		"gdscript":
			add_comment_delimiter("#", "", true)
			add_string_delimiter("\"\"\"", "\"\"\"", false)
			add_string_delimiter("\"", "\"", true)
			add_string_delimiter("'", "'", true)
		"shader":
			add_comment_delimiter("//", "", true)
			add_comment_delimiter("/*", "*/", false)
			add_string_delimiter("\"", "\"", true)
		"json", "scene":
			add_string_delimiter("\"", "\"", true)
	var openers: Array[String] = []
	openers.assign([":"] if syntax_language == "gdscript" else ["{", "[", "("])
	indent_automatic_prefixes = openers
	var triggers: Array[String] = ["."]
	code_completion_prefixes = triggers
	var guides: Array[int] = []
	if syntax_language == "gdscript":
		guides.append(100)
	line_length_guidelines = guides
	_words_stale = true

## Loads a document without making the load itself undoable.
func load_text(text: String) -> void:
	fx.show_text(text)
	clear_undo_history()
	set_caret_line(0)
	set_caret_column(0)
	_last_length = get_line(0).length()

## Replaces the document as one undoable step and shows the difference as it lands.
func replace_text(text: String) -> void:
	var line := get_caret_line()
	var column := get_caret_column()
	var scroll := get_v_scroll()
	fx.show_text(text, true)
	set_caret_line(mini(line, get_line_count() - 1))
	set_caret_column(column)
	set_v_scroll(scroll)

func go_to_line(line: int) -> void:
	var row := clampi(line, 0, get_line_count() - 1)
	set_caret_line(row)
	set_caret_column(get_first_non_whitespace_column(row))
	center_viewport_to_caret()
	grab_focus()

func mark_errors(lines: Array) -> void:
	for line in _errors:
		if line < get_line_count():
			set_line_background_color(line, Color(0, 0, 0, 0))
	_errors.clear()
	for line in lines:
		if line >= 0 and line < get_line_count():
			set_line_background_color(line, Look.ERROR_BG)
			_errors.append(line)

func toggle_comment() -> void:
	var token := Highlighters.comment_token(syntax_language)
	if token.is_empty() or not editable:
		return
	var first := get_caret_line()
	var last := first
	if has_selection():
		first = get_selection_from_line()
		last = get_selection_to_line()
		if last > first and get_selection_to_column() == 0:
			last -= 1
	var lines := PackedStringArray()
	for line in range(first, last + 1):
		lines.append(get_line(line))
	var toggled := toggle_comment_lines(lines, token)
	begin_complex_operation()
	for index in toggled.size():
		if toggled[index] != lines[index]:
			set_line(first + index, toggled[index])
	end_complex_operation()

func document_words() -> PackedStringArray:
	if _words_stale:
		var found := {}
		for match_result in _word_pattern.search_all(text):
			found[match_result.get_string()] = true
		_words = PackedStringArray(found.keys())
		_words_stale = false
	return _words

func _gui_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return
	var command := command_for(key)
	if command.is_empty():
		return
	accept_event()
	match command:
		"toggle_comment":
			toggle_comment()
		"duplicate_lines", "delete_lines", "move_lines_up", "move_lines_down":
			if editable and has_method(command):
				call(command)
		_:
			command_requested.emit(command)

## The panel command for a key chord, shared by the editors and the panel's own shortcuts.
static func command_for(key: InputEventKey) -> String:
	var control := key.is_command_or_control_pressed()
	if key.alt_pressed and not control:
		match key.keycode:
			KEY_UP:
				return "move_lines_up"
			KEY_DOWN:
				return "move_lines_down"
		return ""
	if not control:
		return ""
	match key.keycode:
		KEY_SLASH:
			return "toggle_comment"
		KEY_K:
			return "delete_lines" if key.shift_pressed else "toggle_comment"
		KEY_D:
			return "duplicate_lines" if key.shift_pressed else ""
		KEY_F:
			return "find"
		KEY_H:
			return "replace"
		KEY_G:
			return "goto"
		KEY_P:
			return "quick_open"
		KEY_W:
			return "close_file"
		KEY_B:
			return "toggle_sidebar"
		KEY_S:
			return "save"
		KEY_TAB:
			return "previous_file" if key.shift_pressed else "next_file"
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
			return "zoom_in"
		KEY_MINUS, KEY_KP_SUBTRACT:
			return "zoom_out"
	return ""

func _on_text_changed() -> void:
	_words_stale = true
	var line := get_caret_line()
	var length := get_line(line).length()
	var typed_one := line == _last_line and length == _last_length + 1
	_last_line = line
	_last_length = length
	if not typed_one or not editable or not has_focus() or syntax_language == "text":
		_suggest.stop()
		return
	var text_line := get_line(line)
	var column := get_caret_column()
	if column >= 2 and _is_word(text_line, column - 1) and _is_word(text_line, column - 2) \
			and not _is_word(text_line, column) and is_in_comment(line, column) == -1 and is_in_string(line, column) == -1:
		_suggest.start()
	else:
		_suggest.stop()

func _complete() -> void:
	var line := get_line(get_caret_line())
	var start := get_caret_column()
	while start > 0 and _is_word(line, start - 1):
		start -= 1
	var prefix := line.substr(start, get_caret_column() - start).to_lower()
	var seen := {prefix: true}
	var offered := 0
	var sources: Array = [Highlighters.vocabulary(syntax_language), document_words()]
	if extra_words.is_valid():
		sources.append(extra_words.call())
	for words in sources:
		for word in words:
			if offered >= MAX_SUGGESTIONS:
				break
			var lower: String = word.to_lower()
			if seen.has(lower) or (not prefix.is_empty() and not lower.begins_with(prefix.left(1))):
				continue
			seen[lower] = true
			offered += 1
			if Highlighters.is_type(word):
				add_code_completion_option(CodeEdit.KIND_CLASS, word, word, Highlighters.TYPE)
			elif word in Highlighters.GD_KEYWORDS or word in Highlighters.GD_CONTROL or word in Highlighters.SHADER_KEYWORDS:
				add_code_completion_option(CodeEdit.KIND_PLAIN_TEXT, word, word, Highlighters.KEYWORD)
			else:
				add_code_completion_option(CodeEdit.KIND_VARIABLE, word, word, Look.INK)
	update_code_completion_options(false)

static func _is_word(text: String, index: int) -> bool:
	if index < 0 or index >= text.length():
		return false
	var code := text.unicode_at(index)
	return code == 95 or (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122)
