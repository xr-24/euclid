extends Control
## Text effects drawn above a TextEdit or LineEdit without touching its text: a smoothed caret
## with a motion trail and glow, flashes for new characters, dissolving ghosts for removed ones
## and a scan-line reveal when a whole document loads. Positions assume a monospace font.
const Look = preload("res://scripts/ui/terminal_theme.gd")

const IN := 0
const OUT := 1
const BIT := 2
const LIFE := [0.42, 0.55, 0.85]
const MAX_PARTICLES := 900
const CHANGE_BUDGET := 420
const TRAIL_TIME := 0.09
const REVEAL_TIME := 0.38

## Shared switch for every text surface; the Workbench FX toggle flips it.
static var enabled := true

var block_caret := false
var target: Control
var _lines := PackedStringArray()
var _animate_next_set := false
var _pending: Array = []
var _particles: Array = []
var _trail: Array = []
# The caret, its trail and particles live in document space (screen position plus scroll) so
# scrolling moves them with the text and only real caret moves are animated.
var _caret := Vector2.ZERO
var _caret_goal := Vector2(-1.0e6, -1.0e6)
var _caret_ready := false
var _moved_at := 0.0
var _reveal_at := -10.0
var _reveal_time := REVEAL_TIME
var _clock := 0.0
var _char_width := 9.0
var _applied := false
var _rng := RandomNumberGenerator.new()

## Where one text differs from another, as the first changed position and the removed and added
## text. Empty when they match.
static func change_between(before: PackedStringArray, after: PackedStringArray) -> Dictionary:
	var limit := mini(before.size(), after.size())
	var top := 0
	while top < limit and before[top] == after[top]:
		top += 1
	if top == before.size() and top == after.size():
		return {}
	var tail := 0
	while tail < limit - top and before[before.size() - 1 - tail] == after[after.size() - 1 - tail]:
		tail += 1
	# Keep one unchanged line of context so whole-line removals keep their line break.
	if top > 0:
		top -= 1
	var old_text := "\n".join(before.slice(top, before.size() - tail))
	var new_text := "\n".join(after.slice(top, after.size() - tail))
	var shortest := mini(old_text.length(), new_text.length())
	var prefix := 0
	while prefix < shortest and old_text.unicode_at(prefix) == new_text.unicode_at(prefix):
		prefix += 1
	var suffix := 0
	while suffix < shortest - prefix \
			and old_text.unicode_at(old_text.length() - 1 - suffix) == new_text.unicode_at(new_text.length() - 1 - suffix):
		suffix += 1
	var lead := old_text.substr(0, prefix)
	var breaks := lead.count("\n")
	return {"line": top + breaks, "old_line": top + breaks, "column": prefix - (lead.rfind("\n") + 1),
		"removed": old_text.substr(prefix, old_text.length() - prefix - suffix),
		"added": new_text.substr(prefix, new_text.length() - prefix - suffix)}

