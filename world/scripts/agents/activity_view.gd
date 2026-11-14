extends Control
## Draws one agent activity event, animated by `time`: lines being read, an edit's removed lines
## collapsing and added lines typing in, a command and its output, search results, or text.
## Rendered into a SubViewport and shown above the agent (activity_card.gd).

const Look = preload("res://scripts/ui/terminal_theme.gd")
const WIDTH := 760
const FULL_HEIGHT := 440
const COMPACT_HEIGHT := 76
const HEADER := 76
const LINE := 24
const FONT_SIZE := 17
const TITLE_SIZE := 19
const TYPE_RATE := 240.0
const LABELS := {"read": "READ", "search": "SEARCH", "edit": "EDIT", "write": "WRITE", "delete": "DELETE", "run": "RUN",
	"tool": "TOOL", "think": "THINK", "say": "SAYS", "start": "TASK", "done": "DONE", "error": "ERROR"}
const REMOVED_BG := Color(0.62, 0.13, 0.17, 0.55)
const REMOVED_INK := Color("ffadb6")
const ADDED_BG := Color(0.1, 0.5, 0.3, 0.5)
const ADDED_INK := Color("a8ffd2")

var event := {}
var time := 0.0
var tint := Color("ff4813")
var highlight := Color("ffbc55")
var compact := false
var show_code := true
var fade := 1.0
var _rows: Array = []
var _rows_for := -1

## How long an event takes to play, before any speed-up for a backlog.
static func duration(entry: Dictionary) -> float:
	match str(entry.get("kind", "")):
		"read":
			return clampf(1.4 + entry.get("lines", []).size() * 0.05, 1.8, 4.5)
		"edit", "write":
			var removed := 0
			var typed := 0
			for row in _diff_rows(entry):
				if row.t == "-":
					removed += 1
				elif row.t == "+":
					typed += str(row.text).length() + 1
			return _collapse_time(removed) + minf(typed / TYPE_RATE, 4.5) + 1.2
		"run":
			return 1.4 + minf(entry.get("output", []).size(), 16) * 0.12 + 0.8
		"search":
			return 1.4 + minf(entry.get("results", []).size(), 12) * 0.1
		"think", "say":
			return clampf(str(entry.get("text", "")).length() / 70.0, 1.8, 4.5)
	return 2.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	if event.is_empty():
		return
	var height := COMPACT_HEIGHT if compact else FULL_HEIGHT
	var font := Look.mono_font()
	var kind := str(event.get("kind", ""))
	var alpha := clampf(fade, 0.0, 1.0)
	# Panel and header.
	var panel := Rect2(2, 2, WIDTH - 4, height - 4)
	draw_style_box(_panel_style(alpha), panel)
	var pill := Rect2(18, 20, 96, 34)
	draw_rect(pill, _kind_color(kind) * Color(1, 1, 1, 0.9 * alpha))
	_text(font, Vector2(pill.position.x + pill.size.x * 0.5, 44), LABELS.get(kind, kind.to_upper()), 15, Color(0.02, 0.03, 0.05, alpha), HORIZONTAL_ALIGNMENT_CENTER, pill.size.x)
	var title := str(event.get("path", event.get("tool", ""))) if event.has("path") or event.has("tool") else str(event.get("title", ""))
	if title.is_empty():
		title = str(event.get("title", ""))
	_text(font, Vector2(132, 44), _fit(font, title, TITLE_SIZE, WIDTH - 132 - 150), TITLE_SIZE, Look.BRIGHT * Color(1, 1, 1, alpha))
	if kind in ["edit", "write"] and event.has("added"):
		var badge := "+%d  -%d" % [int(event.get("added", 0)), int(event.get("removed", 0))]
		_text(font, Vector2(WIDTH - 22, 44), badge, 16, ADDED_INK * Color(1, 1, 1, alpha), HORIZONTAL_ALIGNMENT_RIGHT, 140)
	if compact:
		return
	draw_line(Vector2(16, HEADER - 4), Vector2(WIDTH - 16, HEADER - 4), tint * Color(1, 1, 1, 0.35 * alpha), 2.0)
	var body := Rect2(16, HEADER + 6, WIDTH - 32, height - HEADER - 22)
	if event.get("hidden", false):
		_text(font, body.position + Vector2(0, 30), "Contents hidden: this file looks like it holds secrets.", 17, Look.MUTED * Color(1, 1, 1, alpha))
		return
	match kind:
		"read":
			_draw_read(font, body, alpha)
		"edit", "write":
			_draw_edit(font, body, alpha)
		"run":
			_draw_run(font, body, alpha)
		"search":
			_draw_list(font, body, alpha, str(event.get("title", "")), event.get("results", []))
		"delete":
			_text(font, body.position + Vector2(0, 30), "The file is removed.", 18, REMOVED_INK * Color(1, 1, 1, alpha))
		"tool":
			_draw_paragraph(font, body, alpha, str(event.get("title", "")) + ("\n" + str(event.text) if event.has("text") else ""), true)
		_:
			_draw_paragraph(font, body, alpha, str(event.get("text", event.get("title", ""))), kind != "start")

