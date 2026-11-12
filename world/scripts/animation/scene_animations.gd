extends RefCounted
## One live draft at a time. Prop commits use the workshop's existing save and undo.

const Commands = preload("res://scripts/workshop/command_registry.gd")
const MotionClip = preload("res://scripts/animation/motion_clip.gd")
const Store = preload("res://scripts/persistence/world_state_store.gd")
const COMPANION := "companion"
var _path: String
var _companion: Node
var _draft: Node
var _target := ""
var _previous := {}
var _draft_value := {}

func _init(path: String, companion: Node) -> void:
	_path = path
	attach_companion(companion)

func attach_companion(companion: Node) -> void:
	if companion == _companion:
		return
	_companion = companion
	if companion and not _path.is_empty() and FileAccess.file_exists(_path):
		var file := FileAccess.open(_path, FileAccess.READ)
		if file and file.get_length() <= 65536:
			var saved: Variant = JSON.parse_string(file.get_as_text())
			if saved is Dictionary and saved.get("schema_version") == 1 and _valid_for(saved.get("clip"), companion):
				companion.set_clip(saved.clip)

func context(workshop: RefCounted) -> Dictionary:
	var targets := _targets(workshop).slice(0, 12)
	# Keep the typed planner's input small. Native inspection returns the full rig.
	var remaining_joints := 160
	for target in targets:
		var player := _player(target.id, workshop)
		if player and player.rig and remaining_joints > 0:
			var names := _joint_names(player.rig)
			if target.id == COMPANION:
				names = names.filter(func(name: String) -> bool:
					return name.begins_with("spine") or name.begins_with("neck") or name in ["head", "root"] or \
						["upperarm", "lowerarm", "wrist", "upperleg", "lowerleg", "foot"].any(func(prefix: String) -> bool: return name.begins_with(prefix)))
			target["joints"] = names.slice(0, mini(64, remaining_joints))
			remaining_joints -= target.joints.size()
	return {"targets": targets, "draft": {"id": _target, "clip": _draft_value} if _has_preview() else {}}

func execute(plan: Dictionary, workshop: RefCounted) -> Dictionary:
	var definition := Commands.command(plan.get("tool"))
	if definition.get("service") != "animation" or not has_method(definition.handler) or not Commands.valid_plan(definition, plan):
		return _error("Invalid animation command.")
	return call(definition.handler, plan, workshop)

func _inspect_animation(plan: Dictionary, workshop: RefCounted) -> Dictionary:
	var id: String = plan.get("target", "")
	if id.is_empty():
		var available := _targets(workshop)
		var names := PackedStringArray()
		for item in available.slice(0, 12):
			names.append(item.name)
		return {"ok": true, "message": "Animation targets include " + ", ".join(names) + ".", "targets": available.slice(0, 24)}
	var player := _player(id, workshop)
	if not player:
		return _error("That animation target is unavailable in this environment.")
	var joints := _joint_names(player.rig)
	var channels := ["lift", "drift"] if id == COMPANION else ["offset", "rotation"]
	if not joints.is_empty():
		channels.append("joint_rotation")
	return {"ok": true, "message": "This target supports %s." % ", ".join(channels), "channels": channels,
		"joints": joints, "clip": player.clip, "preview": player == _draft and _has_preview()}

func _preview_animation(plan: Dictionary, workshop: RefCounted) -> Dictionary:
	var id: String = plan.get("target", "")
	var player := _player(id, workshop)
	if not player:
		return _error("That animation target is unavailable in this environment.")
	if id == COMPANION and not _companion.is_visible_in_tree():
		return _error("The companion is parked in another environment. Ask it to follow to preview its animation here.")
	var clip: Variant = plan.get("clip")
	if not _valid_for(clip, player):
		return _error("Use a closed loop with ordered keys and channels or joints supported by the target.")
	clear_preview()
	_previous = player.clip
	_draft = player
	_target = id
	_draft_value = clip.duplicate(true)
	player.set_clip(_draft_value)
	return {"ok": true, "message": "Previewing %s. Say ‘save this animation’ or ‘discard this preview’." % clip.name}

func _finish_animation(plan: Dictionary, workshop: RefCounted) -> Dictionary:
	var id: String = plan.get("target", "")
	if not _has_preview() or (not id.is_empty() and id != _target):
		return _error("There is no active preview for that target.")
	var name: String = _draft.clip.name
	if Commands.command(plan.tool).mode == "discard":
		clear_preview()
		return {"ok": true, "message": "Discarded %s and restored the previous motion." % name}
	if _target == COMPANION:
		if not _path.is_empty() and Store.write_json(_path, {"schema_version": 1, "clip": _draft.clip}) != OK:
			return _error("The companion animation could not be saved.")
	else:
		if not workshop or workshop.animation_player(_target) != _draft:
			return _error("The draft's prop is no longer in this workshop.")
		var result: Dictionary = workshop.execute("edit", {"id": _target, "changes": {"animation": _draft.clip}})
		if not result.ok:
			return _error(result.error)
	_forget()
	return {"ok": true, "message": "Saved %s." % name}

func leave_workshop() -> void:
	if _target != COMPANION:
		clear_preview()

func clear_preview() -> void:
	if _has_preview():
		_draft.set_clip(_previous)
	_forget()

func _forget() -> void:
	_draft = null
	_target = ""
	_previous = {}
	_draft_value = {}

func _has_preview() -> bool:
	return is_instance_valid(_draft) and _draft.clip == _draft_value

func _player(id: String, workshop: RefCounted) -> Node:
	if id == COMPANION:
		return _companion
	return workshop.animation_player(id) if workshop else null

func _targets(workshop: RefCounted) -> Array[Dictionary]:
	var targets: Array[Dictionary] = []
	if is_instance_valid(_companion):
		targets.append({"id": COMPANION, "name": "Codex companion", "channels": ["lift", "drift", "joint_rotation"]})
	if workshop:
		targets.append_array(workshop.animation_targets())
	return targets

func _valid_for(clip: Variant, player: Node) -> bool:
	if not MotionClip.valid(clip) or not MotionClip.supports(clip, player == _companion):
		return false
	var tracks: Array = clip.get("joint_tracks", [])
	if tracks.is_empty():
		return true
	if not player.rig or tracks.any(func(track: Dictionary) -> bool: return player.rig.find_bone(track.joint) < 0):
		return false
	# Lift and Drift are baked from the original rest pose. Joint clips use the rig directly.
	return clip.keyframes.all(func(key: Dictionary) -> bool: return float(key.pose[0]) == 0 and float(key.pose[1]) == 0)

static func _joint_names(rig: Skeleton3D) -> Array[String]:
	var names: Array[String] = []
	if rig:
		for index in rig.get_bone_count():
			names.append(rig.get_bone_name(index))
	return names

static func _error(message: String) -> Dictionary:
	return {"ok": false, "message": message}
