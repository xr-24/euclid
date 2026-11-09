extends MeshInstance3D
## The two rig poses are baked into the point mesh and sampled by the filaments.

const PERIOD := 6.4
const MotionClip = preload("res://scripts/animation/motion_clip.gd")
var clip := {}
var _time := 0.0
var _filaments: ShaderMaterial
var rig: Skeleton3D
var _tracks: Array[Dictionary] = []

func _ready() -> void:
	_filaments = get_child(0).material_override as ShaderMaterial
	rig = get_node("ProjectionRig") as Skeleton3D
	set_hover_time(0.0)

func _process(delta: float) -> void:
	if is_visible_in_tree():
		set_hover_time(_time + delta)

func set_hover_time(seconds: float) -> void:
	_time = fposmod(seconds, PERIOD if clip.is_empty() else clip.duration)
	var phase := TAU * _time / PERIOD
	var weights: Vector2 = Vector2(sin(phase), cos(phase)) if clip.is_empty() else MotionClip.sample(clip, _time).pose
	if not _tracks.is_empty():
		MotionClip.apply_joints(rig, _tracks, _time, clip.interpolation)
	set_blend_shape_value(0, weights.x)
	set_blend_shape_value(1, weights.y)
	_filaments.set_shader_parameter("hover_pose", weights)

func set_clip(value: Dictionary) -> void:
	clip = value
	if is_node_ready():
		rig.reset_bone_poses()
		_tracks = MotionClip.bind_joints(clip, rig)
		set_hover_time(0.0)
