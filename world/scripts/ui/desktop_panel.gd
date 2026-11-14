extends PanelContainer
## Shared chrome for the world's desktop panels. The wrist has its own viewport.

const EDGE := 8.0
const MINIMUM := Vector2(360, 220)
const ThemeColors = preload("res://scripts/ui/terminal_theme.gd")

var content := VBoxContainer.new()
var _grip := Label.new()
var _pointer_start := Vector2.ZERO
var _rect_start := Rect2()
var _edge := Vector2.ZERO
var _dragging := false
var keyboard_active := false
var _last_focus: Control

func _ready() -> void:
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 5)
	add_child(stack)
	_grip.text = "•••"
	_grip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_grip.mouse_filter = MOUSE_FILTER_PASS
	_grip.mouse_default_cursor_shape = CURSOR_MOVE
	_grip.tooltip_text = "Drag to move. Drag an edge or corner to resize."
	_grip.add_theme_color_override("font_color", ThemeColors.MUTED)
	stack.add_child(_grip)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.follow_focus = true
	stack.add_child(scroll)
	content.size_flags_horizontal = SIZE_EXPAND_FILL
	content.size_flags_vertical = SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	scroll.add_child(content)
	get_viewport().size_changed.connect(_fit_to_viewport.call_deferred)
	visibility_changed.connect(func() -> void:
		_dragging = false
		set_keyboard_active(is_visible_in_tree()))
	resized.connect(queue_redraw)

func set_keyboard_active(active: bool) -> void:
	if keyboard_active == active:
		return
	keyboard_active = active
	if not active:
		_release_panel_focus()
	elif is_instance_valid(_last_focus) and is_ancestor_of(_last_focus) and _last_focus.is_visible_in_tree():
		_last_focus.grab_focus()

func _release_panel_focus() -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if is_instance_valid(focused) and is_ancestor_of(focused):
		_last_focus = focused
		focused.release_focus()

func _draw() -> void:
	for offset in [5.0, 9.0, 13.0]:
		draw_line(size - Vector2(offset, 3), size - Vector2(3, offset), ThemeColors.MUTED)

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventKey and not keyboard_active:
		_release_panel_focus()
		return
	if event is InputEventMouseMotion:
		var point: Vector2 = get_canvas_transform().affine_inverse() * event.position
		if _dragging:
			if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
				_drag_to(point)
				get_viewport().set_input_as_handled()
			else:
				_dragging = false
		else:
			_set_edge_cursor(_edge_at(point))
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		var point: Vector2 = get_canvas_transform().affine_inverse() * event.position
		set_keyboard_active(get_global_rect().has_point(point))
		if event.button_index == MOUSE_BUTTON_LEFT:
			var edge := _edge_at(point)
			if edge != Vector2.ZERO or _grip.get_global_rect().has_point(point):
				_dragging = true
				_edge = edge
				_pointer_start = point
				_rect_start = get_global_rect()
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and _dragging:
		_dragging = false
		get_viewport().set_input_as_handled()

func _edge_at(point: Vector2) -> Vector2:
	var rect := get_global_rect()
	if not rect.has_point(point):
		return Vector2.ZERO
	var x := -1.0 if point.x - rect.position.x < EDGE else (1.0 if rect.end.x - point.x < EDGE else 0.0)
	var y := -1.0 if point.y - rect.position.y < EDGE else (1.0 if rect.end.y - point.y < EDGE else 0.0)
	return Vector2(x, y)

func _set_edge_cursor(edge: Vector2) -> void:
	if edge.x != 0 and edge.y != 0:
		mouse_default_cursor_shape = CURSOR_FDIAGSIZE if edge.x == edge.y else CURSOR_BDIAGSIZE
	elif edge.x != 0:
		mouse_default_cursor_shape = CURSOR_HSIZE
	elif edge.y != 0:
		mouse_default_cursor_shape = CURSOR_VSIZE
	else:
		mouse_default_cursor_shape = CURSOR_ARROW

func _drag_to(point: Vector2) -> void:
	var view := get_viewport_rect().size
	var delta := point - _pointer_start
	var rect := _rect_start
	if _edge == Vector2.ZERO:
		rect.position += delta
		_set_rect(rect, view)
		return
	var minimum := MINIMUM.min(view)
	var start := rect.position
	var end := rect.end
	for axis in 2:
		if _edge[axis] < 0:
			start[axis] = clampf(start[axis] + delta[axis], 0.0, maxf(0.0, end[axis] - minimum[axis]))
		elif _edge[axis] > 0:
			end[axis] = clampf(end[axis] + delta[axis], minf(view[axis], start[axis] + minimum[axis]), view[axis])
	_set_rect(Rect2(start, end - start), view)

func _fit_to_viewport() -> void:
	_set_rect(get_global_rect(), get_viewport_rect().size)

func _set_rect(rect: Rect2, view: Vector2) -> void:
	var extent := rect.size.clamp(MINIMUM.min(view), view)
	set_size(extent)
	set_global_position(rect.position.clamp(Vector2.ZERO, (view - size).max(Vector2.ZERO)))
