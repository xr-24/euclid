extends HTTPRequest
## Advertises the live catalog and runs one incoming MCP command on the main thread.

var session := Crypto.new().generate_random_bytes(16).hex_encode()
var _url: String
var _headers: PackedStringArray
var _context: Callable
var _dispatch: Callable
var _busy := false
var _last_result := {}

func configure(url: String, token: String, context: Callable, dispatch: Callable) -> void:
	_url = url
	_headers = ["Authorization: Bearer " + token, "Content-Type: application/json"]
	_context = context
	_dispatch = dispatch
	timeout = 4.0
	body_size_limit = 65536
	if url.is_empty() or token.is_empty():
		return
	var timer := Timer.new()
	timer.wait_time = 1.25
	add_child(timer)
	timer.timeout.connect(_pulse)
	timer.start()

func _pulse() -> void:
	if _busy:
		return
	_busy = true
	var body := {"session": session, "context": _context.call(), "result": _last_result}
	if request(_url + "/v1/companion/sync", _headers, HTTPClient.METHOD_POST, JSON.stringify(body)) != OK:
		_busy = false
		return
	var response: Array = await request_completed
	if response[0] == RESULT_SUCCESS and response[1] == 200:
		var data: Variant = JSON.parse_string(response[3].get_string_from_utf8())
		if data is Dictionary and data.get("command") is Dictionary:
			var command: Dictionary = data.command
			if command.get("id") != _last_result.get("id") and float(command.get("expires_at", 0)) > Time.get_unix_time_from_system():
				var value: Dictionary = await _dispatch.call(command)
				_last_result = {"id": command.id, "value": value}
	_busy = false
