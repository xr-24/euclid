extends RefCounted

const YouTube = preload("res://scripts/assets/youtube_link.gd")
const Screen = preload("res://scripts/pieces/video_surface.gd")

static func valid_record(record: Dictionary) -> bool:
	var url: String = record.get("youtube_url", "")
	return url.is_empty() or not YouTube.parse(url).is_empty()

static func build(record: Dictionary) -> Node3D:
	var screen := Screen.new()
	screen.configure(record)
	return screen

static func update_fields(node: Node3D, before: Dictionary, record: Dictionary) -> bool:
	if before.get("video_id") != record.get("video_id") or before.get("youtube_url") != record.get("youtube_url") \
			or before.screen_size != record.screen_size:
		return false
	(node as Screen).update_options(record)
	return true
