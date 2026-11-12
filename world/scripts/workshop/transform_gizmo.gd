extends Node3D
## Handles for the selected prop while the build palette is open, in two modes (Q or the
## Handles button switches them):
##   Move   arrows move it along X (red), Y (green) and Z (blue), the ball slides it over the
##          ground and the yellow ring turns it.
##   Shape  a handle on each face stretches the prop from that side, keeping the opposite face
##          where it is, along the prop's own axes; the white cube resizes it evenly.
## Hold Ctrl to snap and press Escape mid-drag to put it back. Click a prop in the world to
## select it, and hold the middle mouse button to look around. A drag is one edit and one undo
## step, through the same path as the grab beam.

const Placement = preload("res://scripts/workshop/scene_placement.gd")
const Commands = preload("res://scripts/workshop/command_registry.gd")
const EntityTypes = preload("res://scripts/workshop/entity_types.gd")
const RenderLayers = preload("res://scripts/rendering/render_layers.gd")
const PieceBuilder = preload("res://scripts/pieces/piece_builder.gd")
const Packages = preload("res://scripts/zones/zone_packages.gd")

signal picked(id: String)
signal edited(id: String)

## The handles' size as a share of the view's height, whatever the distance.
const SCREEN_SIZE := 0.16
const RING := 1.25
const SCALE_CORNER := Vector3(0.72, 0.72, 0.72)
const SNAP := {"move": 0.25, "turn": 15.0, "size": 0.1, "stretch": 0.1}
const PICK_PIXELS := 11.0
const AXIS_COLORS := {"x": Color("ff4a5a"), "y": Color("6effa0"), "z": Color("4f9dff")}
const COLORS := {"plane": Color("f2f2f2"), "turn": Color("ffd166"), "size": Color("f2f2f2")}
const AXES := {"x": Vector3.RIGHT, "y": Vector3.UP, "z": Vector3.BACK}
## Each handle's tip in the gizmo's own space, and which mode shows it.
const TIPS := {"x": Vector3.RIGHT, "y": Vector3.UP, "z": Vector3.BACK,
	"+x": Vector3.RIGHT, "-x": Vector3.LEFT, "+y": Vector3.UP, "-y": Vector3.DOWN, "+z": Vector3.BACK, "-z": Vector3.FORWARD}
const MOVE := ["plane", "x", "y", "z", "turn"]
const SHAPE := ["size", "+x", "-x", "+y", "-y", "+z", "-z"]

var world # world.gd
var selected := ""
var mode := "move"
## The palette's Handles button, kept in step with the mode.
var mode_button: Button
var _handles := {}
var _materials := {}
var _hover := ""
var _drag := {}
var _looking := false
var _info := {}

func _ready() -> void:
	for key in AXES:
		_handles[key] = _arrow(key, false)
		for sign_text in ["+", "-"]:
			_handles[sign_text + key] = _arrow(sign_text + key, true)
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
	_show_mode()
	visible = false

func toggle_mode() -> void:
	mode = "shape" if mode == "move" else "move"
	_show_mode()

func mode_label() -> String:
	return "Handles: %s  [Q]" % ("Move" if mode == "move" else "Shape")

func _show_mode() -> void:
	for key in _handles:
		(_handles[key] as Node3D).visible = key in (MOVE if mode == "move" else SHAPE)
	if is_instance_valid(mode_button):
		mode_button.text = mode_label()

func active() -> bool:
	return world != null and world.overlay.visible and world._scene_ready() and (_piece_mode() or (
		is_instance_valid(world._palette_host.panel) and world._palette_host.panel.is_visible_in_tree()))

func _piece_mode() -> bool:
	return is_instance_valid(world.piece_panel) and world.piece_panel.is_visible_in_tree() and world.pieces.can_edit()

func target() -> Node3D:
	if _piece_mode():
		return world.pieces.node_for(selected)
	return world.world_tools.scene_node(selected) if not selected.is_empty() else null

