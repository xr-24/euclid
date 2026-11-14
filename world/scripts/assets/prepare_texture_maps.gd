extends SceneTree
## Headless image conversion for the gateway. Reads staged images only, never the source model.

const MAX_EDGE := 8192
const TILE := Vector2i(1024, 1024)

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or args[0] not in ["material", "sky"]:
		quit(1)
		return
	var folder: String = args[1]
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("input.json")))
	if not data is Array:
		quit(1)
		return
	for candidate: Dictionary in data:
		var ok := _sky(folder, candidate.maps) if args[0] == "sky" else _material(folder, candidate)
		if ok:
			print("EUCLID_TEXTURE_MAPS_OK")
			quit()
			return
	quit(1)

static func _source(folder: String, maps: Dictionary, key: String) -> Image:
	if not maps.has(key):
		return null
	var bytes := FileAccess.get_file_as_bytes(folder.path_join(maps[key]))
	if bytes.is_empty():
		return null
	var dimensions := _dimensions(bytes)
	if dimensions.x < 1 or dimensions.y < 1 or dimensions.x > MAX_EDGE or dimensions.y > MAX_EDGE:
		return null
	var image := Image.new()
	var error := image.load_png_from_buffer(bytes) if str(maps[key]).ends_with(".png") else image.load_jpg_from_buffer(bytes)
	return image if error == OK and not image.is_empty() else null

static func _dimensions(bytes: PackedByteArray) -> Vector2i:
	if bytes.size() < 24:
		return Vector2i.ZERO
	if bytes[0] == 0x89 and bytes.slice(1, 4).get_string_from_ascii() == "PNG":
		return Vector2i(_u16(bytes, 16) * 65536 + _u16(bytes, 18), _u16(bytes, 20) * 65536 + _u16(bytes, 22))
	if bytes[0] != 0xff or bytes[1] != 0xd8:
		return Vector2i.ZERO
	var offset := 2
	while offset + 9 < bytes.size() and bytes[offset] == 0xff:
		var marker := bytes[offset + 1]
		if marker in [0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf]:
			return Vector2i(_u16(bytes, offset + 7), _u16(bytes, offset + 5))
		var length := _u16(bytes, offset + 2)
		if length < 2 or marker == 0xda:
			break
		offset += 2 + length
	return Vector2i.ZERO

static func _u16(bytes: PackedByteArray, offset: int) -> int:
	return bytes[offset] * 256 + bytes[offset + 1]

static func _tile(image: Image) -> PackedByteArray:
	image.convert(Image.FORMAT_RGB8)
	if image.get_size() != TILE:
		image.resize(TILE.x, TILE.y, Image.INTERPOLATE_LANCZOS)
	return image.get_data()

static func _material(folder: String, candidate: Dictionary) -> bool:
	var maps: Dictionary = candidate.maps
	var albedo := _source(folder, maps, "albedo")
	if albedo == null or albedo.get_width() != albedo.get_height():
		return false
	var normal := _source(folder, maps, "normal")
	var surface := _source(folder, maps, "rough_metal")
	var ambient := _source(folder, maps, "occlusion")
	if (maps.has("normal") and normal == null) or (maps.has("rough_metal") and surface == null) or (maps.has("occlusion") and ambient == null):
		return false
	var factors: Dictionary = candidate.factors
	var color: Array = factors.albedo
	var colors := _tile(albedo)
	var normals := _tile(normal) if normal else PackedByteArray()
	var surfaces := _tile(surface) if surface else PackedByteArray()
	var ambients := _tile(ambient) if ambient else PackedByteArray()
	var normal_scale := maxf(0.0, float(factors.normal))
	var occlusion := clampf(float(factors.occlusion), 0.0, 1.0)
	var roughness := clampf(float(factors.roughness), 0.0, 1.0)
	var metallic := clampf(float(factors.metallic), 0.0, 1.0)
	var orm := PackedByteArray()
	orm.resize(colors.size())
	if normals.is_empty():
		normals.resize(colors.size())
		normals.fill(128)
	for index in range(0, colors.size(), 3):
		if color != [1, 1, 1]:
			var linear := Color(colors[index] / 255.0, colors[index + 1] / 255.0, colors[index + 2] / 255.0).srgb_to_linear()
			linear = Color(linear.r * clampf(color[0], 0.0, 1.0), linear.g * clampf(color[1], 0.0, 1.0),
				linear.b * clampf(color[2], 0.0, 1.0)).linear_to_srgb()
			colors[index] = roundi(linear.r * 255.0)
			colors[index + 1] = roundi(linear.g * 255.0)
			colors[index + 2] = roundi(linear.b * 255.0)
		if not normal:
			normals[index + 2] = 255
		elif normal_scale != 1.0:
			var direction := Vector3((normals[index] / 127.5 - 1.0) * normal_scale,
				(normals[index + 1] / 127.5 - 1.0) * normal_scale, normals[index + 2] / 127.5 - 1.0).normalized()
			normals[index] = roundi(127.5 * (1.0 + direction.x))
			normals[index + 1] = roundi(127.5 * (1.0 + direction.y))
			normals[index + 2] = roundi(127.5 * (1.0 + direction.z))
		orm[index] = roundi(lerpf(255.0, ambients[index] if ambient else 255.0, occlusion))
		orm[index + 1] = roundi((surfaces[index + 1] if surface else 255.0) * roughness)
		orm[index + 2] = roundi((surfaces[index + 2] if surface else 255.0) * metallic)
	return _save_tile(folder, "albedo", colors) and _save_tile(folder, "normal", normals) and _save_tile(folder, "orm", orm)

static func _save_tile(folder: String, key: String, pixels: PackedByteArray) -> bool:
	var image := Image.create_from_data(TILE.x, TILE.y, false, Image.FORMAT_RGB8, pixels)
	return image.save_jpg(folder.path_join(key + ".jpg"), 0.95) == OK

static func _sky(folder: String, maps: Dictionary) -> bool:
	var image := _source(folder, maps, "panorama")
	if image == null or image.get_width() < 8 or image.get_width() != image.get_height() * 2:
		return false
	if image.get_width() > 2048:
		image.resize(2048, 1024, Image.INTERPOLATE_LANCZOS)
	image.convert(Image.FORMAT_RGB8)
	var file := FileAccess.open(folder.path_join("panorama.hdr"), FileAccess.WRITE)
	if file == null:
		return false
	var width := image.get_width()
	var height := image.get_height()
	file.store_string("#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y %d +X %d\n" % [height, width])
	# Radiance scanlines store the RGBE channels separately. Literal packets are at most 128 bytes.
	for y in height:
		file.store_buffer(PackedByteArray([2, 2, width >> 8, width & 255]))
		var scanline := PackedByteArray()
		scanline.resize(width * 4)
		for x in width:
			var pixel := image.get_pixel(x, y).srgb_to_linear()
			var peak := maxf(pixel.r, maxf(pixel.g, pixel.b))
			if peak < 1e-9:
				continue
			var exponent := floori(log(peak) / log(2.0)) + 1
			var scale := 256.0 / pow(2.0, exponent)
			scanline[x] = mini(255, int(pixel.r * scale))
			scanline[x + width] = mini(255, int(pixel.g * scale))
			scanline[x + width * 2] = mini(255, int(pixel.b * scale))
			scanline[x + width * 3] = exponent + 128
		for channel in 4:
			for begin in range(0, width, 128):
				var count := mini(128, width - begin)
				file.store_8(count)
				file.store_buffer(scanline.slice(channel * width + begin, channel * width + begin + count))
	return file.get_error() == OK
