extends Node
## Tracks a Workbench draft requested through the in-world agent.

signal changed

const Client = preload("res://scripts/agents/workbench_client.gd")
var draft := {}
var _client: Client
var _busy := false

func configure(url: String, token: String, capability: String) -> void:
	_client = Client.new()
	add_child(_client)
	_client.configure(url, token, capability)
	var timer := Timer.new()
	timer.wait_time = 2.5
	timer.timeout.connect(func() -> void:
		if not draft.is_empty():
			refresh())
	add_child(timer)
	timer.start()

func request(tool: String, prompt: String, context: Dictionary) -> Dictionary:
	match tool:
		"draft_shoreline": return await _send("shoreline", {"prompt": prompt})
		"draft_grid": return await _send("grid", {"prompt": prompt})
		"draft_behavior": return await _send("author", {"prompt": prompt, "context": context, "from_world": true})
		"draft_workshop_tool": return await _send("tool", {"prompt": prompt, "context": context})
	return {"error": "Unknown development request."}

func command(action: String) -> Dictionary:
	if draft.is_empty():
		return {"error": "There is no development draft to review."}
	return await _send(action, {"id": draft.id})

func refresh() -> void:
	if not _busy:
		await _send("state", {})

func forget(id: String) -> void:
	if draft.get("id") == id:
		draft = {}
		changed.emit()

func _send(action: String, arguments: Dictionary) -> Dictionary:
	if _busy:
		return {"error": "The Workbench is handling another request. Try again in a moment."}
	_busy = true
	var response := await _client.send(action, arguments)
	_busy = false
	if not response.has("error"):
		var item: Variant = response.get("draft")
		var next := {}
		if item is Dictionary and item.get("from_world", false):
			next = {"id": item.id, "status": item.status, "summary": item.summary, "error": item.error,
				"activation": item.activation, "subject": item.subject, "preview_zone": item.preview_zone}
		if next != draft:
			draft = next
			changed.emit()
	return response
