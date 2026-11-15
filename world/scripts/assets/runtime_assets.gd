extends RefCounted
const Commands = preload("res://scripts/workshop/command_registry.gd")
## Runtime assets are data in the user cache. Saved entities store IDs, never file paths.

static var cache_root := "user://runtime-assets"
static var _scenes := {}

static func valid_id(id: Variant) -> bool:
	return Commands.valid_field("asset_id", id)

static func folder(id: String) -> String:
	return cache_root.path_join(id) if valid_id(id) else ""

static func metadata(id: String) -> Dictionary:
	if not valid_id(id):
		return {}
	var file := FileAccess.open(folder(id).path_join("asset.json"), FileAccess.READ)
	if file == null or file.get_length() > 16384:
		return {}
	var data: Variant = JSON.parse_string(file.get_as_text())
	return data if data is Dictionary and data.get("asset_id") == id else {}

static func scene(id: String) -> PackedScene:
	if not valid_id(id):
		return null
	if _scenes.has(id):
		return _scenes[id]
	var location := folder(id).path_join("model.glb")
	if metadata(id).is_empty() or not FileAccess.file_exists(location):
		return null
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_file(ProjectSettings.globalize_path(location), state) != OK:
		return null
	var imported := document.generate_scene(state)
	if imported == null:
		return null
	var packed := PackedScene.new()
	var result := packed.pack(imported)
	imported.free()
	if result != OK:
		return null
	_scenes[id] = packed
	return packed

## Drop a model from the cache, so the next use loads it from disk again.
static func forget(id: String) -> void:
	_scenes.erase(id)
