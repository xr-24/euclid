extends Control
## The wrist computer's face: header, page tabs and the page, laid out at a design size of
## 1008 x 672 and scaled to whatever size the wrist renders it at. It is drawn as light
## (additively, over a faint veil), in the Grid's colours: red traces and lamps on near-black
## (see grid_wall.gdshader).

const TerminalTheme = preload("res://scripts/ui/terminal_theme.gd")
const BRIGHT := Color("ffe4e1")
const INK := Color("ffaba5")
const ACCENT := Color("ff4a42")
const MUTED := Color("b65652")
const DIM := Color("5c2024")
const BORDER := Color("9c252c")
const WARN := Color("ff9466")
const BASE_WIDTH := 1008.0
const SCAN_SPLIT := 0.45

var wrist # wrist_computer.gd

func _draw() -> void:
	if wrist == null:
		return
	var u := size.x / BASE_WIDTH
	var font := TerminalTheme.mono_font()
	var margin := 12.0 * u
	var frame := Rect2(Vector2(margin, margin), size - Vector2(margin, margin) * 2.0)
	draw_rect(frame, Color(BORDER, 0.9), false, maxf(1.0, 1.5 * u))
	var left := frame.position.x + 22.0 * u
	var right := frame.end.x - 22.0 * u
	var header := frame.position.y + 40.0 * u
	draw_string(font, Vector2(left, header), "EUCLID", HORIZONTAL_ALIGNMENT_LEFT, -1, _px(24, u), BRIGHT)
	draw_string(font, Vector2(left, header), str(wrist.status_line()), HORIZONTAL_ALIGNMENT_RIGHT, right - left, _px(15, u), MUTED)
	var tabs_bottom := _tabs(font, u, left, header + 16.0 * u)
	draw_rect(Rect2(left - 8.0 * u, tabs_bottom + 8.0 * u, right - left + 16.0 * u, maxf(1.0, u)), Color(BORDER, 0.8))
	var bottom := frame.end.y - 18.0 * u
	_notice(font, u, left, right, bottom)
	var area := Rect2(left, tabs_bottom + 28.0 * u, right - left, bottom - tabs_bottom - 58.0 * u)
	var page: Dictionary = wrist.current()
	if wrist.typing:
		var box := Rect2(area.position.x, area.end.y - 46.0 * u, area.size.x, 46.0 * u)
		_draw_input(font, u, box)
		area = area.grow_side(SIDE_BOTTOM, -62.0 * u)
	if page.has("scan_label"):
		var preview := scanner_frame(size)
		var split := preview.size.x
		draw_rect(preview, Color(BORDER, 0.75), false, 2.0 * u)
		if page.has("preview"):
			draw_texture_rect(page.preview, preview.grow(-3.0 * u), false)
		var label := str(page.scan_label) if not str(page.scan_label).is_empty() else "Aim the frame at a prop or water"
		draw_string(font, Vector2(preview.position.x, preview.end.y + 26.0 * u), _fit(font, label, split, _px(17, u)),
			HORIZONTAL_ALIGNMENT_LEFT, -1, _px(17, u), BRIGHT)
		_rows(font, u, Rect2(area.position + Vector2(split + 22.0 * u, 0), Vector2(area.size.x - split - 22.0 * u, area.size.y)), page)
	elif page.has("log"):
		var split := area.size.x * 0.4
		_rows(font, u, Rect2(area.position, Vector2(split, area.size.y)), page)
		var log_area := Rect2(area.position.x + split + 34.0 * u, area.position.y, area.size.x - split - 34.0 * u, area.size.y)
		draw_rect(Rect2(log_area.position.x - 17.0 * u, log_area.position.y, maxf(1.0, u), log_area.size.y), Color(BORDER, 0.6))
		_log(font, u, log_area, page.log)
	else:
		_rows(font, u, area, page)

static func scanner_frame(face_size: Vector2) -> Rect2:
	var u := face_size.x / BASE_WIDTH
	var inset := 34.0 * u
	var width := (face_size.x - inset * 2.0) * SCAN_SPLIT
	return Rect2(Vector2(inset, 132.0 * u), Vector2(width, width * 0.8))

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
			draw_rect(Rect2(x, top, width, height), Color(ACCENT, 0.14))
			draw_rect(Rect2(x, top + height - 2.0 * u, width, 2.0 * u), ACCENT)
		draw_string(font, Vector2(x + 16.0 * u, _baseline(font, top + height * 0.5, font_size)), title,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, BRIGHT if selected else MUTED)
		x += width + 6.0 * u
	return top + height

