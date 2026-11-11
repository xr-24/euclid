extends Node
## The wrist computer: Euclid's only menu. Tab brings the left forearm up and a hologram rises out
## of the emitter on top of it. Everything is reached from here: areas, build tools, Codex,
## Workbench, settings and quitting. Pages come from a source with pages() and status_line()
## (see wrist_pages.gd), so the projection, the keys and the content stay separate.
##
##   Tab            raise / lower          Escape   lower, or raise on SYSTEM
##   Q / E, ← →     previous / next page   ↑ ↓, wheel   select
##   Enter          choose; on a typing row, takes the keyboard for one line
##
## Walking and looking stay free while the wrist is up; only typing holds you still.
## The face is drawn into its own viewport at the size it appears, then laid over the view in
## 2D at the projected emitter, so text stays sharp under TAA, upscaling and tone mapping.

const Face = preload("res://scripts/ui/wrist_face.gd")
const HOLOGRAM = preload("res://shaders/wrist_hologram.gdshader")
const VEIL = preload("res://shaders/wrist_veil.gdshader")

const OPEN_SECONDS := 0.3
const CLOSE_SECONDS := 0.2
## The face's share of the window width (its height follows the 3:2 face).
const SCREEN_WIDTH := 0.42
## How far the face leans from above the emitter toward the middle of the view, 0 to 1.
const LEAN := 0.45
## Where the emitter sits on the forearm, lifted off the sleeve, in camera space.
const EMITTER_LIFT := Vector3(0, 0.03, 0)
const INPUT_LIMIT := 240
const FAN := 18

var source = null
var is_open := false
var open_t := 0.0
var page := 0
var typing := false
var entry := ""
var time := 0.0
var _pages: Array = []
var _cursors := {}
var _armed := ""
var _submit_to := Callable()
var _then_page := ""
var _notice := ""
var _notice_warn := false
var _notice_left := 0.0
var _ever_opened := false
var _camera: Camera3D
var _hands = null
var _layer: CanvasLayer
var _viewport: SubViewport
var _face: Face
var _face_rect: TextureRect
var _veil: ColorRect
var _beams: Control
var _face_material: ShaderMaterial
var _veil_material: ShaderMaterial
var _k := 0.0
var _flicker := 1.0
var _emitter := Vector2.ZERO
var _rect := Rect2()

func _init() -> void:
	name = "WristComputer"

## Shows the wrist on the player's view. hands is duck-typed: set_wrist_raised(up) and
## wrist_emitter() -> {point, raised} in camera space; without it the face rises from the bottom.
func mount(parent: Node, camera: Camera3D, hands, pages_source) -> void:
	_camera = camera
	_hands = hands
	parent.add_child(self)
	configure(pages_source)
	_layer = CanvasLayer.new()
	_layer.layer = 2
	_layer.add_to_group("private_world_surfaces")
	add_child(_layer)
	_viewport = SubViewport.new()
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.size = Vector2i(1008, 672)
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	_face = Face.new()
	_face.wrist = self
	_face.size = Vector2(_viewport.size)
	_viewport.add_child(_face)
	var screen := Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(screen)
	_veil = ColorRect.new()
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil_material = ShaderMaterial.new()
	_veil_material.shader = VEIL
	_veil.material = _veil_material
	screen.add_child(_veil)
	_beams = Control.new()
	_beams.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_beams.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_beams.material = additive
	_beams.draw.connect(_draw_beams)
	screen.add_child(_beams)
	_face_rect = TextureRect.new()
	_face_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_face_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_face_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_face_rect.texture = _viewport.get_texture()
	_face_material = ShaderMaterial.new()
	_face_material.shader = HOLOGRAM
	_face_rect.material = _face_material
	screen.add_child(_face_rect)
	_layer.visible = false

func configure(pages_source) -> void:
	source = pages_source
	refresh()

func refresh() -> void:
	_pages = source.pages() if source != null else []
	page = clampi(page, 0, maxi(0, _pages.size() - 1))

func page_list() -> Array:
	return _pages

func current() -> Dictionary:
	return _pages[page] if page < _pages.size() else {}

func rows() -> Array:
	return current().get("rows", [])

func cursor() -> int:
	var count := rows().size()
	return clampi(int(_cursors.get(current().get("id", ""), 0)), 0, maxi(0, count - 1))

