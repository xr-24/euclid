extends RefCounted

static func run(world: Node3D) -> void:
	var output := OS.get_environment("EUCLID_CAPTURE_DIR")
	var tree := world.get_tree()
	if output.is_empty():
		tree.quit(1)
		return
	for entry: Dictionary in world.manifest.zones.slice(0, 12):
		var zone: String = entry.id
		world._load_zone(zone)
		world._close_panel()
		for frame in range(30):
			await tree.process_frame
		await RenderingServer.frame_post_draw
		var image := world.get_viewport().get_texture().get_image()
		if image == null or image.is_empty():
			tree.quit(1)
			return
		image.resize(640, 400, Image.INTERPOLATE_BILINEAR)
		if image.save_jpg(output.path_join(zone + ".jpg"), 0.82) != OK:
			tree.quit(1)
			return
	print("EUCLID_DRAFT_VIEWS_OK")
	tree.quit()
