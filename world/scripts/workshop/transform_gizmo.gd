extends Node3D
## Move, turn and resize a selected prop by dragging handles in the world, while the build
## palette is open. Arrows move along X (red), Y (green) and Z (blue); the white ball slides it
## over the ground; the yellow ring turns it; the white cube resizes it. Hold Ctrl to snap. Click
## a prop in the world to select it, and hold the middle mouse button to look around. A drag is
## one edit and one undo step, through the same path as the grab beam.

const Placement = preload("res://scripts/workshop/scene_placement.gd")
const Commands = preload("res://scripts/workshop/command_registry.gd")
const RenderLayers = preload("res://scripts/rendering/render_layers.gd")

signal picked(id: String)
signal edited(id: String)

## The handles' size as a share of the view's height, whatever the distance.
const SCREEN_SIZE := 0.16
const RING := 1.25
const SCALE_CORNER := Vector3(0.72, 0.72, 0.0)
const SNAP := {"move": 0.25, "turn": 15.0, "size": 0.1}
const PICK_PIXELS := 11.0
const COLORS := {"x": Color("ff4a5a"), "y": Color("6effa0"), "z": Color("4f9dff"),
	"plane": Color("f2f2f2"), "turn": Color("ffd166"), "size": Color("f2f2f2")}
const AXES := {"x": Vector3.RIGHT, "y": Vector3.UP, "z": Vector3.BACK}

var world # world.gd
var selected := ""
var _handles := {}
var _materials := {}
var _hover := ""
var _drag := {}
var _looking := false

func _ready() -> void:
	top_level = true
	for key in AXES:
		_handles[key] = _arrow(key)
	_handles["plane"] = _part("plane", _sphere(0.09), Transform3D.IDENTITY)
	var torus := TorusMesh.new()
	torus.inner_radius = RING - 0.03
	torus.outer_radius = RING + 0.03
	torus.rings = 48
	torus.ring_segments = 8
	_handles["turn"] = _part("turn", torus, Transform3D.IDENTITY)
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE * 0.15
	_handles["size"] = _part("size", cube, Transform3D(Basis.IDENTITY, SCALE_CORNER))
	visible = false

func active() -> bool:
	return world != null and world.overlay.visible and is_instance_valid(world._palette_host.panel) \
		and world._palette_host.panel.is_visible_in_tree() and world._scene_ready()

func target() -> Node3D:
	return world.world_tools.scene_node(selected) if not selected.is_empty() else null

func _process(_delta: float) -> void:
	if not active():
		if not _drag.is_empty():
			_cancel()
		visible = false
		_looking = false
		return
	selected = _palette_selection()
	var node := target()
	visible = node != null and is_instance_valid(node)
	if not visible:
		return
	var camera: Camera3D = world.camera
	var center := node.global_position
	var distance := maxf(0.5, camera.global_position.distance_to(center))
	var size := distance * tan(deg_to_rad(camera.fov) * 0.5) * SCREEN_SIZE * 2.0
	global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size), center)
	for key in _materials:
		var lit: bool = key == _hover or key == _drag.get("handle", "")
		(_materials[key] as StandardMaterial3D).albedo_color = (COLORS[key] as Color).lerp(Color.WHITE, 0.55) if lit else COLORS[key]

## Presses that start a drag or a pick, hover and middle-button looking. Drags in progress run in
## _input, so they keep going over the palette.
func _unhandled_input(event: InputEvent) -> void:
	if not active() or not _drag.is_empty():
		return
	var camera: Camera3D = world.camera
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		_looking = event.pressed
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		if _looking:
			world._look(event.relative)
			get_viewport().set_input_as_handled()
		else:
			_hover = _handle_at(event.position, camera) if visible else ""
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var handle := _handle_at(event.position, camera) if visible else ""
		if not handle.is_empty():
			_begin(handle, event.position, camera)
		else:
			var aim := Placement.aim_at(world.player, camera, event.position, 60.0)
			if not str(aim.id).is_empty():
				picked.emit(aim.id)
		get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	if _drag.is_empty():
		return
	if event is InputEventMouseMotion:
		_update(event.position, (event as InputEventMouseMotion).ctrl_pressed)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_commit()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_cancel()
		get_viewport().set_input_as_handled()

