extends Node
## Long-polls the gateway's agent activity feed (gateway/agent-activity.mjs) and emits each event.
## One request waits until there is something new, so the feed costs little while agents are idle.

const Graphics = preload("res://scripts/rendering/graphics_settings.gd")
const WAIT := 20

signal activity(entry: Dictionary)

var _url := ""
var _headers := PackedStringArray()
var _since := -1
var _running := false

func configure(url: String, token: String, capability: String) -> void:
	_url = url
	_headers = ["Authorization: Bearer " + token, "X-Euclid-Workbench: " + capability, "Content-Type: application/json"]
	if not _running:
		_run()

func _run() -> void:
	_running = true
	while is_inside_tree():
		if Graphics.agent_activity == "off" or _url.is_empty():
			# Off: skip what happened meanwhile rather than replaying it later.
			_since = -1
			await get_tree().create_timer(1.0).timeout
			continue
		# The first request only learns where the feed is, so old events are not replayed.
		var first := _since < 0
		var reply := await _post({"since": maxi(_since, 0), "wait": 0 if first else WAIT})
		if not is_inside_tree():
			return
		if not reply.has("events"):
			await get_tree().create_timer(3.0).timeout
			continue
		var next := int(reply.get("next", 0))
		if not first and Graphics.agent_activity != "off":
			for entry in reply.events:
				if entry is Dictionary:
					activity.emit(entry)
		_since = next

func _post(body: Dictionary) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = WAIT + 10
	http.body_size_limit = 1024 * 1024
	add_child(http)
	if http.request(_url + "/v1/activity/feed", _headers, HTTPClient.METHOD_POST, JSON.stringify(body)) != OK:
		http.queue_free()
		return {}
	var reply: Array = await http.request_completed
	http.queue_free()
	if int(reply[1]) != 200:
		return {}
	var data: Variant = JSON.parse_string(reply[3].get_string_from_utf8())
	return data if data is Dictionary else {}
