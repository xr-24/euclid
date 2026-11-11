extends Control
## The wrist computer's face: header, page tabs, the page and a key line, laid out at a design
## size of 1008 x 672 and scaled to whatever size the wrist renders it at. It is drawn as light
## (additively, over a faint veil), so it uses only the bright end of the Grid-cyan palette.

const Theme = preload("res://scripts/ui/terminal_theme.gd")
const BASE_WIDTH := 1008.0

var wrist # wrist_computer.gd

func _draw() -> void:
	if wrist == null:
		return
	var u := size.x / BASE_WIDTH
	var font := Theme.mono_font()
	var margin := 12.0 * u
	var frame := Rect2(Vector2(margin, margin), size - Vector2(margin, margin) * 2.0)
	draw_rect(frame, Color(Theme.BORDER, 0.9), false, maxf(1.0, 1.5 * u))
	var left := frame.position.x + 22.0 * u
	var right := frame.end.x - 22.0 * u
	var header := frame.position.y + 40.0 * u
	draw_string(font, Vector2(left, header), "EUCLID", HORIZONTAL_ALIGNMENT_LEFT, -1, _px(24, u), Theme.BRIGHT)
	draw_string(font, Vector2(left, header), str(wrist.status_line()), HORIZONTAL_ALIGNMENT_RIGHT, right - left, _px(15, u), Theme.MUTED)
	var tabs_bottom := _tabs(font, u, left, header + 16.0 * u)
	draw_rect(Rect2(left - 8.0 * u, tabs_bottom + 8.0 * u, right - left + 16.0 * u, maxf(1.0, u)), Color(Theme.BORDER, 0.8))
	var footer := frame.end.y - 44.0 * u
	draw_rect(Rect2(left - 8.0 * u, footer, right - left + 16.0 * u, maxf(1.0, u)), Color(Theme.BORDER, 0.8))
	_footer(font, u, left, right, footer + 29.0 * u)
	var area := Rect2(left, tabs_bottom + 28.0 * u, right - left, footer - tabs_bottom - 44.0 * u)
	var page: Dictionary = wrist.current()
	var lead := str(page.get("lead", ""))
	if not lead.is_empty():
		draw_string(font, Vector2(area.position.x, area.position.y + 16.0 * u), _fit(font, lead, area.size.x, _px(16, u)),
			HORIZONTAL_ALIGNMENT_LEFT, -1, _px(16, u), Theme.INK)
		area = area.grow_side(SIDE_TOP, -38.0 * u)
	if wrist.typing:
		var box := Rect2(area.position.x, area.end.y - 46.0 * u, area.size.x, 46.0 * u)
		_draw_input(font, u, box)
		area = area.grow_side(SIDE_BOTTOM, -62.0 * u)
	if page.has("log"):
		var split := area.size.x * 0.4
		_rows(font, u, Rect2(area.position, Vector2(split, area.size.y)), page)
		var log_area := Rect2(area.position.x + split + 34.0 * u, area.position.y, area.size.x - split - 34.0 * u, area.size.y)
		draw_rect(Rect2(log_area.position.x - 17.0 * u, log_area.position.y, maxf(1.0, u), log_area.size.y), Color(Theme.BORDER, 0.6))
		_log(font, u, log_area, str(page.get("log_title", "LOG")), page.log)
	else:
		_rows(font, u, area, page)

func _tabs(font: Font, u: float, left: float, top: float) -> float:
	var height := 36.0 * u
	var font_size := _px(17, u)
	var x := left
	var pages: Array = wrist.page_list()
	for index in pages.size():
		var title := str(pages[index].get("title", ""))
		var width := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 32.0 * u
		var selected: bool = index == wrist.page
		if selected:
			draw_rect(Rect2(x, top, width, height), Color(Theme.ACCENT, 0.14))
			draw_rect(Rect2(x, top + height - 2.0 * u, width, 2.0 * u), Theme.ACCENT)
		draw_string(font, Vector2(x + 16.0 * u, _baseline(font, top + height * 0.5, font_size)), title,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Theme.BRIGHT if selected else Theme.MUTED)
		x += width + 6.0 * u
	return top + height

