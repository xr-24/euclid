extends RefCounted
## Atomic scene snapshots and their bounded, durable undo journal.

const Store = preload("res://scripts/persistence/world_state_store.gd")
const MAX_ENTITIES := 256
const MAX_UNDO := 64
const MAX_DRESSING := 256
const MAX_SAVE_BYTES := 12 * 1024 * 1024
const MAX_UNDO_BYTES := 2 * 1024 * 1024
static var _id := RegEx.create_from_string("^[a-fA-F0-9]{32}$")

static func read(path: String, valid_record: Callable, valid_override: Callable) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_SAVE_BYTES:
		return {"error": "The scene prop save could not be read."}
	var state: Variant = JSON.parse_string(file.get_as_text())
	if not state is Dictionary or not state.get("entities") is Array:
		return {"error": "The scene prop save has an invalid format."}
	var version: Variant = state.get("schema_version")
	if version != 1 and version != 2:
		return {"error": "The scene prop save has an invalid format."}
	if state.entities.size() > MAX_ENTITIES:
		return {"error": "The scene prop save exceeds the entity limit."}
	var entities := {}
	for item in state.entities:
		if not item is Dictionary or not valid_record.call(item) or entities.has(item.id):
			return {"error": "The scene prop save contains an invalid entity."}
		entities[item.id] = item
	var dressing: Variant = state.get("dressing", {}) if version == 2 else {}
	if not _valid_updates(dressing, MAX_DRESSING, valid_override, false):
		return {"error": "The scene prop save contains an invalid dressing override."}
	var history: Array[Dictionary] = []
	var saved: Variant = state.get("undo", []) if version == 2 else []
	if saved is Array and saved.size() <= MAX_UNDO and saved.all(
			func(entry: Variant) -> bool: return _valid_entry(entry, valid_record, valid_override)):
		history.assign(saved)
	return {"entities": entities, "dressing": dressing, "undo": trimmed(history)}

static func valid_id(id: Variant) -> bool:
	return id is String and _id.search(id) != null

static func trimmed(history: Array[Dictionary]) -> Array[Dictionary]:
	var result := history.slice(maxi(0, history.size() - MAX_UNDO))
	var sizes: Array[int] = []
	var bytes := 0
	for edit in result:
		var size := JSON.stringify(edit).to_utf8_buffer().size()
		sizes.append(size)
		bytes += size
	while bytes > MAX_UNDO_BYTES and not result.is_empty():
		bytes -= sizes.pop_front()
		result.pop_front()
	return result

static func write(path: String, entities: Dictionary, dressing: Dictionary, history: Array[Dictionary]) -> bool:
	if path.is_empty():
		return true
	var text := JSON.stringify({"schema_version": 2, "entities": entities.values(), "dressing": dressing, "undo": history})
	return text.to_utf8_buffer().size() <= MAX_SAVE_BYTES and Store.write_text(path, text) == OK

static func _valid_updates(values: Variant, limit: int, check: Callable, allow_empty: bool) -> bool:
	if not values is Dictionary or values.size() > limit:
		return false
	for id in values:
		var value: Variant = values[id]
		if not valid_id(id) or not value is Dictionary:
			return false
		if value.is_empty():
			if not allow_empty: return false
		elif not check.call(value):
			return false
	return true

static func _valid_entry(entry: Variant, valid_record: Callable, valid_override: Callable) -> bool:
	if not entry is Dictionary or not (entry.get("id") == "" or valid_id(entry.get("id"))):
		return false
	var previous: Variant = entry.get("previous")
	if not _valid_updates(previous, MAX_ENTITIES, valid_record, true):
		return false
	for id in previous:
		if not previous[id].is_empty() and previous[id].id != id:
			return false
	if not _valid_updates(entry.get("dressing", {}), MAX_DRESSING, valid_override, true):
		return false
	var doors: Variant = entry.get("doors", {})
	if not doors is Dictionary or doors.size() > MAX_ENTITIES:
		return false
	for id in doors:
		var height: Variant = doors[id]
		if not valid_id(id) or not (height is int or height is float) or not is_finite(float(height)) or height < 0 or height > 10:
			return false
	return true
