extends Node
## Downloads into a private staging directory, then publishes the complete map set.

const Cache = preload("res://scripts/assets/runtime_materials.gd")
signal installed

var _assets: Node
var _pending := {}

func configure(assets: Node) -> void:
	_assets = assets

func search(query: String) -> Dictionary:
	return await _assets.request_json("/v1/materials/search", {"query": query})

func import_material(id: String) -> Dictionary:
	if not Cache.valid_id(id):
		return {"ok": false, "message": "Invalid material ID."}
	if _pending.has(id):
		return {"ok": false, "message": "This material is already importing."}
	var cached := Cache.info(id)
	if not cached.is_empty() and not Cache.cached_images(id).is_empty():
		return {"ok": true, "material": cached}
	_pending[id] = true
	var result := await _download(id)
	_pending.erase(id)
	if result.ok:
		installed.emit()
	return result

func _download(id: String) -> Dictionary:
	var result: Dictionary = await _assets.request_json("/v1/materials/import", {"id": id})
	if not result.get("ok", false):
		return result
	var material: Variant = result.get("material")
	if not material is Dictionary or material.get("id") != id or not material.get("name") is String:
		return {"ok": false, "message": "The gateway returned an invalid material."}
	var stage := Cache.cache_root.path_join(".import-" + id + "-" + str(Time.get_ticks_usec()))
	if DirAccess.make_dir_recursive_absolute(stage) != OK:
		return {"ok": false, "message": "Could not create the material cache."}
	var saved := await _save_maps(id, material, stage)
	for key in Cache.MAPS + ["material"]:
		DirAccess.remove_absolute(stage.path_join(key + (".json" if key == "material" else ".jpg")))
	DirAccess.remove_absolute(stage)
	return saved

func _save_maps(id: String, material: Dictionary, stage: String) -> Dictionary:
	for key in Cache.MAPS:
		var result: Dictionary = await _assets.download_file("/v1/materials/%s/%s.jpg" % [id, key],
			stage.path_join(key + ".jpg"), Cache.LIMIT)
		if not result.ok:
			return result
	var decoded := Cache.images(stage)
	if decoded.is_empty():
		return {"ok": false, "message": "Godot could not read the downloaded maps."}
	var file := FileAccess.open(stage.path_join("material.json"), FileAccess.WRITE)
	if file == null:
		return {"ok": false, "message": "Could not save the material metadata."}
	file.store_string(JSON.stringify(material))
	file.close()
	var folder := Cache.folder(id)
	# Keep the previous cache available until the replacement is complete.
	var backup := stage + "-old"
	var had_folder := DirAccess.dir_exists_absolute(folder)
	if had_folder and DirAccess.rename_absolute(folder, backup) != OK:
		return {"ok": false, "message": "Could not replace the material cache."}
	if DirAccess.rename_absolute(stage, folder) != OK:
		if had_folder:
			DirAccess.rename_absolute(backup, folder)
		return {"ok": false, "message": "Could not publish the material cache."}
	if had_folder:
		for key in Cache.MAPS:
			DirAccess.remove_absolute(backup.path_join(key + ".jpg"))
		DirAccess.remove_absolute(backup.path_join("material.json"))
		DirAccess.remove_absolute(backup)
	Cache.remember(id, decoded)
	return {"ok": true, "material": material}