## Every separate change between two texts. Unchanged lines between edits are matched by a
## line-level LCS so two distant edits (multi-caret typing, replace all, an agent's patch) do not
## animate the untouched text between them. Large rewrites fall back to one span.
static func changes_between(before: PackedStringArray, after: PackedStringArray) -> Array:
	var limit := mini(before.size(), after.size())
	var top := 0
	while top < limit and before[top] == after[top]:
		top += 1
	if top == before.size() and top == after.size():
		return []
	var tail := 0
	while tail < limit - top and before[before.size() - 1 - tail] == after[after.size() - 1 - tail]:
		tail += 1
	var rows := before.size() - tail - top
	var cols := after.size() - tail - top
	if rows * cols > 40000 or rows <= 1 or cols <= 1:
		return [change_between(before, after)]
	# lengths[i * (cols + 1) + j]: LCS of before[top + i:] and after[top + j:]
	var width := cols + 1
	var lengths := PackedInt32Array()
	lengths.resize((rows + 1) * width)
	for i in range(rows - 1, -1, -1):
		for j in range(cols - 1, -1, -1):
			if before[top + i] == after[top + j]:
				lengths[i * width + j] = lengths[(i + 1) * width + j + 1] + 1
			else:
				lengths[i * width + j] = maxi(lengths[(i + 1) * width + j], lengths[i * width + j + 1])
	var found := []
	var i := 0
	var j := 0
	var hunk := Vector4i(-1, -1, -1, -1)
	while i < rows or j < cols:
		if i < rows and j < cols and before[top + i] == after[top + j]:
			if hunk.x >= 0:
				found.append(_hunk(before, after, top + hunk.x, top + i, top + hunk.z, top + j))
				hunk = Vector4i(-1, -1, -1, -1)
			i += 1
			j += 1
			continue
		if hunk.x < 0:
			hunk = Vector4i(i, 0, j, 0)
		if j < cols and (i >= rows or lengths[i * width + j + 1] >= lengths[(i + 1) * width + j]):
			j += 1
		else:
			i += 1
	if hunk.x >= 0:
		found.append(_hunk(before, after, top + hunk.x, top + rows, top + hunk.z, top + cols))
	return found

## One changed block of lines, refined to characters. A matching line on either side is included
## as context so whole-line insertions and removals keep their line breaks.
static func _hunk(before: PackedStringArray, after: PackedStringArray, old_from: int, old_to: int, new_from: int, new_to: int) -> Dictionary:
	if old_from > 0 and new_from > 0 and before[old_from - 1] == after[new_from - 1]:
		old_from -= 1
		new_from -= 1
	elif old_to < before.size() and new_to < after.size():
		old_to += 1
		new_to += 1
	var old_text := "\n".join(before.slice(old_from, old_to))
	var new_text := "\n".join(after.slice(new_from, new_to))
	var shortest := mini(old_text.length(), new_text.length())
	var prefix := 0
	while prefix < shortest and old_text.unicode_at(prefix) == new_text.unicode_at(prefix):
		prefix += 1
	var suffix := 0
	while suffix < shortest - prefix \
			and old_text.unicode_at(old_text.length() - 1 - suffix) == new_text.unicode_at(new_text.length() - 1 - suffix):
		suffix += 1
	var lead := old_text.substr(0, prefix)
	return {"line": new_from + lead.count("\n"), "old_line": old_from + lead.count("\n"), "column": prefix - (lead.rfind("\n") + 1),
		"removed": old_text.substr(prefix, old_text.length() - prefix - suffix),
		"added": new_text.substr(prefix, new_text.length() - prefix - suffix)}

static func visual_column(text: String, column: int, tab_size: int) -> int:
	var cells := 0
	for index in mini(column, text.length()):
		if text.unicode_at(index) == 9:
			cells += tab_size - cells % tab_size
		else:
			cells += 1
	return cells

func attach(control: Control) -> void:
	target = control
	name = "TextEffects"
	mouse_filter = MOUSE_FILTER_IGNORE
	focus_mode = FOCUS_NONE
	clip_contents = true
	control.add_child(self, false, Node.INTERNAL_MODE_BACK)
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	if control is TextEdit:
		var edit := control as TextEdit
		_lines = edit.text.split("\n")
		edit.text_changed.connect(func() -> void: _record(edit.text.split("\n")))
		edit.text_set.connect(_on_text_set)
	elif control is LineEdit:
		_lines = PackedStringArray([(control as LineEdit).text])
	control.focus_entered.connect(func() -> void: _moved_at = _clock)
	control.visibility_changed.connect(func() -> void:
		if control.is_visible_in_tree():
			reveal(0.22))

## Replace a TextEdit's document. Animated changes flash in the difference; otherwise the
## whole document scans in.
func show_text(text: String, animate := false) -> void:
	var edit := target as TextEdit
	if edit.text == text:
		return
	_animate_next_set = animate
	edit.text = text
	_animate_next_set = false

