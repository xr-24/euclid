extends Control
## The embedded terminal: draws the screen the gateway's emulator keeps, cell by cell in the
## Workbench's monospace font, and turns keys into terminal input. Scroll the wheel for history.
const Look = preload("res://scripts/ui/terminal_theme.gd")
const TerminalClient = preload("res://scripts/agents/terminal_client.gd")
const MARGIN := 6.0
signal frame_changed(session: Dictionary)

var _client: TerminalClient
var _session := {}
var _font: Font
var _font_size := Look.FONT_SIZE
var _cell := Vector2(9, 18)
var _ascent := 14.0
var _grid := Vector2i.ZERO
var _status := ""
var _starting := false

## The bytes a key sends to the shell, as xterm does. app_cursor follows the program's cursor-key mode.
static func key_sequence(key: InputEventKey, app_cursor := false) -> String:
	var code := key.keycode
	var arrows := {KEY_UP: "A", KEY_DOWN: "B", KEY_RIGHT: "C", KEY_LEFT: "D"}
	if arrows.has(code):
		return ("\u001bO" if app_cursor and not key.ctrl_pressed else "\u001b[") + arrows[code]
	var named := {KEY_ENTER: "\r", KEY_KP_ENTER: "\r", KEY_ESCAPE: "\u001b", KEY_HOME: "\u001b[H", KEY_END: "\u001b[F",
		KEY_PAGEUP: "\u001b[5~", KEY_PAGEDOWN: "\u001b[6~", KEY_DELETE: "\u001b[3~", KEY_INSERT: "\u001b[2~",
		KEY_F1: "\u001bOP", KEY_F2: "\u001bOQ", KEY_F3: "\u001bOR", KEY_F4: "\u001bOS", KEY_F5: "\u001b[15~",
		KEY_F6: "\u001b[17~", KEY_F7: "\u001b[18~", KEY_F8: "\u001b[19~", KEY_F9: "\u001b[20~", KEY_F10: "\u001b[21~",
		KEY_F11: "\u001b[23~", KEY_F12: "\u001b[24~"}
	if named.has(code):
		return named[code]
	if code == KEY_BACKSPACE:
		return "\u0008" if key.ctrl_pressed else "\u007f"
	if code == KEY_TAB:
		return "\u001b[Z" if key.shift_pressed else "\t"
	if key.ctrl_pressed and not key.alt_pressed and code >= KEY_A and code <= KEY_Z:
		return String.chr(code - KEY_A + 1)
	if key.unicode >= 32:
		var text := String.chr(key.unicode)
		return "\u001b" + text if key.alt_pressed else text
	return ""

func setup(url: String, token: String, capability: String) -> void:
	setup_display()
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	_client = TerminalClient.new()
	add_child(_client)
	_client.configure(url, token, capability)
	_client.screen_changed.connect(_on_screen)
	_client.failed.connect(func(message: String) -> void:
		_status = message
		queue_redraw())
	resized.connect(_on_resized)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)

func setup_display() -> void:
	_font = Look.mono_font()
	_cell = Vector2(ceilf(_font.get_char_size(ord("M"), _font_size).x), ceilf(_font.get_height(_font_size)))
	_ascent = _font.get_ascent(_font_size)
	clip_contents = true
	size_flags_vertical = Control.SIZE_EXPAND_FILL

func mirror_frame(session: Dictionary) -> void:
	var screen: Dictionary = session.get("screen", {})
	size = Vector2(screen.get("cols", 80), screen.get("rows", 24)) * _cell + Vector2.ONE * MARGIN * 2.0
	var viewport := get_parent() as SubViewport
	viewport.size = Vector2i(size).max(Vector2i(32, 32))
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_on_screen(session)

## Attaches to a running shell, or starts one, the first time the terminal is shown.
func start() -> void:
	if _starting or not _client.session_id.is_empty():
		return
	_starting = true
	_status = ""
	_grid = _fit()
	var error := await _client.attach(_grid.x, _grid.y)
	_starting = false
	_status = error
	queue_redraw()

func _fit() -> Vector2i:
	return Vector2i(maxi(10, int((size.x - MARGIN * 2.0) / _cell.x)), maxi(4, int((size.y - MARGIN * 2.0) / _cell.y)))

func _on_resized() -> void:
	var grid := _fit()
	if grid != _grid and not _client.session_id.is_empty():
		_grid = grid
		_client.resize(grid.x, grid.y)

