extends Node3D

const Arms = preload("res://assets/player/mannequin_arms.glb")
const Poses = preload("res://scripts/player/hand_poses.gd")
const Wrist = preload("res://scripts/player/hand_wrist.gd")
const Motion = preload("res://scripts/animation/motion_clip.gd")
const Follow = preload("res://scripts/player/spring_follow.gd")
const RenderLayers = preload("res://scripts/rendering/render_layers.gd")
const SIDES := ["l", "r"]
## Camera-space slope from the eye down to the wrist. The elbow and wrist sit at the same
## height and depth, so the forearm runs horizontally across the bottom of the view.
const WATCH_SLOPE := 0.66
const WATCH_PUSHBACK := 0.14
const WATCH_PALM := Vector3(0.0, -1.0, -0.35)
## Where the right wrist goes while the wrist computer is up: down by the hip, out of view.
const RIGHT_AWAY := Vector3(0.36, -0.95, 0.02)
## How the arms move. Each *_FOLLOW is a spring (spring_follow.gd): frequency in Hz, damping
## (below 1 overshoots), response (above 1 overshoots at the start). Wrists chase their poses
## through REACH_FOLLOW and hands turn through TURN_FOLLOW, so every change of pose eases in and
## settles. On top of that the arms trail behind turning and acceleration (SWAY_FOLLOW, with
## LOOK_LAG metres per rad/s of yaw and pitch and ACCEL_LAG metres per m/s²) and swing with the
## stride: BOB is the side sway, the dip at each footfall and each arm's fore-and-aft swing, in
## metres at full speed.
const REACH_FOLLOW := Vector3(3.0, 0.74, 0.9)
const TURN_FOLLOW := Vector3(3.8, 0.85, 1.0)
const SWAY_FOLLOW := Vector3(2.1, 0.5, 0.0)
const LOOK_LAG := Vector2(0.011, 0.008)
const ACCEL_LAG := 0.0009
const SWAY_LIMIT := 0.045
const BOB := Vector3(0.008, 0.013, 0.012)
## While the wrist computer is up the forearm stays level and readable but still looks carried:
## WATCH_BOB is its side sway, footfall dip and fore-and-aft give in metres at full speed,
## WATCH_BREATH how far it rises with each breath, and WATCH_LAG the share of the turning and
## acceleration lag it keeps.
const WATCH_BOB := Vector3(0.003, 0.005, 0.002)
const WATCH_BREATH := 0.0015
const WATCH_LAG := 0.3
## How far the sway and bob tilt the hands, in radians per metre of offset.
const TILT := 2.6
## How far along the forearm, from elbow to wrist, the wrist computer's emitter sits.
const EMITTER_ALONG := 0.78

var _rig: Skeleton3D
var _wrist := Wrist.new()
var _chains: Array[Dictionary] = []
var _pose := Poses.Pose.REST
var _point := Vector3.INF
var _blend := 0.0
var _pulse_left := 0.0
var _watch := false
var _watch_blend := 0.0
var _left_elbow := -1
var _left_hand := -1
var _right_knuckle := -1
var _watch_point := Vector3.ZERO
var _palm_point := Vector3(0.25, -0.24, -0.49)
var _watch_elbow := Vector3.ZERO
var _watch_wrist := Vector3.ZERO
var _finger_rotations := {}
var _breath_phase := 0.0
var _stride_phase := 0.0
var _movement := 0.0
var _reach_offset := Vector3.ZERO
var _palm := Vector3.DOWN
var _finger_lift := 0.0
var _clips := {}
var _track_bindings := {}
var _bob_scale := 1.0
var _preview_slot := -1
var _seek_time := -1.0
var _clip_time := 0.0
var _playing_slot := -1
var _motion := {}
var _last_basis := Basis()
var _has_basis := false
var _velocity := Vector3.ZERO

