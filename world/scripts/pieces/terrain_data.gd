extends RefCounted
## A bounded height field and three material weights per sample. Saved samples use centimetres
## for height and two bytes for paint; the remaining weight belongs to the base material.

const CELLS := 256
const SIDE := CELLS + 1
const COUNT := SIDE * SIDE
const HEIGHT_LIMIT := 24.0
const BYTES := COUNT * 4

var heights := PackedFloat32Array()
var paint := PackedByteArray()

func _init() -> void:
	heights.resize(COUNT)
	paint.resize(COUNT * 2)

func decode(encoded: String) -> bool:
	if encoded.is_empty():
		heights.fill(0.0)
		paint.fill(0)
		return true
	var compressed := Marshalls.base64_to_raw(encoded)
	if compressed.is_empty():
		return false
	var raw := compressed.decompress(BYTES, FileAccess.COMPRESSION_DEFLATE)
	if raw.size() != BYTES:
		return false
	for index in COUNT:
		var at := index * 4
		var height := raw.decode_s16(at)
		if absi(height) > 2400 or int(raw[at + 2]) + int(raw[at + 3]) > 255:
			return false
		heights[index] = height / 100.0
		paint[index * 2] = raw[at + 2]
		paint[index * 2 + 1] = raw[at + 3]
	return true

func encode() -> String:
	var raw := PackedByteArray()
	raw.resize(BYTES)
	var changed := false
	for index in COUNT:
		var at := index * 4
		var height := roundi(heights[index] * 100.0)
		raw.encode_s16(at, height)
		raw[at + 2] = paint[index * 2]
		raw[at + 3] = paint[index * 2 + 1]
		changed = changed or height != 0 or raw[at + 2] != 0 or raw[at + 3] != 0
	return Marshalls.raw_to_base64(raw.compress(FileAccess.COMPRESSION_DEFLATE)) if changed else ""

func height_at(x: int, z: int) -> float:
	return heights[clampi(z, 0, CELLS) * SIDE + clampi(x, 0, CELLS)]

func surface_at(point: Vector2, size: Vector2) -> float:
	var cell := ((point / size + Vector2.ONE * 0.5) * CELLS).clamp(Vector2.ZERO, Vector2.ONE * CELLS)
	var x := mini(floori(cell.x), CELLS - 1)
	var z := mini(floori(cell.y), CELLS - 1)
	var u := cell.x - x
	var v := cell.y - z
	# Same diagonal as the render and collision triangles.
	var a := height_at(x, z)
	var b := height_at(x + 1, z)
	var c := height_at(x, z + 1)
	var d := height_at(x + 1, z + 1)
	return a + u * (b - a) + v * (c - a) if u + v <= 1.0 else d + (1.0 - u) * (c - d) + (1.0 - v) * (b - d)

func weights(index: int) -> Color:
	var sand := float(paint[index * 2]) / 255.0
	var rock := float(paint[index * 2 + 1]) / 255.0
	return Color(1.0 - sand - rock, sand, rock, 1.0)

func dab(center: Vector2, size: Vector2, mode: String, radius: float, amount: float, layer: int, level: float) -> Rect2i:
	var step := size / CELLS
	var cell := (center + size * 0.5) / step
	var span := Vector2.ONE * radius / step
	var minimum := Vector2i((cell - span).floor()).clamp(Vector2i.ZERO, Vector2i(CELLS, CELLS))
	var maximum := Vector2i((cell + span).ceil()).clamp(Vector2i.ZERO, Vector2i(CELLS, CELLS))
	var source := heights if mode == "smooth" else PackedFloat32Array()
	var dirty := Rect2i()
	for z in range(minimum.y, maximum.y + 1):
		for x in range(minimum.x, maximum.x + 1):
			var distance := ((Vector2(x, z) - cell) * step).length()
			var falloff := 1.0 - smoothstep(0.0, radius, distance)
			if falloff <= 0.0:
				continue
			var index := z * SIDE + x
			var strength := amount * falloff
			var changed := false
			if mode == "paint":
				changed = _paint(index, layer, minf(strength, 1.0))
			else:
				var before := heights[index]
				var after := before
				match mode:
					"raise": after += strength
					"lower": after -= strength
					"flatten": after = lerpf(before, level, minf(strength, 1.0))
					"smooth": after = lerpf(before, _average(source, x, z), minf(strength, 1.0))
				heights[index] = clampf(roundf(after * 100.0) / 100.0, -HEIGHT_LIMIT, HEIGHT_LIMIT)
				changed = not is_equal_approx(before, heights[index])
			if changed:
				var cell_rect := Rect2i(x, z, 1, 1)
				dirty = dirty.merge(cell_rect) if dirty.has_area() else cell_rect
	return dirty

func _paint(index: int, layer: int, amount: float) -> bool:
	var sand := int(paint[index * 2])
	var rock := int(paint[index * 2 + 1])
	var next_sand := roundi(lerpf(sand, 255 if layer == 1 else 0, amount))
	var next_rock := mini(255 - next_sand, roundi(lerpf(rock, 255 if layer == 2 else 0, amount)))
	paint[index * 2] = next_sand
	paint[index * 2 + 1] = next_rock
	return next_sand != sand or next_rock != rock

static func _average(source: PackedFloat32Array, x: int, z: int) -> float:
	var total := 0.0
	for row in range(z - 1, z + 2):
		for col in range(x - 1, x + 2):
			total += source[clampi(row, 0, CELLS) * SIDE + clampi(col, 0, CELLS)]
	return total / 9.0
