extends Node
## Asynchronous provider preparation and authenticated GLB download, owned by the world.
const Assets = preload("res://scripts/assets/runtime_assets.gd")
var _url := ""
var _headers: PackedStringArray
var _busy := false

func configure(url: String, token: String) -> void:
	_url = url
	_headers = ["Authorization: Bearer " + token, "Content-Type: application/json"]

func _json(route: String, body: Variant = null) -> Dictionary:
	var request := HTTPRequest.new()
	request.timeout = 85
	request.body_size_limit = 262144
	request.use_threads = true
	add_child(request)
	var method := HTTPClient.METHOD_GET if body == null else HTTPClient.METHOD_POST
	var started := request.request(_url + route, _headers, method, "" if body == null else JSON.stringify(body))
	if started != OK:
		request.queue_free()
		return {"ok": false, "message": "The asset service could not be reached."}
	var response: Array = await request.request_completed
	request.queue_free()
	var data: Variant = JSON.parse_string(response[3].get_string_from_utf8())
	if response[0] != HTTPRequest.RESULT_SUCCESS or not data is Dictionary:
		return {"ok": false, "message": "The asset service timed out or returned invalid data."}
	if response[1] != 200:
		return {"ok": false, "message": str(data.get("error", "The asset request failed."))}
	return data

func list_assets() -> Dictionary:
	return await _json("/v1/assets")

func ensure_asset(target: String, context: Dictionary, preserve_rig := false) -> Dictionary:
	if _busy:
		return {"ok": false, "message": "Another model is being imported."}
	if _url.is_empty():
		return {"ok": false, "message": "Launch Euclid with its local gateway to import models."}
	_busy = true
	var result := await _prepare(target, context, preserve_rig)
	_busy = false
	return result

func _prepare(target: String, context: Dictionary, preserve_rig: bool) -> Dictionary:
	var data: Dictionary
	if Assets.valid_id(target):
		if preserve_rig and not target.begins_with("rig-"):
			target = "rig-" + target
		if Assets.scene(target) != null:
			return {"ok": true, "asset": Assets.metadata(target)}
		data = await _json("/v1/assets/import", {"asset_id": target})
	else:
		data = await _json("/v1/assets/resolve", {"query": target, "context": context, "preserve_rig": preserve_rig})
	if not data.get("ok", false):
		return data
	var id: String = str(data.get("asset_id", data.get("asset", {}).get("asset_id", "")))
	if not Assets.valid_id(id):
		return {"ok": false, "message": "The asset service returned an invalid ID."}
	var deadline := Time.get_ticks_msec() + 210000
	while data.get("status") != "ready":
		if Time.get_ticks_msec() > deadline:
			return {"ok": false, "message": "The model is still preparing. Retry after the import finishes."}
		await get_tree().create_timer(1.5).timeout
		data = await _json("/v1/assets/" + id)
		if not data.get("ok", false):
			return data
	var location := Assets.folder(id)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(location))
	var request := HTTPRequest.new()
	request.timeout = 85
	request.body_size_limit = 67108864
	request.use_threads = true
	request.download_file = location.path_join("model.part")
	add_child(request)
	if request.request(_url + "/v1/assets/" + id + "/model.glb", _headers) != OK:
		request.queue_free()
		return {"ok": false, "message": "The model download could not start."}
	var response: Array = await request.request_completed
	request.queue_free()
	if response[0] != HTTPRequest.RESULT_SUCCESS or response[1] != 200:
		return {"ok": false, "message": "The model download failed. You can retry it."}
	if DirAccess.rename_absolute(location.path_join("model.part"), location.path_join("model.glb")) != OK:
		return {"ok": false, "message": "The model cache could not be saved."}
	var metadata_file := FileAccess.open(location.path_join("asset.json"), FileAccess.WRITE)
	if metadata_file == null:
		return {"ok": false, "message": "The model metadata could not be saved."}
	metadata_file.store_string(JSON.stringify(data.asset))
	metadata_file.close()
	var packed := Assets.scene(id)
	if packed == null:
		return {"ok": false, "message": "Godot could not load the prepared model."}
	return {"ok": true, "asset": data.asset}
