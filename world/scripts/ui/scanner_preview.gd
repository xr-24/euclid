extends SubViewport
## Small, isolated render of the selected prop. It updates only when the selection changes.

var _model: Node3D
var _camera: Camera3D

func _ready() -> void:
	size = Vector2i(352, 264)
	own_world_3d = true
	transparent_bg = true
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.67, 0.79, 0.88)
	environment.environment.ambient_light_energy = 0.75
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-42, -34, 0)
	add_child(light)
	_camera = Camera3D.new()
	_camera.fov = 32
	add_child(_camera)
	_camera.make_current()

func show_prop(node: Node3D) -> void:
	_reset()
	if not is_instance_valid(node):
		return
	var bounds := AABB()
	var sources := node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D:
		sources.push_front(node)
	for source: MeshInstance3D in sources.slice(0, 64):
		if not source.mesh or not source.visible:
			continue
		var mesh := MeshInstance3D.new()
		mesh.mesh = source.mesh
		mesh.transform = node.global_transform.affine_inverse() * source.global_transform
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for index in source.mesh.get_surface_count():
			mesh.set_surface_override_material(index, source.get_active_material(index))
		_model.add_child(mesh)
		var box := mesh.transform * mesh.get_aabb()
		bounds = bounds.merge(box) if bounds.has_surface() else box
	_frame(bounds)

func show_water(color: Color, roughness: float) -> void:
	_reset()
	var surface := MeshInstance3D.new()
	var box := CylinderMesh.new()
	box.top_radius = 0.83
	box.bottom_radius = 0.83
	box.height = 0.09
	surface.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	surface.material_override = material
	_model.add_child(surface)
	_frame(surface.get_aabb())

func _reset() -> void:
	if is_instance_valid(_model):
		_model.free()
	_model = Node3D.new()
	add_child(_model)

func _frame(bounds: AABB) -> void:
	var center := bounds.get_center()
	_camera.position = center + Vector3(0.60, 0.37, 0.70).normalized() * maxf(0.12, bounds.size.length() * 1.95)
	_camera.look_at(center)
	render_target_update_mode = SubViewport.UPDATE_ONCE