func mount(camera: Camera3D) -> MeshInstance3D:
	camera.add_child(self)
	var arms := Arms.instantiate() as Node3D
	arms.rotation.y = PI
	arms.position = Vector3(0, -1.72, -0.05)
	add_child(arms)
	var mesh := arms.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	# The arms float in front of the eye; a mirror would show them hanging in mid-air.
	mesh.layers = RenderLayers.REFLECTION_HIDDEN
	_rig = arms.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var ik := TwoBoneIK3D.new()
	_rig.add_child(ik)
	ik.setting_count = SIDES.size()
	for index in SIDES.size():
		var side: String = SIDES[index]
		var handedness := -1.0 if index == 0 else 1.0
		var upper := _rig.find_bone("upperarm_" + side)
		var elbow := _rig.find_bone("lowerarm_" + side)
		var wrist := _rig.find_bone("hand_" + side)
		var target := Node3D.new()
		var pole := Node3D.new()
		add_child(target)
		add_child(pole)
		pole.position = Vector3(handedness * 0.63, -0.71, -0.10)
		if index == 0:
			_left_elbow = elbow
			_left_hand = wrist
		else:
			_right_knuckle = _rig.find_bone("middle_01_r")
		ik.set_root_bone(index, upper)
		ik.set_middle_bone(index, elbow)
		ik.set_end_bone(index, wrist)
		ik.set_target_node(index, ik.get_path_to(target))
		ik.set_pole_node(index, ik.get_path_to(pole))
		var rest := _rig.get_bone_global_rest(wrist)
		var finger_forward := _rig.get_bone_global_rest(_rig.find_bone("middle_01_" + side)).origin - rest.origin
		var to_local := rest.basis.inverse()
		var upper_rest := _rig.get_bone_global_rest(upper).origin
		var elbow_rest := _rig.get_bone_global_rest(elbow).origin
		var shoulder := to_local(_rig.to_global(upper_rest))
		var upper_length := elbow_rest.distance_to(upper_rest)
		var lower_length := rest.origin.distance_to(elbow_rest)
		if index == 0:
			_set_watch_targets(shoulder, upper_length, lower_length)
		_chains.append({
			"shoulder": shoulder,
			"reach": upper_length + lower_length,
			"target": target,
			"pole": pole,
			"pole_rest": pole.position,
			"finger_joints": _finger_joints(side),
			"hand_frame": _frame(to_local * finger_forward, to_local * Vector3.DOWN).inverse(),
		})
		_wrist.wrists.append(wrist)
		_wrist.orientations.append(rest.basis)
		_wrist.finger_axes.append((to_local * finger_forward).normalized())
	_rig.add_child(_wrist)
	_wrist.modification_processed.connect(_cache_hand_points)
	tick(1.0, Poses.Pose.REST, Vector3.INF)
	return mesh

func _set_watch_targets(shoulder: Vector3, upper_length: float, lower_length: float) -> void:
	# Intersect the upper arm's reach with a ray at the desired screen height. Use
	# the farther intersection to put the forearm at a comfortable viewing distance.
	var ray := Vector2(-WATCH_SLOPE, -1.0).normalized()
	var origin := Vector2(shoulder.y, shoulder.z)
	var distance := origin.dot(ray)
	var offset := origin - ray * distance
	var yz := ray * (distance + sqrt(maxf(upper_length * upper_length - offset.length_squared(), 0.0)))
	_watch_elbow = Vector3(shoulder.x, yz.x, yz.y)
	_watch_wrist = _watch_elbow + Vector3.RIGHT * lower_length

## Brings the left forearm up for the wrist computer, or lets it fall back.
func set_wrist_raised(up: bool) -> void:
	_watch = up

func editable_joints() -> PackedStringArray:
	var names := PackedStringArray()
	for chain in _chains:
		for joint: Dictionary in chain.finger_joints:
			names.append(_rig.get_bone_name(joint.bone))
	return names

func set_authored_clips(clips: Dictionary, bob: float) -> void:
	_clips = clips
	_bob_scale = bob
	_track_bindings.clear()
	for slot in clips:
		var bindings := {}
		for track in clips[slot].get("joint_tracks", []):
			bindings[_rig.find_bone(track.joint)] = track.keyframes
		_track_bindings[slot] = bindings
	for chain in _chains:
		chain["still"] = false

func preview_pose(slot: int, time := -1.0) -> void:
	if slot != _preview_slot or (time < 0 and _seek_time >= 0):
		_clip_time = maxf(0.0, time)
	_preview_slot = slot
	_seek_time = time

func stop_pose_preview() -> void:
	_preview_slot = -1
	_seek_time = -1.0
	_playing_slot = -1

func authored_time() -> float:
	return _clip_time

## The point on top of the left forearm the wrist computer projects from, in camera space, and
## how far the arm has come up (0 to 1).
func wrist_emitter() -> Dictionary:
	if _rig == null or _left_elbow < 0:
		return {}
	return {"point": position + _watch_point, "raised": smoothstep(0.0, 1.0, _watch_blend)}

func palm_position() -> Vector3:
	return to_global(_palm_point)

func _cache_hand_points() -> void:
	# The skeleton restores its pre-modifier pose after it updates the skin.
	var in_view := global_transform.affine_inverse() * _rig.global_transform
	var elbow := _rig.get_bone_global_pose(_left_elbow).origin
	var left := _rig.get_bone_global_pose(_left_hand).origin
	var right := _rig.get_bone_global_pose(_wrist.wrists[1]).origin
	var knuckle := _rig.get_bone_global_pose(_right_knuckle).origin
	_watch_point = in_view * elbow.lerp(left, EMITTER_ALONG)
	_palm_point = in_view * right.lerp(knuckle, 0.58)

