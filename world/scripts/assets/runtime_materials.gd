extends RefCounted
## Cached material maps are data in the user directory. Terrain records keep stable IDs.

const MAPS := ["albedo", "normal", "orm"]
const LIMIT := 5 * 1024 * 1024
static var cache_root := "user://runtime-materials"
static var _id := RegEx.create_from_string("^[a-z0-9_]{1,64}$")
static var _images := {}
static var _mutex := Mutex.new()

static func valid_id(id: Variant) -> bool:
	return id is String and id not in ["earth", "sand", "rock"] and _id.search(id) != null

static func folder(id: String) -> String:
	return cache_root.path_join(id)

static func info(id: String) -> Dictionary:
	if not valid_id(id):
		return {}
	var file := FileAccess.open(folder(id).path_join("material.json"), FileAccess.READ)
	if file == null or file.get_length() > 8192:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or parsed.get("id") != id or not parsed.get("name") is String:
		return {}
	for key in MAPS:
		if not FileAccess.file_exists(folder(id).path_join(key + ".jpg")):
			return {}
	return parsed

static func installed() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(cache_root):
		return results
	for id in DirAccess.get_directories_at(cache_root):
		var material := info(id)
		if not material.is_empty():
			results.append(material)
	results.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.name.nocasecmp_to(b.name) < 0)
	return results

static func images(path: String) -> Array[Image]:
	var result: Array[Image] = []
	for key in MAPS:
		var file := FileAccess.open(path.path_join(key + ".jpg"), FileAccess.READ)
		if file == null or file.get_length() > LIMIT:
			return []
		var image := Image.new()
		if image.load_jpg_from_buffer(file.get_buffer(file.get_length())) != OK:
			return []
		if image.get_width() > 1024 or image.get_height() > 1024 or image.is_empty():
			return []
		image.convert(Image.FORMAT_RGB8)
		if image.get_size() != Vector2i(1024, 1024):
			image.resize(1024, 1024, Image.INTERPOLATE_BILINEAR)
		image.generate_mipmaps(key == "normal")
		result.append(image)
	return result

static func missing_image(map: int) -> Image:
	var image := Image.create_empty(1024, 1024, false, Image.FORMAT_RGB8)
	image.fill([Color("ad9274"), Color(0.5, 0.5, 1.0), Color(1.0, 0.8, 0.0)][map])
	image.generate_mipmaps()
	return image

static func cached_images(id: String) -> Array[Image]:
	if not valid_id(id):
		return []
	_mutex.lock()
	var cached: Array[Image] = _images.get(id, [] as Array[Image])
	_mutex.unlock()
	if not cached.is_empty():
		return cached
	if info(id).is_empty():
		return []
	var decoded := images(folder(id))
	if not decoded.is_empty():
		remember(id, decoded)
	return decoded

static func remember(id: String, decoded: Array[Image]) -> void:
	_mutex.lock()
	if _images.size() >= 10:
		_images.erase(_images.keys()[0])
	_images[id] = decoded
	_mutex.unlock()
