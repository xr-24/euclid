extends RefCounted

## Trusted entity factories. Persisted records choose a registered type, never a script path.
const Assets = preload("res://scripts/assets/runtime_assets.gd")
const MotionClip = preload("res://scripts/animation/motion_clip.gd")
const BehaviorRegistry = preload("res://scripts/plugins/behavior_registry.gd")
const TYPES := {"traffic_cone": {"label": "Traffic cone", "color": "ff681d"},
	"imported_model": {"label": "Imported model", "color": "ffffff"}}

static func valid_properties(record: Dictionary) -> bool:
	var type: Variant = record.get("type")
	var color: Variant = record.get("color")
	return type is String and TYPES.has(type) \
		and (type != "imported_model" or Assets.valid_id(record.get("asset_id"))) \
		and (not record.has("animation") or (MotionClip.valid(record.animation) and MotionClip.supports(record.animation, false))) \
		and (not record.has("behavior") or BehaviorRegistry.valid_record(record.behavior)) \
		and number_between(record.get("yaw"), -360.0, 360.0) \
		and number_between(record.get("scale"), 0.25, 4.0) \
		and color is String and color.length() == 6 and Color.html_is_valid(color)

static func number_between(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and value >= minimum and value <= maximum

static func label(record: Dictionary) -> String:
	if record.type == "imported_model":
		return str(Assets.metadata(record.get("asset_id", "")).get("title", "Imported model"))
	return TYPES[record.type].label

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
		"imported_model":
			var packed := Assets.scene(record.get("asset_id", ""))
			if packed:
				var model := packed.instantiate() as Node3D
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
					if record.color != "ffffff":
						for surface in part.mesh.get_surface_count():
							var original := part.get_active_material(surface) as BaseMaterial3D
							if original:
								var material := original.duplicate() as BaseMaterial3D
								material.albedo_color *= Color.html(record.color)
								part.set_surface_override_material(surface, material)
				var shape := BoxShape3D.new()
				shape.size = bounds.size.max(Vector3.ONE * 0.02) * size
				var collider := CollisionShape3D.new()
				collider.shape = shape
				collider.position = bounds.get_center() * size
				body.add_child(collider)
			else:
				body.set_meta("asset_unavailable", true)
	return body

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
