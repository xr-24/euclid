extends Node
## Shares the authenticated asset transport with model and material imports.

const Cache = preload("res://scripts/assets/runtime_skies.gd")
var _assets: Node
var _pending := {}

func configure(assets: Node) -> void:
	_assets = assets

func search(query: String) -> Dictionary:
	return await _assets.request_json("/v1/skies/search", {"query": query})

func import_sky(id: String) -> Dictionary:
	if not Cache.valid_id(id):
		return _error("Invalid sky ID.")
	if _pending.has(id):
		return _error("This sky is already importing.")
	var key := Cache.PREFIX + id + ".hdr"
	if Cache.texture(key) != null:
		return {"ok": true, "sky": {"id": id, "key": key, "name": id.capitalize()}}
	_pending[id] = true
	var result := await _download(id, key)
	_pending.erase(id)
	return result

func _download(id: String, key: String) -> Dictionary:
	var result: Dictionary = await _assets.request_json("/v1/skies/import", {"id": id})
	if not result.ok:
		return result
	var sky: Variant = result.get("sky")
	if not sky is Dictionary or sky.get("id") != id or not sky.get("name") is String:
		return _error("The gateway returned an invalid sky.")
	if DirAccess.make_dir_recursive_absolute(Cache.directory) != OK:
		return _error("Could not create the sky cache.")
	var stage := Cache.directory.path_join(".download-%s-%d.hdr" % [id, Time.get_ticks_usec()])
	var downloaded: Dictionary = await _assets.download_file("/v1/skies/" + id + "/panorama.hdr", stage, Cache.LIMIT)
	var image := Cache.read(stage) if downloaded.ok else null
	if image == null:
		DirAccess.remove_absolute(stage)
		return _error("Godot could not read the panorama.") if downloaded.ok else downloaded
	if DirAccess.rename_absolute(stage, Cache.directory.path_join(key)) != OK:
		DirAccess.remove_absolute(stage)
		return _error("Could not save the sky.")
	Cache.remember(key, image)
	sky["key"] = key
	return {"ok": true, "sky": sky}

static func _error(message: String) -> Dictionary:
	return {"ok": false, "message": message}
