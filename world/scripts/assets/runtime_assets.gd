extends RefCounted
## Runtime assets are data in the user cache. Saved entities store IDs, never file paths.

static var cache_root := "user://runtime-assets"
static var _scenes := {}

static func valid_id(id: Variant) -> bool:
	if not id is String:
		return false
	var pattern := RegEx.new()
	pattern.compile("^(rig-)?(sf-[a-f0-9]{32}|ph-[A-Za-z0-9_-]{1,80})$")
	return pattern.search(id) != null

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
