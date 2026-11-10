extends Node
## Tracks a Workbench draft requested through the in-world agent.

signal changed
signal diagnostics_changed
signal _refresh_finished

const Client = preload("res://scripts/agents/workbench_client.gd")
var draft := {}
var benchmark_target := {}
var diagnostic := {}
var diagnostic_job := {}
var diagnostic_notice := ""
var _client: Client
var _busy := false
var _refreshing := false

func configure(url: String, token: String, capability: String) -> void:
	_client = Client.new()
	add_child(_client)
	_client.configure(url, token, capability)
	var timer := Timer.new()
	timer.wait_time = 2.5
	timer.timeout.connect(func() -> void:
		if not benchmark_target.is_empty() or not diagnostic_job.is_empty():
			refresh())
	add_child(timer)
	timer.start()

func request(definition: Dictionary, prompt: String, context: Dictionary) -> Dictionary:
	var arguments := {"prompt": prompt}
	if definition.get("workshop_context", false):
		arguments["context"] = context
	if definition.get("from_world", false):
		arguments["from_world"] = true
	return await _send(definition.action, arguments)

func command(action: String) -> Dictionary:
	if draft.is_empty():
		return {"error": "There is no development draft to review."}
	return await _send(action, {"id": draft.id, "version": draft.version,
		"cancel_revision": action == "discard" and draft.status == "revising"})

func revise(prompt: String, reviewed: Dictionary, preview_output := "") -> Dictionary:
	return await _send("revise", {"id": reviewed.id, "version": reviewed.version, "prompt": prompt,
		"live_preview_output": preview_output})

func benchmark(action: String, arguments: Dictionary) -> Dictionary:
	return await _send(action, arguments)

func refresh() -> void:
	if not _busy:
		await _send("state", {})

func forget(id: String) -> void:
	if draft.get("id") == id:
		draft = {}
		changed.emit()

func _send(action: String, arguments: Dictionary) -> Dictionary:
	if action != "state" and _refreshing:
		await _refresh_finished
	if _busy:
		return {"error": "The Workbench is handling another request. Try again in a moment."}
	_busy = true
	_refreshing = action == "state"
	var response := await _client.send(action, arguments)
	_busy = false
	if not response.has("error"):
		var item: Variant = response.get("draft")
		var before := benchmark_target
		benchmark_target = {"id": item.id, "version": item.get("version", "")} if item is Dictionary else {}
		var next := {}
		if item is Dictionary and item.get("from_world", false):
			next = {"id": item.id, "status": item.status, "summary": item.summary, "error": item.error,
				"activation": item.activation, "subject": item.subject, "preview_zone": item.preview_zone,
				"agent_source": item.get("agent_source", false), "has_patch": not item.files.is_empty(),
				"version": item.get("version", ""), "can_revise": item.get("can_revise", false),
				"revision_notice": item.get("revision_notice", ""),
				"playing": response.get("playing", false)}
		if next != draft or before != benchmark_target:
			draft = next
			changed.emit()
		var report: Variant = response.get("diagnostic")
		var job: Variant = response.get("diagnostic_job")
		_update_diagnostics(report if report is Dictionary else {}, job if job is Dictionary else {},
			response.get("diagnostic_notice", ""))
	elif action == "state" and not diagnostic_job.is_empty():
		_update_diagnostics(diagnostic, {}, "The gateway connection was lost during the benchmark.")
	if action == "state":
		_refreshing = false
		_refresh_finished.emit()
	return response

func _update_diagnostics(report: Dictionary, job: Dictionary, notice: String) -> void:
	if report != diagnostic or job != diagnostic_job or notice != diagnostic_notice:
		diagnostic = report
		diagnostic_job = job
		diagnostic_notice = notice
		diagnostics_changed.emit()
