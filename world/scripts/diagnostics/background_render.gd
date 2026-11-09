extends SceneTree
## GPU capture without a visible window; the native parent is owned by background-render.py.
func _initialize() -> void:
	call_deferred("_start")

func _start() -> void:
	Engine.max_fps = 60
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1440,900)
	viewport.own_world_3d = true
	viewport.use_taa = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var scene := load("res://main.tscn") as PackedScene
	viewport.add_child(scene.instantiate())
