extends Node3D
## A bounded rain volume follows the viewer. Atmosphere owns the saved controls.

var _rain: GPUParticles3D
var intensity := 0.0

func update(camera: Camera3D, amount: float) -> void:
	if amount <= 0.001:
		if _rain and _rain.emitting:
			_rain.emitting = false
			_rain.hide()
		return
	if _rain == null:
		_rain = _create_rain()
		add_child(_rain)
	global_position = camera.global_position + Vector3.UP * 6.0
	if not is_equal_approx(intensity, amount) or not _rain.emitting:
		intensity = amount
		_rain.amount_ratio = amount
		_rain.show()
		_rain.emitting = true

static func sun_at(hour: float, noon_heading: float) -> Vector2:
	var angle := (hour - 12.0) * TAU / 24.0
	var sun := Vector3(sin(angle), cos(angle) * sin(deg_to_rad(58)), cos(angle) * cos(deg_to_rad(58)))
	return Vector2(fposmod(noon_heading + rad_to_deg(atan2(sun.x, sun.z)), 360.0), rad_to_deg(asin(sun.y)))

static func _create_rain() -> GPUParticles3D:
	var rain := GPUParticles3D.new()
	rain.name = "Rain"
	rain.amount = 1500
	rain.lifetime = 0.8
	rain.local_coords = false
	rain.visibility_aabb = AABB(Vector3(-15, -17, -15), Vector3(30, 21, 30))
	var drops := ParticleProcessMaterial.new()
	drops.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	drops.emission_box_extents = Vector3(11, 1.5, 11)
	drops.direction = Vector3(0.13, -1, 0.04)
	drops.spread = 2.5
	drops.gravity = Vector3.DOWN * 2.0
	drops.initial_velocity_min = 17.0
	drops.initial_velocity_max = 22.0
	rain.process_material = drops
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.017, 0.44)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	material.albedo_color = Color(0.62, 0.78, 0.9, 0.32)
	mesh.material = material
	rain.draw_pass_1 = mesh
	rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rain.layers = preload("res://scripts/rendering/render_layers.gd").REFLECTION_HIDDEN
	return rain