func _process(_delta: float) -> void:
	if not active():
		if not _drag.is_empty():
			_cancel()
		visible = false
		_looking = false
		return
	var id := _palette_selection()
	var piece_mode := _piece_mode()
	if id != selected or _info.get("id") != id or _info.get("piece", false) != piece_mode \
			or (piece_mode and _info.get("revision") != world.pieces.revision):
		selected = id
		_refresh_info()
	var node := target()
	visible = node != null and is_instance_valid(node)
	if not visible:
		return
	for key in ["+x", "-x", "+y", "-y", "+z", "-z"]:
		(_handles[key] as Node3D).visible = mode == "shape" and _info.get("stretchable", false)
	var camera: Camera3D = world.camera
	var center := node.global_position
	var distance := maxf(0.5, camera.global_position.distance_to(center))
	var size := distance * tan(deg_to_rad(camera.fov) * 0.5) * SCREEN_SIZE * 2.0
	# Piece positions are local to their parent, so their handles follow the parent axes.
	var facing := Basis.IDENTITY if mode == "move" else Basis(Vector3.UP, deg_to_rad(float(_info.get("yaw", 0.0))))
	if piece_mode:
		facing = (node.get_parent() as Node3D).global_basis.orthonormalized() * facing
	global_transform = Transform3D(facing.scaled(Vector3.ONE * size), center)
	for key in _materials:
		var lit: bool = key == _hover or key == _drag.get("handle", "")
		var base := _color(key)
		(_materials[key] as StandardMaterial3D).albedo_color = base.lerp(Color.WHITE, 0.55) if lit else base

func _refresh_info() -> void:
	if _piece_mode():
		var piece: Dictionary = world.pieces.record(selected)
		var rotation: Array = piece.get("rotation", [0.0, 0.0, 0.0])
		_info = {"id": selected, "piece": true, "yaw": rotation[1], "stretch": Vector3.ONE,
			"scale": 1.0, "record": piece, "stretchable": false, "revision": world.pieces.revision}
		return
	var inspected: Dictionary = world.world_tools.execute("inspect", {"id": selected}) if not selected.is_empty() else {}
	var record: Dictionary = inspected.get("entity", {})
	_info = {"id": selected, "yaw": world.world_tools.live_yaw(selected) if not record.is_empty() else 0.0,
		"stretch": EntityTypes.stretch_of(record), "scale": float(record.get("scale", 1.0)), "record": record,
		"stretchable": not record.is_empty() and EntityTypes.TYPES.get(record.get("type"), {}).get("factory") != "door"}

## Presses that start a drag or a pick, Q, hover and middle-button looking. Drags in progress
## run in _input, so they keep going over the palette.
func _unhandled_input(event: InputEvent) -> void:
	if not active() or not _drag.is_empty():
		return
	var camera: Camera3D = world.camera
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_Q:
		toggle_mode()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
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
			var picked_id: String = aim.piece if _piece_mode() else aim.id
			if not picked_id.is_empty():
				picked.emit(picked_id)
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
	if _piece_mode():
		return world.piece_panel.selected_piece()
	var panel: Control = world._palette_host.panel
	if panel.has_method("selected_entity"):
		return panel.selected_entity()
	return str(panel.capture_view().get("selected", ""))

func _color(key: String) -> Color:
	return AXIS_COLORS[key.right(1)] if key.length() <= 2 and AXIS_COLORS.has(key.right(1)) else COLORS[key]

# ---------------------------------------------------------------- picking