## The target is in world space. INF uses the crosshair direction for an unbound gesture.
func pulse(pose: Poses.Pose, target: Vector3) -> void:
	_pose = pose
	_point = target
	_pulse_left = float(_clips[pose].duration) if _clips.has(pose) else 0.5
	_playing_slot = -1

## velocity is the player's, in world space; it makes the arms lag on starts, stops and landings.
func tick(delta: float, pose: Poses.Pose, target: Vector3, speed := 0.0, velocity := Vector3.ZERO) -> void:
	_pulse_left = maxf(0.0, _pulse_left - delta)
	if _preview_slot >= 0:
		pose = _preview_slot as Poses.Pose
		target = Vector3.INF
		_pulse_left = 0.0
	var reaching := _pulse_left > 0.0 or pose != Poses.Pose.REST
	if _pulse_left == 0.0 and pose != Poses.Pose.REST:
		_pose = pose
		_point = target
	var amount := 1.0 - exp(-delta * 15.0)
	# Fast here: the reach spring supplies the easing and the settle.
	_blend = lerpf(_blend, 1.0 if reaching else 0.0, 1.0 - exp(-delta * (18.0 if reaching else 14.0)))
	var at_rest := not reaching and _blend < 0.012
	if at_rest:
		_blend = 0.0
	var lift := smoothstep(0.0, 1.0, _blend)
	var slot := int(_pose) if not at_rest else int(Poses.Pose.REST)
	if slot != _playing_slot:
		_clip_time = 0.0
		_playing_slot = slot
	var clip: Dictionary = _clips.get(slot, {})
	var bindings: Dictionary = _track_bindings.get(slot, {})
	var sample := {}
	var time := 0.0
	if not clip.is_empty():
		_clip_time = fposmod(_clip_time + delta, clip.duration)
		time = _seek_time if _preview_slot >= 0 and _seek_time >= 0 else _clip_time
		sample = Motion.sample(clip, time)
	_watch_blend = lerpf(_watch_blend, 1.0 if _watch else 0.0, 1.0 - exp(-delta * 10.0))
	if absf(_watch_blend - (1.0 if _watch else 0.0)) < 0.004:
		_watch_blend = 1.0 if _watch else 0.0
	var watch := smoothstep(0.0, 1.0, _watch_blend)
	# Move the viewmodel back along the same screen line as the level forearm.
	position = Vector3(0.0, -WATCH_SLOPE, -1.0) * WATCH_PUSHBACK * watch
	_movement = lerpf(_movement, clampf(speed / 4.5, 0.0, 1.0), 1.0 - exp(-delta * 7.0))
	_breath_phase = fposmod(_breath_phase + delta * 1.9, TAU)
	# Advance a stride by distance so a slow walk also slows the swing.
	_stride_phase = fposmod(_stride_phase + delta * _movement * 8.6, TAU)
	var to_rig := _rig.global_basis.inverse() * global_basis
	var aim := to_local(_point) if _point.is_finite() else Vector3(0, 0, -1.5)
	var palm_target := Vector3(-0.42, -0.91, 0)
	var finger_lift := 0.0
	match _pose:
		Poses.Pose.GRAB, Poses.Pose.FIST: palm_target = Vector3(-0.82, -0.57, 0)
		Poses.Pose.PINCH:
			palm_target = Vector3(-1.0, 0.10, 0)
			finger_lift = 0.43
		Poses.Pose.OPEN_PALM:
			palm_target = Vector3(0, -0.30, -1.0)
			finger_lift = 0.74
	_palm = _palm.lerp(palm_target, amount)
	_finger_lift = lerpf(_finger_lift, finger_lift, amount)
	var offset: Vector3 = Poses.REACH.get(_pose, Vector3.ZERO)
	_reach_offset = _reach_offset.lerp(offset, amount)
	var breath := sin(_breath_phase)
	var sway := _sway(delta, velocity)
	# A figure eight with each pair of steps: the hands dip at every footfall, drift side to side
	# with the weight and swing fore and aft against each other.
	var stride := _movement * _bob_scale
	var step_dip := (absf(sin(_stride_phase)) - 2.0 / PI) * BOB.y * stride
	var step_side := sin(_stride_phase) * BOB.x * stride
	for index in _chains.size():
		var chain := _chains[index]
		var side := -1.0 if index == 0 else 1.0
		var weight := lift if index == 1 else 0.0
		var shoulder: Vector3 = chain.shoulder
		var rest := Vector3(side * 0.30, -0.295, -0.49)
		rest += Vector3(side * 0.003 * breath, breath * 0.004, 0)
		var reach: float = chain.reach
		var direction := (aim - shoulder).normalized() if aim.z < -0.15 else Vector3.FORWARD
		var distant := shoulder + direction * -_reach_offset.z + Vector3(_reach_offset.x, _reach_offset.y, 0)
		var near_target := aim - direction * (0.19 if _pose == Poses.Pose.POINT else 0.145)
		var wrist := near_target.lerp(distant, smoothstep(0.44, 0.82, aim.length()))
		wrist.z = minf(wrist.z, -0.27)
		wrist.y += 0.003 * breath
		wrist = shoulder + (wrist - shoulder).limit_length(reach * 0.95)
		var goal: Node3D = chain.target
		var lift_arc := sin(weight * PI) * Vector3(-0.025, 0.02, -0.05)
		goal.position = rest.lerp(wrist, weight) + lift_arc
		var reaching_forward := (direction + Vector3.UP * _finger_lift).normalized()
		var hand_forward := Vector3(-side * 0.13, 0.43, -0.90).lerp(reaching_forward, weight)
		var palm := Vector3(-side * 0.46, -0.88, 0.12).lerp(_palm, weight)
		var finger_pose := _pose
		var finger_weight := smoothstep(0.05, 0.83, weight)
		var still := at_rest and bindings.is_empty()
		if index == 0:
			goal.position = goal.position.lerp(_watch_wrist, watch) + sin(watch * PI) * Vector3(0.02, 0.03, -0.04)
			hand_forward = hand_forward.lerp(Vector3.RIGHT, watch)
			palm = palm.lerp(WATCH_PALM, watch)
			var pole: Node3D = chain.pole
			pole.position = (chain.pole_rest as Vector3).lerp(_watch_elbow, watch)
			finger_pose = Poses.Pose.GRAB
			finger_weight = watch * 0.85
			still = watch == 0.0 and bindings.is_empty()
		elif watch > 0.0:
			goal.position = goal.position.lerp(RIGHT_AWAY, watch)
		var authored_weight := (1.0 - watch) * ((1.0 - lift) if slot == Poses.Pose.REST else lift)
		if not sample.is_empty() and (slot == Poses.Pose.REST or index == 1):
			var translation: Vector3 = sample.offset
			translation.x *= side
			goal.position += translation * authored_weight
			goal.position = shoulder + (goal.position - shoulder).limit_length(reach * 0.97)
			var angles: Vector3 = sample.rotation
			angles.y *= side
			angles.z *= side
			var rotation := Basis.from_euler(angles * (PI / 180.0) * authored_weight)
			hand_forward = rotation * hand_forward
			palm = rotation * palm
		# Ease toward the pose, then add the sway and stride on top. A hand that is reaching, or
		# holding up the wrist computer, stays steadier.
		var steady := (1.0 - watch) if index == 0 else 1.0 - 0.6 * weight
		var motion := (sway + Vector3(step_side, step_dip, side * cos(_stride_phase) * BOB.z * stride)) * steady
		if index == 0 and watch > 0.0:
			# The raised forearm moves gently with the walk instead of hanging still.
			var carried := Vector3(sin(_stride_phase) * WATCH_BOB.x * stride,
				(absf(sin(_stride_phase)) - 2.0 / PI) * WATCH_BOB.y * stride + breath * WATCH_BREATH,
				cos(_stride_phase) * WATCH_BOB.z * stride)
			motion += (carried + sway * WATCH_LAG) * watch
		var settled := _follow(chain, "spring_reach", goal.position, delta, REACH_FOLLOW)
		goal.position = shoulder + (settled + motion - shoulder).limit_length(reach * 0.97)
		var tilt := Basis.from_euler(Vector3(-motion.y * TILT, motion.x * TILT, motion.x * TILT * 0.6))
		hand_forward = tilt * _follow(chain, "spring_forward", hand_forward.normalized(), delta, TURN_FOLLOW).normalized()
		palm = tilt * _follow(chain, "spring_palm", palm.normalized(), delta, TURN_FOLLOW).normalized()
		_wrist.orientations[index] = _frame(to_rig * hand_forward, to_rig * palm) * chain.hand_frame
		if not chain.get("still", false) or not still:
			_pose_fingers(chain.finger_joints, finger_pose, finger_weight, 1.0 if still else amount)
			for joint: Dictionary in chain.finger_joints:
				if bindings.has(joint.bone):
					var rotation := Motion.sample_rotation(bindings[joint.bone], time, clip.interpolation) * (PI / 180.0)
					_rig.set_bone_pose_rotation(joint.bone, joint.rest * _finger_rotations[joint.bone] * Quaternion.from_euler(rotation * authored_weight))
		chain["still"] = still

