extends Node

signal notice(text: String)

var _url := ""
var _headers := PackedStringArray()
var _seen := {}
var _status := {}
var _polling := false

func configure(url: String, token: String, capability: String) -> void:
	_url = url + "/v1/tasks/"
	_headers = ["Authorization: Bearer " + token, "X-Euclid-Workbench: " + capability, "Content-Type: application/json"]

func share_view(to: String, zone: String, image: PackedByteArray) -> void:
	var result := await _request("share_view", {"to": to, "zone": zone, "image": Marshalls.raw_to_base64(image)})
	notice.emit(str(result.get("error", "Shared the view with @" + to + ".")))

func _request(action: String, body: Dictionary) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = 8
	http.body_size_limit = 196608
	add_child(http)
	if http.request(_url + action, _headers, HTTPClient.METHOD_POST, JSON.stringify(body)) != OK:
		http.queue_free()
		return {"error": "Could not reach the task gateway."}
	var reply: Array = await http.request_completed
	http.queue_free()
	var data: Variant = JSON.parse_string(reply[3].get_string_from_utf8())
	return data if data is Dictionary else {"error": "Could not read the task gateway response."}

func submit(prompt: String, session: String) -> void:
	var parts := prompt.split(" ", false, 2)
	var action := ""
	var body := {}
	match parts[0]:
		"/task", "/msg", "/cancel":
			if parts.size() == 3:
				action = {"/task": "assign", "/msg": "send_message", "/cancel": "cancel"}[parts[0]]
				body["id" if action == "cancel" else "to"] = parts[1].to_lower()
				body["text"] = parts[2]
		"/inbox":
			await poll(parts[1].to_lower() if parts.size() >= 2 else "", true)
			return
		"/journal":
			var journal := await _request("task_log", {})
			if journal.has("error"):
				notice.emit(str(journal.error))
				return
			for entry: Dictionary in journal.get("entries", []):
				notice.emit("%s · %s · %s\n%s" % [entry.event, entry.actor, entry.id, entry.get("text", "")])
			return
		_:
			var address := prompt.split(" ", false, 1)
			if address.size() == 2 and address[0].begins_with("@"):
				var agent := address[0].substr(1).to_lower()
				action = "assign" if agent in ["local-codex", "local-claude"] else "send_message"
				body = {"to": agent, "text": address[1]}
	if action.is_empty():
		notice.emit("Use /task <agent|*> <request>, @agent <message>, /inbox [agent], /cancel <id> <reason>, or /journal.")
		return
	if action == "assign":
		body["session"] = session
	var result := await _request(action, body)
	if result.has("error"):
		notice.emit(str(result.error))
	elif result.has("task"):
		_show_task(result.task, true)
	elif result.has("message"):
		notice.emit("To @%s  %s" % [result.message.to, result.message.text])
		_seen[result.message.id] = true

func poll(peer := "", explicit := false) -> void:
	if _polling and not explicit:
		return
	if not explicit:
		_polling = true
	var result := await _request("inbox", {"peer": peer})
	if not explicit:
		_polling = false
	if result.has("error"):
		if explicit:
			notice.emit(str(result.error))
		return
	for task: Dictionary in result.get("tasks", []):
		_show_task(task, explicit)
	for message: Dictionary in result.get("messages", []):
		if explicit or not _seen.has(message.id):
			var label := "To @%s" % message.to if message.from == "@player" else "@%s" % message.from
			notice.emit("%s  %s" % [label, message.text])
		_seen[message.id] = true
	if explicit and result.get("tasks", []).is_empty() and result.get("messages", []).is_empty():
		notice.emit("No tasks or messages.")

func _show_task(task: Dictionary, explicit: bool) -> void:
	var detail := str(task.get("update", task.text))
	var stamp := "%s/%s" % [task.status, task.get("updated_at", "")]
	if explicit or _status.get(task.id) != stamp:
		var recipient := str(task.owner) if not str(task.owner).is_empty() else str(task.to)
		notice.emit("%s · @%s · %s\n%s" % [task.status, recipient, task.id, detail])
	_status[task.id] = stamp
