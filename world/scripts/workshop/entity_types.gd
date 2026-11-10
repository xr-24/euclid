extends RefCounted

## Trusted entity factories. Persisted records choose a registered type, never a script path.
const Assets = preload("res://scripts/assets/runtime_assets.gd")
const Library = preload("res://scripts/asset_library.gd")
const MotionClip = preload("res://scripts/animation/motion_clip.gd")
const BehaviorRegistry = preload("res://scripts/plugins/behavior_registry.gd")
const TYPES := {"traffic_cone": {"label": "Traffic cone", "color": "ff681d"},
	"pressure_plate": {"label": "Pressure plate", "color": "2d8394"},
	"sliding_door": {"label": "Sliding door", "color": "475567"},
	"imported_model": {"label": "Imported model", "color": "ffffff"},
	"library_model": {"label": "Library model", "color": "ffffff"}}
const LIBRARY_CATEGORIES := ["bust", "fragment", "furniture", "plant", "prop", "rock", "sarcophagus", "statue", "tree"]

static func valid_properties(record: Dictionary) -> bool:
	var type: Variant = record.get("type")
	var color: Variant = record.get("color")
	return type is String and TYPES.has(type) \
		and (type != "imported_model" or Assets.valid_id(record.get("asset_id"))) \
		and (type != "library_model" or library_id(record.get("asset_id"))) \
		and (not record.has("name") or valid_name(record.name)) \
		and (not record.has("animation") or (MotionClip.valid(record.animation) and MotionClip.supports(record.animation, false))) \
		and (not record.has("behavior") or BehaviorRegistry.valid_record(record.behavior)) \
		and number_between(record.get("yaw"), -360.0, 360.0) \
		and number_between(record.get("scale"), 0.25, 4.0) \
		and color is String and color.length() == 6 and Color.html_is_valid(color)

static func number_between(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and value >= minimum and value <= maximum

static func label(record: Dictionary) -> String:
	if record.has("name"):
		return record.name
	if record.type == "imported_model":
		return str(Assets.metadata(record.get("asset_id", "")).get("title", "Imported model"))
	if record.type in ["library_model", "authored_dressing"]:
		return str(Library.info(record.asset_id).get("title", record.asset_id.capitalize()))
	return TYPES[record.type].label

static func valid_name(value: Variant) -> bool:
	if not value is String or value.length() > 64 or value.strip_edges().is_empty():
		return false
	for index in value.length():
		if value.unicode_at(index) < 32 or value.unicode_at(index) == 127:
			return false
	return true

static func library_id(id: Variant) -> bool:
	return id is String and id.length() <= 96 and id.is_valid_identifier()

static func library_available(id: Variant) -> bool:
	return library_id(id) and Library.info(id).get("category") in LIBRARY_CATEGORIES and Library.has(id)

static func library_catalog() -> Array[Dictionary]:
	var available: Array[Dictionary] = []
	for id in Library.ids():
		if library_available(id):
			var entry := Library.info(id)
			available.append({"id": id, "name": str(entry.get("title", id)).left(64),
				"category": entry.category, "license": entry.get("licence", "")})
	return available

static func create(record: Dictionary) -> AnimatableBody3D:
	var body := AnimatableBody3D.new()
	body.sync_to_physics = false
	body.name = "Entity_" + record.id
	body.set_meta("entity_id", record.id)
	var point: Array = record.position
	body.position = Vector3(point[0], point[1], point[2])
	body.rotation_degrees.y = record.yaw
	var size: float = record.scale
	match record.type:
		"traffic_cone":
			_cone(body, Color.html(record.color), size)
		"pressure_plate":
			_box_body(body, Vector3(1.2, 0.09, 1.2) * size, Color.html(record.color)).name = "SignalSurface"
		"sliding_door":
			var leaf := AnimatableBody3D.new()
			leaf.name = "DoorLeaf"
			leaf.sync_to_physics = false
			leaf.set_meta("entity_id", record.id)
			_box_body(leaf, Vector3(1.55, 2.35, 0.18) * size, Color.html(record.color))
			body.add_child(leaf)
		"imported_model", "library_model":
			var model: Node3D
			if record.type == "library_model":
				model = Library.instance(record.asset_id)
			else:
				var packed := Assets.scene(record.asset_id)
				if packed:
					model = packed.instantiate() as Node3D
			if model:
				_place_model(body, model, size, record.color)
			else:
				body.set_meta("asset_unavailable", true)
	return body

static func _place_model(body: AnimatableBody3D, model: Node3D, size: float, color: String) -> void:
	var placement := Node3D.new()
	placement.scale = Vector3.ONE * size
	body.add_child(placement)
	placement.add_child(model)
	var bounds := AABB()
	var first := true
	for child in placement.find_children("*", "MeshInstance3D", true, false):
		var part := child as MeshInstance3D
		var local := part.transform
		var ancestor := part.get_parent()
		while ancestor != placement:
			local = (ancestor as Node3D).transform * local
			ancestor = ancestor.get_parent()
		var box := local * part.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
		if color != "ffffff":
			for surface in part.mesh.get_surface_count():
				var original := part.get_active_material(surface) as BaseMaterial3D
				if original:
					var material := original.duplicate() as BaseMaterial3D
					material.albedo_color *= Color.html(color)
					part.set_surface_override_material(surface, material)
	var shape := BoxShape3D.new()
	shape.size = bounds.size.max(Vector3.ONE * 0.02) * size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position = bounds.get_center() * size
	body.add_child(collider)

static func _box_body(body: StaticBody3D, size: Vector3, color: Color) -> MeshInstance3D:
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = size.y * 0.5
	body.add_child(collider)
	var mesh := BoxMesh.new()
	mesh.size = size
	return _mesh(body, mesh, size.y * 0.5, color, 0.48)

static func _cone(body: StaticBody3D, color: Color, size: float) -> void:
	var base := BoxMesh.new()
	base.size = Vector3(0.58, 0.07, 0.58) * size
	_mesh(body, base, 0.035 * size, Color("22292e"), 0.88)
	_mesh(body, _taper(0.24, 0.032, 0.78, size), 0.46 * size, color, 0.6).name = "SignalSurface"
	_mesh(body, _taper(0.153, 0.115, 0.14, size), 0.48 * size, Color("edf1e8"), 0.7)

	var shape := ConvexPolygonShape3D.new()
	var points := PackedVector3Array()
	for x in [-0.29, 0.29]:
		for z in [-0.29, 0.29]:
			points.append(Vector3(x, 0, z) * size)
			points.append(Vector3(x, 0.07, z) * size)
			points.append(Vector3(x * 0.1, 0.85, z * 0.1) * size)
	shape.points = points
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)

static func _taper(bottom: float, top: float, height: float, size: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = bottom * size
	mesh.top_radius = top * size
	mesh.height = height * size
	mesh.radial_segments = 24
	mesh.rings = 0
	return mesh

static func _mesh(parent: Node3D, mesh: Mesh, height: float, color: Color, roughness: float) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.18
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position.y = height
	instance.material_override = material
	parent.add_child(instance)
	return instance
