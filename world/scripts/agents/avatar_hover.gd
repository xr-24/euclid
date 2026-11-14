extends MeshInstance3D
## The two rig poses are baked into the point mesh and sampled by the filaments.

const PERIOD := 6.4
const MotionClip = preload("res://scripts/animation/motion_clip.gd")
const ActivityMotions = preload("res://scripts/agents/activity_motions.gd")
const ActivityProp = preload("res://scripts/agents/activity_prop.gd")
## Seconds to blend into or out of an activity's motion.
const BLEND := 0.35
var clip := {}
var _time := 0.0
var _filaments: ShaderMaterial
var rig: Skeleton3D
var _tracks: Array[Dictionary] = []
## The activity motion layered over the hover: the one playing and the one fading out.
var activity := ""
var _layers: Array[Dictionary] = []
var _prop: Node3D

func _ready() -> void:
	_filaments = get_child(0).material_override as ShaderMaterial
	rig = get_node("ProjectionRig") as Skeleton3D
	set_hover_time(0.0)

func _process(delta: float) -> void:
	if is_visible_in_tree():
		for layer in _layers:
			layer.time += delta
			layer.weight = move_toward(layer.weight, 1.0 if layer == _layers.back() and layer.on else 0.0, delta / BLEND)
		var kept: Array[Dictionary] = []
		for layer in _layers:
			if layer.weight > 0.0 or (layer == _layers.back() and layer.on):
				kept.append(layer)
			else:
				_rest(layer)
		_layers = kept
		set_hover_time(_time + delta)

func set_hover_time(seconds: float) -> void:
	_time = fposmod(seconds, PERIOD if clip.is_empty() else clip.duration)
	var phase := TAU * _time / PERIOD
	var weights: Vector2 = Vector2(sin(phase), cos(phase)) if clip.is_empty() else MotionClip.sample(clip, _time).pose
	if not _tracks.is_empty():
		MotionClip.apply_joints(rig, _tracks, _time, clip.interpolation)
	# The baked hover poses deform from rest, so they ease off while an activity holds a pose.
	var held := 0.0
	for layer in _layers:
		held = maxf(held, layer.weight)
	weights *= 1.0 - held
	_apply_layers()
	set_blend_shape_value(0, weights.x)
	set_blend_shape_value(1, weights.y)
	_filaments.set_shader_parameter("hover_pose", weights)

## Play the motion for an agent activity kind ("" returns to the hover).
func set_activity(kind: String) -> void:
	var motion := ActivityMotions.clip(kind) if not kind.is_empty() else {}
	var key := ActivityMotions.resolve(kind) if not motion.is_empty() else ""
	if key == activity:
		return
	activity = key
	if not _layers.is_empty():
		_layers.back().on = false
	if not motion.is_empty() and rig:
		_layers.append({"clip": motion, "tracks": MotionClip.bind_joints(motion, rig), "time": 0.0, "weight": 0.0, "on": true})
	_conjure(ActivityMotions.prop(key) if not key.is_empty() else "")

## Swap the holographic prop: the old one dissolves while the new one materializes.
func _conjure(prop_name: String) -> void:
	if is_instance_valid(_prop) and _prop.key == prop_name and not _prop.leaving:
		return
	if is_instance_valid(_prop):
		_prop.leave()
	_prop = null
	var spec := ActivityMotions.prop_spec(activity)
	if prop_name.is_empty() or spec.is_empty() or rig == null:
		return
	var look := material_override as ShaderMaterial
	var tint: Color = look.get_shader_parameter("core_color") if look else Color("ff0e49")
	var accent: Color = look.get_shader_parameter("highlight_color") if look else Color("ff4669")
	_prop = ActivityProp.create(prop_name, spec, rig, tint, accent)
	add_child(_prop)

## The prop the current activity conjured, if any.
func prop() -> Node3D:
	return _prop if is_instance_valid(_prop) else null

## Replay the current activity's motion after it was revised.
func refresh_activity() -> void:
	var kind := activity
	activity = ""
	if not _layers.is_empty():
		_layers.back().on = false
	set_activity(kind)

## Return a finished layer's bones to rest, unless the hover clip moves them.
func _rest(layer: Dictionary) -> void:
	for track: Dictionary in layer.tracks:
		if not _tracks.any(func(own: Dictionary) -> bool: return own.index == track.index):
			rig.set_bone_pose_rotation(track.index, track.rest)

## Each layer blends from the hover's pose toward its clip's; bones the hover does not move start at rest.
func _apply_layers() -> void:
	if _layers.is_empty() or rig == null:
		return
	var moved := {}
	for track in _tracks:
		moved[track.index] = true
	for layer in _layers:
		var motion: Dictionary = layer.clip
		var at := fposmod(float(layer.time), float(motion.duration))
		for track: Dictionary in layer.tracks:
			if not moved.has(track.index):
				rig.set_bone_pose_rotation(track.index, track.rest)
				moved[track.index] = true
			var target: Quaternion = track.rest * Quaternion.from_euler(MotionClip.sample_rotation(track.keys, at, motion.interpolation) * (PI / 180.0))
			var current := rig.get_bone_pose_rotation(track.index)
			rig.set_bone_pose_rotation(track.index, current.slerp(target, float(layer.weight)))

func set_clip(value: Dictionary) -> void:
	clip = value
	if is_node_ready():
		rig.reset_bone_poses()
		_tracks = MotionClip.bind_joints(clip, rig)
		set_hover_time(0.0)
