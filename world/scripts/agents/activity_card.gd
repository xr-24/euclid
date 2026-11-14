extends Node3D
## The panel above an agent showing what it is doing (activity_view.gd draws it). Events queue
## and play one after another; a backlog plays faster. Far away, or with Graphics set to icons,
## only the header shows. After the last event the panel lingers, then fades out.

const View = preload("res://scripts/agents/activity_view.gd")
const Graphics = preload("res://scripts/rendering/graphics_settings.gd")
## Width of the panel in metres.
const WIDTH_M := 1.3
## Height of the panel's lower edge above the agent's centre.
const LIFT := 1.12
const LINGER := 8.0
const FADE := 1.2
const COMPACT_DISTANCE := 13.0
const HIDE_DISTANCE := 45.0
const BACKLOG := 24
## Seconds the agent holds its last activity's motion after the event finishes.
const HOLD := 1.5

## The kind of activity the agent should act out now ("" to go back to hovering).
signal motion(kind: String)

var tint := Color("ff4813")
var highlight := Color("ffbc55")
var _viewport: SubViewport
var _view: View
var _sprite: Sprite3D
var _queue: Array[Dictionary] = []
var _time := 0.0
var _length := 0.0
## Seconds since the last event finished; the panel lingers, then fades.
var _idle := LINGER + FADE + 1.0
var _compact := false
var _laid_out := false
var _motion := ""

func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.gui_disable_input = true
	_viewport.size = Vector2i(View.WIDTH, View.FULL_HEIGHT)
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	_view = View.new()
	_view.size = Vector2(View.WIDTH, View.FULL_HEIGHT)
	_view.tint = tint
	_view.highlight = highlight
	_viewport.add_child(_view)
	_sprite = Sprite3D.new()
	_sprite.texture = _viewport.get_texture()
	_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sprite.pixel_size = WIDTH_M / View.WIDTH
	_sprite.shaded = false
	_sprite.double_sided = true
	_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_sprite)
	_layout(false)
	visible = false

## Queue an event from the activity feed.
func push(entry: Dictionary) -> void:
	_queue.append(entry)
	# A long backlog drops the oldest events that are only talk.
	while _queue.size() > BACKLOG:
		var drop := _queue.find_custom(func(item: Dictionary) -> bool: return str(item.get("kind")) in ["think", "say", "tool", "search"])
		_queue.remove_at(drop if drop > 0 else 1)
	if _queue.size() == 1:
		_start()

## The event playing now, or {}.
func current() -> Dictionary:
	return _queue.front() if not _queue.is_empty() else {}

func _start() -> void:
	_time = 0.0
	_idle = 0.0
	_view.event = _queue.front()
	_length = View.duration(_view.event)
	_act(str(_view.event.get("kind", "")))

func _act(kind: String) -> void:
	if kind != _motion:
		_motion = kind
		motion.emit(kind)

func _process(delta: float) -> void:
	var mode := Graphics.agent_activity
	if mode == "off" or (_queue.is_empty() and _idle > LINGER + FADE):
		visible = false
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		if mode == "off":
			_queue.clear()
		_act("")
		return
	var camera := get_viewport().get_camera_3d()
	var distance := camera.global_position.distance_to(global_position) if camera else 0.0
	if distance > HIDE_DISTANCE:
		visible = false
		return
	visible = true
	_layout(mode == "icons" or distance > COMPACT_DISTANCE)
	if not _queue.is_empty():
		# A backlog plays faster so the panel keeps up with the agent.
		_time += delta * maxf(1.0, _queue.size() / 3.0)
		if _time >= _length and _queue.size() > 1:
			_queue.pop_front()
			_start()
		elif _time >= _length:
			_queue.pop_front()
			_idle = 0.0
			_time = _length
	else:
		_idle += delta
		if _idle > HOLD:
			_act("")
	_view.time = _time
	_view.fade = 1.0 if not _queue.is_empty() else 1.0 - clampf((_idle - LINGER) / FADE, 0.0, 1.0)
	_view.show_code = Graphics.show_code
	_view.queue_redraw()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

func _layout(compact: bool) -> void:
	if _laid_out and compact == _compact:
		return
	_laid_out = true
	_compact = compact
	_view.compact = compact
	var height := View.COMPACT_HEIGHT if compact else View.FULL_HEIGHT
	_viewport.size = Vector2i(View.WIDTH, height)
	_view.size = Vector2(View.WIDTH, height)
	_sprite.position.y = LIFT + height * _sprite.pixel_size * 0.5