func _rows(font: Font, u: float, area: Rect2, page: Dictionary) -> void:
	var list: Array = page.get("rows", [])
	if list.is_empty():
		return
	var row_height := 46.0 * u
	var selected: int = wrist.cursor()
	var fit := maxi(1, floori(area.size.y / row_height))
	var first := clampi(selected - int(fit * 0.5), 0, maxi(0, list.size() - fit))
	var label_size := _px(20, u)
	var small := _px(15, u)
	for index in range(first, mini(list.size(), first + fit)):
		var row: Dictionary = list[index]
		var box := Rect2(area.position.x, area.position.y + (index - first) * row_height, area.size.x, row_height - 6.0 * u)
		var enabled: bool = row.get("enabled", true)
		if index == selected:
			draw_rect(box, Color(ACCENT, 0.13))
			draw_rect(Rect2(box.position, Vector2(3.0 * u, box.size.y)), ACCENT)
		var baseline := _baseline(font, box.get_center().y, label_size)
		var ink := DIM
		if enabled:
			ink = BRIGHT if index == selected else INK
		var value := str(row.get("value", ""))
		var value_width := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, small).x if not value.is_empty() else 0.0
		draw_string(font, Vector2(box.position.x + 16.0 * u, baseline),
			_fit(font, str(row.get("label", "")), box.size.x - 46.0 * u - value_width, label_size), HORIZONTAL_ALIGNMENT_LEFT, -1, label_size, ink)
		if not value.is_empty():
			draw_string(font, Vector2(box.position.x, _baseline(font, box.get_center().y, small)), value, HORIZONTAL_ALIGNMENT_RIGHT,
				box.size.x - 14.0 * u, small, _tone(str(row.get("tone", "")), enabled))
	if first > 0:
		draw_string(font, Vector2(area.position.x, area.position.y - 6.0 * u), "↑", HORIZONTAL_ALIGNMENT_RIGHT, area.size.x - 4.0 * u, small, MUTED)
	if first + fit < list.size():
		draw_string(font, Vector2(area.position.x, area.position.y + fit * row_height + 8.0 * u), "↓", HORIZONTAL_ALIGNMENT_RIGHT, area.size.x - 4.0 * u, small, MUTED)

func _log(font: Font, u: float, area: Rect2, lines: Variant) -> void:
	var font_size := _px(15, u)
	var top := area.position.y
	var y := area.end.y
	var entries := []
	for said in lines:
		entries.append(said)
	for index in range(entries.size() - 1, -1, -1):
		var line := str(entries[index])
		var block := font.get_multiline_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, area.size.x, font_size)
		if y - block.y < top:
			break
		y -= block.y
		draw_multiline_string(font, Vector2(area.position.x, y + font.get_ascent(font_size)), line, HORIZONTAL_ALIGNMENT_LEFT,
			area.size.x, font_size, -1, ACCENT if line.begins_with("> ") else INK)
		y -= 8.0 * u

func _draw_input(font: Font, u: float, box: Rect2) -> void:
	draw_rect(box, Color(ACCENT, 0.08))
	draw_rect(box, Color(ACCENT, 0.7), false, maxf(1.0, u))
	var font_size := _px(18, u)
	var baseline := _baseline(font, box.get_center().y, font_size)
	var left := box.position.x + 14.0 * u
	draw_string(font, Vector2(left, baseline), ">", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ACCENT)
	left += 24.0 * u
	var room := box.end.x - 20.0 * u - left
	var text: String = wrist.entry
	# Keep the end of a long line in view, the way a single-line field scrolls.
	while text.length() > 1 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > room:
		text = text.substr(1)
	var text_width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	if wrist.entry_selected:
		draw_rect(Rect2(left - 2.0 * u, box.get_center().y - 12.0 * u, text_width + 4.0 * u, 24.0 * u), Color(ACCENT, 0.36))
	draw_string(font, Vector2(left, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, BRIGHT)
	if not wrist.entry_selected and fposmod(wrist.time, 1.0) < 0.55:
		var caret_x := left + text_width + 2.0 * u
		draw_rect(Rect2(caret_x, box.get_center().y - 11.0 * u, 2.0 * u, 22.0 * u), ACCENT)

## Only what the wrist has to say back: why a row is unavailable, or to press Enter again.
func _notice(font: Font, u: float, left: float, right: float, baseline: float) -> void:
	var said: Dictionary = wrist.notice()
	if not said.is_empty():
		var font_size := _px(15, u)
		draw_string(font, Vector2(left, baseline), _fit(font, str(said.text), right - left, font_size), HORIZONTAL_ALIGNMENT_RIGHT,
			right - left, font_size, WARN if said.warn else BRIGHT)

func _tone(tone: String, enabled: bool) -> Color:
	if not enabled and tone != "good":
		return DIM
	match tone:
		"good": return BRIGHT
		"warn": return WARN
		"accent": return ACCENT
	return MUTED

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