func _on_screen(session: Dictionary) -> void:
	_session = session
	if session.get("alive", true):
		_status = ""
	queue_redraw()
	frame_changed.emit(session)

func _color(value: Variant, fallback: Color) -> Color:
	return Color(value) if value is String and str(value).begins_with("#") else fallback

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Look.BACKGROUND)
	var screen: Dictionary = _session.get("screen", {})
	var origin := Vector2(MARGIN, MARGIN)
	if screen.is_empty():
		var waiting := _status if not _status.is_empty() else "Starting a shell…"
		draw_string(_font, origin + Vector2(0, _ascent), waiting, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, Look.MUTED)
		return
	var styles: Array = screen.get("styles", [])
	var lines: Array = screen.get("lines", [])
	for row in lines.size():
		var column := 0
		for run in lines[row]:
			var text: String = run[0]
			var index := int(run[1])
			var look: Dictionary = styles[index] if index < styles.size() else {}
			var fg := _color(look.get("fg"), Look.BRIGHT if look.get("bold", false) else Look.INK)
			var bg := _color(look.get("bg"), Color(0, 0, 0, 0))
			if look.get("inverse", false):
				var front := fg
				fg = bg if bg.a > 0.0 else Look.BACKGROUND
				bg = front
			if look.get("dim", false):
				fg = fg.darkened(0.45)
			var at := origin + Vector2(column * _cell.x, row * _cell.y)
			var width := text.length() * _cell.x
			if bg.a > 0.0:
				draw_rect(Rect2(at, Vector2(width, _cell.y)), bg)
			for offset in text.length():
				var glyph := text[offset]
				if glyph != " ":
					draw_char(_font, at + Vector2(offset * _cell.x, _ascent), glyph, _font_size, fg)
			if look.get("underline", false):
				draw_line(at + Vector2(0, _cell.y - 2), at + Vector2(width, _cell.y - 2), fg)
			if look.get("strike", false):
				draw_line(at + Vector2(0, _cell.y * 0.55), at + Vector2(width, _cell.y * 0.55), fg)
			column += text.length()
	var cursor: Dictionary = screen.get("cursor", {})
	if cursor.get("visible", false):
		var box := Rect2(origin + Vector2(float(cursor.get("x", 0)) * _cell.x, float(cursor.get("y", 0)) * _cell.y), _cell)
		if has_focus():
			draw_rect(box, Color(Look.ACCENT, 0.5))
		else:
			draw_rect(box, Look.ACCENT, false, 1.0)
	var notice := ""
	if not _session.get("alive", true):
		notice = str(_session.get("exit_error", ""))
		if notice.is_empty():
			notice = "The shell ended. Press Enter for a new one."
	elif int(screen.get("offset", 0)) > 0:
		notice = "History, %d lines back. Type or scroll down to return." % int(screen.offset)
	elif not _status.is_empty():
		notice = _status
	if not notice.is_empty():
		var band := Rect2(Vector2(0, size.y - _cell.y - MARGIN * 2.0), Vector2(size.x, _cell.y + MARGIN * 2.0))
		draw_rect(band, Color(Look.RAISED, 0.92))
		draw_string(_font, Vector2(MARGIN, band.position.y + MARGIN + _ascent), notice, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, Look.WARN)

func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed:
		grab_focus()
		var history := int(_session.get("screen", {}).get("history", 0))
		if click.button_index == MOUSE_BUTTON_WHEEL_UP:
			_client.scroll_to(mini(history, _client.offset + 3))
		elif click.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_client.scroll_to(maxi(0, _client.offset - 3))
		accept_event()
		return
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return
	if not _session.is_empty() and not _session.get("alive", true):
		if key.keycode in [KEY_ENTER, KEY_KP_ENTER]:
			_session = {}
			_client.session_id = ""
			start()
		accept_event()
		return
	var modes: Dictionary = _session.get("screen", {}).get("modes", {})
	var sequence := ""
	if key.ctrl_pressed and key.shift_pressed and key.keycode == KEY_V:
		sequence = DisplayServer.clipboard_get()
		if modes.get("bracketed_paste", false) and not sequence.is_empty():
			sequence = "\u001b[200~" + sequence + "\u001b[201~"
	else:
		sequence = key_sequence(key, modes.get("app_cursor", false))
	if sequence.is_empty():
		return
	if _client.offset > 0:
		_client.scroll_to(0)
	_client.send_text(sequence)
	accept_event()
