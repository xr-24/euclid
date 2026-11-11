extends RefCounted
## Scatters many copies of library models cheaply: every model part becomes one
## MultiMeshInstance3D, so a thousand ice-plant mats or forty palms cost a few draw calls. Rules
## come from data files (world/data/vegetation/*.json, documented in the README there): which model,
## how many, where (region, height band, slope band, a noise mask for natural clumping, minimum
## spacing, areas to keep clear), how big, how far away it stays visible, and whether it gets a
## simple collider. Placement is seeded, so the same rules always give the same landscape.

const AssetLibrary = preload("res://scripts/asset_library.gd")
const RenderLayers = preload("res://scripts/rendering/render_layers.gd")

static var _parts := {}

## Mesh parts of a library model: [{mesh, transform}], relative to the model's origin.
static func parts(id: String) -> Array:
	if _parts.has(id):
		return _parts[id]
	var out := []
	var node := AssetLibrary.instance(id)
	if node:
		for child in node.find_children("*", "MeshInstance3D", true, false):
			var mi := child as MeshInstance3D
			if mi.mesh == null:
				continue
			var xf := Transform3D.IDENTITY
			var n: Node = mi
			while n != node and n is Node3D:
				xf = (n as Node3D).transform * xf
				n = n.get_parent()
			out.append({"mesh": mi.mesh, "transform": xf})
		node.free()
	_parts[id] = out
	return out

## Draw copies of a model at the given transforms (relative to root): one MultiMeshInstance3D per
## model part per tile. With a visibility range the copies are split into square tiles about half
## that range across, each culled on its own, so near plants show and far ones drop out.
static func instance_many(root: Node3D, id: String, transforms: Array, visibility_end := 0.0, shadows := true) -> void:
	if transforms.is_empty():
		return
	var tiles := {}
	var tile := maxf(visibility_end * 0.75, 40.0) if visibility_end > 0.0 else INF
	for t in transforms:
		var o := (t as Transform3D).origin
		var key := Vector2i(floori(o.x / tile), floori(o.z / tile)) if tile < INF else Vector2i.ZERO
		if not tiles.has(key):
			tiles[key] = []
		tiles[key].append(t)
	for key in tiles:
		var group: Array = tiles[key]
		var centre := Vector3.ZERO
		for t in group:
			centre += (t as Transform3D).origin
		centre /= group.size()
		for part in parts(id):
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = part.mesh
			mm.instance_count = group.size()
			for i in group.size():
				var t: Transform3D = group[i]
				t.origin -= centre
				mm.set_instance_transform(i, t * (part.transform as Transform3D))
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.position = centre
			mmi.name = "%s_%d_%d" % [id, key.x, key.y]
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			# Small plants too slight to cast shadows are too slight to notice in a reflection.
			if not shadows:
				mmi.layers = RenderLayers.REFLECTION_HIDDEN
			if visibility_end > 0.0:
				mmi.visibility_range_end = visibility_end
				mmi.visibility_range_end_margin = minf(visibility_end * 0.1, 20.0)
			root.add_child(mmi)

## Apply a rules file. field: a TerrainField; keep_clear: Array of Rect2 (x, z) where nothing grows.
## Returns how many instances were placed.
static func apply(root: Node3D, path: String, field: RefCounted, keep_clear: Array) -> int:
	if not FileAccess.file_exists(path):
		return 0
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		push_warning("Scatter: %s is not valid JSON" % path)
		return 0
	var total := 0
	var index := 0
	for rule in data.get("rules", []):
		index += 1
		if not rule is Dictionary or not AssetLibrary.has(str(rule.get("asset", ""))):
			continue
		var placed := _rule(root, rule, field, keep_clear, int(data.get("seed", 1)) * 7919 + index)
		total += placed
	return total

static func _rule(root: Node3D, rule: Dictionary, field: RefCounted, keep_clear: Array, seed: int) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var noise: FastNoiseLite = null
	if rule.has("noise"):
		noise = FastNoiseLite.new()
		noise.seed = seed
		noise.frequency = 1.0 / float(rule.noise.get("scale", 30.0))
		noise.fractal_octaves = 3
	var region: Array = rule.get("region", [field.x0, field.x0 + (field.nx - 1) * field.step, field.z0, field.z0 + (field.nz - 1) * field.step])
	var y_band: Array = rule.get("y", [-INF, INF])
	var slope: Array = rule.get("slope", [0.0, 1.0])  # range of normal.y
	var spacing := float(rule.get("spacing", 1.0))
	var scale_band: Array = rule.get("scale", [1.0, 1.0])
	var align := float(rule.get("align", 0.0))
	var sink := float(rule.get("sink", 0.0))
	var count := int(rule.get("count", 0))
	var grid := {}
	var transforms := []
	var radius := float(rule.get("collider", 0.0))
	var bodies: StaticBody3D = null
	if radius > 0.0:
		bodies = StaticBody3D.new()
		bodies.name = "%s_colliders" % rule.asset
		root.add_child(bodies)
	var tries := 0
	while transforms.size() < count and tries < count * 12:
		tries += 1
		var x := rng.randf_range(region[0], region[1])
		var z := rng.randf_range(region[2], region[3])
		if not field.contains(x, z) or _blocked(x, z, keep_clear, spacing * 0.5):
			continue
		var y: float = field.height(x, z)
		if y < float(y_band[0]) or y > float(y_band[1]):
			continue
		var n: Vector3 = field.normal(x, z)
		if n.y < float(slope[0]) or n.y > float(slope[1]):
			continue
		if noise and (noise.get_noise_2d(x, z) * 0.5 + 0.5) < float(rule.noise.get("threshold", 0.5)):
			continue
		var cell := Vector2i(floori(x / spacing), floori(z / spacing))
		if _crowded(grid, cell, Vector2(x, z), spacing):
			continue
		grid[cell] = Vector2(x, z)
		var s := rng.randf_range(scale_band[0], scale_band[1])
		var up := Vector3.UP.lerp(n, align).normalized()
		var basis := Basis(Quaternion(Vector3.UP, up)) * Basis(Vector3.UP, rng.randf() * TAU)
		transforms.append(Transform3D(basis.scaled(Vector3.ONE * s), Vector3(x, y - sink * s, z)))
		if bodies:
			var shape := CollisionShape3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = radius * s
			cyl.height = float(rule.get("collider_height", 3.0)) * s
			shape.shape = cyl
			shape.position = Vector3(x, y + cyl.height * 0.5 - sink * s, z)
			bodies.add_child(shape)
	instance_many(root, str(rule.asset), transforms, float(rule.get("range", 0.0)), bool(rule.get("shadows", true)))
	return transforms.size()

static func _blocked(x: float, z: float, keep_clear: Array, margin: float) -> bool:
	for r in keep_clear:
		var rect: Rect2 = r
		if x > rect.position.x - margin and x < rect.end.x + margin and z > rect.position.y - margin and z < rect.end.y + margin:
			return true
	return false

static func _crowded(grid: Dictionary, cell: Vector2i, p: Vector2, spacing: float) -> bool:
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			var other: Variant = grid.get(cell + Vector2i(dx, dz))
			if other != null and (other as Vector2).distance_to(p) < spacing:
				return true
	return false
