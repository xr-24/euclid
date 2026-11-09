extends CanvasLayer
## Opt-in live statistics. No per-frame text formatting or timing queries while hidden.
var _label: Label
var _timer: Timer

func _ready() -> void:
	_label = Label.new()
	_label.position = Vector2(36, 85)
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	_label.hide()
	_timer = Timer.new()
	_timer.wait_time = 0.5
	_timer.timeout.connect(_sample)
	add_child(_timer)

func toggle() -> void:
	_label.visible = not _label.visible
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), _label.visible)
	if _label.visible:
		_sample()
		_timer.start()
	else:
		_timer.stop()

func _sample() -> void:
	var fps := Engine.get_frames_per_second()
	var gpu_ms := RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
	_label.text = "%d FPS  |  %.1f ms/frame  |  GPU %.1f ms  |  %d draws" % [
		fps, 1000.0/maxi(fps,1), gpu_ms, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)]
