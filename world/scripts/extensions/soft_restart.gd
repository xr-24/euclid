extends RefCounted
## Restart the world inside the running process: the window, the gateway connection, the engine
## and every loaded resource stay. The old world saves your place and is freed, then a hot load can
## reload scripts completely (between), and a new world is built from the main scene and restores
## your place. Used when a change cannot reach objects that are already running.

static func run(world: Node, between: Callable) -> void:
	if not world.smoke_mode:
		world._write_state(world.SAVE_PATH)
	_swap.call_deferred(world, str(world.scene_file_path), str(world._dev.capability), between)

static func _swap(world: Node, scene: String, capability: String, between: Callable) -> void:
	var tree := world.get_tree()
	var parent := world.get_parent()
	parent.remove_child(world)
	world.free()
	between.call()
	# The new world reads the Workbench credential the launcher gave the first one.
	if not capability.is_empty():
		OS.set_environment("EUCLID_WORKBENCH_TOKEN", capability)
	var next: Node = (load(scene) as PackedScene).instantiate()
	parent.add_child(next)
	tree.current_scene = next
