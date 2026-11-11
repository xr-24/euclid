extends Node3D
## The world-space mannequin and the matching camera-space hands share their surface materials.

const Body = preload("res://assets/player/mannequin.glb")
const Hands = preload("res://scripts/player/first_person_hands.gd")
const Poses = preload("res://scripts/player/hand_poses.gd")

var hands := Hands.new()
var _meshes: Array[MeshInstance3D] = []
var _animation: AnimationPlayer
var _camera: Camera3D
var _grounded := true
var _current := &"Idle"
var _reaching := false

func mount(player: CharacterBody3D, camera: Camera3D) -> void:
	player.add_child(self)
	_camera = camera
	var body := Body.instantiate() as Node3D
	body.rotation.y = PI
	# Keep the eye ahead of the animated chest even when the jog leans forward.
	body.position.z = 0.34
	add_child(body)
	var materials := {}
	for child in body.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		_meshes.append(mesh)
		if mesh.name == &"FirstPersonOccluders":
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.mesh.surface_get_material(surface)
			materials[material.resource_name] = material
	_meshes.append(hands.mount(camera))
	set_materials(materials)
	_animation = body.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	_animation.play(_current)

func set_materials(materials: Dictionary) -> void:
	for mesh in _meshes:
		for surface in mesh.mesh.get_surface_count():
			var original := mesh.mesh.surface_get_material(surface)
			if materials.has(original.resource_name):
				mesh.set_surface_override_material(surface, materials[original.resource_name])

func interact() -> void:
	_reaching = true
	if _grounded and _current == &"Idle":
		_play(&"Interact")

func tick(player: CharacterBody3D, delta: float, swimming: bool, controls: bool) -> void:
	var velocity := player.get_real_velocity()
	var speed := Vector2(velocity.x, velocity.z).length()
	var grounded := player.is_on_floor()
	_animate(grounded, velocity.y, speed, swimming)
	var pose := Poses.Pose.REST
	if controls:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			pose = Poses.Pose.PINCH if Input.is_physical_key_pressed(KEY_SHIFT) else Poses.Pose.GRAB
		elif Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			pose = Poses.Pose.POINT
	var target := Vector3.INF
	if _reaching or pose != Poses.Pose.REST:
		var ray := PhysicsRayQueryParameters3D.create(_camera.global_position, _camera.to_global(Vector3(0, 0, -3.0)))
		ray.exclude = [player.get_rid()]
		var hit := player.get_world_3d().direct_space_state.intersect_ray(ray)
		target = hit.get("position", Vector3.INF)
	if _reaching:
		hands.pulse(Poses.Pose.OPEN_PALM, target)
		_reaching = false
	hands.tick(delta, pose, target, speed if grounded and not swimming else 0.0)

func _animate(grounded: bool, vertical_speed: float, speed: float, swimming: bool) -> void:
	if swimming:
		_play(&"Swim_Fwd" if speed > 0.35 else &"Swim_Idle")
	elif not grounded:
		if _grounded and vertical_speed > 0.4:
			_play(&"Jump_Start")
		elif _current != &"Jump_Start" or vertical_speed < 0.0 or not _animation.is_playing():
			_play(&"Jump")
	elif not _grounded and _current in [&"Jump_Start", &"Jump"]:
		_play(&"Jump_Land")
	elif (_current != &"Jump_Land" and _current != &"Interact") or not _animation.is_playing():
		if speed < 0.12:
			_play(&"Idle")
		elif speed < 2.7:
			_play(&"Walk", clampf(speed / 1.7, 0.7, 1.5))
		else:
			_play(&"Jog_Fwd", clampf(speed / 4.2, 0.7, 1.4))
	_grounded = grounded

func _play(clip: StringName, speed := 1.0) -> void:
	if clip != _current:
		_current = clip
		_animation.play(clip, 0.16)
	_animation.speed_scale = speed