func _handle_at(pixel: Vector2, camera: Camera3D) -> String:
	var center := global_position
	if camera.is_position_behind(center):
		return ""
	var middle := camera.unproject_position(center)
	var shown := func(key: String) -> bool: return (_handles[key] as Node3D).visible
	if shown.call("plane") and pixel.distance_to(middle) < PICK_PIXELS * 1.4:
		return "plane"
	var corner := global_transform * SCALE_CORNER
	if shown.call("size") and not camera.is_position_behind(corner) and pixel.distance_to(camera.unproject_position(corner)) < PICK_PIXELS * 1.3:
		return "size"
	var best := ""
	var nearest := PICK_PIXELS
	for key in TIPS:
		if not shown.call(key):
			continue
		var tip := global_transform * (TIPS[key] as Vector3)
		if camera.is_position_behind(tip):
			continue
		var gap := _segment_distance(pixel, middle, camera.unproject_position(tip))
		if gap < nearest:
			nearest = gap
			best = key
	if not best.is_empty() or not shown.call("turn"):
		return best
	var previous := Vector2.INF
	for step in 49:
		var angle := TAU * step / 48.0
		var point := global_transform * (Vector3(sin(angle), 0.0, cos(angle)) * RING)
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
	_refresh_info()
	var record: Dictionary = _info.record
	if node == null or record.is_empty() or record.get("hidden", false):
		return
	var parent := node.get_parent() as Node3D
	var facing := Basis(Vector3.UP, deg_to_rad(float(_info.yaw)))
	_drag = {"handle": handle, "id": selected, "node": node, "parent": parent, "camera": camera,
		"transform": node.transform, "start": node.position, "basis": node.global_basis, "facing": facing,
		"yaw": float(_info.yaw), "scale": float(_info.scale), "stretch": _info.stretch, "pixel": pixel,
		"center": camera.unproject_position(node.global_position), "parts": {}}
	if _info.get("piece", false):
		_drag["piece"] = record
		_drag["piece_revision"] = world.pieces.revision
	if handle.length() == 2:
		# Stretch: the handle's direction in the parent's space, the prop's extent along it and
		# where its opposite face sits, all measured in the prop's own frame.
		var along: Vector3 = facing * (TIPS[handle] as Vector3)
		_drag["axis"] = (parent.global_basis.inverse() * along).normalized()
		_drag["index"] = "xyz".find(handle.right(1))
		var bounds := _frame_bounds(node, Transform3D(facing, node.global_position))
		var outward: float = TIPS[handle][_drag.index]
		_drag["extent"] = maxf(bounds.size[_drag.index], 0.01)
		_drag["far_face"] = bounds.position[_drag.index] if outward > 0.0 else -bounds.end[_drag.index]
	_drag["anchor"] = _measure(pixel)
	if node is RigidBody3D:
		_drag["frozen"] = node.freeze
		node.freeze = true
		for part in node.get_children():
			if part is Node3D and part is not CollisionShape3D:
				_drag.parts[part] = part.transform

## The prop's visual bounds in a frame (its position, turned by its yaw).
static func _frame_bounds(node: Node3D, frame: Transform3D) -> AABB:
	var bounds := AABB()
	var first := true
	var meshes := node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D:
		meshes.push_front(node)
	for child in meshes:
		var mesh := child as MeshInstance3D
		if not mesh.is_visible_in_tree():
			continue
		var local := (frame.affine_inverse() * mesh.global_transform) * mesh.get_aabb()
		bounds = local if first else bounds.merge(local)
		first = false
	return bounds

## The quantity a drag changes, measured at a pixel: distance along an axis, a point on the
## ground plane, an angle round the ring, or a distance on screen from the prop.
func _measure(pixel: Vector2) -> Variant:
	var camera: Camera3D = _drag.camera
	var parent: Node3D = _drag.parent
	var origin := parent.to_local(camera.project_ray_origin(pixel))
	var direction := (parent.global_basis.inverse() * camera.project_ray_normal(pixel)).normalized()
	var start: Vector3 = _drag.start
	var handle: String = _drag.handle
	if handle in AXES or handle.length() == 2:
		var axis: Vector3 = AXES[handle] if handle in AXES else _drag.axis
		var b := axis.dot(direction)
		var denominator := 1.0 - b * b
		if denominator < 0.0004:
			return null
		var w := start - origin
		return (b * direction.dot(w) - axis.dot(w)) / denominator
	if handle in ["plane", "turn"]:
		if absf(direction.y) < 0.001:
			return null
		var hit := origin + direction * ((start.y - origin.y) / direction.y)
		if handle == "plane":
			return hit
		return atan2(hit.x - start.x, hit.z - start.z)
	if handle == "size":
		return maxf(4.0, pixel.distance_to(_drag.center))
	return null

