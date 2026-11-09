extends Node
## Moves the workshop body and its collision from the stored placement.

const MotionClip = preload("res://scripts/animation/motion_clip.gd")
var clip := {}
var _body: AnimatableBody3D
var _rest: Transform3D
var _time := 0.0
var rig: Skeleton3D
var _tracks: Array[Dictionary] = []

func _ready() -> void:
	_body = get_parent() as AnimatableBody3D
	_rest = _body.transform
	for node in _body.find_children("*", "Skeleton3D", true, false):
		rig = node as Skeleton3D
		break
	set_clip(clip)

func set_clip(value: Dictionary) -> void:
	clip = value
	_time = 0.0
	if not is_instance_valid(_body):
		return
	set_physics_process(not clip.is_empty())
	if rig:
		rig.reset_bone_poses()
		_tracks = MotionClip.bind_joints(clip, rig)
	if clip.is_empty():
		_body.transform = _rest
	else:
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