func reveal(duration := REVEAL_TIME) -> void:
	_reveal_at = _clock
	_reveal_time = duration
	_particles.clear()
	_pending.clear()
	_caret_ready = false

func _on_text_set() -> void:
	var after := (target as TextEdit).text.split("\n")
	if _animate_next_set:
		_record(after)
	else:
		_lines = after
		reveal()

func _record(after: PackedStringArray) -> void:
	var before := _lines
	_lines = after
	if not enabled or not is_visible_in_tree():
		return
	# Placed on the next frame, after the owner has scrolled or the layout has settled.
	for change in changes_between(before, after):
		_pending.append([change, before, after])

func _spawn_added(change: Dictionary, after: PackedStringArray) -> void:
	var text: String = change.added
	var line: int = change.line
	var column: int = change.column
	var stagger := clampf(0.45 / maxf(text.length(), 1.0), 0.0012, 0.012)
	var spawned := 0
	for index in text.length():
		var glyph := text[index]
		if glyph == "\n":
			line += 1
			column = 0
			continue
		if glyph != " " and glyph != "\t" and spawned < CHANGE_BUDGET:
			var at := _cell(line, column, after[line] if line < after.size() else "")
			if _on_screen(at):
				_add(IN, glyph, at, index * stagger)
				spawned += 1
		column += 1

func _spawn_removed(change: Dictionary, before: PackedStringArray) -> void:
	var text: String = change.removed
	var anchor: int = change.line
	var origin: int = change.old_line
	var offset := 0
	var column: int = change.column
	var source: String = before[origin] if origin < before.size() else ""
	var spawned := 0
	for index in text.length():
		var glyph := text[index]
		if glyph == "\n":
			offset += 1
			column = 0
			source = before[origin + offset] if origin + offset < before.size() else ""
			continue
		if glyph != " " and glyph != "\t" and spawned < CHANGE_BUDGET:
			var at := _cell(anchor, column, source, offset)
			if _on_screen(at):
				var delay := minf(index * 0.002, 0.25)
				_add(OUT, glyph, at, delay)
				if _rng.randf() < 0.2:
					_add(BIT, "1" if _rng.randf() < 0.5 else "0", at, delay)
				spawned += 1
		column += 1

func _add(kind: int, glyph: String, at: Vector2, delay: float) -> void:
	if _particles.size() >= MAX_PARTICLES:
		return
	_particles.append({"kind": kind, "glyph": glyph, "at": at + _scroll_px(), "born": _clock, "delay": delay,
		"life": LIFE[kind], "drift": _rng.randf_range(-1.0, 1.0), "seed": _rng.randf() * TAU})

func _process(delta: float) -> void:
	_clock += delta
	if target == null or not is_visible_in_tree():
		return
	if _applied != enabled:
		_applied = enabled
		if enabled:
			target.add_theme_color_override("caret_color", Color(0, 0, 0, 0))
		else:
			target.remove_theme_color_override("caret_color")
			_particles.clear()
			queue_redraw()
	if not enabled:
		return
	if target is LineEdit:
		var current := (target as LineEdit).text
		if _lines.size() != 1 or _lines[0] != current:
			_record(PackedStringArray([current]))
	_measure()
	for item in _pending:
		_spawn_removed(item[0], item[1])
		_spawn_added(item[0], item[2])
	_pending.clear()
	var goal := _caret_cell() + _scroll_px()
	if not _caret_ready:
		_caret = goal
		_caret_ready = true
		_trail.clear()
	else:
		# Long jumps (Ctrl+End, a click far away) smear over at most eight rows.
		var gap := goal - _caret
		var reach := _row_height() * 8.0
		if gap.length() > reach:
			_caret = goal - gap.normalized() * reach
		_caret = _caret.lerp(goal, 1.0 - exp(-delta * 30.0))
	if goal != _caret_goal:
		_moved_at = _clock
	_caret_goal = goal
	_trail.append({"at": _caret, "time": _clock})
	while not _trail.is_empty() and _clock - _trail[0].time > TRAIL_TIME:
		_trail.pop_front()
	if not _particles.is_empty():
		var alive := []
		for particle in _particles:
			if _clock - particle.born - particle.delay < particle.life:
				alive.append(particle)
		_particles = alive
	queue_redraw()