func _update(pixel: Vector2, snap: bool) -> void:
	if not is_instance_valid(_drag.node) or target() != _drag.node \
			or (_drag.has("piece") and _drag.piece_revision != world.pieces.revision):
		_cancel()
		return
	var now: Variant = _measure(pixel)
	var anchor: Variant = _drag.anchor
	if now == null or anchor == null:
		return
	var node: Node3D = _drag.node
	var handle: String = _drag.handle
	var moved := _drag.start as Vector3
	var yaw: float = _drag.yaw
	var scale_value: float = _drag.scale
	var stretch: Vector3 = _drag.stretch
	if handle in AXES:
		var step := float(now) - float(anchor)
		if snap:
			step = snappedf(step, SNAP.move)
		moved += (AXES[handle] as Vector3) * step
	elif handle == "plane":
		var shift: Vector3 = now - anchor
		if snap:
			shift = Vector3(snappedf(shift.x, SNAP.move), 0.0, snappedf(shift.z, SNAP.move))
		moved += Vector3(shift.x, 0.0, shift.z)
	elif handle == "turn":
		yaw = wrapf(yaw + rad_to_deg(wrapf(float(now) - float(anchor), -PI, PI)), -180.0, 180.0)
		if snap:
			yaw = snappedf(yaw, SNAP.turn)
	elif handle == "size":
		var minimum: float = Commands.field("scale").minimum
		var maximum: float = Commands.field("scale").maximum
		if _drag.has("piece"):
			var axes: Array = _drag.piece.get("scale", [1.0, 1.0, 1.0])
			minimum = 0.01 / axes.min()
			maximum = 100.0 / axes.max()
		scale_value *= float(now) / float(anchor)
		if snap:
			scale_value = snappedf(scale_value, SNAP.size)
		scale_value = clampf(scale_value, minimum, maximum)
	else:
		# Pull this face out or in; the prop scales about its pivot, so shift the pivot by just
		# enough to keep the opposite face still.
		var index: int = _drag.index
		var rule: Dictionary = Commands.field("stretch").get("items", {})
		var extent: float = _drag.extent
		var amount := clampf(stretch[index] * (extent + float(now) - float(anchor)) / extent,
			float(rule.get("minimum", 0.2)), float(rule.get("maximum", 5.0)))
		if snap:
			amount = maxf(snappedf(amount, SNAP.stretch), float(rule.get("minimum", 0.2)))
		var ratio := amount / stretch[index]
		stretch[index] = amount
		moved += (_drag.axis as Vector3) * float(_drag.far_face) * (1.0 - ratio)
	var bounds: AABB = world.world_tools.bounds
	if _drag.has("piece"):
		var piece: Dictionary = _drag.piece
		var local_bounds: AABB = (_drag.parent as Node3D).global_transform.affine_inverse() * (world.zone_root.global_transform * bounds)
		moved = moved.clamp(local_bounds.position, local_bounds.end)
		var turn: Array = piece.get("rotation", [0.0, 0.0, 0.0]).duplicate()
		turn[1] = yaw
		var scale_axes := Packages.vector(piece.get("scale", [1.0, 1.0, 1.0])) * scale_value
		var values := {}
		if not moved.is_equal_approx(_drag.start):
			values["position"] = Placement.coordinates(moved)
		if handle == "turn" and not is_equal_approx(yaw, float(_drag.yaw)):
			values["rotation"] = turn
		if handle == "size" and not is_equal_approx(scale_value, 1.0):
			values["scale"] = Placement.coordinates(scale_axes)
		_drag["values"] = values
		node.transform = PieceBuilder.transform_of(piece.merged(values, true))
		return
	moved = moved.clamp(bounds.position, bounds.end)
	_drag["position"] = moved
	_drag["new_yaw"] = yaw
	_drag["new_scale"] = scale_value
	_drag["new_stretch"] = stretch
	# Live preview; the edit itself is made on release.
	var turn_by := Basis(Vector3.UP, deg_to_rad(yaw - float(_drag.yaw)))
	var factor := Vector3.ONE * (scale_value / float(_drag.scale)) * (stretch / (_drag.stretch as Vector3))
	var facing: Basis = _drag.facing
	if node is RigidBody3D:
		# A physics body cannot be scaled itself; its parts sit in its own (the prop's) frame.
		node.global_basis = turn_by * (_drag.basis as Basis)
		for part: Node3D in _drag.parts:
			part.transform = (_drag.parts[part] as Transform3D).scaled(factor)
	else:
		node.global_basis = turn_by * facing * Basis.from_scale(factor) * facing.inverse() * (_drag.basis as Basis)
	node.position = moved

