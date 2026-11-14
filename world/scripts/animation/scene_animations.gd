extends RefCounted
## One live draft at a time. Prop commits use the workshop's existing save and undo.

const Commands = preload("res://scripts/workshop/command_registry.gd")
const MotionClip = preload("res://scripts/animation/motion_clip.gd")
const Store = preload("res://scripts/persistence/world_state_store.gd")
const ActivityMotions = preload("res://scripts/agents/activity_motions.gd")
const COMPANION := "companion"
## Targets "activity:<kind>" revise the motion agents play while they read, edit, run, ...
const ACTIVITY := "activity:"
var _path: String
var _companion: Node
var _activities := {}
var _draft: Object
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
			if target.id == COMPANION or target.id.begins_with(ACTIVITY):
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
	var channels := ["lift", "drift"] if id == COMPANION else [] if id.begins_with(ACTIVITY) else ["offset", "rotation"]
	if not joints.is_empty():
		channels.append("joint_rotation")
	return {"ok": true, "message": "This target supports %s." % ", ".join(channels), "channels": channels,
		"joints": joints, "clip": player.clip, "preview": player == _draft and _has_preview()}

func _preview_animation(plan: Dictionary, workshop: RefCounted) -> Dictionary:
	var id: String = plan.get("target", "")
	var player := _player(id, workshop)
	if not player:
		return _error("That animation target is unavailable in this environment.")
	if (id == COMPANION or id.begins_with(ACTIVITY)) and not _companion.is_visible_in_tree():
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
	if _target.begins_with(ACTIVITY):
		if not ActivityMotions.save():
			return _error("The activity motion could not be saved.")
		_companion.set_activity("")
	elif _target == COMPANION:
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
	if _target != COMPANION and not _target.begins_with(ACTIVITY):
		clear_preview()

func clear_preview() -> void:
	if _has_preview():
		_draft.set_clip(_previous)
		if _target.begins_with(ACTIVITY) and is_instance_valid(_companion):
			_companion.set_activity("")
	_forget()

func _forget() -> void:
	_draft = null
	_target = ""
	_previous = {}
	_draft_value = {}

func _has_preview() -> bool:
	return is_instance_valid(_draft) and _draft.clip == _draft_value

func _player(id: String, workshop: RefCounted) -> Object:
	if id == COMPANION:
		return _companion
	if id.begins_with(ACTIVITY):
		var kind := id.trim_prefix(ACTIVITY)
		if not is_instance_valid(_companion) or kind not in ActivityMotions.kinds():
			return null
		if not _activities.has(kind):
			_activities[kind] = ActivityTarget.new(kind, _companion)
		return _activities[kind]
	return workshop.animation_player(id) if workshop else null

func _targets(workshop: RefCounted) -> Array[Dictionary]:
	var targets: Array[Dictionary] = []
	if is_instance_valid(_companion):
		targets.append({"id": COMPANION, "name": "Codex companion", "channels": ["lift", "drift", "joint_rotation"]})
	if workshop:
		targets.append_array(workshop.animation_targets())
	if is_instance_valid(_companion):
		for kind in ActivityMotions.kinds():
			targets.append({"id": ACTIVITY + kind, "name": "Agent %s motion" % kind, "channels": ["joint_rotation"]})
	return targets

func _valid_for(clip: Variant, player: Object) -> bool:
	var hover := player == _companion or player is ActivityTarget
	if not MotionClip.valid(clip) or not MotionClip.supports(clip, hover):
		return false
	var tracks: Array = clip.get("joint_tracks", [])
	if tracks.is_empty():
		return not player is ActivityTarget
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

## An agent activity's motion as an animation target: previews play it on the companion.
class ActivityTarget extends RefCounted:
	var kind: String
	var companion: Node
	var clip: Dictionary:
		get: return ActivityMotions.clip(kind)
	var rig: Skeleton3D:
		get: return companion.rig if is_instance_valid(companion) else null

	func _init(activity: String, owner: Node) -> void:
		kind = activity
		companion = owner

	func set_clip(value: Dictionary) -> void:
		ActivityMotions.set_override(kind, {})
		if value != ActivityMotions.clip(kind):
			ActivityMotions.set_override(kind, value)
		if is_instance_valid(companion):
			if companion.activity == ActivityMotions.resolve(kind):
				companion.refresh_activity()
			else:
				companion.set_activity(kind)
