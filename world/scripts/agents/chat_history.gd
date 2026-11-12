extends RefCounted
## Converts the durable task and message inbox into the selected conversation's transcript.

static func read(inbox: Dictionary) -> Dictionary:
	var entries: Array[Dictionary] = []
	for task: Dictionary in inbox.get("tasks", []):
		entries.append({"at": task.at, "text": task.text, "outgoing": true})
		var reply: String = task.get("update", "")
		var status: String = task.status
		if not reply.is_empty():
			var label := "" if status in ["working", "completed"] else status.capitalize() + " · "
			entries.append({"at": task.get("updated_at", task.at), "text": label + reply, "outgoing": false})
		elif status in ["queued", "working"]:
			entries.append({"at": task.at, "text": "Queued" if status == "queued" else "Working…", "outgoing": false})
	for message: Dictionary in inbox.get("messages", []):
		entries.append({"at": message.at, "text": message.text, "outgoing": message.from == "@player"})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.outgoing and not b.outgoing if a.at == b.at else a.at < b.at)
	var lines := PackedStringArray()
	var prompts := PackedStringArray()
	var latest_reply := {}
	for entry in entries:
		if entry.outgoing:
			prompts.append(entry.text)
		elif entry.text not in ["Queued", "Working…"]:
			latest_reply = {"text": entry.text, "at": entry.at}
		lines.append(("> " if entry.outgoing else "") + entry.text)
	return {"lines": lines, "prompts": prompts, "reply": latest_reply}