## How far the arms trail behind the view: turning leaves them behind, speeding up or landing pushes
## them back or down, and a spring brings them home with a little overshoot.
func _sway(delta: float, velocity: Vector3) -> Vector3:
	var view := global_basis.orthonormalized()
	var look := Vector3.ZERO
	if _has_basis and delta > 0.0:
		var turn := (_last_basis.inverse() * view).get_euler()
		look = Vector3(turn.y * LOOK_LAG.x, -turn.x * LOOK_LAG.y, 0.0) / delta
	_last_basis = view
	_has_basis = true
	# The motor sets velocity outright, so smooth it before taking its change as acceleration.
	var previous := _velocity
	_velocity = _velocity.lerp(view.inverse() * velocity, 1.0 - exp(-delta * 8.0))
	var accel := (_velocity - previous) / maxf(delta, 0.001)
	accel.y *= 0.7
	var target := (look - accel * ACCEL_LAG).limit_length(SWAY_LIMIT)
	return _follow(_motion, "spring_sway", target, delta, SWAY_FOLLOW)

func _follow(springs: Dictionary, key: String, target: Vector3, delta: float, tuning: Vector3) -> Vector3:
	if not springs.has(key):
		springs[key] = Follow.new(tuning.x, tuning.y, tuning.z, target)
		return target
	var spring: Follow = springs[key]
	return spring.step(minf(delta, 0.05), target)

