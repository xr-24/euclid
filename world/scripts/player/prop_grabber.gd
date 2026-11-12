extends Node3D
## Temporary physics pose while held. Release and lock commit one scene undo step. Letting go
## drops a prop that can move freely; M2 while holding places it and locks it there.

const Placement = preload("res://scripts/workshop/scene_placement.gd")
const Pose = preload("res://scripts/player/hand_poses.gd").Pose
const Beam = preload("res://shaders/grab_beam.gdshader")
const Layers = preload("res://scripts/rendering/render_layers.gd")
const REACH := 18.0
const MODES := ["Rotate", "Resize", "Distance"]

var _down := false
var _events: Array[int] = []
var _hold := {}
var _mode := 0
var _fist := 0.0
var _beam: MeshInstance3D
var _ink: ShaderMaterial
var _notice := ""
var _notice_time := 0.0

func _ready() -> void:
	_beam = MeshInstance3D.new()
	var tube := CylinderMesh.new()
	tube.height = 1.0
	tube.top_radius = 0.043
	tube.bottom_radius = 0.025
	tube.radial_segments = 10
	tube.rings = 1
	tube.cap_top = false
	tube.cap_bottom = false
	_beam.mesh = tube
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_beam.layers = Layers.REFLECTION_HIDDEN
	_ink = ShaderMaterial.new()
	_ink.shader = Beam
	_beam.material_override = _ink
	_beam.hide()
	add_child(_beam)

func handle(event: InputEvent) -> bool:
	var button := event as InputEventMouseButton
	if not button:
		return false
	if button.button_index == MOUSE_BUTTON_LEFT:
		_events.append(1 if button.pressed else -1)
		return true
	if button.pressed and (button.button_index == MOUSE_BUTTON_RIGHT or not _hold.is_empty()):
		if button.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_events.append(button.button_index)
			return true
	return false

func tick(delta: float, player: CharacterBody3D, camera: Camera3D, tools, hands, enabled: bool) -> Dictionary:
	_fist = maxf(0.0, _fist - delta)
	_notice_time = maxf(0.0, _notice_time - delta)
	if not enabled:
		cancel()
		return {}
	if not _down and _events.is_empty() and _hold.is_empty() and _fist == 0.0:
		return {}
	var aim := Placement.aim_at(player, camera, camera.get_viewport().get_visible_rect().get_center(), REACH)
	for event in _events:
		match event:
			1:
				_down = true
				_begin(tools, aim)
			-1:
				_down = false
				_finish(tools, false)
			MOUSE_BUTTON_RIGHT:
				if not _hold.is_empty():
					_finish(tools, true)
					_down = false
				else:
					_unlock(tools, aim)
			MOUSE_BUTTON_MIDDLE:
				_mode = (_mode + 1) % MODES.size()
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				_adjust(1.0 if event == MOUSE_BUTTON_WHEEL_UP else -1.0)
	_events.clear()
	var end: Vector3 = aim.point
	if not _hold.is_empty():
		var body: Node3D = _hold.node
		if not is_instance_valid(body) or tools.scene_node(_hold.id) != body:
			_hold.clear()
		else:
			end = _move(player, tools.bounds, aim)
	_beam.visible = _down and _fist == 0.0
	if _beam.visible:
		_draw_beam(hands.palm_position(), end)
		return {"pose": Pose.OPEN_PALM, "point": end}
	return {"pose": Pose.FIST} if _fist > 0.0 else {}

func hint() -> String:
	if not _hold.is_empty():
		var action := "place"
		if _hold.lockable:
			action = "unlock" if _hold.record.get("locked", false) else "lock"
		return "%s · Wheel · M3 mode · M2 %s" % [MODES[_mode], "place" if _hold.lockable else action]
	return _notice if _notice_time > 0 else ""

func cancel() -> void:
	_events.clear()
	_down = false
	_fist = 0.0
	_restore()
	_hold.clear()
	_beam.hide()

func _begin(tools, aim: Dictionary) -> void:
	if aim.id.is_empty() or not _hold.is_empty():
		return
	var node: Node3D = tools.scene_node(aim.id)
	var inspected: Dictionary = tools.execute("inspect", {"id": aim.id})
	if not node or not inspected.ok:
		return
	var record: Dictionary = inspected.entity
	if record.has("behavior") or not record.get("animation", {}).is_empty() or node.has_node("DoorActuator"):
		_say("This prop is driven by an animation or behavior.")
		return
	_hold = {"id": aim.id, "node": node, "transform": node.transform, "world_basis": node.global_basis,
		"hit_offset": node.global_position - aim.point, "depth": aim.from.distance_to(aim.point),
		"yaw": 0.0, "scale": float(record.scale), "initial_scale": float(record.scale), "record": record,
		"lockable": tools.can_toggle_lock(aim.id), "parts": {}, "yaw_from": tools.live_yaw(aim.id)}
	if node is RigidBody3D:
		_hold["frozen"] = node.freeze
		_hold["linear"] = node.linear_velocity
		_hold["angular"] = node.angular_velocity
		node.freeze = true
		node.linear_velocity = Vector3.ZERO
		node.angular_velocity = Vector3.ZERO
		for part in node.get_children():
			if part is Node3D and part is not CollisionShape3D:
				_hold.parts[part] = part.transform

