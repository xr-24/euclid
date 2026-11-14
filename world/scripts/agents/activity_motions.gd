extends RefCounted
## The motion and prop each kind of agent activity plays (data/agents/activity_motions.json),
## with revisions saved from the world's animation tools layered over them.

const MotionClip = preload("res://scripts/animation/motion_clip.gd")
const Store = preload("res://scripts/persistence/world_state_store.gd")
const DATA := "res://data/agents/activity_motions.json"
static var _data := _load()
static var _overrides := {}
static var _path := ""

## Load revisions saved in a user file (none in tests and smoke runs).
static func use_overrides(path: String) -> void:
	_path = path
	_overrides = {}
	if path.is_empty() or not FileAccess.file_exists(path):
		return
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if saved is Dictionary and saved.get("schema_version") == 1 and saved.get("clips") is Dictionary:
		for kind: String in saved.clips:
			if kinds().has(kind) and MotionClip.valid(saved.clips[kind]):
				_overrides[kind] = saved.clips[kind]

static func kinds() -> Array:
	return _data.get("activities", {}).keys()

## The activity whose motion an event kind plays (write and delete play edit's).
static func resolve(kind: String) -> String:
	return str(_data.get("aliases", {}).get(kind, kind))

static func clip(kind: String) -> Dictionary:
	var key := resolve(kind)
	if _overrides.has(key):
		return _overrides[key]
	return _data.get("activities", {}).get(key, {}).get("clip", {})

static func prop(kind: String) -> String:
	return str(_data.get("activities", {}).get(resolve(kind), {}).get("prop", ""))

## The holographic prop spec an activity conjures, or {}.
static func prop_spec(kind: String) -> Dictionary:
	return _data.get("props", {}).get(prop(kind), {})

## Replace an activity's motion for this session; {} restores the shipped one.
static func set_override(kind: String, value: Dictionary) -> void:
	if value.is_empty():
		_overrides.erase(kind)
	else:
		_overrides[kind] = value.duplicate(true)

static func save() -> bool:
	return _path.is_empty() or Store.write_json(_path, {"schema_version": 1, "clips": _overrides}) == OK

static func _load() -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	if not value is Dictionary or value.get("version") != 1:
		push_error("Invalid agent activity motions: " + DATA)
		return {}
	return value
