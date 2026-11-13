extends Node
## A single screen's browser and YouTube IFrame API state.

const Link = preload("res://scripts/assets/youtube_link.gd")
const EXTENSION := "res://addons/godot_cef/godot_cef.gdextension"
const TEXTURE_SIZE := Vector2i(640, 360)
var texture: Texture2D
var player_ready := false
var error := ""
var state := {}
var _options := {}
var _browser: Control
var _viewport: SubViewport
var _nearby := true

func start(source: String, loop: bool, volume: float) -> bool:
	var link := Link.parse(source)
	if link.is_empty():
		error = "Paste a YouTube video or playlist link."
		return false
	var origin := OS.get_environment("CONSTRUCT_GATEWAY_URL").trim_suffix("/")
	if not origin.begins_with("http://127.0.0.1:"):
		error = "Launch Euclid normally to connect YouTube."
		return false
	if not ClassDB.class_exists("CefTexture") and FileAccess.file_exists(EXTENSION):
		GDExtensionManager.load_extension(EXTENSION)
	if not ClassDB.class_exists("CefTexture"):
		error = "Install the browser runtime with scripts/setup-video.ps1."
		return false
	_browser = ClassDB.instantiate("CefTexture") as Control
	if _browser == null:
		error = "Could not start the YouTube player."
		return false
	_viewport = SubViewport.new()
	_viewport.size = TEXTURE_SIZE
	_viewport.disable_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_browser.size = Vector2(TEXTURE_SIZE)
	_browser.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_browser.set("enable_accelerated_osr", false)
	_browser.set("popup_policy", 0)
	_browser.set("permission_policy", 0)
	_browser.set("dialog_policy", 2)
	_browser.connect("ipc_message", _receive)
	_browser.connect("load_error", _load_error)
	_options = {"action": "options", "loop": loop, "volume": volume * 100.0}
	_browser.set("url", "%s/media/youtube#v=%s&list=%s&index=%d&loop=%d" % [
		origin, link.video, link.playlist, link.index, int(loop)])
	_viewport.add_child(_browser)
	add_child(_viewport)
	texture = _viewport.get_texture()
	return true

func set_nearby(nearby: bool) -> void:
	if _browser and nearby != _nearby:
		_nearby = nearby
		_browser.call("set_browser_hidden", not nearby)
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if nearby else SubViewport.UPDATE_DISABLED

func options(loop: bool, volume: float) -> void:
	var next := {"action": "options", "loop": loop, "volume": volume * 100.0}
	if next != _options:
		_options = next
		_send(_options)

func command(action: String) -> void:
	_send({"action": action})

func _send(message: Dictionary) -> void:
	if player_ready and _browser:
		_browser.call("eval", "window.euclidVideo?.(" + JSON.stringify(message) + ")")

func _load_error(_url: String, _code: int, _message: String) -> void:
	error = "YouTube could not load. Check your connection and launch Euclid again."

func _receive(message: String) -> void:
	if message.length() > 1024:
		return
	var next: Variant = JSON.parse_string(message)
	if not next is Dictionary:
		return
	var became_ready: bool = not player_ready and next.get("ready") == true
	player_ready = next.get("ready") == true
	error = str(next.get("error", "")).left(180)
	state = next
	if became_ready:
		_send(_options)
