extends Node
## Transport for the embedded terminal. The gateway keeps the shell and its screen, so the world can
## restart and attach again. One request waits for screen changes, one sends keystrokes and resizes
## in order, and one handles opening, listing and closing.

signal screen_changed(session: Dictionary)
signal failed(message: String)

var session_id := ""
var version := -1
## How many lines the view is scrolled back into history. Zero follows the live screen.
var offset := 0
var _url := ""
var _headers := PackedStringArray()
var _reader := HTTPRequest.new()
var _input := HTTPRequest.new()
var _control := HTTPRequest.new()
var _queue: Array = []
var _writing := false
var _reading := false

func configure(url: String, token: String, capability: String) -> void:
	_url = url + "/v1/terminal/"
	_headers = PackedStringArray(["Authorization: Bearer " + token, "X-Euclid-Workbench: " + capability, "Content-Type: application/json"])
	_reader.timeout = 35.0
	_input.timeout = 15.0
	_control.timeout = 30.0
	for node in [_reader, _input, _control]:
		add_child(node)

## Attaches to the newest running shell, or opens one. Returns an error message, or "" on success.
func attach(cols: int, rows: int, shell := "powershell") -> String:
	var listed := await _post(_control, "list", {})
	if listed.has("error"):
		return str(listed.error)
	session_id = ""
	for entry in listed.get("sessions", []):
		if entry is Dictionary and entry.get("alive", false):
			session_id = str(entry.id)
	if session_id.is_empty():
		var opened := await _post(_control, "open", {"shell": shell, "cols": cols, "rows": rows})
		if opened.has("error"):
			return str(opened.error)
		session_id = str(opened.id)
	else:
		resize(cols, rows)
	version = -1
	offset = 0
	_read_loop()
	return ""

## Ends the current shell. The next attach opens a new one.
func close_session() -> void:
	if session_id.is_empty():
		return
	var id := session_id
	session_id = ""
	await _post(_control, "close", {"id": id})

func send_text(data: String) -> void:
	if not session_id.is_empty() and not data.is_empty():
		_enqueue("write", {"id": session_id, "data": data})

func resize(cols: int, rows: int) -> void:
	if not session_id.is_empty():
		_enqueue("resize", {"id": session_id, "cols": cols, "rows": rows})

## Shows history `lines` back from the live screen, at once.
func scroll_to(lines: int) -> void:
	offset = maxi(0, lines)
	if session_id.is_empty():
		return
	var result := await _post(_control, "read", {"id": session_id, "since": -1, "wait": 0, "offset": offset})
	if not result.has("error"):
		screen_changed.emit(result)

func _read_loop() -> void:
	if _reading:
		return
	_reading = true
	while not session_id.is_empty() and is_inside_tree():
		var id := session_id
		var result := await _post(_reader, "read", {"id": id, "since": version, "wait": 20000, "offset": offset})
		if id != session_id:
			continue
		if result.has("error"):
			failed.emit(str(result.error))
			if str(result.error).contains("no terminal session"):
				session_id = ""
				break
			await get_tree().create_timer(1.0).timeout
			continue
		version = int(result.screen.version)
		screen_changed.emit(result)
		if not result.get("alive", true):
			break
	_reading = false

# Fast typing becomes one write, and only the latest size matters.
func _enqueue(action: String, body: Dictionary) -> void:
	var last: Array = _queue.back() if not _queue.is_empty() else []
	if not last.is_empty() and last[0] == action and last[1].id == body.id and action == "write":
		last[1]["data"] = str(last[1].data) + str(body.data)
	elif not last.is_empty() and last[0] == action and action == "resize":
		_queue[_queue.size() - 1] = [action, body]
	else:
		_queue.append([action, body])
	_flush()

func _flush() -> void:
	if _writing:
		return
	_writing = true
	while not _queue.is_empty():
		var next: Array = _queue.pop_front()
		var result := await _post(_input, next[0], next[1])
		if result.has("error"):
			failed.emit(str(result.error))
	_writing = false

func _post(node: HTTPRequest, action: String, body: Dictionary) -> Dictionary:
	if node.request(_url + action, _headers, HTTPClient.METHOD_POST, JSON.stringify(body)) != OK:
		return {"error": "The terminal could not reach its local gateway."}
	var response: Array = await node.request_completed
	if response[0] != HTTPRequest.RESULT_SUCCESS:
		return {"error": "The terminal lost its local gateway."}
	var data: Variant = JSON.parse_string(response[3].get_string_from_utf8())
	if not data is Dictionary:
		return {"error": "The gateway returned an invalid terminal response."}
	if response[1] != 200 and not data.has("error"):
		data["error"] = "The gateway answered %d." % response[1]
	return data

## A hot reload of this script ends the read and write loops mid-request; start them again.
func _hot_reload() -> void:
	_reader.cancel_request()
	_input.cancel_request()
	_reading = false
	_writing = false
	if not session_id.is_empty():
		_read_loop()
	_flush()
