extends RefCounted
## Imported panoramas are cached outside the project and identified by a stable sky key.

const LIMIT := 12 * 1024 * 1024
const PREFIX := "polyhaven_"
static var directory := "user://runtime-skies"
static var _key := RegEx.create_from_string("^polyhaven_[a-z0-9_]{1,64}\\.hdr$")
static var _textures := {}

static func valid_id(id: String) -> bool:
	return _key.search(PREFIX + id + ".hdr") != null

static func installed() -> Array:
	if not DirAccess.dir_exists_absolute(directory):
		return []
	return Array(DirAccess.get_files_at(directory)).filter(func(name: String) -> bool:
		return _key.search(name) != null)

static func read(path: String) -> Image:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > LIMIT:
		return null
	var header := file.get_buffer(mini(8192, file.get_length())).get_string_from_ascii()
	var dims := RegEx.create_from_string("\\n-Y ([0-9]+) \\+X ([0-9]+)\\r?\\n").search(header)
	if dims == null or int(dims.get_string(1)) > 1024 or int(dims.get_string(2)) > 2048:
		return null
	var image := Image.load_from_file(path)
	if image == null or image.is_empty() or image.get_width() > 2048 or image.get_height() > 1024:
		return null
	return image

static func texture(key: String) -> Texture2D:
	if _key.search(key) == null:
		return null
	if _textures.has(key):
		return _textures[key]
	var image := read(directory.path_join(key))
	if image == null:
		return null
	return remember(key, image)

static func remember(key: String, image: Image) -> Texture2D:
	if _textures.size() >= 4:
		_textures.erase(_textures.keys()[0])
	var loaded := ImageTexture.create_from_image(image)
	_textures[key] = loaded
	return loaded
