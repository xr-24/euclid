extends Node
## Voice preferences stay in Godot. Sign-in, account voices and synthesis live in the gateway.

signal changed
signal voice_selected(id: String)

const REQUEST_TIMEOUT := 32.0
const MAX_RESPONSE_BYTES := 4 * 1024 * 1024
const DEFAULT_SAMPLE := "This is how I’ll sound in Euclid."
## Replies waiting for the current one to finish. Past this many, the oldest are dropped.
const QUEUE := 4

var enabled := false
var selected := ""
var voices: Array = []
var status := ""
var can_connect := false
var loading := false
var _url := ""
var _headers := PackedStringArray()
var _audio := AudioStreamPlayer.new()
var _speech: HTTPRequest
var _catalog_request: HTTPRequest
var _pending: Array[String] = []

func _ready() -> void:
	add_child(_audio)
	_audio.finished.connect(_next)

func configure(url: String, token: String, capability: String) -> void:
	_url = url
	_headers = ["Authorization: Bearer " + token, "X-Euclid-Workbench: " + capability, "Content-Type: application/json"]

func toggle(value: bool) -> void:
	enabled = value
	if not enabled:
		_pending.clear()
		stop()
		status = ""
		can_connect = false
	changed.emit()
	if enabled and not loading:
		_load_voices(true)

## Turn voice back on at launch, without starting a sign-in.
func resume() -> void:
	if enabled:
		return
	enabled = true
	changed.emit()
	_load_voices(false)

## Speak a reply after whatever is playing now, instead of cutting it off.
func say(line: String) -> void:
	if not enabled or line.strip_edges().is_empty():
		return
	if is_instance_valid(_speech) or _audio.playing:
		_pending.append(line)
		while _pending.size() > QUEUE:
			_pending.pop_front()
		return
	speak(line)

func _next() -> void:
	if not _pending.is_empty() and not is_instance_valid(_speech) and not _audio.playing:
		speak(_pending.pop_front())

func retry() -> void:
	if enabled and not loading:
		_load_voices(can_connect)

func select(id: String) -> void:
	if id == selected or not voices.any(func(voice: Dictionary) -> bool: return voice.id == id):
		return
	stop()
	selected = id
	voice_selected.emit(id)
	status = ""
	changed.emit()

func preview() -> void:
	speak(DEFAULT_SAMPLE)

func stop() -> void:
	if is_instance_valid(_speech):
		_speech.cancel_request()
		_speech.queue_free()
		_speech = null
	_audio.stop()
	_audio.stream = null

func speak(line: String) -> void:
	var body := line.strip_edges().left(4000)
	if not enabled or loading or selected.is_empty() or can_connect or body.is_empty():
		return
	stop()
	status = ""
	_speech = _request("synthesize", {"voice": selected, "text": body})
	if _speech == null:
		status = "Could not reach the voice gateway."
	else:
		_speech.request_completed.connect(_play)
	changed.emit()

func _play(result: int, code: int, _response_headers: PackedStringArray, data: PackedByteArray) -> void:
	_speech.queue_free()
	_speech = null
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		var audio := AudioStreamMP3.load_from_buffer(data)
		if audio != null:
			_audio.stream = audio
			_audio.play()
			return
		status = "Could not play the audio returned by ElevenLabs."
		_next()
	else:
		var reply := _json_reply(result, data)
		status = str(reply.get("error", "Could not play the ElevenLabs voice."))
		can_connect = bool(reply.get("connect", false))
		_pending.clear()
	changed.emit()

func _load_voices(connect_if_needed: bool) -> void:
	if _url.is_empty():
		status = "Launch Euclid normally to use ElevenLabs."
		changed.emit()
		return
	loading = true
	status = "Loading voices…"
	changed.emit()
	var reply := await _post("voices", {"refresh": true})
	if enabled and bool(reply.get("connect", false)) and connect_if_needed:
		reply = await _authorize()
	elif enabled and bool(reply.get("connecting", false)):
		reply = await _wait_for_approval()
	loading = false
	if enabled:
		can_connect = bool(reply.get("connect", false))
		status = str(reply.get("error", ""))
		if reply.has("voices"):
			voices = reply.voices
			_select_available_voice()
	changed.emit()

func _select_available_voice() -> void:
	if voices.is_empty():
		selected = ""
		status = "No voices are available in this ElevenLabs account."
		return
	if not voices.any(func(voice: Dictionary) -> bool: return voice.id == selected):
		selected = ""
		if voices.size() == 1:
			select(voices[0].id)

func _authorize() -> Dictionary:
	var reply := await _post("authorize")
	if not enabled or reply.has("error"):
		return reply
	var link: String = reply.get("authorization_url", "")
	if not link.begins_with("https://elevenlabs.io/app/oauth/authorize?") or OS.shell_open(link) != OK:
		return {"error": "Could not open ElevenLabs in your browser.", "connect": true}
	return await _wait_for_approval()

func _wait_for_approval() -> Dictionary:
	status = "Finish authorizing ElevenLabs in your browser…"
	changed.emit()
	while enabled:
		await get_tree().create_timer(1.5).timeout
		if not enabled:
			break
		var reply := await _post("voices")
		if not reply.get("connecting", false):
			return reply
	return {}

func _post(route: String, body := {}) -> Dictionary:
	_catalog_request = _request(route, body)
	if _catalog_request == null:
		return {"error": "Could not reach the voice gateway."}
	var reply: Array = await _catalog_request.request_completed
	_catalog_request.queue_free()
	_catalog_request = null
	return _json_reply(reply[0], reply[3])

func _request(route: String, body: Dictionary) -> HTTPRequest:
	var request := HTTPRequest.new()
	request.timeout = REQUEST_TIMEOUT
	request.body_size_limit = MAX_RESPONSE_BYTES
	add_child(request)
	if request.request(_url + "/v1/speech/" + route, _headers, HTTPClient.METHOD_POST, JSON.stringify(body)) == OK:
		return request
	request.queue_free()
	return null

func _json_reply(result: int, data: PackedByteArray) -> Dictionary:
	if result == HTTPRequest.RESULT_SUCCESS and not data.is_empty():
		var parsed: Variant = JSON.parse_string(data.get_string_from_utf8())
		if parsed is Dictionary:
			return parsed
	return {"error": "The voice gateway did not respond. Try again."}
