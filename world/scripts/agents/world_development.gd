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

func request_shoreline(prompt: String) -> Dictionary:
	return await _send("shoreline", {"prompt": prompt})

func command(action: String) -> Dictionary:
	if draft.is_empty():
		return {"error": "There is no shoreline draft to review."}
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
		if item is Dictionary and item.get("shoreline", false):
			next = {"id": item.id, "status": item.status, "summary": item.summary, "error": item.error}
		if next != draft:
			draft = next
			changed.emit()
	return response
