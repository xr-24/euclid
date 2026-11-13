extends StaticBody3D
## Chunked render and collision for the terrain piece. A preview updates the touched meshes.
## The saved stroke updates colliders once on release.

const Data = preload("res://scripts/pieces/terrain_data.gd")
const Assets = preload("res://scripts/assets/asset_library.gd")
const Runtime = preload("res://scripts/assets/runtime_materials.gd")
const TERRAIN_SHADER = preload("res://shaders/terrain.gdshader")
const CHUNK := 32
const CHUNKS := 8
const PALETTE_PATH := "res://data/pieces/terrain_palette.json"

static var _palette: Array = JSON.parse_string(FileAccess.get_file_as_string(PALETTE_PATH)).materials
static var _indices := _make_indices()

var data := Data.new()
var material_ids: Array = []
var _ground_material: ShaderMaterial
var terrain_size: Vector2
var _tiles: Array[MeshInstance3D] = []
var _shapes: Array[CollisionShape3D] = []
var _step: Vector2
var _cuts: Array[Dictionary] = []
var _cut_heights := PackedFloat32Array()
var _cut_cells := Rect2i()
var _pending := Rect2i()
var _pending_collision := Rect2i()

static func palette() -> Array:
	return _palette.duplicate(true)

func setup(record: Dictionary) -> void:
	terrain_size = Vector2(record.terrain_size[0], record.terrain_size[1])
	_step = terrain_size / Data.CELLS
	data.decode(record.get("terrain_surface", ""), record.get("terrain_paint_data", ""))
	_ground_material = _material()
	_set_imports(record.get("terrain_materials", []))
	for z in CHUNKS:
		for x in CHUNKS:
			var tile := MeshInstance3D.new()
			tile.material_override = _ground_material
			tile.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if record.get("cast_shadow", false) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(tile)
			_tiles.append(tile)
			var shape := CollisionShape3D.new()
			add_child(shape)
			_shapes.append(shape)
			_rebuild_tile(x, z, true)

func apply_excavations(cuts: Array[Dictionary]) -> bool:
	if cuts == _cuts:
		return false
	var dirty := _cut_cells
	_cuts = cuts
	_cut_cells = Rect2i()
	_cut_heights = PackedFloat32Array()
	if not cuts.is_empty():
		_cut_heights.resize(Data.COUNT)
		_cut_heights.fill(INF)
		for cut: Dictionary in cuts:
			_apply_cut(cut)
	dirty = _merge(dirty, _cut_cells)
	_rebuild(dirty, dirty)
	return true

func _apply_cut(cut: Dictionary) -> void:
	var blend := maxf(_step.x, _step.y)
	var extent: Vector2 = cut.half + Vector2.ONE * blend
	var axis := Vector2.from_angle(cut.angle).abs()
	var bounds := Vector2(axis.dot(extent), Vector2(axis.y, axis.x).dot(extent))
	var center: Vector2 = (cut.center + terrain_size * 0.5) / _step
	var start := Vector2i((center - bounds / _step).floor()).clamp(Vector2i.ZERO, Vector2i(Data.CELLS, Data.CELLS))
	var end := Vector2i((center + bounds / _step).ceil()).clamp(Vector2i.ZERO, Vector2i(Data.CELLS, Data.CELLS))
	_cut_cells = _merge(_cut_cells, Rect2i(start, end - start + Vector2i.ONE))
	for z in range(start.y, end.y + 1):
		for x in range(start.x, end.x + 1):
			var point := ((Vector2(x, z) - center) * _step).rotated(-cut.angle).abs()
			var margin: Vector2 = point - cut.half
			var outside := maxf(margin.x, margin.y)
			if outside < blend:
				var at := z * Data.SIDE + x
				var limit := lerpf(cut.bottom, maxf(cut.bottom, Data.HEIGHT_LIMIT), smoothstep(0.0, blend, outside))
				_cut_heights[at] = minf(_cut_heights[at], limit)

