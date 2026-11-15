extends Node
## Agent vision: an agent sees the 3D world through your current view, from a point it chooses, or
## from a camera it placed. Each look renders off-screen into its own viewport sharing the world,
## so your view is untouched. Private surfaces (terminals, desktop and app panels, the wrist) move
## to a layer the agent's camera never draws while it renders, so agents see the world, never your
## screen. Agent vision on the wrist's System page allows your view and cameras, cameras only, or
## nothing.

const Graphics = preload("res://scripts/rendering/graphics_settings.gd")
const RenderLayers = preload("res://scripts/rendering/render_layers.gd")
const SIZE := Vector2i(768, 432)
const QUALITY := 0.82
const MAX_CAMERAS := 16

signal looked(agent: String, source: String)

var _world: Node3D
## name -> {"position": Vector3, "target": Vector3, "fov": float}
var cameras := {}

func _init(world: Node3D) -> void:
	_world = world
	name = "AgentVision"

## Remember a camera an agent can look through again by name.
func place(camera_name: String, position: Vector3, target: Variant, fov: float) -> Dictionary:
	if Graphics.agent_vision == "off":
		return {"ok": false, "message": "Agent vision is off on the wrist's System page."}
	var aim: Variant = _point(target)
	if aim == null:
		return {"ok": false, "message": "Aim the camera at a point [x, y, z] or a node path from inspect_scene."}
	if not cameras.has(camera_name) and cameras.size() >= MAX_CAMERAS:
		return {"ok": false, "message": "Up to %d cameras can be placed." % MAX_CAMERAS}
	cameras[camera_name] = {"position": position, "target": aim, "fov": clampf(fov, 20.0, 110.0)}
	return {"ok": true, "message": "Placed camera %s." % camera_name, "cameras": cameras.keys()}

## Render a view. from: "player" (your current view), "camera" (a placed camera by name) or
## "point" (position aimed at target). Returns {"ok", "message", "image"} with a base64 JPEG.
func capture(from: String, camera_name := "", position := Vector3.ZERO, target: Variant = null, fov := 70.0, agent := "") -> Dictionary:
	var mode := Graphics.agent_vision
	if mode == "off":
		return {"ok": false, "message": "Agent vision is off on the wrist's System page."}
	if from == "player" and mode != "all":
		return {"ok": false, "message": "Agent vision allows placed cameras only, not the player's view."}
	if DisplayServer.get_name() == "headless":
		return {"ok": false, "message": "Euclid is running without a renderer, so there is nothing to see."}
	var view := Transform3D()
	var angle := fov
	match from:
		"player":
			var eye: Camera3D = _world.camera
			view = eye.global_transform
			angle = eye.fov
		"camera":
			if not cameras.has(camera_name):
				return {"ok": false, "message": "There is no camera named %s. Place one with place_camera." % camera_name}
			var placed: Dictionary = cameras[camera_name]
			view = _aimed(placed.position, placed.target)
			angle = placed.fov
		_:
			var aim: Variant = _point(target)
			if aim == null:
				return {"ok": false, "message": "Aim at a point [x, y, z] or a node path from inspect_scene."}
			view = _aimed(position, aim)
	var image := await _render(view, clampf(angle, 20.0, 110.0))
	if image == null or image.is_empty():
		return {"ok": false, "message": "The view could not be rendered."}
	var jpeg := image.save_jpg_to_buffer(QUALITY)
	looked.emit(agent, "your view" if from == "player" else ("camera " + camera_name if from == "camera" else "a point it chose"))
	return {"ok": true, "message": "Captured %dx%d from %s." % [image.get_width(), image.get_height(),
		"your view" if from == "player" else from], "image": Marshalls.raw_to_base64(jpeg),
		"position": _vector(view.origin), "facing": _vector(-view.basis.z)}

func _render(view: Transform3D, fov: float) -> Image:
	var port := SubViewport.new()
	port.size = SIZE
	port.world_3d = get_viewport().world_3d
	port.render_target_update_mode = SubViewport.UPDATE_ONCE
	var eye := Camera3D.new()
	eye.cull_mask = RenderLayers.AGENT_VIEW
	eye.fov = fov
	eye.far = 900.0
	eye.attributes = _world.camera.attributes
	port.add_child(eye)
	add_child(port)
	eye.global_transform = view
	eye.make_current()
	var moved := _hide_private()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_restore(moved)
	var image := port.get_texture().get_image()
	port.queue_free()
	return image

## Move every visual under a private surface to the private layer; return what to put back.
func _hide_private() -> Dictionary:
	var moved := {}
	for surface in get_tree().get_nodes_in_group("private_world_surfaces"):
		var stack: Array[Node] = [surface]
		while not stack.is_empty():
			var node: Node = stack.pop_back()
			if node is VisualInstance3D:
				moved[node] = node.layers
				node.layers = RenderLayers.PRIVATE
			stack.append_array(node.get_children())
	return moved

func _restore(moved: Dictionary) -> void:
	for node in moved:
		if is_instance_valid(node):
			node.layers = moved[node]

func _point(target: Variant) -> Variant:
	if target is Array and target.size() == 3:
		return Vector3(target[0], target[1], target[2])
	if target is String and not target.is_empty():
		var node := _world.get_node_or_null(NodePath(target)) as Node3D
		return node.global_position if node else null
	return null

static func _aimed(from: Vector3, at: Vector3) -> Transform3D:
	var up := Vector3.UP if absf((at - from).normalized().dot(Vector3.UP)) < 0.98 else Vector3.BACK
	return Transform3D(Basis(), from).looking_at(at, up) if from.distance_to(at) > 0.01 else Transform3D(Basis(), from)

static func _vector(value: Vector3) -> Array:
	return [snappedf(value.x, 0.01), snappedf(value.y, 0.01), snappedf(value.z, 0.01)]
