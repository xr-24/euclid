extends StaticBody3D
## Chunked render and collision for the terrain piece. A preview updates the touched meshes.
## The saved stroke updates colliders once on release.

const Data = preload("res://scripts/pieces/terrain_data.gd")
const Assets = preload("res://scripts/assets/asset_library.gd")
const TERRAIN_SHADER = preload("res://shaders/terrain.gdshader")
const CHUNK := 32
const CHUNKS := 8
const PALETTE_PATH := "res://data/pieces/terrain_palette.json"

static var _palette: Array = JSON.parse_string(FileAccess.get_file_as_string(PALETTE_PATH)).materials
static var _indices := _make_indices()

var data := Data.new()
var terrain_size: Vector2
var _tiles: Array[MeshInstance3D] = []
var _shapes: Array[CollisionShape3D] = []
var _step: Vector2
var _pending := Rect2i()
var _pending_collision := Rect2i()

static func palette() -> Array:
	return _palette.duplicate(true)

func setup(record: Dictionary) -> void:
	terrain_size = Vector2(record.terrain_size[0], record.terrain_size[1])
	_step = terrain_size / Data.CELLS
	data.decode(record.get("terrain_surface", ""))
	var material := _material()
	for z in CHUNKS:
		for x in CHUNKS:
			var tile := MeshInstance3D.new()
			tile.material_override = material
			tile.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if record.get("cast_shadow", false) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(tile)
			_tiles.append(tile)
			var shape := CollisionShape3D.new()
			add_child(shape)
			_shapes.append(shape)
			_rebuild_tile(x, z, true)

func load_surface(encoded: String) -> bool:
	var next := Data.new()
	if not next.decode(encoded):
		return false
	var visual := _pending
	var collision := _pending_collision
	for index in Data.COUNT:
		var height_changed := data.heights[index] != next.heights[index]
		if height_changed or data.paint[index * 2] != next.paint[index * 2] or data.paint[index * 2 + 1] != next.paint[index * 2 + 1]:
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

func preview_dab(point: Vector2, mode: String, radius: float, strength: float, layer: int, level: float) -> void:
	var dirty := data.dab(point, terrain_size, mode, radius, strength, layer, level)
	_pending = _merge(_pending, dirty)
	if mode != "paint":
		_pending_collision = _merge(_pending_collision, dirty)

func flush_preview() -> void:
	_rebuild(_pending, Rect2i())
	_pending = Rect2i()

func surface_point(point: Vector2, offset := 0.0) -> Vector3:
	return to_global(Vector3(point.x, data.surface_at(point, terrain_size) + offset, point.y))

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
	for z in range(tz * CHUNK, (tz + 1) * CHUNK + 1):
		for x in range(tx * CHUNK, (tx + 1) * CHUNK + 1):
			var dx := (data.height_at(x + 1, z) - data.height_at(x - 1, z)) / (2.0 * _step.x)
			var dz := (data.height_at(x, z + 1) - data.height_at(x, z - 1)) / (2.0 * _step.y)
			var at := Vector2(x, z) * _step - terrain_size * 0.5
			points.append(Vector3(at.x, data.height_at(x, z), at.y))
			normals.append(Vector3(-dx, 1.0, -dz).normalized())
			var tangent := Vector3(1.0, dx, 0.0).normalized()
			tangents.append_array(PackedFloat32Array([tangent.x, tangent.y, tangent.z, -1.0]))
			weights.append(data.weights(z * Data.SIDE + x))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_COLOR] = weights
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
