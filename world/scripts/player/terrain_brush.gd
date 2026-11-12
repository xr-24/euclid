extends Node3D
## The pointer, live stroke and camera navigation for the terrain panel.

const Terrain = preload("res://scripts/pieces/terrain_node.gd")
const Placement = preload("res://scripts/workshop/scene_placement.gd")
const TerrainPanel = preload("res://scripts/ui/terrain_panel.gd")
const Editor = preload("res://scripts/pieces/piece_editor.gd")
const Tools = preload("res://scripts/pieces/terrain_tools.gd")
const INTERVAL := 0.075

var _editor: Editor
var _panel: TerrainPanel
var _player: CharacterBody3D
var _camera: Camera3D
var _look: Callable
var _looking := false
var _target: Terrain
var _id := ""
var _revision := 0
var _level := 0.0
var _last := Vector2.ZERO
var _left_surface := false
var _time := 0.0
var _mode := ""
var _radius := 0.0
var _strength := 0.0
var _material := 0
var _ring := ImmediateMesh.new()
var _marker: MeshInstance3D
var _ink := StandardMaterial3D.new()

func _ready() -> void:
	_ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ink.albedo_color = Color("75ffe8")
	_ink.cull_mode = BaseMaterial3D.CULL_DISABLED
	_marker = MeshInstance3D.new()
	_marker.mesh = _ring
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.hide()
	add_child(_marker)

func attach(editor: Editor, panel: TerrainPanel, player: CharacterBody3D, camera: Camera3D, look: Callable) -> void:
	_editor = editor
	_panel = panel
	_player = player
	_camera = camera
	_look = look

func active() -> bool:
	return is_instance_valid(_panel) and _panel.is_visible_in_tree()

func looking() -> bool:
	return active() and _looking

func cancel() -> void:
	if is_instance_valid(_target) and _editor.node_for(_id) == _target:
		_target.load_surface(_editor.record(_id).get("terrain_surface", ""))
	_clear_stroke()
	_stop_look()
	_marker.hide()

func _clear_stroke() -> void:
	_target = null
	_id = ""

func _stop_look() -> void:
	if _looking:
		_looking = false
		if active():
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _input(event: InputEvent) -> void:
	if not active():
		return
	if event is InputEventMouseMotion and _looking:
		_look.call(event.relative)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and not _id.is_empty():
			_finish()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_MIDDLE and not event.pressed and _looking:
			_stop_look()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and not _id.is_empty():
		cancel()
		_panel.show_status("Stroke discarded.")
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not active() or not event is InputEventMouseButton or not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_MIDDLE:
		_looking = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.button_index == MOUSE_BUTTON_LEFT:
		var hit := _aim(event.position)
		if hit.is_empty():
			_panel.show_status("Aim at terrain.")
		elif _id.is_empty():
			_begin(hit)
	else:
		return
	get_viewport().set_input_as_handled()

func _physics_process(delta: float) -> void:
	if not active():
		if not _id.is_empty() or _looking:
			cancel()
		_marker.hide()
		return
	if not _id.is_empty() and (_editor.revision != _revision or not is_instance_valid(_target)):
		cancel()
		_panel.show_status("The scene changed. Start a new stroke.")
	var hit := _aim()
	if hit.is_empty():
		_left_surface = not _id.is_empty()
		_marker.hide()
		return
	var node: Terrain = hit.node
	var point: Vector2 = hit.point
	if node == _target:
		_time += delta
		if _time >= INTERVAL:
			if _left_surface:
				_last = point
				_left_surface = false
			_paint_to(point)
			_time = 0.0
	elif not _id.is_empty():
		_left_surface = true
	_draw_ring(node, point, _panel.radius() if _id.is_empty() else _radius)

func _aim(pointer := Vector2.INF) -> Dictionary:
	var viewport := _camera.get_viewport()
	var pixel := viewport.get_visible_rect().get_center() if _looking else pointer
	if not pixel.is_finite():
		pixel = viewport.get_mouse_position()
	if not _looking and _panel.get_global_rect().has_point(pixel):
		return {}
	var hit := Placement.aim_at(_player, _camera, pixel, 220.0)
	var node := _editor.node_for(hit.piece) as Terrain
	if node == null or not node.is_visible_in_tree():
		return {}
	return {"node": node, "id": hit.piece, "point": node.local_point(hit.point)}

func _begin(hit: Dictionary) -> void:
	if not _editor.can_edit():
		return
	_target = hit.node
	_id = hit.id
	_revision = _editor.revision
	_mode = _panel.mode
	_radius = _panel.radius()
	_strength = _panel.strength()
	_material = _panel.material_index()
	_last = hit.point
	_left_surface = false
	_level = _target.data.surface_at(_last, _target.terrain_size)
	_time = 0.0
	_panel.show_status("")
	_paint_to(_last)

func _paint_to(point: Vector2) -> void:
	var count := clampi(ceili(_last.distance_to(point) / (_radius * 0.25)), 1, 12)
	for index in range(1, count + 1):
		var at := _last.lerp(point, float(index) / count)
		_target.preview_dab(at, _mode, _radius, _strength * 0.55, _material, _level)
	_target.flush_preview()
	_last = point

func _finish() -> void:
	if not is_instance_valid(_target) or _revision != _editor.revision:
		cancel()
		return
	var result := _editor.commit_storage(_id, {"terrain_surface": _target.data.encode()}, _revision, "Stroke saved.")
	if result.ok:
		_player.global_position = Tools.above_surface(_editor, _player.global_position, _id)
		_clear_stroke()
	else:
		cancel()
	_panel.show_status(result.message)

func _draw_ring(node: Terrain, center: Vector2, radius: float) -> void:
	_ring.clear_surfaces()
	_ring.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _ink)
	var half_width := clampf(radius * 0.009, 0.06, 0.20)
	for index in 65:
		var radial := Vector2.from_angle(TAU * index / 64.0)
		for edge in [radius - half_width, radius + half_width]:
			var point := (center + radial * float(edge)).clamp(-node.terrain_size * 0.5, node.terrain_size * 0.5)
			_ring.surface_add_vertex(to_local(node.surface_point(point, 0.06)))
	_ring.surface_end()
	_marker.show()
