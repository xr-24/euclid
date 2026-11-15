extends Control
## In-world approvals and the live status strip. A card at the top asks one question at a time when
## something needs your yes (load an agent's draft live, commit a checked one); Y or N answers it
## without opening a panel. The strip at the bottom right says what is live, what is checking, how
## many approvals wait and what last rolled back. Both stay out of the way when there is nothing.

const Look = preload("res://scripts/ui/terminal_theme.gd")
const HotLoad = preload("res://scripts/extensions/hot_load.gd")

## {"id", "text", "yes": Callable, "no": Callable}
var _queue: Array[Dictionary] = []
var _card: PanelContainer
var _question: Label
var _strip: Label
## A callable returning extra strip parts from the Workbench, such as a check in progress.
var workbench_status := Callable()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card = PanelContainer.new()
	_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_card.offset_top = 22
	_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var style := StyleBoxFlat.new()
	style.bg_color = Color(Look.SURFACE, 0.94)
	style.border_color = Look.ACCENT
	style.set_border_width_all(1)
	style.set_content_margin_all(14)
	style.set_corner_radius_all(4)
	_card.add_theme_stylebox_override("panel", style)
	_question = Label.new()
	_question.add_theme_color_override("font_color", Look.BRIGHT)
	_question.add_theme_font_size_override("font_size", 17)
	_question.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_question.custom_minimum_size.x = 520
	_card.add_child(_question)
	_card.visible = false
	add_child(_card)
	_strip = Label.new()
	_strip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_strip.offset_left = -760
	_strip.offset_top = -40
	_strip.offset_right = -28
	_strip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_strip.add_theme_color_override("font_color", Look.MUTED)
	_strip.add_theme_color_override("font_outline_color", Look.BACKGROUND)
	_strip.add_theme_constant_override("outline_size", 5)
	_strip.add_theme_font_size_override("font_size", 14)
	add_child(_strip)
	var timer := Timer.new()
	timer.wait_time = 0.5
	timer.timeout.connect(refresh_strip)
	add_child(timer)
	timer.start()

## Ask a question. Asking again with the same id replaces it.
func ask(id: String, text: String, yes: Callable, no := Callable()) -> void:
	withdraw(id)
	_queue.append({"id": id, "text": text, "yes": yes, "no": no})
	_show()

func withdraw(id: String) -> void:
	_queue = _queue.filter(func(item: Dictionary) -> bool: return item.id != id)
	_show()

## Withdraw every question whose id starts with prefix, except keep.
func withdraw_prefix(prefix: String, keep := "") -> void:
	_queue = _queue.filter(func(item: Dictionary) -> bool: return not str(item.id).begins_with(prefix) or item.id == keep)
	_show()

func pending() -> int:
	return _queue.size()

func asking(id: String) -> bool:
	return _queue.any(func(item: Dictionary) -> bool: return item.id == id)

## Answer the question on show. Returns false when there is none.
func answer(accept: bool) -> bool:
	if _queue.is_empty():
		return false
	var item: Dictionary = _queue.pop_front()
	_show()
	var action: Callable = item.yes if accept else item.no
	if action.is_valid():
		action.call()
	return true

func _show() -> void:
	_card.visible = not _queue.is_empty()
	if _queue.is_empty():
		return
	var more := "   (+%d more)" % (_queue.size() - 1) if _queue.size() > 1 else ""
	_question.text = "%s\n[Y] yes   [N] no%s" % [_queue[0].text, more]
	refresh_strip()

func refresh_strip() -> void:
	var parts := PackedStringArray()
	var live := HotLoad.timeline()
	var active := live.filter(func(entry: Dictionary) -> bool: return entry.status == "active").size()
	if active > 0:
		parts.append("%d LIVE" % active)
	if workbench_status.is_valid():
		parts.append_array(workbench_status.call())
	if not _queue.is_empty():
		parts.append("%d WAITING · Y/N" % _queue.size())
	for entry: Dictionary in live:
		if entry.status == "failed":
			parts.append("ROLLED BACK: %s" % str(entry.error).left(60))
			break
	_strip.text = "  ·  ".join(parts)
	_strip.visible = not parts.is_empty()