func _draw_read(font: Font, body: Rect2, alpha: float) -> void:
	var lines: Array = event.get("lines", [])
	if lines.is_empty():
		_text(font, body.position + Vector2(0, 30), str(event.get("title", "")), 18, Look.INK * Color(1, 1, 1, alpha))
		return
	var visible := int(body.size.y / LINE)
	# A band sweeps down the lines over most of the event; the view scrolls to keep it in sight.
	var progress := clampf(time / maxf(duration(event) * 0.85, 0.1), 0.0, 1.0)
	var focus := progress * (lines.size() - 1)
	var first := clampi(int(focus) - visible / 2, 0, maxi(0, lines.size() - visible))
	for row in range(first, mini(lines.size(), first + visible)):
		var y := body.position.y + (row - first) * LINE
		var near := absf(float(row) - focus)
		if near < 1.5:
			draw_rect(Rect2(body.position.x - 4, y, body.size.x + 8, LINE), highlight * Color(1, 1, 1, (0.28 - near * 0.12) * alpha))
		_code_row(font, body, y, int(lines[row].n), str(lines[row].text), Look.INK, alpha)

func _draw_edit(font: Font, body: Rect2, alpha: float) -> void:
	var rows := _rows_cached()
	var removed_count := rows.filter(func(row: Dictionary) -> bool: return row.t == "-").size()
	var collapse := _collapse_time(removed_count)
	var typed := maxf(0.0, time - collapse) * TYPE_RATE
	# Removed lines hold, get struck through, then fold away before the new lines type in.
	var hold := collapse * 0.55
	var shrink := clampf((time - hold) / maxf(collapse - hold, 0.05), 0.0, 1.0)
	# Rows grow and shrink, so lay them out first, then scroll to the typing caret.
	var layout: Array = []
	var cursor_y := 0.0
	var y := 0.0
	var budget := typed
	for row: Dictionary in rows:
		var h := float(LINE)
		var shown := str(row.text)
		var caret := false
		if row.t == "-":
			h = LINE * (1.0 - shrink)
		elif row.t == "+":
			var length := shown.length() + 1
			if budget <= 0.0:
				h = 0.0
			elif budget < length:
				shown = shown.substr(0, int(budget))
				caret = true
				cursor_y = y
			budget -= length
		elif row.t == "~":
			h = LINE * 0.7
		if h > 0.5:
			layout.append({"row": row, "y": y, "h": h, "text": shown, "caret": caret})
			if not caret and row.t == "+":
				cursor_y = y
		y += h
	var scroll := clampf(cursor_y - body.size.y * 0.55, 0.0, maxf(0.0, y - body.size.y))
	for item: Dictionary in layout:
		var top: float = body.position.y + item.y - scroll
		if top + item.h < body.position.y or top > body.end.y - 4:
			continue
		var row: Dictionary = item.row
		var squash: float = item.h / LINE
		match str(row.t):
			"-":
				draw_rect(Rect2(body.position.x - 4, top, body.size.x + 8, item.h), REMOVED_BG * Color(1, 1, 1, alpha * squash))
				if squash > 0.45:
					_code_row(font, body, top, int(row.n), str(item.text), REMOVED_INK, alpha * squash, "-")
					var ink_end := body.position.x + 62 + font.get_string_size(str(item.text), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
					var strike := clampf((time - collapse * 0.25) / maxf(collapse * 0.3, 0.05), 0.0, 1.0)
					if strike > 0.0:
						draw_line(Vector2(body.position.x + 62, top + LINE * 0.55), Vector2(lerpf(body.position.x + 62, minf(ink_end, body.end.x), strike), top + LINE * 0.55), REMOVED_INK * Color(1, 1, 1, alpha), 2.0)
			"+":
				draw_rect(Rect2(body.position.x - 4, top, body.size.x + 8, item.h), ADDED_BG * Color(1, 1, 1, alpha))
				_code_row(font, body, top, int(row.n), str(item.text), ADDED_INK, alpha, "+")
				if item.caret and fmod(time, 0.6) < 0.38:
					var x := body.position.x + 62 + (font.get_string_size(str(item.text), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x if show_code else str(item.text).length() * 9.5)
					draw_rect(Rect2(minf(x, body.end.x - 4), top + 3, 3, LINE - 6), ADDED_INK * Color(1, 1, 1, alpha))
			"~":
				_text(font, Vector2(body.position.x + 62, top + item.h * 0.8), "⋯", FONT_SIZE, Look.DIM * Color(1, 1, 1, alpha))
			_:
				_code_row(font, body, top, int(row.n), str(item.text), Look.MUTED, alpha)

func _draw_run(font: Font, body: Rect2, alpha: float) -> void:
	var command := "$ " + str(event.get("command", ""))
	var typed := int(clampf(time / 0.5, 0.0, 1.0) * command.length())
	_text(font, body.position + Vector2(0, 20), _fit(font, command.substr(0, typed), FONT_SIZE, body.size.x), FONT_SIZE, Look.ACCENT * Color(1, 1, 1, alpha))
	var output: Array = event.get("output", [])
	var shown := clampi(int((time - 0.8) / 0.12), 0, output.size())
	var visible := int((body.size.y - 34) / LINE)
	var first := maxi(0, shown - visible)
	for index in range(first, shown):
		var y := body.position.y + 34 + (index - first) * LINE
		_line_text(font, Vector2(body.position.x, y + 18), str(output[index]), Look.INK if event.get("ok", true) else REMOVED_INK, alpha, body.size.x)

func _draw_list(font: Font, body: Rect2, alpha: float, heading: String, items: Array) -> void:
	_text(font, body.position + Vector2(0, 20), _fit(font, heading, FONT_SIZE, body.size.x), FONT_SIZE, Look.ACCENT * Color(1, 1, 1, alpha))
	var shown := clampi(int((time - 0.5) / 0.1) + 1, 0, items.size())
	for index in shown:
		var y := body.position.y + 34 + index * LINE
		if y > body.end.y - LINE:
			break
		_line_text(font, Vector2(body.position.x + 12, y + 18), str(items[index]), Look.INK, alpha, body.size.x - 12)

func _draw_paragraph(font: Font, body: Rect2, alpha: float, text: String, typed: bool) -> void:
	var count := int(time * 90.0) if typed else text.length()
	var shown := text.substr(0, mini(count, text.length()))
	var y := body.position.y + 22
	for line in _wrap(font, shown, body.size.x, 18):
		if y > body.end.y:
			break
		_text(font, Vector2(body.position.x, y), line, 18, Look.INK * Color(1, 1, 1, alpha))
		y += 26

func _code_row(font: Font, body: Rect2, y: float, number: int, code: String, ink: Color, alpha: float, mark := " ") -> void:
	_text(font, Vector2(body.position.x + 44, y + 18), str(number) if number > 0 else "", 14, Look.DIM * Color(1, 1, 1, alpha), HORIZONTAL_ALIGNMENT_RIGHT, 44)
	if mark != " ":
		_text(font, Vector2(body.position.x + 50, y + 18), mark, FONT_SIZE, ink * Color(1, 1, 1, alpha))
	_line_text(font, Vector2(body.position.x + 62, y + 18), code, ink, alpha, body.size.x - 62)

## One line of code, or, with code hidden, a bar in its place so its shape still shows.
func _line_text(font: Font, at: Vector2, code: String, ink: Color, alpha: float, width: float) -> void:
	if show_code:
		_text(font, at, _fit(font, code, FONT_SIZE, width), FONT_SIZE, ink * Color(1, 1, 1, alpha))
		return
	var indent := code.length() - code.strip_edges(true, false).length()
	var length := code.strip_edges().length()
	if length > 0:
		draw_rect(Rect2(at.x + indent * 9.5, at.y - 11, minf(length * 9.5, width - indent * 9.5), 8), ink * Color(1, 1, 1, 0.45 * alpha))

func _text(font: Font, at: Vector2, text: String, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	var x := at.x
	if align == HORIZONTAL_ALIGNMENT_RIGHT:
		x -= width
	elif align == HORIZONTAL_ALIGNMENT_CENTER:
		x -= width * 0.5
	draw_string(font, Vector2(x, at.y), text, align, width, size, color)

func _fit(font: Font, text: String, size: int, width: float) -> String:
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= width:
		return text
	var low := 0
	var high := text.length()
	while low < high:
		var middle := (low + high + 1) / 2
		if font.get_string_size(text.substr(0, middle) + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= width:
			low = middle
		else:
			high = middle - 1
	return text.substr(0, low) + "…"

func _wrap(font: Font, text: String, width: float, size: int) -> PackedStringArray:
	var lines := PackedStringArray()
	for paragraph in text.split("\n"):
		var current := ""
		for word in paragraph.split(" "):
			var candidate := word if current.is_empty() else current + " " + word
			if font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width and not current.is_empty():
				lines.append(current)
				current = word
			else:
				current = candidate
		lines.append(current)
	return lines

func _rows_cached() -> Array:
	var id := int(event.get("seq", -1))
	if id != _rows_for:
		_rows = _diff_rows(event)
		_rows_for = id
	return _rows

## Time removed lines take to show, strike through and fold away.
static func _collapse_time(removed: int) -> float:
	return 0.0 if removed == 0 else 0.9 + minf(removed * 0.15, 1.2)

## An edit's hunks as one list of rows, with a "~" row between hunks.
static func _diff_rows(entry: Dictionary) -> Array:
	var rows: Array = []
	for hunk in entry.get("hunks", []):
		if not rows.is_empty():
			rows.append({"t": "~", "n": 0, "text": ""})
		for line in hunk.get("lines", []):
			rows.append({"t": str(line.get("t", " ")), "n": int(line.get("n", 0)), "text": str(line.get("text", ""))})
	return rows

func _kind_color(kind: String) -> Color:
	match kind:
		"edit", "write", "done":
			return Color("6effc8")
		"delete", "error":
			return Color("ff6b7d")
		"run":
			return Color("ffc46b")
		"read", "search":
			return Color("4fdcff")
		"think", "say":
			return highlight
	return tint.lightened(0.25)

func _panel_style(alpha: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.015, 0.035, 0.055, 0.88 * alpha)
	style.border_color = tint * Color(1, 1, 1, 0.85 * alpha)
	style.set_border_width_all(3)
	style.set_corner_radius_all(14)
	style.shadow_color = tint * Color(1, 1, 1, 0.25 * alpha)
	style.shadow_size = 10
	return style
