extends RefCounted
## A model from the installed library or an imported (runtime) asset, with optional collision
## from its own meshes. A missing model leaves an empty marker so the document still loads.

const Library = preload("res://scripts/asset_library.gd")
const Runtime = preload("res://scripts/assets/runtime_assets.gd")
const Shared = preload("res://scripts/assets/asset_library.gd")

const ModelSurface = preload("res://scripts/pieces/model_surface.gd")
const RenderLayers = preload("res://scripts/rendering/render_layers.gd")

static func build(record: Dictionary) -> Node3D:
	var id := str(record.asset_id)
	var model: Node3D = null
	if record.source == "library":
		model = Library.instance(id)
	elif record.source == "polyhaven":
		model = Shared.model(id)
	elif record.source == "generated":
		var path := "res://assets/generated/" + id + ".glb"
		var scene := Shared.get_resource(path) as PackedScene if ResourceLoader.exists(path) else null
		if scene != null:
			model = scene.instantiate() as Node3D
	elif Runtime.valid_id(id):
		var packed := Runtime.scene(id)
		if packed != null:
			model = packed.instantiate() as Node3D
	if model == null:
		var missing := Node3D.new()
		missing.set_meta("asset_unavailable", true)
		return missing
	var treatment := {}
	for rule: Dictionary in record.get("mesh_rules", []):
		treatment[rule.mesh] = rule
	var finish: Dictionary = record.get("model_finish", {})
	var surfaces := {}
	for key in treatment:
		surfaces[key] = ModelSurface.make(treatment[key])
	var all := ModelSurface.make(finish) if not finish.is_empty() else null
	for child: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var key := str(child.name).to_lower().trim_prefix("col_").trim_prefix("art_")
		var rule: Dictionary = treatment.get(key, {})
		if surfaces.get(key) != null or all != null:
			child.material_override = surfaces.get(key, all)
		if rule.get("main_view_only", false):
			child.layers = RenderLayers.REFLECTION_HIDDEN
		if rule.has("cast_shadow"):
			child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if rule.cast_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if record.get("collision", false) or (record.get("named_collision", false) and child.name.begins_with("COL_")):
			Shared.add_mesh_collision(child)
		if rule.get("hidden", false):
			child.hide()
	var height := float(record.get("model_height", 0))
	var size := Library.size(id) if record.source == "library" else Shared.bounds(model).size
	if height > 0.0 and size.y > 0.0:
		model.scale = Vector3.ONE * height / size.y
	var root := Node3D.new()
	var lift := float(record.get("model_lift", 0.0))
	model.position.y = lift
	root.add_child(model)
	if record.get("box_collision", false) and size[size.min_axis_index()] > 0:
		size *= model.scale
		Shared.add_static_box(root, Vector3.UP * (lift + size.y * 0.5), size)
	if record.has("trunk"):
		var trunk: Array = record.trunk
		var collision := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var cylinder := CylinderShape3D.new()
		cylinder.radius = trunk[0]
		cylinder.height = trunk[1]
		shape.shape = cylinder
		collision.position.y = cylinder.height * 0.5
		collision.add_child(shape)
		root.add_child(collision)
	if record.get("legacy_prop", false):
		root.set_meta("legacy_prop", {"asset": id, "label": record.get("name", ""), "placement_surface": record.get("placement_surface", false)})
	return root
