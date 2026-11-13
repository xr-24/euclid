extends RefCounted
## A height field with three built-in and five imported material layers.
## The first two weights retain the original save layout; earth is the remainder.

const CELLS := 256
const SIDE := CELLS + 1
const COUNT := SIDE * SIDE
const HEIGHT_LIMIT := 24.0
const BYTES := COUNT * 4
const IMPORT_SLOTS := 5
const LAYERS := 3 + IMPORT_SLOTS

var heights := PackedFloat32Array()
var paint := PackedByteArray()
var imported := PackedByteArray()

func _init() -> void:
	heights.resize(COUNT)
	paint.resize(COUNT * 2)
	imported.resize(COUNT * IMPORT_SLOTS)

func decode(encoded: String, extra := "", slots := IMPORT_SLOTS) -> bool:
	if not extra.is_empty():
		var compressed := Marshalls.base64_to_raw(extra)
		if compressed.is_empty():
			return false
		imported = compressed.decompress(COUNT * IMPORT_SLOTS, FileAccess.COMPRESSION_DEFLATE)
		if imported.size() != COUNT * IMPORT_SLOTS:
			return false
	else:
		imported.fill(0)
	if encoded.is_empty():
		heights.fill(0.0)
		paint.fill(0)
		return _valid_weights(slots) if not extra.is_empty() else true
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
	return _valid_weights(slots) if not extra.is_empty() else true

func _valid_weights(slots: int) -> bool:
	for index in COUNT:
		var total := int(paint[index * 2]) + int(paint[index * 2 + 1])
		for slot in IMPORT_SLOTS:
			var value := imported[index * IMPORT_SLOTS + slot]
			if slot >= slots and value != 0:
				return false
			total += value
		if total > 255:
			return false
	return true

func encode_imported() -> String:
	return "" if imported.count(0) == imported.size() else Marshalls.raw_to_base64(
		imported.compress(FileAccess.COMPRESSION_DEFLATE))

func has_import_paint(slot: int) -> bool:
	for index in range(slot, imported.size(), IMPORT_SLOTS):
		if imported[index] != 0:
			return true
	return false

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

func surface_at(point: Vector2, size: Vector2, cuts := PackedFloat32Array()) -> float:
	var cell := ((point / size + Vector2.ONE * 0.5) * CELLS).clamp(Vector2.ZERO, Vector2.ONE * CELLS)
	var x := mini(floori(cell.x), CELLS - 1)
	var z := mini(floori(cell.y), CELLS - 1)
	var u := cell.x - x
	var v := cell.y - z
	# Same diagonal as the render and collision triangles.
	var a := rendered_height(x, z, cuts)
	var b := rendered_height(x + 1, z, cuts)
	var c := rendered_height(x, z + 1, cuts)
	var d := rendered_height(x + 1, z + 1, cuts)
	return a + u * (b - a) + v * (c - a) if u + v <= 1.0 else d + (1.0 - u) * (c - d) + (1.0 - v) * (b - d)

func rendered_height(x: int, z: int, cuts: PackedFloat32Array) -> float:
	var index := clampi(z, 0, CELLS) * SIDE + clampi(x, 0, CELLS)
	return heights[index] if cuts.is_empty() else minf(heights[index], cuts[index])

func weights(index: int) -> Color:
	var sand := float(paint[index * 2]) / 255.0
	var rock := float(paint[index * 2 + 1]) / 255.0
	var extra := 0
	for slot in IMPORT_SLOTS:
		extra += imported[index * IMPORT_SLOTS + slot]
	return Color(maxf(0.0, 1.0 - sand - rock - extra / 255.0), sand, rock,
		imported[index * IMPORT_SLOTS] / 255.0)

func weight(index: int, layer: int) -> int:
	if layer <= 2:
		return paint[index * 2 + layer - 1]
	return imported[index * IMPORT_SLOTS + layer - 3]

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
	var changed := false
	var remaining := 255
	for slot in range(1, LAYERS):
		var before := weight(index, slot)
		var after := mini(remaining, roundi(lerpf(before, 255 if layer == slot else 0, amount)))
		remaining -= after
		if slot <= 2:
			paint[index * 2 + slot - 1] = after
		else:
			imported[index * IMPORT_SLOTS + slot - 3] = after
		changed = changed or before != after
	return changed

static func _average(source: PackedFloat32Array, x: int, z: int) -> float:
	var total := 0.0
	for row in range(z - 1, z + 2):
		for col in range(x - 1, x + 2):
			total += source[clampi(row, 0, CELLS) * SIDE + clampi(col, 0, CELLS)]
	return total / 9.0