func status_line() -> String:
	return source.status_line() if source != null and source.has_method("status_line") else ""

func notice() -> Dictionary:
	return {"text": _notice, "warn": _notice_warn} if _notice_left > 0.0 else {}

## A one-time nudge for the hint line until the wrist has been raised once.
func idle_hint() -> String:
	return "Tab: wrist computer" if not _ever_opened and time < 45.0 else ""

func blocks_movement() -> bool:
	return typing

func raise_wrist(page_id := "") -> void:
	refresh()
	if not page_id.is_empty():
		for index in _pages.size():
			if _pages[index].get("id", "") == page_id:
				page = index
	is_open = true
	_ever_opened = true

func lower_wrist() -> void:
	is_open = false
	typing = false
	_armed = ""

func toggle_wrist() -> void:
	if is_open:
		lower_wrist()
	else:
		raise_wrist()

func turn(direction: int) -> void:
	if _pages.is_empty():
		return
	page = posmod(page + direction, _pages.size())
	typing = false
	_armed = ""

func move(direction: int) -> void:
	var count := rows().size()
	if count == 0:
		return
	_cursors[current().get("id", "")] = clampi(cursor() + direction, 0, count - 1)
	_armed = ""

func choose() -> void:
	var list := rows()
	if list.is_empty():
		return
	var row: Dictionary = list[cursor()]
	if not row.get("enabled", true):
		say(str(row.get("why", "Not available right now.")), true)
		return
	var key := "%s/%s" % [current().get("id", ""), row.get("label", "")]
	if row.has("confirm") and _armed != key:
		_armed = key
		say(str(row.confirm), true)
		return
	_armed = ""
	var run: Callable = row.get("run", Callable())
	if row.get("input", false):
		typing = true
		entry = ""
		_submit_to = run
		_then_page = str(row.get("then", ""))
		return
	if row.get("close", false):
		lower_wrist()
	if run.is_valid():
		run.call()

func say(line: String, warn := false) -> void:
	_notice = line
	_notice_warn = warn
	_notice_left = 3.5

