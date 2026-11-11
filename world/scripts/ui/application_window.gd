extends VBoxContainer

const TerminalView = preload("res://scripts/ui/terminal_view.gd")

func setup(app_id: String, close: Callable, connection: Dictionary, station: Node3D) -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var bar := HBoxContainer.new()
	add_child(bar)
	var title := Label.new()
	title.text = "Terminal" if app_id == "terminal" else "Images"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(title)
	var back := Button.new()
	back.text = "Return to world"
	back.pressed.connect(close)
	bar.add_child(back)
	if app_id == "terminal":
		if connection.capability.is_empty():
			var unavailable := Label.new()
			unavailable.text = "Open Euclid through its launcher to use the terminal."
			add_child(unavailable)
			return
		var terminal := TerminalView.new()
		add_child(terminal)
		terminal.setup(connection.url, connection.token, connection.capability)
		if is_instance_valid(station) and station.has_meta("terminal_screen"):
			var surface := station.get_node_or_null("TerminalSurface") as MeshInstance3D
			if surface == null:
				surface = _mount_screen(station)
			var mirror: TerminalView = surface.get_node("Screen/Terminal")
			terminal.frame_changed.connect(mirror.mirror_frame)
			surface.show()
		terminal.start.call_deferred()
		terminal.grab_focus.call_deferred()
	else:
		_image_viewer(bar, back)

func _image_viewer(bar: HBoxContainer, back: Button) -> void:
	var open := Button.new()
	open.text = "Open image…"
	bar.add_child(open)
	bar.move_child(open, back.get_index())
	var chooser := FileDialog.new()
	chooser.title = "Open image"
	chooser.access = FileDialog.ACCESS_FILESYSTEM
	chooser.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	chooser.filters = PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp ; Images"])
	add_child(chooser)
	open.pressed.connect(func() -> void: chooser.popup_centered_ratio(0.65))
	var preview := TextureRect.new()
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(preview)
	var status := Label.new()
	add_child(status)
	chooser.file_selected.connect(func(path: String) -> void:
		var image := Image.load_from_file(path)
		if image == null or image.is_empty():
			status.text = "Could not open that image."
			return
		preview.texture = ImageTexture.create_from_image(image)
		status.text = path.get_file())

static func _mount_screen(station: Node3D) -> MeshInstance3D:
	var surface := MeshInstance3D.new()
	surface.name = "TerminalSurface"
	surface.position = Vector3(0, 1.265, 0.085)
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	surface.add_to_group("private_world_surfaces")
	var plane := QuadMesh.new()
	plane.size = Vector2(1.24, 0.52)
	surface.mesh = plane
	station.add_child(surface)
	var viewport := SubViewport.new()
	viewport.name = "Screen"
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	surface.add_child(viewport)
	var mirror := TerminalView.new()
	mirror.name = "Terminal"
	viewport.add_child(mirror)
	mirror.setup_display()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = viewport.get_texture()
	surface.material_override = material
	surface.hide()
	return surface
