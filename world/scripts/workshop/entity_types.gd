extends RefCounted

## Trusted entity factories. Persisted records choose a registered type, never a script path.
const Assets = preload("res://scripts/assets/runtime_assets.gd")
const Library = preload("res://scripts/asset_library.gd")
const MotionClip = preload("res://scripts/animation/motion_clip.gd")
const BehaviorRegistry = preload("res://scripts/plugins/behavior_registry.gd")
const Commands = preload("res://scripts/workshop/command_registry.gd")
const AuthoredProps = preload("res://scripts/zones/authored_props.gd")
static var TYPES := Commands.entity_types()
const LIBRARY_CATEGORIES := ["bust", "fragment", "furniture", "plant", "prop", "rock", "sarcophagus", "statue", "tree"]

static func valid_properties(record: Dictionary) -> bool:
	var type: Variant = record.get("type")
	var source: String = TYPES.get(type, {}).get("asset_source", "")
	return type is String and TYPES.has(type) \
		and (source != "runtime" or Assets.valid_id(record.get("asset_id"))) \
		and (source != "library" or library_id(record.get("asset_id"))) \
		and (not record.has("name") or valid_name(record.name)) \
		and (not record.has("animation") or (MotionClip.valid(record.animation) and MotionClip.supports(record.animation, false))) \
		and (not record.has("behavior") or BehaviorRegistry.valid_record(record.behavior)) \
		and record.get("locked", false) is bool \
		and record.get("collision", true) is bool \
		and Commands.valid_field("yaw", record.get("yaw")) \
		and Commands.valid_field("scale", record.get("scale")) \
		and (not record.has("stretch") or (Commands.valid_field("stretch", record.stretch) \
			and TYPES[type].get("factory") != "door")) \
		and Commands.valid_field("color", record.get("color"))

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
	return value != "" and Commands.valid_field("prop_name", value)

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

static func create(record: Dictionary) -> PhysicsBody3D:
	var body: PhysicsBody3D
	if TYPES[record.type].factory != "door":
		var rigid := RigidBody3D.new()
		rigid.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		rigid.continuous_cd = true
		rigid.mass = clampf(float(record.scale) * 4.0, 1.0, 16.0)
		body = rigid
	else:
		var scripted := AnimatableBody3D.new()
		scripted.sync_to_physics = false
		body = scripted
	body.name = "Entity_" + record.id
	body.set_meta("entity_id", record.id)
	var point: Array = record.position
	body.position = Vector3(point[0], point[1], point[2])
	body.rotation_degrees.y = record.yaw
	var size: float = record.scale
	var definition: Dictionary = TYPES[record.type]
	match definition.factory:
		"cone":
			_cone(body, Color.html(record.color), size)
		"box":
			_box_body(body, _size(definition) * size, Color.html(record.color)).name = "SignalSurface"
		"door":
			var leaf := AnimatableBody3D.new()
			leaf.name = "DoorLeaf"
			leaf.sync_to_physics = false
			leaf.set_meta("entity_id", record.id)
			_box_body(leaf, _size(definition) * size, Color.html(record.color))
			body.add_child(leaf)
		"model":
			var model: Node3D
			if definition.asset_source == "library":
				model = Library.instance(record.asset_id)
			else:
				var packed := Assets.scene(record.asset_id)
				if packed:
					model = packed.instantiate() as Node3D
			if model:
				_place_model(body, model, size, record.color)
			else:
				body.set_meta("asset_unavailable", true)
	var stretch := stretch_of(record)
	if stretch != Vector3.ONE:
		_resize_parts(body, stretch)
	set_collision(body, record.get("collision", true))
	if body is RigidBody3D:
		set_locked(body, record.get("locked", false) or not movable(record))
	return body

## Stretch along the prop's own axes (X, Y and Z after its yaw), on top of its scale.
static func stretch_of(record: Dictionary) -> Vector3:
	var value: Variant = record.get("stretch")
	return Vector3(float(value[0]), float(value[1]), float(value[2])) if value is Array and value.size() == 3 else Vector3.ONE

static func movable(record: Dictionary) -> bool:
	return TYPES.get(record.get("type"), {}).get("factory") != "door" and not record.has("animation") and not record.has("behavior")

static func update_placement(body: RigidBody3D, previous: Dictionary, record: Dictionary, keep_pose: bool) -> void:
	if not keep_pose and previous.position != record.position:
		body.position = Vector3(record.position[0], record.position[1], record.position[2])
	if not keep_pose and previous.yaw != record.yaw:
		body.rotation.y = deg_to_rad(record.yaw)
	var before := float(previous.scale) * stretch_of(previous)
	var after := float(record.scale) * stretch_of(record)
	if before != after:
		_resize_parts(body, after / before)
		body.mass = clampf(float(record.scale) * 4.0, 1.0, 16.0)
	set_collision(body, record.get("collision", true))
	if not keep_pose:
		set_locked(body, record.get("locked", false))

## Keep a selection-only area on the moving part of the prop while its physics bodies are disabled.
static func set_collision(node: PhysicsBody3D, enabled: bool) -> void:
	if node.get_meta("collision_enabled", true) == enabled:
		return
	node.set_meta("collision_enabled", enabled)
	var bodies := node.find_children("*", "PhysicsBody3D", true, false)
	bodies.push_front(node)
	for body: PhysicsBody3D in bodies:
		if enabled:
			var filters: Vector2i = body.get_meta("collision_filters")
			body.collision_layer = filters.x
			body.collision_mask = filters.y
			body.remove_meta("collision_filters")
		else:
			body.set_meta("collision_filters", Vector2i(body.collision_layer, body.collision_mask))
			body.collision_layer = 0
			body.collision_mask = 0
	var target := node.get_node_or_null("DoorLeaf") as Node3D
	if target == null:
		target = node
	var picker := target.get_node_or_null("EntityPicker") as Area3D
	if enabled:
		if picker:
			picker.free()
	elif not picker:
		AuthoredProps.add_picker(target, node.get_meta("entity_id"))

static func set_locked(body: RigidBody3D, locked: bool) -> void:
	# With no solid collider, keep the authored pose instead of allowing gravity to sink it.
	locked = locked or not body.get_meta("collision_enabled", true)
	if body.freeze != locked:
		body.freeze = locked
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
		if not locked:
			body.sleeping = false

## Scales a body's parts and colliders along its own axes. Shapes are copied first, since a model's
## collision shapes can be shared with other copies of it.
static func _resize_parts(body: Node3D, factor: Vector3) -> void:
	for part in body.get_children():
		if part is CollisionShape3D:
			part.position *= factor
			if part.shape is BoxShape3D:
				part.shape = part.shape.duplicate()
				part.shape.size *= factor
			elif part.shape is ConvexPolygonShape3D:
				part.shape = part.shape.duplicate()
				var points: PackedVector3Array = part.shape.points
				for index in points.size():
					points[index] *= factor
				part.shape.points = points
		elif part is Node3D:
			part.transform = part.transform.scaled(factor)

static func _size(definition: Dictionary) -> Vector3:
	var size: Array = definition.size
	return Vector3(size[0], size[1], size[2])

static func _place_model(body: PhysicsBody3D, model: Node3D, size: float, color: String) -> void:
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

static func _box_body(body: PhysicsBody3D, size: Vector3, color: Color) -> MeshInstance3D:
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = size.y * 0.5
	body.add_child(collider)
	var mesh := BoxMesh.new()
	mesh.size = size
	return _mesh(body, mesh, size.y * 0.5, color, 0.48)

static func _cone(body: PhysicsBody3D, color: Color, size: float) -> void:
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