func _draw() -> void:
	if not enabled or target == null:
		return
	var font := target.get_theme_font("font")
	var font_size := target.get_theme_font_size("font_size")
	var row := _row_height()
	var baseline := (row - font.get_height(font_size)) * 0.5 + font.get_ascent(font_size)
	var shift := _scroll_px()
	for particle in _particles:
		var age: float = _clock - particle.born - particle.delay
		if age < 0.0:
			continue
		var t: float = age / particle.life
		var at: Vector2 = particle.at - shift
		match particle.kind:
			IN:
				var glow := (1.0 - t) * (1.0 - t)
				draw_rect(Rect2(at + Vector2(-1, 2), Vector2(_char_width + 2, row - 4)), Color(Look.ACCENT, 0.3 * glow))
				draw_char(font, at + Vector2(0, baseline - 4.0 * glow), particle.glyph, font_size, Color(Look.BRIGHT, glow))
			OUT:
				var flicker := 0.65 + 0.35 * sin(age * 70.0 + particle.seed)
				var drift := Vector2(particle.drift * t * 8.0, t * t * 14.0)
				draw_char(font, at + Vector2(0, baseline) + drift, particle.glyph, font_size,
					Color(Look.ERROR.lerp(Look.ACCENT, t), (1.0 - t) * flicker * 0.9))
			BIT:
				var rise := Vector2(particle.drift * 10.0 * t, -26.0 * t)
				draw_char(font, at + Vector2(_char_width * 0.2, baseline) + rise, particle.glyph,
					maxi(8, int(font_size * 0.7)), Color(Look.ACCENT, (1.0 - t) * 0.75))
	_draw_reveal()
	_draw_caret(row, shift)

func _draw_reveal() -> void:
	var progress := (_clock - _reveal_at) / _reveal_time
	if progress >= 1.0 or progress < 0.0:
		return
	var edge := size.y * (1.0 - pow(1.0 - progress, 2.0))
	draw_rect(Rect2(0, edge, size.x, size.y - edge), _background())
	var band := 26.0
	draw_polygon(PackedVector2Array([Vector2(0, edge - band), Vector2(size.x, edge - band), Vector2(size.x, edge), Vector2(0, edge)]),
		PackedColorArray([Color(Look.ACCENT, 0.0), Color(Look.ACCENT, 0.0), Color(Look.ACCENT, 0.22), Color(Look.ACCENT, 0.22)]))
	draw_rect(Rect2(0, edge - 1.5, size.x, 1.5), Color(Look.BRIGHT, 0.85))

