extends Node
## Transport only. Agent reports are data; this client never evaluates them or controls the OS.
signal snapshot_changed(states: Dictionary, connected: bool)
var url := ""
var pending := false
var request: HTTPRequest
var last_http_status := 0
var last_result := HTTPRequest.RESULT_SUCCESS
var _token := ""
var _states := {}

func _ready() -> void:
	url = OS.get_environment("CONSTRUCT_GATEWAY_URL")
	_token = OS.get_environment("CONSTRUCT_GATEWAY_TOKEN")
	request = HTTPRequest.new()
	# Asset construction can occupy the main thread during initial load. Keep transport moving.
	request.use_threads = true
	request.timeout = 3
	request.body_size_limit = 1048576
	add_child(request)
	request.request_completed.connect(_on_result)
	var timer := Timer.new()
	timer.wait_time = 2
	timer.timeout.connect(poll)
	add_child(timer)
	timer.start()
	poll()

func poll() -> void:
	if pending:
		return
	if url.is_empty() or _token.is_empty():
		snapshot_changed.emit(_states, false)
		return
	pending = true
	if request.request(url + "/v1/world", ["Authorization: Bearer " + _token]) != OK:
		pending = false
		snapshot_changed.emit(_states, false)

func _on_result(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	pending = false
	last_http_status = code
	last_result = result
	var json := JSON.new()
	if code != 200 or json.parse(body.get_string_from_utf8()) != OK:
		snapshot_changed.emit(_states, false)
		return
	var data = json.data
	if not data is Dictionary or not data.get("agents") is Array:
		snapshot_changed.emit(_states, false)
		return
	var next := {}
	for agent in data.agents:
		if not agent is Dictionary or not agent.get("agent_id") is String:
			snapshot_changed.emit(_states, false)
			return
		next[agent.agent_id] = agent
	_states = next
	snapshot_changed.emit(_states, true)