func _palette_selection() -> String:
	var panel: Control = world._palette_host.panel
	if panel.has_method("selected_entity"):
		return panel.selected_entity()
	return str(panel.capture_view().get("selected", ""))

# ---------------------------------------------------------------- picking

func _handle_at(pixel: Vector2, camera: Camera3D) -> String:
	var center := global_position
	if camera.is_position_behind(center):
		return ""
	var size := global_basis.x.length()
	var middle := camera.unproject_position(center)
	if pixel.distance_to(middle) < PICK_PIXELS * 1.4:
		return "plane"
	var corner := center + SCALE_CORNER * size
	if not camera.is_position_behind(corner) and pixel.distance_to(camera.unproject_position(corner)) < PICK_PIXELS * 1.3:
		return "size"
	var best := ""
	var nearest := PICK_PIXELS
	for key in AXES:
		var tip: Vector3 = center + AXES[key] * size
		if camera.is_position_behind(tip):
			continue
		var gap := _segment_distance(pixel, middle, camera.unproject_position(tip))
		if gap < nearest:
			nearest = gap
			best = key
	if not best.is_empty():
		return best
	var previous := Vector2.INF
	for step in 49:
		var angle := TAU * step / 48.0
		var point := center + Vector3(sin(angle), 0.0, cos(angle)) * RING * size
		if camera.is_position_behind(point):
			previous = Vector2.INF
			continue
		var at := camera.unproject_position(point)
		if previous.is_finite() and _segment_distance(pixel, previous, at) < PICK_PIXELS:
			return "turn"
		previous = at
	return ""

static func _segment_distance(point: Vector2, a: Vector2, b: Vector2) -> float:
	var along := b - a
	var t := clampf((point - a).dot(along) / maxf(along.length_squared(), 0.0001), 0.0, 1.0)
	return point.distance_to(a + along * t)

# ---------------------------------------------------------------- dragging

func _begin(handle: String, pixel: Vector2, camera: Camera3D) -> void:
	var node := target()
	var inspected: Dictionary = world.world_tools.execute("inspect", {"id": selected})
	if node == null or not inspected.get("ok", false):
		return
	var record: Dictionary = inspected.entity
	if record.get("hidden", false):
		return
	var parent := node.get_parent() as Node3D
	_drag = {"handle": handle, "id": selected, "node": node, "parent": parent, "camera": camera,
		"transform": node.transform, "start": node.position, "basis": node.global_basis,
		"yaw": rad_to_deg(node.transform.basis.get_euler().y) if node is RigidBody3D else float(record.get("yaw", 0.0)),
		"scale": float(record.get("scale", 1.0)), "pixel": pixel,
		"center": camera.unproject_position(node.global_position), "parts": {}}
	_drag["anchor"] = _measure(pixel)
	if node is RigidBody3D:
		_drag["frozen"] = node.freeze
		node.freeze = true
		for part in node.get_children():
			if part is Node3D and part is not CollisionShape3D:
				_drag.parts[part] = part.transform

## The quantity a drag changes, measured at a pixel: distance along the axis, a point on the
## ground plane, an angle round the ring, or a distance on screen from the prop.
func _measure(pixel: Vector2) -> Variant:
	var camera: Camera3D = _drag.camera
	var parent: Node3D = _drag.parent
	var origin := parent.to_local(camera.project_ray_origin(pixel))
	var direction := (parent.global_basis.inverse() * camera.project_ray_normal(pixel)).normalized()
	var start: Vector3 = _drag.start
	match _drag.handle:
		"x", "y", "z":
			var axis: Vector3 = AXES[_drag.handle]
			var b := axis.dot(direction)
			var denominator := 1.0 - b * b
			if denominator < 0.0004:
				return null
			var w := start - origin
			return (b * direction.dot(w) - axis.dot(w)) / denominator
		"plane", "turn":
			if absf(direction.y) < 0.001:
				return null
			var hit := origin + direction * ((start.y - origin.y) / direction.y)
			if _drag.handle == "plane":
				return hit
			return atan2(hit.x - start.x, hit.z - start.z)
		"size":
			return maxf(4.0, pixel.distance_to(_drag.center))
	return null

