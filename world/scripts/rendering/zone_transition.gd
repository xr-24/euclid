extends RefCounted
## Transition presentation owns its shader animation and cleanup, not loading or persistence.
const Effects = preload("res://scripts/rendering/zone_effects.gd")
const ZoneEnvironment = preload("res://scripts/rendering/zone_environment.gd")
var _tree: SceneTree
var _environment: Environment
var _sun: DirectionalLight3D
var _camera: Camera3D

func _init(tree: SceneTree, environment: Environment, sun: DirectionalLight3D, camera: Camera3D) -> void:
	_tree = tree
	_environment = environment
	_sun = sun
	_camera = camera

static func prepare(old_root: Node3D, new_root: Node3D) -> void:
	for body in old_root.find_children("*", "CollisionObject3D", true, false):
		body.process_mode = Node.PROCESS_MODE_DISABLED
	Effects.set_side(old_root, -1.0)
	Effects.set_side(new_root, 1.0)

func play(old_root: Node3D, new_root: Node3D, from_state: Dictionary, to_state: Dictionary,
		destination: String, seconds: float, diagnostics := false) -> void:
	var old_lights := old_root.find_children("*", "Light3D", true, false)
	var new_lights := new_root.find_children("*", "Light3D", true, false)
	for light in old_lights + new_lights:
		light.set_meta("energy", light.light_energy)
	RenderingServer.global_shader_parameter_set("construct_origin", _camera.global_position)
	# Wall-clock timing: frame deltas are capped when a frame runs long, which would otherwise
	# stretch the effect.
	var start := Time.get_ticks_usec()
	var t := 0.0
	var old_dropped := false
	var frame_us := Time.get_ticks_usec()
	while t < 1.0:
		await _tree.process_frame
		if diagnostics and Time.get_ticks_usec() - frame_us > 40000:
			print("CONSTRUCT_SHIFT_STEP long frame %.1f ms at t=%.2f" % [(Time.get_ticks_usec() - frame_us) / 1000.0, t])
		frame_us = Time.get_ticks_usec()
		t = clampf((Time.get_ticks_usec() - start) / 1000000.0 / seconds, 0.0, 1.0)
		# Slow and close at first, then racing out to the horizon.
		RenderingServer.global_shader_parameter_set("construct_radius", 30.0 * pow(t, 1.6) + 600.0 * pow(t, 4.0))
		RenderingServer.global_shader_parameter_set("construct_progress", t)
		ZoneEnvironment.apply_state(_environment, _sun, from_state, to_state, smoothstep(0.1, 0.8, t))
		for light in new_lights:
			light.light_energy = light.get_meta("energy") * smoothstep(0.15, 0.5, t)
		if is_instance_valid(old_root):
			for light in old_lights:
				light.light_energy = light.get_meta("energy") * (1.0 - smoothstep(0.0, 0.35, t))
			# By now what is left of the old zone is hundreds of metres out: drop it and let
			# global illumination re-learn the new zone while the effect still covers the change.
			if t >= 0.78 and not old_dropped:
				old_dropped = true
				var us := Time.get_ticks_usec()
				old_root.queue_free()
				ZoneEnvironment.rebuild_gi(_environment, _tree, destination)
				_log("drop old zone (queued)", us, diagnostics)
	if is_instance_valid(old_root) and not old_dropped:
		old_root.queue_free()
	Effects.set_side(new_root, 0.0)
	for light in new_lights:
		light.light_energy = light.get_meta("energy")
	RenderingServer.global_shader_parameter_set("construct_radius", 0.0)
	RenderingServer.global_shader_parameter_set("construct_progress", 0.0)
	ZoneEnvironment.apply_environment(_environment, _sun, destination)

static func _log(step: String, since_usec: int, enabled: bool) -> void:
	if enabled:
		print("CONSTRUCT_SHIFT_STEP %s %.1f ms" % [step, (Time.get_ticks_usec() - since_usec) / 1000.0])
