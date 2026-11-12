extends Node
## Moves the workshop body and its collision from the stored placement.

const MotionClip = preload("res://scripts/animation/motion_clip.gd")
var clip := {}
var _body: Node3D
var _rest: Transform3D
var _time := 0.0
var rig: Skeleton3D
var _tracks: Array[Dictionary] = []
var _motion_froze_body := false

func _ready() -> void:
	_body = get_parent() as Node3D
	_rest = _body.transform
	for node in _body.find_children("*", "Skeleton3D", true, false):
		rig = node as Skeleton3D
		break
	set_clip(clip)

func set_clip(value: Dictionary) -> void:
	var was_playing := not clip.is_empty()
	clip = value
	_time = 0.0
	if not is_instance_valid(_body):
		return
	set_physics_process(not clip.is_empty())
	if _body is RigidBody3D:
		if not was_playing and not clip.is_empty():
			_rest = _body.transform
		if not clip.is_empty() and not _body.freeze:
			_body.freeze = true
			_motion_froze_body = true
		elif clip.is_empty() and _motion_froze_body:
			_body.transform = _rest
			_body.freeze = false
			_motion_froze_body = false
	if rig:
		rig.reset_bone_poses()
		_tracks = MotionClip.bind_joints(clip, rig)
	if clip.is_empty() and _body is not RigidBody3D:
		_body.transform = _rest
	elif not clip.is_empty():
		_physics_process(0.0)

func _physics_process(delta: float) -> void:
	_time = fposmod(_time + delta, clip.duration)
	var pose := MotionClip.sample(clip, _time)
	var rotation: Vector3 = pose.rotation * (PI / 180.0)
	var transform := _rest * Transform3D(Basis.from_euler(rotation), pose.offset)
	if not _body.transform.is_equal_approx(transform):
		_body.transform = transform
	if not _tracks.is_empty():
		MotionClip.apply_joints(rig, _tracks, _time, clip.interpolation)