func _pose_fingers(fingers: Array, pose: Poses.Pose, weight: float, amount: float) -> void:
	for joint: Dictionary in fingers:
		var angles: Array = Poses.CURL[pose][joint.finger]
		var idle: Array = Poses.CURL[Poses.Pose.REST][joint.finger]
		var bend := deg_to_rad(lerpf(idle[joint.segment], angles[joint.segment], weight))
		var rotation := Quaternion(joint.axis, bend)
		if joint.segment == 0:
			if joint.finger == 0:
				var opposition := lerpf(Poses.THUMB_OPPOSITION[Poses.Pose.REST], Poses.THUMB_OPPOSITION[pose], weight)
				rotation = Quaternion(joint.opposition, deg_to_rad(opposition)) * rotation
			else:
				var spread := lerpf(Poses.SPREAD[Poses.Pose.REST][joint.finger], Poses.SPREAD[pose][joint.finger], weight)
				rotation = Quaternion(joint.spread, deg_to_rad(spread)) * rotation
		var previous: Quaternion = _finger_rotations.get(joint.bone, rotation)
		var blended := previous.slerp(rotation, amount)
		_finger_rotations[joint.bone] = blended
		_rig.set_bone_pose_rotation(joint.bone, joint.rest * blended)

func _finger_joints(side: String) -> Array[Dictionary]:
	var joints: Array[Dictionary] = []
	var center := _rig.get_bone_global_rest(_rig.find_bone("middle_01_" + side)).origin
	for finger in Poses.FINGERS.size():
		for segment in 3:
			var prefix: String = Poses.FINGERS[finger]
			var id := _rig.find_bone("%s_%02d_%s" % [prefix, segment + 1, side])
			var tip_name := "%s_%02d_%s" % [prefix, segment + 2, side] if segment < 2 else "%s_04_leaf_%s" % [prefix, side]
			var rest := _rig.get_bone_global_rest(id)
			var forward := (_rig.get_bone_global_rest(_rig.find_bone(tip_name)).origin - rest.origin).normalized()
			var toward := (center - rest.origin).normalized()
			var axis := forward.cross(Vector3.DOWN if finger > 0 else (Vector3.DOWN + toward * 0.6)).normalized()
			joints.append({"bone": id, "finger": finger, "segment": segment,
				"rest": _rig.get_bone_rest(id).basis.get_rotation_quaternion(),
				"axis": rest.basis.inverse() * axis,
				"spread": rest.basis.inverse() * (Vector3.DOWN if side == "l" else Vector3.UP),
				"opposition": rest.basis.inverse() * forward.cross(toward).normalized()})
	return joints

static func _frame(forward: Vector3, palm: Vector3) -> Basis:
	var y := forward.normalized()
	var x := y.cross(palm).normalized()
	if x.is_zero_approx():
		x = y.cross(Vector3.RIGHT).normalized()
	return Basis(x, y, x.cross(y))