func _rows(font: Font, u: float, area: Rect2, page: Dictionary) -> void:
	var list: Array = page.get("rows", [])
	if list.is_empty():
		return
	var detailed := false
	for row in list:
		detailed = detailed or row.has("detail")
	var row_height := (60.0 if detailed else 42.0) * u
	var selected: int = wrist.cursor()
	var about := str(list[selected].get("about", ""))
	var about_space := 0.0 if about.is_empty() else 86.0 * u
	var fit := maxi(1, floori((area.size.y - about_space) / row_height))
	var first := clampi(selected - int(fit * 0.5), 0, maxi(0, list.size() - fit))
	var label_size := _px(19, u)
	var small := _px(15, u)
	for index in range(first, mini(list.size(), first + fit)):
		var row: Dictionary = list[index]
		var box := Rect2(area.position.x, area.position.y + (index - first) * row_height, area.size.x, row_height - 6.0 * u)
		var enabled: bool = row.get("enabled", true)
		if index == selected:
			draw_rect(box, Color(Theme.ACCENT, 0.12))
			draw_rect(Rect2(box.position, Vector2(3.0 * u, box.size.y)), Theme.ACCENT)
		var label_y := box.position.y + 26.0 * u if detailed else _baseline(font, box.get_center().y, label_size)
		var ink := Theme.DIM
		if enabled:
			ink = Theme.BRIGHT if index == selected else Theme.INK
		var value := str(row.get("value", ""))
		var value_width := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, small).x if not value.is_empty() else 0.0
		draw_string(font, Vector2(box.position.x + 16.0 * u, label_y),
			_fit(font, str(row.get("label", "")), box.size.x - 46.0 * u - value_width, label_size), HORIZONTAL_ALIGNMENT_LEFT, -1, label_size, ink)
		if not value.is_empty():
			draw_string(font, Vector2(box.position.x, label_y), value, HORIZONTAL_ALIGNMENT_RIGHT, box.size.x - 14.0 * u, small,
				_tone(str(row.get("tone", "")), enabled))
		if row.has("detail"):
			draw_string(font, Vector2(box.position.x + 16.0 * u, label_y + 22.0 * u),
				_fit(font, str(row.detail), box.size.x - 30.0 * u, small), HORIZONTAL_ALIGNMENT_LEFT, -1, small,
				Theme.MUTED if enabled else Theme.DIM)
	if first > 0:
		draw_string(font, Vector2(area.position.x, area.position.y - 6.0 * u), "↑", HORIZONTAL_ALIGNMENT_RIGHT, area.size.x - 4.0 * u, small, Theme.MUTED)
	if first + fit < list.size():
		draw_string(font, Vector2(area.position.x, area.position.y + fit * row_height + 8.0 * u), "↓", HORIZONTAL_ALIGNMENT_RIGHT, area.size.x - 4.0 * u, small, Theme.MUTED)
	if not about.is_empty():
		draw_multiline_string(font, Vector2(area.position.x + 4.0 * u, area.end.y - about_space + 30.0 * u), about,
			HORIZONTAL_ALIGNMENT_LEFT, area.size.x - 8.0 * u, small, 3, Theme.MUTED)

func _log(font: Font, u: float, area: Rect2, title: String, lines: Variant) -> void:
	draw_string(font, Vector2(area.position.x, area.position.y + 12.0 * u), title, HORIZONTAL_ALIGNMENT_LEFT, -1, _px(13, u), Theme.MUTED)
	var font_size := _px(15, u)
	var top := area.position.y + 30.0 * u
	var y := area.end.y
	var entries := []
	for said in lines:
		entries.append(said)
	if entries.is_empty():
		draw_string(font, Vector2(area.position.x, top + 18.0 * u), "Nothing yet.", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Theme.DIM)
		return
	for index in range(entries.size() - 1, -1, -1):
		var line := str(entries[index])
		var block := font.get_multiline_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, area.size.x, font_size)
		if y - block.y < top:
			break
		y -= block.y
		draw_multiline_string(font, Vector2(area.position.x, y + font.get_ascent(font_size)), line, HORIZONTAL_ALIGNMENT_LEFT,
			area.size.x, font_size, -1, Theme.ACCENT if line.begins_with("> ") else Theme.INK)
		y -= 8.0 * u

func _draw_input(font: Font, u: float, box: Rect2) -> void:
	draw_rect(box, Color(Theme.ACCENT, 0.08))
	draw_rect(box, Color(Theme.ACCENT, 0.7), false, maxf(1.0, u))
	var font_size := _px(18, u)
	var baseline := _baseline(font, box.get_center().y, font_size)
	var left := box.position.x + 14.0 * u
	draw_string(font, Vector2(left, baseline), ">", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Theme.ACCENT)
	left += 24.0 * u
	var room := box.end.x - 20.0 * u - left
	var text: String = wrist.entry
	if text.is_empty():
		draw_string(font, Vector2(left, baseline), _fit(font, str(wrist.placeholder), room, font_size), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Theme.DIM)
	else:
		# Keep the end of a long line in view, the way a single-line field scrolls.
		while text.length() > 1 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > room:
			text = text.substr(1)
		draw_string(font, Vector2(left, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Theme.BRIGHT)
	if fposmod(wrist.time, 1.0) < 0.55:
		var caret_x := left + (0.0 if wrist.entry.is_empty() else font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x) + 2.0 * u
		draw_rect(Rect2(caret_x, box.get_center().y - 11.0 * u, 2.0 * u, 22.0 * u), Theme.ACCENT)

func _footer(font: Font, u: float, left: float, right: float, baseline: float) -> void:
	var font_size := _px(14, u)
	var keys := "ENTER  SEND     ESC  STOP     TAB  CLOSE" if wrist.typing else "Q E  PAGE     ↑ ↓  SELECT     ENTER  CHOOSE     TAB  CLOSE"
	draw_string(font, Vector2(left, baseline), keys, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Theme.MUTED)
	var said: Dictionary = wrist.notice()
	if not said.is_empty():
		var width := right - left - font.get_string_size(keys, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x - 24.0 * u
		draw_string(font, Vector2(left, baseline), _fit(font, str(said.text), width, font_size), HORIZONTAL_ALIGNMENT_RIGHT,
			right - left, font_size, Theme.WARN if said.warn else Theme.GOOD)

func _tone(tone: String, enabled: bool) -> Color:
	if not enabled and tone != "good":
		return Theme.DIM
	match tone:
		"good": return Theme.GOOD
		"warn": return Theme.WARN
		"accent": return Theme.ACCENT
	return Theme.MUTED

## Shortens text with an ellipsis to fit width.
static func _fit(font: Font, text: String, width: float, font_size: int) -> String:
	if width <= 0.0 or font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= width:
		return text
	var cut := text
	while cut.length() > 1 and font.get_string_size(cut + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
		cut = cut.left(-1)
	return cut.strip_edges() + "…"

static func _baseline(font: Font, center: float, font_size: int) -> float:
	return center + (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5

static func _px(points: float, u: float) -> int:
	return maxi(8, roundi(points * u))
