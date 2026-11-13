extends RefCounted

static var _url := RegEx.create_from_string("^https://((?:www[.]|m[.]|music[.])?youtube[.]com|youtu[.]be)(/[^?#]*)(?:[?]([^#]*))?(?:#.*)?$")
static var _video := RegEx.create_from_string("^[A-Za-z0-9_-]{11}$")
static var _playlist := RegEx.create_from_string("^[A-Za-z0-9_-]{2,128}$")

static func parse(source: String) -> Dictionary:
	var match_url := _url.search(source.strip_edges())
	if match_url == null or source.length() > 1024:
		return {}
	var path := match_url.get_string(2).split("/", false)
	if path.is_empty():
		return {}
	var query := {}
	for pair in match_url.get_string(3).split("&", false):
		var item := pair.split("=", true, 1)
		if item.size() == 2 and not query.has(item[0]):
			query[item[0]] = item[1].uri_decode()
	var video := ""
	if match_url.get_string(1) == "youtu.be" and path.size() == 1:
		video = path[0]
	elif path.size() == 1 and path[0] == "watch":
		video = query.get("v", "")
	elif path.size() == 2 and path[0] in ["shorts", "live", "embed"]:
		video = path[1] if path[1] != "videoseries" else ""
	elif path.size() != 1 or path[0] != "playlist":
		return {}
	var playlist: String = query.get("list", "")
	if (not video.is_empty() and _video.search(video) == null) or (not playlist.is_empty() and _playlist.search(playlist) == null):
		return {}
	if video.is_empty() and playlist.is_empty():
		return {}
	var index: String = query.get("index", "")
	return {"video": video, "playlist": playlist, "index": clampi(int(index), 0, 10000) if index.is_valid_int() else 0}
