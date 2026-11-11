extends Node3D

const Arms = preload("res://assets/player/mannequin_arms.glb")
const Poses = preload("res://scripts/player/hand_poses.gd")
const Wrist = preload("res://scripts/player/hand_wrist.gd")
const SIDES := ["l", "r"]
## The wrist computer pose, like checking a watch: the left forearm laid across the lower middle
## of the view, back of the hand up, a loose fist. Camera space (-Z ahead, +X right). The wrist
## goes this fraction of the arm's reach from the shoulder, in this direction.
const WATCH_DIRECTION := Vector3(0.55, 0.2, -0.81)
const WATCH_EXTENT := 0.74
const WATCH_FORWARD := Vector3(1.0, 0.1, 0.05)
const WATCH_PALM := Vector3(0.0, -1.0, -0.35)
const WATCH_POLE := Vector3(-0.7, -0.45, -0.25)
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
var _finger_rotations := {}
var _breath_phase := 0.0
var _stride_phase := 0.0
var _movement := 0.0
var _reach_offset := Vector3.ZERO
var _palm := Vector3.DOWN
var _finger_lift := 0.0

func mount(camera: Camera3D) -> MeshInstance3D:
	camera.add_child(self)
	var arms := Arms.instantiate() as Node3D
	arms.rotation.y = PI
	arms.position = Vector3(0, -1.72, -0.05)
	add_child(arms)
	var mesh := arms.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
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
		ik.set_root_bone(index, upper)
		ik.set_middle_bone(index, elbow)
		ik.set_end_bone(index, wrist)
		ik.set_target_node(index, ik.get_path_to(target))
		ik.set_pole_node(index, ik.get_path_to(pole))
		var rest := _rig.get_bone_global_rest(wrist)
		var finger_forward := _rig.get_bone_global_rest(_rig.find_bone("middle_01_" + side)).origin - rest.origin
		var to_local := rest.basis.inverse()
		_chains.append({
			"shoulder": to_local(_rig.to_global(_rig.get_bone_global_rest(upper).origin)),
			"reach": (_rig.get_bone_global_rest(elbow).origin - _rig.get_bone_global_rest(upper).origin).length() +
				(rest.origin - _rig.get_bone_global_rest(elbow).origin).length(),
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
	tick(1.0, Poses.Pose.REST, Vector3.INF)
	return mesh

## Brings the left forearm up for the wrist computer, or lets it fall back.
func set_wrist_raised(up: bool) -> void:
	_watch = up

## The point on top of the left forearm the wrist computer projects from, in camera space, and
## how far the arm has come up (0 to 1).
func wrist_emitter() -> Dictionary:
	if _rig == null or _left_elbow < 0:
		return {}
	var elbow := to_local(_rig.to_global(_rig.get_bone_global_pose(_left_elbow).origin))
	var hand := to_local(_rig.to_global(_rig.get_bone_global_pose(_left_hand).origin))
	return {"point": elbow.lerp(hand, EMITTER_ALONG), "raised": smoothstep(0.0, 1.0, _watch_blend)}

## The target is in world space. INF uses the crosshair direction for an unbound gesture.
func pulse(pose: Poses.Pose, target: Vector3) -> void:
	_pose = pose
	_point = target
	_pulse_left = 0.38

func tick(delta: float, pose: Poses.Pose, target: Vector3, speed := 0.0) -> void:
	_pulse_left = maxf(0.0, _pulse_left - delta)
	var reaching := _pulse_left > 0.0 or pose != Poses.Pose.REST
	if _pulse_left == 0.0 and pose != Poses.Pose.REST:
		_pose = pose
		_point = target
	var amount := 1.0 - exp(-delta * 15.0)
	_blend = lerpf(_blend, 1.0 if reaching else 0.0, 1.0 - exp(-delta * (12.0 if reaching else 9.0)))
	var at_rest := not reaching and _blend < 0.012
	if at_rest:
		_blend = 0.0
	var lift := smoothstep(0.0, 1.0, _blend)
	_watch_blend = lerpf(_watch_blend, 1.0 if _watch else 0.0, 1.0 - exp(-delta * 10.0))
	if absf(_watch_blend - (1.0 if _watch else 0.0)) < 0.004:
		_watch_blend = 1.0 if _watch else 0.0
	var watch := smoothstep(0.0, 1.0, _watch_blend)
	_movement = lerpf(_movement, clampf(speed / 4.5, 0.0, 1.0), 1.0 - exp(-delta * 7.0))
	_breath_phase = fposmod(_breath_phase + delta * 1.9, TAU)
	# Advance a stride by distance so a slow walk also slows the swing.
	_stride_phase = fposmod(_stride_phase + delta * _movement * 8.6, TAU)
	var to_rig := _rig.global_basis.inverse() * global_basis
	var aim := to_local(_point) if _point.is_finite() else Vector3(0, 0, -1.5)
	var palm_target := Vector3(-0.42, -0.91, 0)
	var finger_lift := 0.0
	match _pose:
		Poses.Pose.GRAB: palm_target = Vector3(-0.82, -0.57, 0)
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
	# Both wrists rise and dip with each footfall, with a smaller alternating lift.
	var bob := cos(_stride_phase * 2.0) * 0.008 * _movement
	for index in _chains.size():
		var chain := _chains[index]
		var side := -1.0 if index == 0 else 1.0
		var weight := lift if index == 1 else 0.0
		var shoulder: Vector3 = chain.shoulder
		var stride := sin(_stride_phase) * side * _movement
		var rest := Vector3(side * 0.30, -0.295, -0.49)
		rest += Vector3(side * 0.004 * breath, breath * 0.004 + bob - stride * 0.002, 0)
		var reach: float = chain.reach
		var direction := (aim - shoulder).normalized() if aim.z < -0.15 else Vector3.FORWARD
		var distant := shoulder + direction * -_reach_offset.z + Vector3(_reach_offset.x, _reach_offset.y, 0)
		var near_target := aim - direction * (0.19 if _pose == Poses.Pose.POINT else 0.145)
		var wrist := near_target.lerp(distant, smoothstep(0.44, 0.82, aim.length()))
		wrist.z = minf(wrist.z, -0.27)
		wrist.y += 0.004 * breath + bob * 0.4
		wrist = shoulder + (wrist - shoulder).limit_length(reach * 0.95)
		var goal: Node3D = chain.target
		var lift_arc := sin(weight * PI) * Vector3(-0.025, 0.02, -0.05)
		goal.position = rest.lerp(wrist, weight) + lift_arc
		var reaching_forward := (direction + Vector3.UP * _finger_lift).normalized()
		var hand_forward := Vector3(-side * 0.13, 0.43, -0.90).lerp(reaching_forward, weight)
		var palm := Vector3(-side * 0.46, -0.88, 0.12).lerp(_palm, weight)
		var finger_pose := _pose
		var finger_weight := smoothstep(0.05, 0.83, weight)
		var still := at_rest
		if index == 0:
			var watch_wrist := shoulder + WATCH_DIRECTION.normalized() * reach * WATCH_EXTENT
			goal.position = goal.position.lerp(watch_wrist, watch) + sin(watch * PI) * Vector3(0.02, 0.03, -0.04)
			hand_forward = hand_forward.lerp(WATCH_FORWARD, watch)
			palm = palm.lerp(WATCH_PALM, watch)
			var pole: Node3D = chain.pole
			pole.position = (chain.pole_rest as Vector3).lerp(WATCH_POLE, watch)
			finger_pose = Poses.Pose.GRAB
			finger_weight = watch * 0.85
			still = watch == 0.0
		_wrist.orientations[index] = _frame(to_rig * hand_forward, to_rig * palm) * chain.hand_frame
		if not chain.get("still", false) or not still:
			_pose_fingers(chain.finger_joints, finger_pose, finger_weight, 1.0 if still else amount)
		chain["still"] = still

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
