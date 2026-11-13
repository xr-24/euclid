extends StaticBody3D
## A 3D screen driven by the local player's decoded video texture.

const Library = preload("res://scripts/assets/video_library.gd")
const ScreenShader = preload("res://shaders/video_screen.gdshader")
var _player: VideoStreamPlayer
var _material: ShaderMaterial
var _settings: Dictionary
var _shown := false
var _requested_play := false
var _in_range := true

func configure(record: Dictionary) -> void:
	_settings = record.duplicate()
	var dims: Array = record.screen_size
	var size := Vector2(dims[0], dims[1])
	var frame := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(size.x + 0.09, size.y + 0.09, 0.075)
	frame.mesh = box
	frame.position.z = -0.03
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color("263441")
	metal.metallic = 0.55
	metal.roughness = 0.4
	frame.material_override = metal
	add_child(frame)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box.size
	collider.shape = shape
	collider.position = frame.position
	add_child(collider)
	set_meta("piece_interaction", self)
	var surface := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = size
	surface.mesh = quad
	surface.position.z = 0.012
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	surface.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	surface.add_to_group("private_world_surfaces")
	_material = ShaderMaterial.new()
	_material.shader = ScreenShader
	_material.set_shader_parameter("screen_aspect", size.aspect())
	surface.material_override = _material
	add_child(surface)

func _ready() -> void:
	var path := Library.path_for(str(_settings.get("video_id", "")))
	if path.is_empty():
		return
	var stream := VideoStreamTheora.new()
	stream.file = path
	_player = VideoStreamPlayer.new()
	_player.name = "Playback"
	_player.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player.size = Vector2.ONE
	_player.self_modulate.a = 0.0
	_player.stream = stream
	_player.loop = _settings.get("loop", true)
	_player.volume = float(_settings.get("volume", 0.8))
	add_child(_player)
	_player.finished.connect(_finished)
	visibility_changed.connect(_sync_playback)
	if _settings.get("autoplay", true):
		interact()

func interaction_label() -> String:
	if _player == null:
		return ""
	return "Pause video" if _requested_play else "Play video"

func interact() -> void:
	playback("pause" if _requested_play else "play")

func playback(action: String) -> Dictionary:
	if _player == null:
		return {"ok": false, "message": "Assign an imported video to this screen first."}
	match action:
		"play":
			_requested_play = true
			_sync_playback()
		"pause":
			_requested_play = false
			_sync_playback()
		"restart":
			_player.stop()
			_requested_play = true
			_sync_playback()
	var playing := _player.is_playing() and not _player.paused
	return {"ok": true, "playing": playing, "position": _player.stream_position,
		"message": "Video playing." if playing else "Video paused."}

func _sync_playback() -> void:
	var play := _requested_play and _in_range and is_visible_in_tree()
	_player.paused = not play
	if play and not _player.is_playing():
		_player.play()

func _finished() -> void:
	_requested_play = false

func update_options(record: Dictionary) -> void:
	if _player:
		_player.loop = record.get("loop", true)
		_player.volume = float(record.get("volume", 0.8))
		if record.get("autoplay", true) != _settings.get("autoplay", true):
			playback("play" if record.get("autoplay", true) else "pause")
	_settings = record.duplicate()

func _refresh_frame() -> void:
	var texture := _player.get_video_texture()
	if texture == null or texture.get_height() <= 0:
		return
	_material.set_shader_parameter("video_frame", texture)
	_material.set_shader_parameter("video_aspect", float(texture.get_width()) / texture.get_height())
	_material.set_shader_parameter("has_video", true)
	_shown = true

func _process(_delta: float) -> void:
	if _player == null:
		return
	if not _shown and _player.is_playing():
		_refresh_frame()
	# VideoStreamPlayer audio is 2D. Attenuate it from the panel's world position.
	var camera := get_viewport().get_camera_3d()
	if camera:
		var distance := camera.global_position.distance_to(global_position)
		var nearby := distance < 38.0 and is_visible_in_tree()
		if nearby != _in_range:
			_in_range = nearby
			_sync_playback()
		_player.volume = float(_settings.get("volume", 0.8)) * (1.0 - smoothstep(2.0, 12.0, distance))
