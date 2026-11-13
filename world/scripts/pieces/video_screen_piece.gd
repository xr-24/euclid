extends RefCounted

const Screen = preload("res://scripts/pieces/video_surface.gd")

static func build(record: Dictionary) -> Node3D:
	var screen := Screen.new()
	screen.configure(record)
	return screen

static func update_fields(node: Node3D, before: Dictionary, record: Dictionary) -> bool:
	if before.get("video_id") != record.get("video_id") or before.screen_size != record.screen_size:
		return false
	(node as Screen).update_options(record)
	return true
