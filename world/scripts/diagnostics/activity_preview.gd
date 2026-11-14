extends SceneTree
## Renders an agent's activity panel and pose for sample feed events, for reviewing the look.
## godot --path world --script res://scripts/diagnostics/activity_preview.gd -- <events JSON> <output dir> [progress list]
## Progress values are fractions of each event's play time, such as 0.3,0.9.

const Avatar = preload("res://scripts/agents/binary_avatar.gd")
const Card = preload("res://scripts/agents/activity_card.gd")
const View = preload("res://scripts/agents/activity_view.gd")

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var events: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var output := args[1]
	var stops := (args[2] if args.size() > 2 else "0.35,0.95").split(",")
	DirAccess.make_dir_recursive_absolute(output)
	var stage := Node3D.new()
	root.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("10161f")
	stage.add_child(environment)
	var body := Avatar.projection(Color("ff4813"), false, Color("ffbc55"))
	stage.add_child(body)
	var card := Card.new()
	stage.add_child(card)
	var camera := Camera3D.new()
	camera.fov = 50
	stage.add_child(camera)
	var view: String = args[3] if args.size() > 3 else "card"
	var side := view != "card"
	var eye := {"card": Vector3(0.25, 1.25, 2.2), "side": Vector3(2.4, 0.6, 0.6), "close": Vector3(0.75, 0.85, 1.55),
		"front": Vector3(0.0, 0.7, 1.4), "back": Vector3(0.0, 0.7, -1.4)}
	camera.look_at_from_position(eye.get(view, eye.card), Vector3(0, 0.45 if side else 1.05, 0))
	card.visible = not side
	camera.make_current()
	await process_frame
	var index := 0
	for entry: Dictionary in events:
		for stop in stops:
			card._queue = [entry]
			card._start()
			card._time = View.duration(entry) * float(stop)
			card._view.time = card._time
			if body.has_method("set_activity"):
				body.set_activity(str(entry.kind))
				# Hold the motion fully blended in, part way through its loop.
				for layer: Dictionary in body._layers:
					layer.weight = 1.0 if layer == body._layers.back() and layer.on else 0.0
					layer.time = float(layer.clip.duration) * float(stop)
				body.set_hover_time(0.0)
				for child in body.get_children():
					if "leaving" in child and child != body.prop():
						child.free()
				if body.prop():
					body.prop().settle()
					body.prop()._place()
			for frame in 3:
				await process_frame
			var image := root.get_viewport().get_texture().get_image()
			image.save_png(output.path_join("%02d_%s_%s.png" % [index, entry.kind, stop]))
		index += 1
	quit()