func _commit() -> void:
	if _drag.has("piece"):
		var id: String = _drag.id
		var values: Dictionary = _drag.get("values", {})
		if _drag.piece_revision != world.pieces.revision or not is_instance_valid(_drag.node) or target() != _drag.node:
			_cancel()
			return
		_cancel()
		if not values.is_empty():
			var result: Dictionary = world.pieces.execute({"tool": "edit_piece", "target": id, "piece_values": values})
			if not result.ok:
				world._console_notice(result.message)
			edited.emit(id)
		return
	var node: Node3D = _drag.node
	if not _drag.has("position") or not is_instance_valid(node):
		_cancel()
		return
	var changes := {"position": Placement.coordinates(_drag.position), "yaw": _drag.new_yaw, "scale": _drag.new_scale}
	if _drag.new_stretch != _drag.stretch:
		var stretch: Vector3 = _drag.new_stretch
		changes["stretch"] = [stretch.x, stretch.y, stretch.z]
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
	_info.clear()
	edited.emit(id)

func _cancel() -> void:
	if _drag.is_empty():
		return
	var node: Node3D = _drag.node
	if _drag.has("piece"):
		if is_instance_valid(node) and world.pieces.node_for(_drag.id) == node:
			node.transform = PieceBuilder.transform_of(world.pieces.record(_drag.id))
		_drag.clear()
		return
	if is_instance_valid(node):
		node.transform = _drag.transform
		for part: Node3D in _drag.parts:
			if is_instance_valid(part):
				part.transform = _drag.parts[part]
		if node is RigidBody3D:
			node.freeze = _drag.frozen
	_drag.clear()

# ---------------------------------------------------------------- handles

## An arrow from the centre: a cone tip moves (Move mode), a cube tip stretches (Shape mode).
func _arrow(key: String, stretch: bool) -> MeshInstance3D:
	var direction: Vector3 = TIPS[key]
	var length := 0.8 if not stretch else 0.85
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.022
	shaft.bottom_radius = 0.022
	shaft.height = length
	shaft.radial_segments = 8
	var tip_mesh: Mesh
	if stretch:
		var cube := BoxMesh.new()
		cube.size = Vector3.ONE * 0.11
		tip_mesh = cube
	else:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.07
		cone.height = 0.2
		cone.radial_segments = 12
		tip_mesh = cone
	# Cylinders stand along +Y; turn each onto its direction.
	var turn := _turn_onto(direction)
	var handle := _part(key, shaft, Transform3D(turn, direction * length * 0.5))
	var head := _part(key, tip_mesh, Transform3D(turn, direction * (0.9 if not stretch else 0.92)))
	head.reparent(handle)
	return handle

static func _turn_onto(direction: Vector3) -> Basis:
	if direction.is_equal_approx(Vector3.UP):
		return Basis.IDENTITY
	if direction.is_equal_approx(Vector3.DOWN):
		return Basis(Vector3.RIGHT, PI)
	var axis := Vector3.UP.cross(direction).normalized()
	return Basis(axis, Vector3.UP.angle_to(direction))

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
		material.albedo_color = _color(key)
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