func load_record(record: Dictionary) -> bool:
	var next := Data.new()
	if not next.decode(record.get("terrain_surface", ""), record.get("terrain_paint_data", "")):
		return false
	var visual := _pending
	var collision := _pending_collision
	var next_ids: Array = record.get("terrain_materials", [])
	var has_imports := not material_ids.is_empty() or not next_ids.is_empty()
	_set_imports(next_ids)
	for index in Data.COUNT:
		var height_changed := data.heights[index] != next.heights[index]
		var paint_changed := data.paint[index * 2] != next.paint[index * 2] or data.paint[index * 2 + 1] != next.paint[index * 2 + 1]
		if height_changed or paint_changed or (has_imports and _import_differs(index, next)):
			@warning_ignore("integer_division")
			var cell := Rect2i(index % Data.SIDE, index / Data.SIDE, 1, 1)
			visual = _merge(visual, cell)
			if height_changed:
				collision = _merge(collision, cell)
	data = next
	_pending = Rect2i()
	_pending_collision = Rect2i()
	_rebuild(_merge(visual, collision), collision)
	return true

func _import_differs(index: int, next: Data) -> bool:
	var offset := index * Data.IMPORT_SLOTS
	for slot in Data.IMPORT_SLOTS:
		if data.imported[offset + slot] != next.imported[offset + slot]:
			return true
	return false

func prepare_material(id: String) -> int:
	var built_in := builtin_slot(id)
	if built_in >= 0:
		return built_in
	var existing := material_ids.find(id)
	if existing >= 0:
		return existing + 3
	if material_ids.size() >= Data.IMPORT_SLOTS or Runtime.cached_images(id).is_empty():
		return -1
	_set_imports(material_ids + [id])
	return material_ids.size() + 2

static func builtin_slot(id: String) -> int:
	return _palette.find_custom(func(entry: Dictionary) -> bool: return entry.id == id)

static func storage_for(surface: Data, ids: Array) -> Dictionary:
	var extra := surface.encode_imported()
	# Keep slot numbers stable for paints that remain. Empty tail slots can be reused.
	var active := ids.duplicate()
	if not extra.is_empty():
		while not active.is_empty() and not surface.has_import_paint(active.size() - 1):
			active.pop_back()
	var encoded := surface.encode()
	return {"terrain_surface": encoded if not encoded.is_empty() else null,
		"terrain_paint_data": extra if not extra.is_empty() else null,
		"terrain_materials": active if not extra.is_empty() else null}

func preview_dab(point: Vector2, mode: String, radius: float, strength: float, layer: int, level: float) -> void:
	var dirty := data.dab(point, terrain_size, mode, radius, strength, layer, level)
	_pending = _merge(_pending, dirty)
	if mode != "paint":
		_pending_collision = _merge(_pending_collision, dirty)

func flush_preview() -> void:
	_rebuild(_pending, Rect2i())
	_pending = Rect2i()

func surface_height(point: Vector2) -> float:
	return data.surface_at(point, terrain_size, _cut_heights)

func surface_point(point: Vector2, offset := 0.0) -> Vector3:
	return to_global(Vector3(point.x, surface_height(point) + offset, point.y))

func local_point(world_point: Vector3) -> Vector2:
	var point := to_local(world_point)
	return Vector2(point.x, point.z)

func contains_point(point: Vector2) -> bool:
	return Rect2(-terrain_size * 0.5, terrain_size).grow(0.002).has_point(point)

func _rebuild(dirty: Rect2i, collision: Rect2i) -> void:
	if not dirty.has_area():
		return
	for z in CHUNKS:
		for x in CHUNKS:
			var cells := Rect2i(x * CHUNK, z * CHUNK, CHUNK + 1, CHUNK + 1)
			if cells.grow(1).intersects(dirty):
				_rebuild_tile(x, z, cells.intersects(collision))

