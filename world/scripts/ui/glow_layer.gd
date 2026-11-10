extends ColorRect
## Screen-space bloom over a text panel. Add it as the last child of a container that stacks its
## children (MarginContainer, PanelContainer) so it covers the panel and ignores the mouse.
const Effects = preload("res://scripts/ui/code_fx.gd")
const SHADER := preload("res://shaders/ui_glow.gdshader")

func _init(strength := 1.5) -> void:
	name = "Glow"
	mouse_filter = MOUSE_FILTER_IGNORE
	focus_mode = FOCUS_NONE
	color = Color.WHITE
	var glow := ShaderMaterial.new()
	glow.shader = SHADER
	glow.set_shader_parameter("strength", strength)
	material = glow
	resized.connect(func() -> void: glow.set_shader_parameter("rect_size", size))

func _process(_delta: float) -> void:
	# The bloom pass copies the screen every frame, so it follows the shared effects switch.
	if visible != Effects.enabled:
		visible = Effects.enabled
