extends RefCounted
## One player rig draft shared by the editor and the command registry.

const Motion = preload("res://scripts/animation/motion_clip.gd")
const Store = preload("res://scripts/persistence/world_state_store.gd")
const SLOTS := ["rest", "point", "grab", "pinch", "open_palm"]
const SWATCHES := {"shell": "M_Main", "joints": "M_Joints"}
const MAX_TRACKS := 30
signal changed

var _avatar: Node3D
var _path: String
var _saved := {"colors": {}, "clips": {}, "bob": 1.0}
var _draft := {}
var _slot := 0
var _joints := PackedStringArray()

func _init(avatar: Node3D, path: String) -> void:
	_avatar = avatar
	_path = path
	_joints = avatar.hands.editable_joints()
	_saved.colors = avatar.default_colors()
	var file := FileAccess.open(path, FileAccess.READ) if not path.is_empty() else null
	if file and file.get_length() <= 262144:
		var data: Variant = JSON.parse_string(file.get_as_text())
		if data is Dictionary and data.get("version") == 1 and _valid_profile(data.get("profile")):
			_saved = data.profile
	_apply(_saved)

func state() -> Dictionary:
	var profile := _saved if _draft.is_empty() else _draft
	return {"ok": true, "message": "Player shell #%s, joints #%s, walking bob %.2f×." % [profile.colors.shell, profile.colors.joints, profile.bob],
		"slots": SLOTS.duplicate(), "joints": Array(_joints), "profile": profile.duplicate(true),
		"preview": not _draft.is_empty(), "slot": SLOTS[_slot]}

func planning_context() -> Dictionary:
	var profile := _saved if _draft.is_empty() else _draft
	return {"colors": profile.colors, "bob": profile.bob, "authored_slots": profile.clips.keys(),
		"selected_slot": SLOTS[_slot], "joints": Array(_joints), "preview": not _draft.is_empty()}

func inspect(slot: String) -> Dictionary:
	var summary := planning_context()
	summary["ok"] = true
	summary["message"] = "Player shell #%s, joints #%s, walking bob %.2f×." % [summary.colors.shell, summary.colors.joints, summary.bob]
	summary["slots"] = SLOTS.duplicate()
	if not slot.is_empty():
		var profile := _saved if _draft.is_empty() else _draft
		summary["clip"] = profile.clips.get(slot, {})
	return summary

func preview(slot: String, changes: Dictionary) -> Dictionary:
	if slot not in SLOTS:
		return _error("Choose a player hand pose.")
	var next := (_saved if _draft.is_empty() else _draft).duplicate(true)
	if changes.has("clip"):
		var clip: Variant = changes.clip
		if not _valid_clip(clip):
			return _error("Use matching loop endpoints, up to 10 keys per track, finger joints, ±0.12 m wrist offsets and ±60° rotations.")
		next.clips[slot] = clip.duplicate(true)
	if changes.get("reset_clip", false):
		next.clips.erase(slot)
	for key in SWATCHES:
		if changes.has(key):
			next.colors[key] = changes[key]
	if changes.has("bob"):
		next.bob = changes.bob
	if not _valid_profile(next):
		return _error("Use six-digit colors and a walking bob multiplier between 0 and 2.")
	_draft = next
	_slot = SLOTS.find(slot)
	_apply(_draft)
	_avatar.hands.preview_pose(_slot)
	changed.emit()
	return {"ok": true, "message": "Previewing the player rig. Save or discard the draft when finished."}

func seek(slot: String, time: float) -> void:
	if slot not in SLOTS:
		return
	_slot = SLOTS.find(slot)
	_avatar.hands.preview_pose(_slot, time)

func play(slot: String) -> void:
	seek(slot, -1.0)

func playback_time() -> float:
	return _avatar.hands.authored_time()

func stop_preview() -> void:
	_avatar.hands.stop_pose_preview()

func finish(keep: bool) -> Dictionary:
	if _draft.is_empty():
		return _error("There is no player rig draft.")
	if keep and not _path.is_empty() and Store.write_json(_path, {"version": 1, "profile": _draft}) != OK:
		return _error("Could not save the player rig. The preview is still available.")
	if keep:
		_saved = _draft
	_draft = {}
	_apply(_saved)
	stop_preview()
	changed.emit()
	return {"ok": true, "message": "Saved player rig." if keep else "Restored the saved player rig."}

func _apply(profile: Dictionary) -> void:
	_avatar.apply_colors(profile.colors)
	var clips := {}
	for slot in profile.clips:
		clips[SLOTS.find(slot)] = profile.clips[slot]
	_avatar.hands.set_authored_clips(clips, float(profile.bob))

func _valid_profile(profile: Variant) -> bool:
	if not profile is Dictionary or not profile.get("colors") is Dictionary or not profile.get("clips") is Dictionary:
		return false
	var bob: Variant = profile.get("bob")
	if not (bob is int or bob is float) or not is_finite(float(bob)) or bob < 0 or bob > 2:
		return false
	for key in SWATCHES:
		var color: Variant = profile.colors.get(key)
		if not color is String or color.length() != 6 or not Color.html_is_valid(color):
			return false
	for slot in profile.clips:
		if slot not in SLOTS or not _valid_clip(profile.clips[slot]):
			return false
	return true

func _valid_clip(clip: Variant) -> bool:
	if not Motion.valid(clip, MAX_TRACKS) or not Motion.supports(clip, false):
		return false
	for key in clip.keyframes:
		if key.offset.any(func(value: float) -> bool: return absf(value) > 0.12) or _beyond_rotation(key.rotation):
			return false
	for track in clip.get("joint_tracks", []):
		if track.joint not in _joints or track.keyframes.any(func(key: Dictionary) -> bool: return _beyond_rotation(key.rotation)):
			return false
	return true

static func _beyond_rotation(rotation: Array) -> bool:
	return rotation.any(func(value: float) -> bool: return absf(value) > 60.0)

static func _error(message: String) -> Dictionary:
	return {"ok": false, "message": message}