func _rebuild_tile(tx: int, tz: int, collision: bool) -> void:
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var weights := PackedColorArray()
	var extra_low := PackedVector2Array()
	var extra_high := PackedVector2Array()
	for z in range(tz * CHUNK, (tz + 1) * CHUNK + 1):
		for x in range(tx * CHUNK, (tx + 1) * CHUNK + 1):
			var dx := (data.rendered_height(x + 1, z, _cut_heights) - data.rendered_height(x - 1, z, _cut_heights)) / (2.0 * _step.x)
			var dz := (data.rendered_height(x, z + 1, _cut_heights) - data.rendered_height(x, z - 1, _cut_heights)) / (2.0 * _step.y)
			var at := Vector2(x, z) * _step - terrain_size * 0.5
			points.append(Vector3(at.x, data.rendered_height(x, z, _cut_heights), at.y))
			normals.append(Vector3(-dx, 1.0, -dz).normalized())
			var tangent := Vector3(1.0, dx, 0.0).normalized()
			tangents.append_array(PackedFloat32Array([tangent.x, tangent.y, tangent.z, -1.0]))
			var index := z * Data.SIDE + x
			weights.append(data.weights(index))
			extra_low.append(Vector2(data.weight(index, 4), data.weight(index, 5)) / 255.0)
			extra_high.append(Vector2(data.weight(index, 6), data.weight(index, 7)) / 255.0)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_COLOR] = weights
	arrays[Mesh.ARRAY_TEX_UV] = extra_low
	arrays[Mesh.ARRAY_TEX_UV2] = extra_high
	arrays[Mesh.ARRAY_INDEX] = _indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var tile := tz * CHUNKS + tx
	_tiles[tile].mesh = mesh
	if collision:
		var faces := PackedVector3Array()
		faces.resize(_indices.size())
		for index in _indices.size():
			faces[index] = points[_indices[index]]
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		_shapes[tile].shape = shape

static func _make_indices() -> PackedInt32Array:
	var result := PackedInt32Array()
	for z in CHUNK:
		for x in CHUNK:
			var a := z * (CHUNK + 1) + x
			var b := a + 1
			var c := a + CHUNK + 1
			result.append_array(PackedInt32Array([a, b, c, b, c + 1, c]))
	return result

static func _merge(a: Rect2i, b: Rect2i) -> Rect2i:
	if not b.has_area():
		return a
	return a.merge(b) if a.has_area() else b

static func _material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = TERRAIN_SHADER
	var tiles := Vector3.ZERO
	var prefixes := ["base", "sand", "rock"]
	for index in prefixes.size():
		var entry: Dictionary = _palette[index]
		var prefix: String = prefixes[index]
		var textures := Assets.texture_set(entry.texture)
		tiles[index] = entry.tile
		for map in textures:
			material.set_shader_parameter(prefix + "_" + map, textures[map])
		material.set_shader_parameter(prefix + "_tint", Color.html(entry.color) if textures.is_empty() else Color.WHITE)
	material.set_shader_parameter("tile_size", tiles)
	return material

func _set_imports(ids: Array) -> void:
	if ids == material_ids:
		return
	material_ids = ids.duplicate()
	_ground_material.set_shader_parameter("import_count", ids.size())
	if ids.is_empty():
		for key in Runtime.MAPS:
			_ground_material.set_shader_parameter("import_" + key, null)
		return
	var entries: Array = []
	for id: String in ids:
		entries.append(Runtime.cached_images(id))
	for map in Runtime.MAPS.size():
		var images: Array[Image] = []
		for entry: Array in entries:
			images.append(entry[map] if not entry.is_empty() else Runtime.missing_image(map))
		var textures := Texture2DArray.new()
		if textures.create_from_images(images) == OK:
			_ground_material.set_shader_parameter("import_" + Runtime.MAPS[map], textures)