func _draw_caret(row: float, shift: Vector2) -> void:
	if not _caret_shown() or not _on_screen(_caret_goal - shift):
		return
	var focused := target.has_focus()
	var idle := _clock - _moved_at
	var level := 1.0 if idle < 0.5 else 0.62 + 0.38 * cos((idle - 0.5) * TAU / 1.1)
	if not focused:
		level = 0.22
	var extent := Vector2(_char_width if block_caret else 2.0, row - 2.0)
	if focused:
		for index in range(1, _trail.size()):
			var from: Vector2 = _trail[index - 1].at - shift
			var to: Vector2 = _trail[index].at - shift
			var gap := from.distance_to(to)
			if gap < 0.75:
				continue
			var fade := clampf(1.0 - (_clock - float(_trail[index].time)) / TRAIL_TIME, 0.0, 1.0)
			var steps := clampi(int(gap / 2.5), 1, 24)
			for step in steps:
				var f := float(step + 1) / steps
				draw_rect(Rect2(from.lerp(to, f) + Vector2(0, 1), extent), Color(Look.ACCENT, 0.16 * fade * f))
	var at := _caret - shift + Vector2(0, 1)
	draw_rect(Rect2(at - Vector2(5, 3), extent + Vector2(10, 6)), Color(Look.ACCENT, 0.06 * level))
	draw_rect(Rect2(at - Vector2(2, 1), extent + Vector2(4, 2)), Color(Look.ACCENT, 0.16 * level))
	draw_rect(Rect2(at, extent), Color(Look.ACCENT, 0.55 * level) if block_caret else Color(Look.BRIGHT, level))
	if target is TextEdit:
		var edit := target as TextEdit
		for caret in range(1, edit.get_caret_count()):
			var other := _caret_cell(caret)
			if _on_screen(other):
				draw_rect(Rect2(other + Vector2(0, 1), extent), Color(Look.BRIGHT, 0.7 * level))

func _caret_shown() -> bool:
	if target is TextEdit:
		return (target as TextEdit).editable
	return (target as LineEdit).editable

func _caret_cell(index := 0) -> Vector2:
	if target is TextEdit:
		var edit := target as TextEdit
		var line := edit.get_caret_line(index)
		return _cell(line, edit.get_caret_column(index), edit.get_line(line))
	var field := target as LineEdit
	return _cell(0, field.caret_column, field.text)

## Top-left corner of the character cell at a line and column, in this layer's coordinates.
## line_offset places text that has been removed below its surviving anchor line.
func _cell(line: int, column: int, text: String, line_offset := 0) -> Vector2:
	if target is TextEdit:
		var edit := target as TextEdit
		if line < 0 or line >= edit.get_line_count():
			return Vector2(-1.0e6, -1.0e6)
		var style := edit.get_theme_stylebox("normal")
		var x := edit.get_total_gutter_width() + style.get_margin(SIDE_LEFT) - edit.get_h_scroll() \
			+ visual_column(text, column, edit.get_tab_size()) * _char_width
		var y := style.get_margin(SIDE_TOP) + (edit.get_scroll_pos_for_line(line) - edit.get_v_scroll() + line_offset) * edit.get_line_height()
		return Vector2(x, y)
	var field := target as LineEdit
	var box := field.get_theme_stylebox("normal")
	return Vector2(box.get_margin(SIDE_LEFT) - field.get_scroll_offset() + column * _char_width,
		(field.size.y - _row_height()) * 0.5)

func _text_left() -> float:
	if target is TextEdit:
		var edit := target as TextEdit
		return edit.get_total_gutter_width() + edit.get_theme_stylebox("normal").get_margin(SIDE_LEFT)
	return target.get_theme_stylebox("normal").get_margin(SIDE_LEFT)

func _on_screen(at: Vector2) -> bool:
	return at.x >= _text_left() - 1.0 and at.x < size.x and at.y > -_row_height() and at.y < size.y

func _row_height() -> float:
	if target is TextEdit:
		return (target as TextEdit).get_line_height()
	return target.get_theme_font("font").get_height(target.get_theme_font_size("font_size"))

func _scroll_px() -> Vector2:
	if target is TextEdit:
		var edit := target as TextEdit
		return Vector2(edit.get_h_scroll(), edit.get_v_scroll() * edit.get_line_height())
	return Vector2((target as LineEdit).get_scroll_offset(), 0)

func _measure() -> void:
	var font := target.get_theme_font("font")
	var font_size := target.get_theme_font_size("font_size")
	_char_width = font.get_string_size("MMMMMMMMMM", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x / 10.0

func _background() -> Color:
	var style := target.get_theme_stylebox("normal")
	if style is StyleBoxFlat and (style as StyleBoxFlat).bg_color.a > 0.5:
		return (style as StyleBoxFlat).bg_color
	return Look.BACKGROUND
