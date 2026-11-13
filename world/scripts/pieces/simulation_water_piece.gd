extends RefCounted
## A baked water domain with its solver, fallback surface and material bindings.

const Water = preload("res://scripts/simulation/water_system.gd")
const WaterEdits = preload("res://scripts/workshop/water_edits.gd")
const Model = preload("res://scripts/pieces/model_piece.gd")

static func valid_record(record: Dictionary) -> bool:
	if record.domain[2] <= 0 or record.domain[3] <= 0:
		return false
	# A baked solver samples world X/Z coordinates. Its bounds and level are explicit fields.
	return record.get("position", [0, 0, 0]) == [0, 0, 0] and record.get("rotation", [0, 0, 0]) == [0, 0, 0] and record.get("scale", [1, 1, 1]) == [1, 1, 1]

static func build(record: Dictionary) -> Node3D:
	var root := Node3D.new()
	var rect_data: Array = record.domain
	var rect := Rect2(rect_data[0], rect_data[1], rect_data[2], rect_data[3])
	var level := float(record.level)
	var bake := "res://assets/generated/" + str(record.bake)
	var label: String = record.get("name", "Water")
	var water_id: String = record.get("water_id", record.id)
	var result := {}
	if record.simulation == "pool":
		var layout := {"pool": [rect.position.x, rect.end.x, rect.position.y, rect.end.y], "water_y": level}
		result = Water.build_pool_surface(root, layout, bake, water_id, label)
	else:
		var landscape: Dictionary = record.get("landscape", {})
		if not landscape.is_empty():
			var terrain := Model.build(landscape.merged({"id": record.id, "source": "generated", "collision": true}))
			root.add_child(terrain)
		var terrain_material: ShaderMaterial
		for mesh: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
			if mesh.material_override is ShaderMaterial:
				terrain_material = mesh.material_override
				break
		var ocean_materials: Array[ShaderMaterial] = []
		for entry: Dictionary in record.get("ocean_layers", []):
			var size: Array = entry.size
			var center: Array = entry.center
			var plane := PlaneMesh.new()
			plane.size = Vector2(size[0], size[1])
			plane.subdivide_width = int(entry.detail)
			plane.subdivide_depth = int(entry.detail)
			var sea := MeshInstance3D.new()
			sea.mesh = plane
			sea.position = Vector3(center[0], level, center[1])
			sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var material := Water.water_material(true)
			if entry.get("horizon", false):
				material.set_shader_parameter("has_lod_hole", true)
				material.set_shader_parameter("lod_hole", Vector4(rect.position.x + 0.5, rect.position.y + 0.5, rect.end.x - 0.5, rect.end.y - 0.5))
				material.set_shader_parameter("swell", 0.0)
			sea.material_override = material
			root.add_child(sea)
			ocean_materials.append(material)
		if terrain_material != null:
			result = Water.build_surf(root, terrain_material, ocean_materials, bake, level, rect)
		WaterEdits.register(root, water_id, label, rect, level, result.get("surfaces", ocean_materials),
			0.0, [] if result.is_empty() else ocean_materials)
		root.set_meta("water_sea", level)
	if not result.is_empty():
		root.set_meta("water_simulation", result)
	return root