func _adjust(step: float) -> void:
	if _hold.is_empty():
		return
	match _mode:
		0: _hold.yaw += step * 15.0
		1: _hold.scale = clampf(_hold.scale * pow(1.10, step), 0.25, 4.0)
		2: _hold.depth = clampf(_hold.depth + step * 0.35, 0.9, REACH)

func _move(player: CharacterBody3D, bounds: AABB, aim: Dictionary) -> Vector3:
	var node: Node3D = _hold.node
	var yaw := Basis(Vector3.UP, deg_to_rad(_hold.yaw))
	var factor: float = _hold.scale / _hold.initial_scale
	var offset: Vector3 = yaw * _hold.hit_offset * factor
	var depth := minf(_hold.depth, aim.from.distance_to(aim.point) - 0.045) if aim.id != _hold.id else float(_hold.depth)
	var desired: Vector3 = aim.from + aim.direction * maxf(depth, 0.85) + offset
	var parent := node.get_parent() as Node3D
	desired = parent.to_global(parent.to_local(desired).clamp(bounds.position, bounds.end))
	if node is PhysicsBody3D:
		var query := PhysicsTestMotionParameters3D.new()
		query.from = node.global_transform
		query.motion = desired - node.global_position
		query.exclude_bodies = [player.get_rid()]
		var motion := PhysicsTestMotionResult3D.new()
		if PhysicsServer3D.body_test_motion(node.get_rid(), query, motion):
			desired = node.global_position + motion.get_travel()
	if node is RigidBody3D:
		node.global_basis = yaw * _hold.world_basis
		for part: Node3D in _hold.parts:
			part.transform = (_hold.parts[part] as Transform3D).scaled(Vector3.ONE * factor)
	else:
		node.global_basis = (yaw * _hold.world_basis).scaled(Vector3.ONE * factor)
	node.global_position = desired
	return desired - offset

func _finish(tools, toggle_lock: bool) -> void:
	if _hold.is_empty():
		return
	var node: Node3D = _hold.node
	if is_instance_valid(node):
		var initial_yaw: float = _hold.yaw_from
		var changes := {"position": Placement.coordinates(node.position), "yaw": wrapf(initial_yaw + _hold.yaw, -180.0, 180.0), "scale": _hold.scale}
		if tools.can_toggle_lock(_hold.id):
			# Holding freezes physics for the drag. Letting go drops the prop; M2 places and
			# locks it where it is.
			changes["locked"] = toggle_lock
		# Keep the live pose on screen. The scene edit applies scale to the real colliders.
		if node is RigidBody3D and _hold.scale != _hold.initial_scale:
			_restore_parts()
		var result: Dictionary = tools.commit_grab(_hold.id, node, changes)
		if not result.ok:
			_restore()
			_say(result.error)
		elif is_instance_valid(node) and node is RigidBody3D and changes.has("locked") and node.freeze != changes.locked:
			node.freeze = changes.locked
			if not node.freeze:
				node.sleeping = false
		if result.ok and toggle_lock:
			var notice := "Placed"
			if changes.has("locked"):
				notice = "Locked" if changes.locked else "Unlocked"
			_say(notice)
	if toggle_lock:
		_fist = 0.25
	_hold.clear()

func _unlock(tools, aim: Dictionary) -> void:
	var body: Node3D = tools.scene_node(aim.id)
	if body and tools.can_toggle_lock(aim.id) and (not body is RigidBody3D or body.freeze):
		var result: Dictionary = tools.commit_grab(aim.id, body, {"locked": false, "position": Placement.coordinates(body.position)})
		_say("Unlocked" if result.ok else result.error)
		_fist = 0.25

func _restore() -> void:
	if _hold.is_empty() or not is_instance_valid(_hold.node):
		return
	var node: Node3D = _hold.node
	node.transform = _hold.transform
	if node is RigidBody3D:
		_restore_parts()
		node.linear_velocity = _hold.linear
		node.angular_velocity = _hold.angular
		node.freeze = _hold.frozen

func _restore_parts() -> void:
	for part: Node3D in _hold.parts:
		if is_instance_valid(part):
			part.transform = _hold.parts[part]

func _draw_beam(start: Vector3, end: Vector3) -> void:
	var axis := end - start
	var length := maxf(axis.length(), 0.001)
	var up := axis / length
	var right := up.cross(Vector3.UP).normalized() if absf(up.y) < 0.98 else up.cross(Vector3.RIGHT).normalized()
	_beam.global_transform = Transform3D(Basis(right, up * length, right.cross(up)), start.lerp(end, 0.5))
	_ink.set_shader_parameter("strength", 0.15 if _hold.is_empty() else 0.44)

func _say(message: String) -> void:
	_notice = message
	_notice_time = 2.0