## Keys and the wheel while no panel is open. Returns true when the wrist used the event.
func handle(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if not is_open or not button.pressed:
			return false
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			move(-1)
			return true
		if button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			move(1)
			return true
		return false
	if not event is InputEventKey:
		return false
	var key := event as InputEventKey
	if not key.pressed:
		return false
	if typing:
		return _type(key)
	var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
	if key.echo and code != KEY_UP and code != KEY_DOWN:
		return is_open and code in [KEY_Q, KEY_E, KEY_LEFT, KEY_RIGHT, KEY_ENTER, KEY_KP_ENTER, KEY_TAB]
	if code == KEY_TAB:
		toggle_wrist()
		return true
	if code == KEY_ESCAPE:
		if is_open:
			lower_wrist()
		else:
			raise_wrist("system")
		return true
	if not is_open:
		return false
	match code:
		KEY_Q, KEY_LEFT:
			turn(-1)
		KEY_E, KEY_RIGHT:
			turn(1)
		KEY_UP:
			move(-1)
		KEY_DOWN:
			move(1)
		KEY_ENTER, KEY_KP_ENTER:
			choose()
		_:
			return false
	return true

func _type(key: InputEventKey) -> bool:
	match key.keycode:
		KEY_ESCAPE:
			typing = false
		KEY_ENTER, KEY_KP_ENTER:
			_submit()
		KEY_BACKSPACE:
			entry = entry.left(-1)
		KEY_TAB:
			lower_wrist()
		_:
			if key.ctrl_pressed and key.keycode == KEY_V:
				var pasted := DisplayServer.clipboard_get().replace("\r", " ").replace("\n", " ")
				entry = (entry + pasted).left(INPUT_LIMIT)
			elif key.unicode >= 32 and not key.ctrl_pressed and entry.length() < INPUT_LIMIT:
				entry += char(key.unicode)
	return true

func _submit() -> void:
	var line := entry.strip_edges()
	entry = ""
	typing = false
	if line.is_empty() or not _submit_to.is_valid():
		return
	if not _then_page.is_empty():
		raise_wrist(_then_page)
	_submit_to.call(line)

func _process(delta: float) -> void:
	time += delta
	_notice_left = maxf(0.0, _notice_left - delta)
	open_t = move_toward(open_t, 1.0 if is_open else 0.0, delta / (OPEN_SECONDS if is_open else CLOSE_SECONDS))
	if _layer == null:
		return
	if _hands != null and _hands.has_method("set_wrist_raised"):
		# The face goes down before the arm does.
		_hands.set_wrist_raised(is_open or open_t > 0.35)
	var window := _layer.get_viewport().get_visible_rect().size
	var raised := 1.0
	_emitter = Vector2(window.x * 0.5, window.y * 0.9)
	if _hands != null and _hands.has_method("wrist_emitter"):
		var reading: Dictionary = _hands.wrist_emitter()
		if not reading.is_empty():
			raised = float(reading.raised)
			var point: Vector3 = _camera.to_global(reading.point + EMITTER_LIFT)
			if not _camera.is_position_behind(point):
				_emitter = _camera.unproject_position(point)
	var eased := open_t * open_t * (3.0 - 2.0 * open_t)
	_k = eased * smoothstep(0.5, 0.95, raised)
	var showing := _k > 0.002
	_layer.visible = showing
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if showing else SubViewport.UPDATE_DISABLED
	if not showing:
		return
	if is_open:
		refresh()
	_layout(window)
	_face.queue_redraw()
	_beams.queue_redraw()

func _layout(window: Vector2) -> void:
	var width := maxi(560, roundi(window.x * SCREEN_WIDTH))
	var pixels := Vector2i(width, roundi(width * 2.0 / 3.0))
	if _viewport.size != pixels:
		_viewport.size = pixels
		_face.size = Vector2(pixels)
	var face := Vector2(pixels)
	var height := face.y * _k
	var margin := window.y * 0.03
	var center := Vector2(_emitter.x + (window.x * 0.5 - _emitter.x) * LEAN * _k, _emitter.y - window.y * 0.012 - height * 0.5)
	center.x = clampf(center.x, face.x * 0.5 + margin, maxf(face.x * 0.5 + margin, window.x - face.x * 0.5 - margin))
	center.y = clampf(center.y, height * 0.5 + margin, maxf(height * 0.5 + margin, window.y - height * 0.5 - margin))
	_rect = Rect2(center - Vector2(face.x, height) * 0.5, Vector2(face.x, height))
	_face_rect.position = _rect.position
	_face_rect.size = _rect.size
	_veil.position = _rect.position - _rect.size * 0.03
	_veil.size = _rect.size * 1.06
	_flicker = 0.93 + 0.07 * sin(time * 41.0) * sin(time * 13.7)
	if fposmod(time * 0.37, 1.0) > 0.985:
		_flicker *= 0.7
	_face_material.set_shader_parameter("glow", _k * _flicker)
	_face_material.set_shader_parameter("time", time)
	_veil_material.set_shader_parameter("opacity", 0.46 * _k)

func _draw_beams() -> void:
	if _k <= 0.002:
		return
	var accent := Face.ACCENT
	var bottom_left := Vector2(_rect.position.x, _rect.end.y)
	var bottom_right := _rect.end
	for index in FAN + 1:
		var t := float(index) / FAN
		var edge := 1.0 if index == 0 or index == FAN else 0.0
		_beams.draw_line(_emitter, bottom_left.lerp(bottom_right, t),
			Color(accent, (0.05 + edge * 0.3) * _k * _flicker), 1.5 if edge > 0.0 else 1.0, true)
	var reach := _rect.size.x * 0.045
	var bracket := Color(accent, 0.85 * _k * _flicker)
	for corner in [_rect.position, Vector2(_rect.end.x, _rect.position.y), bottom_left, bottom_right]:
		var point: Vector2 = corner
		var inward := Vector2(signf(_rect.get_center().x - point.x), signf(_rect.get_center().y - point.y))
		_beams.draw_line(point, point + Vector2(inward.x * reach, 0), bracket, 2.0, true)
		_beams.draw_line(point, point + Vector2(0, inward.y * minf(reach, _rect.size.y * 0.5)), bracket, 2.0, true)
	var sweep := _rect.end.y - _rect.size.y * fposmod(time * 0.35, 1.0)
	_beams.draw_line(Vector2(_rect.position.x, sweep), Vector2(_rect.end.x, sweep), Color(accent, 0.14 * _k), 1.0)
	_beams.draw_line(_emitter - Vector2(8, 0), _emitter + Vector2(8, 0), Color(Face.BRIGHT, 0.9 * _k), 2.5, true)
