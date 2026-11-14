extends Node3D
## Session-local projections. Selecting a conversation alone never creates one.

const Avatar = preload("res://scripts/agents/binary_avatar.gd")
const CODEX := "local-codex"
const CLAUDE := "local-claude"
const COLORS := {
	CODEX: [Color("ff0e49"), Color("ff4669")],
	CLAUDE: [Color("ff4813"), Color("ffbc55")],
}
const CLOUD_COLORS := [Color("315cff"), Color("65dcff")]
var _avatars := {}

static func label(id: String) -> String:
	return "Codex" if id == CODEX else ("Claude" if id == CLAUDE else id)

func activate(id: String, zone: String, player: CharacterBody3D, daylight: bool) -> Avatar:
	if _avatars.has(id):
		return _avatars[id]
	var avatar := Avatar.new()
	var colors: Array = COLORS.get(id, CLOUD_COLORS)
	avatar.tint = colors[0]
	avatar.highlight = colors[1]
	avatar.slot = 0 if id == CODEX else (1 if id == CLAUDE else 2 + _cloud_count())
	add_child(avatar)
	_avatars[id] = avatar
	avatar.arrive(zone, player, daylight, _occupied(id))
	return avatar

func arrive(zone: String, player: CharacterBody3D, daylight: bool) -> void:
	for id in _avatars:
		_avatars[id].arrive(zone, player, daylight, _occupied(id))

func tick(player: CharacterBody3D, delta: float) -> void:
	for id in _avatars:
		_avatars[id].tick(player, delta, _occupied(id))

func set_mode(id: String, mode: String, zone: String, player: CharacterBody3D) -> void:
	_avatars[id].set_mode(mode, zone, player, _occupied(id))

## Pass an activity event to the agent it belongs to, when that agent is projected here.
func activity(entry: Dictionary) -> void:
	var avatar: Avatar = _avatars.get(str(entry.get("actor", "")))
	if avatar:
		avatar.show_activity(entry)

func has_agent(id: String) -> bool:
	return _avatars.has(id)

func aimed(camera: Camera3D, player: CharacterBody3D) -> String:
	var selected := ""
	var distance := INF
	for id in _avatars:
		var avatar: Avatar = _avatars[id]
		var range_squared := camera.global_position.distance_squared_to(avatar.global_position)
		if range_squared < distance and avatar.can_command(camera, player):
			selected = id
			distance = range_squared
	return selected

func _cloud_count() -> int:
	var count := 0
	for id in _avatars:
		if id not in [CODEX, CLAUDE]:
			count += 1
	return count

func _occupied(except: String) -> Array[Vector3]:
	var positions: Array[Vector3] = []
	for id in _avatars:
		if id != except and _avatars[id].visible:
			positions.append(_avatars[id].global_position)
	return positions
