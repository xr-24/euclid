extends RefCounted
## Bounded, data-only animation clips. The first and last keys close the loop.

static func valid(clip: Variant, max_joint_tracks := 16) -> bool:
	if not clip is Dictionary or not clip.get("name") is String:
		return false
	if clip.keys().any(func(key: String) -> bool: return key not in ["name", "duration", "interpolation", "keyframes", "joint_tracks"]):
		return false
	var title: String = clip.name.strip_edges()
	if title.is_empty() or title.length() > 48 or title.contains("\n") or title.contains("\r"):
		return false
	if not _number(clip.get("duration"), 1.0, 30.0) or clip.get("interpolation") not in ["linear", "smooth"]:
		return false
	var keys: Variant = clip.get("keyframes")
	if not keys is Array or keys.size() < 2 or keys.size() > 10:
		return false
	var previous := -1.0
	for key in keys:
		if not key is Dictionary or key.size() != 4 or not _number(key.get("time"), 0.0, clip.duration) or float(key.time) <= previous:
			return false
		if not _vector(key.get("offset"), 3, 2.0) or not _vector(key.get("rotation"), 3, 720.0) or not _vector(key.get("pose"), 2, 1.0):
			return false
		previous = float(key.time)
	var first: Dictionary = keys.front()
	var last: Dictionary = keys.back()
	if first.time != 0.0 or last.time != clip.duration or _vec3(first.offset) != _vec3(last.offset) or _vec2(first.pose) != _vec2(last.pose):
		return false
	if not _same_rotation(first.rotation, last.rotation):
		return false
	var tracks: Variant = clip.get("joint_tracks", [])
	if not tracks is Array or tracks.size() > max_joint_tracks:
		return false
	var names := {}
	for track in tracks:
		if not track is Dictionary or track.size() != 2 or not track.get("joint") is String:
			return false
		if track.joint.is_empty() or track.joint.length() > 96 or names.has(track.joint):
			return false
		names[track.joint] = true
		var joint_keys: Variant = track.get("keyframes")
		if not joint_keys is Array or joint_keys.size() < 2 or joint_keys.size() > 10:
			return false
		previous = -1.0
		for key in joint_keys:
			if not key is Dictionary or key.size() != 2 or not _number(key.get("time"), 0.0, clip.duration) or float(key.time) <= previous or not _vector(key.get("rotation"), 3, 180.0):
				return false
			previous = float(key.time)
		first = joint_keys.front()
		last = joint_keys.back()
		if first.time != 0.0 or last.time != clip.duration or not _same_rotation(first.rotation, last.rotation):
			return false
	return true

static func supports(clip: Dictionary, companion: bool) -> bool:
	for key in clip.keyframes:
		if companion and (_vec3(key.offset) != Vector3.ZERO or _vec3(key.rotation) != Vector3.ZERO):
			return false
		if not companion and _vec2(key.pose) != Vector2.ZERO:
			return false
	return true

static func bind_joints(clip: Dictionary, skeleton: Skeleton3D) -> Array[Dictionary]:
	var tracks: Array[Dictionary] = []
	if skeleton == null:
		return tracks
	for track in clip.get("joint_tracks", []):
		var index := skeleton.find_bone(track.joint)
		if index >= 0:
			tracks.append({"index": index, "rest": skeleton.get_bone_rest(index).basis.get_rotation_quaternion(), "keys": track.keyframes})
	return tracks

static func apply_joints(skeleton: Skeleton3D, tracks: Array[Dictionary], time: float, interpolation: String) -> void:
	for track in tracks:
		skeleton.set_bone_pose_rotation(track.index, track.rest * Quaternion.from_euler(sample_rotation(track.keys, time, interpolation) * (PI / 180.0)))

static func sample_rotation(keys: Array, time: float, interpolation: String) -> Vector3:
	var index := _next_key(keys, time)
	var a: Dictionary = keys[index - 1]
	var b: Dictionary = keys[index]
	return _vec3(a.rotation).lerp(_vec3(b.rotation), _weight(a.time, b.time, time, interpolation))

static func sample(clip: Dictionary, seconds: float) -> Dictionary:
	var time := fposmod(seconds, clip.duration)
	var keys: Array = clip.keyframes
	var index := _next_key(keys, time)
	var a: Dictionary = keys[index - 1]
	var b: Dictionary = keys[index]
	var t := _weight(a.time, b.time, time, clip.interpolation)
	return {
		"offset": _vec3(a.offset).lerp(_vec3(b.offset), t),
		"rotation": _vec3(a.rotation).lerp(_vec3(b.rotation), t),
		"pose": _vec2(a.pose).lerp(_vec2(b.pose), t),
	}

static func _next_key(keys: Array, time: float) -> int:
	var index := 1
	while index < keys.size() - 1 and time >= float(keys[index].time):
		index += 1
	return index

static func _weight(start: float, end: float, time: float, interpolation: String) -> float:
	var t := inverse_lerp(start, end, time)
	return smoothstep(0.0, 1.0, t) if interpolation == "smooth" else t

static func _same_rotation(a: Array, b: Array) -> bool:
	for axis in 3:
		if not is_zero_approx(wrapf(b[axis] - a[axis], -180.0, 180.0)):
			return false
	return true

static func _vec3(values: Array) -> Vector3:
	return Vector3(values[0], values[1], values[2])

static func _vec2(values: Array) -> Vector2:
	return Vector2(values[0], values[1])

static func _number(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= minimum and value <= maximum

static func _vector(value: Variant, size: int, limit: float) -> bool:
	if not value is Array or value.size() != size:
		return false
	for component in value:
		if not _number(component, -limit, limit):
			return false
	return true