func _update(pixel: Vector2, snap: bool) -> void:
	var now: Variant = _measure(pixel)
	var anchor: Variant = _drag.anchor
	if now == null or anchor == null:
		return
	var node: Node3D = _drag.node
	var moved := _drag.start as Vector3
	var yaw: float = _drag.yaw
	var scale_value: float = _drag.scale
	match _drag.handle:
		"x", "y", "z":
			var step := float(now) - float(anchor)
			if snap:
				step = snappedf(step, SNAP.move)
			moved += (AXES[_drag.handle] as Vector3) * step
		"plane":
			var shift: Vector3 = now - anchor
			if snap:
				shift = Vector3(snappedf(shift.x, SNAP.move), 0.0, snappedf(shift.z, SNAP.move))
			moved += Vector3(shift.x, 0.0, shift.z)
		"turn":
			var turn := rad_to_deg(wrapf(float(now) - float(anchor), -PI, PI))
			yaw = wrapf(yaw + turn, -180.0, 180.0)
			if snap:
				yaw = snappedf(yaw, SNAP.turn)
		"size":
			var rule := Commands.field("scale")
			scale_value = clampf(scale_value * float(now) / float(anchor), float(rule.minimum), float(rule.maximum))
			if snap:
				scale_value = snappedf(scale_value, SNAP.size)
	var bounds: AABB = world.world_tools.bounds
	moved = moved.clamp(bounds.position, bounds.end)
	_drag["position"] = moved
	_drag["new_yaw"] = yaw
	_drag["new_scale"] = scale_value
	# Live preview; the edit itself is made on release.
	var turn_by := Basis(Vector3.UP, deg_to_rad(yaw - float(_drag.yaw)))
	var factor := scale_value / float(_drag.scale)
	if node is RigidBody3D:
		node.global_basis = turn_by * (_drag.basis as Basis)
		for part: Node3D in _drag.parts:
			part.transform = (_drag.parts[part] as Transform3D).scaled(Vector3.ONE * factor)
	else:
		node.global_basis = (turn_by * (_drag.basis as Basis)).scaled(Vector3.ONE * factor)
	node.position = moved

func _commit() -> void:
	var node: Node3D = _drag.node
	if not _drag.has("position") or not is_instance_valid(node):
		_cancel()
		return
	var changes := {"position": Placement.coordinates(_drag.position), "yaw": _drag.new_yaw, "scale": _drag.new_scale}
	for part: Node3D in _drag.parts:
		if is_instance_valid(part):
			part.transform = _drag.parts[part]
	var result: Dictionary = world.world_tools.commit_grab(_drag.id, node, changes)
	var id: String = _drag.id
	if not result.get("ok", false):
		_cancel()
		world._console_notice(str(result.get("error", "That edit could not be saved.")))
		return
	if node is RigidBody3D and is_instance_valid(node):
		node.freeze = _drag.frozen
	_drag.clear()
	edited.emit(id)

func _cancel() -> void:
	if _drag.is_empty():
		return
	var node: Node3D = _drag.node
	if is_instance_valid(node):
		node.transform = _drag.transform
		for part: Node3D in _drag.parts:
			if is_instance_valid(part):
				part.transform = _drag.parts[part]
		if node is RigidBody3D:
			node.freeze = _drag.frozen
	_drag.clear()

# ---------------------------------------------------------------- handles

func _arrow(key: String) -> MeshInstance3D:
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.022
	shaft.bottom_radius = 0.022
	shaft.height = 0.8
	shaft.radial_segments = 8
	var tip := CylinderMesh.new()
	tip.top_radius = 0.0
	tip.bottom_radius = 0.07
	tip.height = 0.2
	tip.radial_segments = 12
	var axis: Vector3 = AXES[key]
	# Cylinders stand along +Y; turn each onto its axis.
	var turn := Basis.IDENTITY if key == "y" else Basis(Vector3.BACK, -PI * 0.5) if key == "x" else Basis(Vector3.RIGHT, PI * 0.5)
	var handle := _part(key, shaft, Transform3D(turn, axis * 0.4))
	var head := _part(key, tip, Transform3D(turn, axis * 0.9))
	head.reparent(handle)
	return handle

func _sphere(radius: float) -> SphereMesh:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	return sphere

func _part(key: String, mesh: Mesh, at: Transform3D) -> MeshInstance3D:
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.no_depth_test = true
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = COLORS[key]
		material.render_priority = 12
		_materials[key] = material
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.transform = at
	part.material_override = _materials[key]
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	part.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	part.layers = RenderLayers.REFLECTION_HIDDEN
	add_child(part)
	return part
