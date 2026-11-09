extends RefCounted
## Versioned save IO. A malformed or interrupted save never partially updates the world.
const SCHEMA_VERSION := 1

static func write(path: String, zone: String, position: Vector3, yaw: float, pitch: float) -> Error:
	var state := {"schema_version":SCHEMA_VERSION, "zone":zone,
		"position":[position.x,position.y,position.z], "yaw":yaw, "pitch":pitch}
	return write_json(path, state)

static func write_json(path: String, state: Dictionary) -> Error:
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(state))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		return error
	return DirAccess.rename_absolute(path + ".tmp", path)

static func read(path: String, zones: Array) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		return {}
	var state: Dictionary = json.data
	if state.get("schema_version") != SCHEMA_VERSION:
		return {}
	if not zones.any(func(zone: Dictionary) -> bool: return zone.id == state.get("zone")):
		return {}
	var position = state.get("position")
	if not position is Array or position.size() != 3:
		return {}
	for value in position + [state.get("yaw", 0.0), state.get("pitch", 0.0)]:
		if not (value is float or value is int) or not is_finite(float(value)):
			return {}
	return state
