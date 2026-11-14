extends RefCounted
## Runtime layer for the grouped model, plinth, and collision produced by the builder.

const AuthoredProps = preload("res://scripts/zones/authored_props.gd")
const Placement = preload("res://scripts/workshop/scene_placement.gd")
const EntityTypes = preload("res://scripts/workshop/entity_types.gd")
const Commands = preload("res://scripts/workshop/command_registry.gd")
const Art = preload("res://scripts/rendering/zone_effects.gd")

var _entries := {}

func attach(zone: Node3D, overrides: Dictionary) -> void:
	_entries = zone.get_meta("authored_dressing", {}) if zone else {}
	for id in overrides:
		if has(id):
			apply(id, overrides[id])

func refresh(zone: Node3D, overrides: Dictionary) -> void:
	var previous := _entries
	_entries = zone.get_meta("authored_dressing", {})
	for id in overrides:
		if has(id) and previous.get(id) != _entries[id]:
			apply(id, overrides[id])

func has(id: Variant) -> bool:
	return _entries.has(id)

func scene_node(id: String) -> Node3D:
	return _entries.get(id, {}).get("node") as Node3D

## The prop's absolute yaw in degrees as it stands now. A physics prop may have turned since its
## record was saved; its body is rotated relative to its authored basis, so add the authored yaw.
func live_yaw(id: String, recorded: float) -> float:
	var entry: Dictionary = _entries.get(id, {})
	if not entry.has("rigid"):
		return recorded
	var body: Node3D = entry.node
	var relative := (body.basis.orthonormalized() * (entry.basis as Basis).orthonormalized().inverse()).get_euler().y
	return wrapf(rad_to_deg(relative) + float(entry.record.yaw), -180.0, 180.0)

func can_unlock(id: String) -> bool:
	var entry: Dictionary = _entries.get(id, {})
	return entry.has("rigid") or (entry.get("physics_bounds", AABB()) as AABB).has_volume()

func records(overrides: Dictionary) -> Array:
	var result := []
	for id in _entries:
		result.append(record(id, overrides.get(id, {})))
	return result

func record(id: String, override: Dictionary) -> Dictionary:
	if not has(id):
		return {}
	var entry: Dictionary = _entries[id]
	var value: Dictionary = entry.record.duplicate(true)
	# Older saves used unlocking alone to give visual-only dressing a collider.
	if override.get("locked", true) == false:
		value["collision"] = true
	value.merge(override.duplicate(true), true)
	value["hidden"] = override.get("hidden", false)
	value["overridden"] = not override.is_empty()
	if _entries[id].has("rigid") and not value.hidden:
		value["live_position"] = Placement.coordinates(_entries[id].node.position)
		value["locked"] = override.get("locked", _entries[id].rigid.freeze)
	elif can_unlock(id):
		value["locked"] = override.get("locked", true)
	return value

func changes_for(id: String, proposed: Dictionary, current: Dictionary) -> Dictionary:
	if proposed.is_empty():
		return current.merged({"hidden": true}, true)
	var entry: Dictionary = _entries[id]
	var base: Dictionary = entry.record
	var result := {}
	for key in Commands.prop_fields(true):
		if proposed.has(key) and proposed[key] != base.get(key):
			result[key] = proposed[key]
	if can_unlock(id):
		var base_lock: bool = _entries[id].get("rigid", {}).get("freeze", true)
		if proposed.get("locked", base_lock) != base_lock:
			result["locked"] = proposed.locked
	if result.get("locked", true) == false and not base.collision:
		# First release supplies a collider for authored scenery that only had a picker.
		result["collision"] = not entry.has("rigid") or proposed.collision
	return result

static func changes_geometry(before: Dictionary, after: Dictionary) -> bool:
	for key in ["position", "yaw", "scale", "stretch", "hidden"]:
		if before.get(key) != after.get(key):
			return true
	return false

func apply(id: String, override: Dictionary, previous := {}, keep_pose := false) -> void:
	var entry: Dictionary = _entries[id]
	var value := record(id, override)
	var node: Node3D = entry.node
	if not entry.has("rigid") and override.get("locked", true) == false and can_unlock(id):
		node = _make_rigid(id, entry, value)
		_apply_rigid(node, entry, value, record(id, previous), true)
	elif entry.has("rigid"):
		_apply_rigid(node as RigidBody3D, entry, value, record(id, previous), false, keep_pose)
	else:
		node.position = Vector3(value.position[0], value.position[1], value.position[2])
		var yaw := deg_to_rad(float(value.yaw) - float(entry.record.yaw))
		var authored_basis: Basis = entry.basis
		# Stretch runs along the prop's own axes: X and Z turned by its yaw, Y up.
		var facing := Basis(Vector3.UP, deg_to_rad(float(value.yaw)))
		var stretch := facing * Basis.from_scale(EntityTypes.stretch_of(value)) * facing.inverse()
		node.basis = stretch * Basis(Vector3.UP, yaw) * authored_basis.scaled(Vector3.ONE * float(value.scale))
	node.visible = not value.hidden and node.process_mode != Node.PROCESS_MODE_DISABLED
	_apply_collision(node, entry, value)
	if override.get("color") != previous.get("color"):
		_apply_color(node, entry, Color.html(value.color))

static func _apply_collision(node: Node3D, entry: Dictionary, value: Dictionary) -> void:
	if not entry.has("picker") and not value.collision:
		entry["picker"] = AuthoredProps.add_picker(entry.get("picker_target", node), value.id)
	var picker := entry.get("picker") as CollisionShape3D
	if value.collision and not entry.record.collision and not entry.has("rigid") and picker and not entry.has("added_collider"):
		var body := StaticBody3D.new()
		body.set_meta("entity_id", value.id)
		var shape := CollisionShape3D.new()
		shape.shape = picker.shape
		shape.transform = picker.transform
		body.add_child(shape)
		node.add_child(body)
		entry["added_collider"] = shape
		entry.shapes[shape] = false
	if picker:
		picker.disabled = value.hidden or value.collision
	for shape: CollisionShape3D in entry.shapes:
		shape.disabled = value.hidden or entry.shapes[shape] or (not value.collision and shape.get_parent() is PhysicsBody3D)
	if node is RigidBody3D and node.get_meta("collision_enabled", true) != value.collision:
		node.set_meta("collision_enabled", value.collision)
		EntityTypes.set_locked(node, value.hidden or value.get("locked", entry.rigid.freeze))

static func _apply_color(node: Node3D, entry: Dictionary, tint: Color) -> void:
	if not entry.has("color_surfaces"):
		var bindings := []
		var meshes := node.find_children("*", "MeshInstance3D", true, false)
		if node is MeshInstance3D:
			meshes.push_front(node)
		for mesh: MeshInstance3D in meshes:
			if mesh.material_override:
				bindings.append([mesh, -1, mesh.material_override])
			elif mesh.mesh:
				for index in mesh.mesh.get_surface_count():
					bindings.append([mesh, index, mesh.get_active_material(index)])
		entry["color_surfaces"] = bindings
	for binding in entry.color_surfaces:
		var original: Material = binding[2]
		var material := original
		if original is BaseMaterial3D and tint != Color.WHITE:
			material = original.duplicate()
			material.albedo_color = original.albedo_color * tint
		elif original is ShaderMaterial and original.shader and original.shader.resource_path in Art.CFX_SHADERS.values() and tint != Color.WHITE:
			material = original.duplicate()
			var albedo: Color = original.get_shader_parameter("albedo")
			material.set_shader_parameter("albedo", albedo * tint)
		var mesh: MeshInstance3D = binding[0]
		if binding[1] < 0:
			mesh.material_override = material
		else:
			mesh.set_surface_override_material(binding[1], material)

static func _make_rigid(id: String, entry: Dictionary, value: Dictionary) -> RigidBody3D:
	var model: Node3D = entry.node
	var parent := model.get_parent()
	# The body takes the prop's authored yaw and the model keeps the rest of its basis, so the
	# body's own axes are the prop's (the axes stretch runs along).
	var facing := Basis(Vector3.UP, deg_to_rad(float(entry.record.yaw)))
	var model_basis: Basis = facing.inverse() * (entry.basis as Basis)
	var box: AABB = Transform3D(model_basis, Vector3.ZERO) * entry.physics_bounds
	var body := RigidBody3D.new()
	body.name = model.name if model.has_meta("piece_id") else "Dressing_" + id
	if model.has_meta("piece_id"):
		for key in ["piece_id", "piece_type", "legacy_prop"]:
			if model.has_meta(key):
				body.set_meta(key, model.get_meta(key))
				model.remove_meta(key)
	body.freeze = true
	body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	body.mass = clampf(box.get_volume() * 7.0, 3.0, 90.0)
	body.continuous_cd = true
	body.set_meta("entity_id", id)
	# The physics server reads the initial pose when the body enters the world.
	body.position = Vector3(value.position[0], value.position[1], value.position[2])
	body.rotation.y = deg_to_rad(value.yaw)
	parent.remove_child(model)
	body.add_child(model)
	model.transform = Transform3D(model_basis, Vector3.ZERO)
	for old_shape in entry.shapes:
		old_shape.disabled = true
	var shape := CollisionShape3D.new()
	var collider := BoxShape3D.new()
	collider.size = box.size.max(Vector3.ONE * 0.04)
	shape.shape = collider
	shape.position = box.get_center()
	body.add_child(shape)
	parent.add_child(body)
	entry["picker_target"] = model
	entry.node = body
	entry.basis = facing
	entry.shapes = {shape: false}
	entry.rigid = {"parts": {model: model.transform, shape: shape.transform}, "boxes": {shape: collider.size}, "freeze": true}
	return body

func reset_motion(id: String) -> void:
	var entry: Dictionary = _entries[id]
	if entry.has("rigid"):
		var value := record(id, {})
		_apply_rigid(entry.node, entry, value, value, true)

static func _apply_rigid(body: RigidBody3D, entry: Dictionary, value: Dictionary, previous: Dictionary,
		reset := false, keep_pose := false) -> void:
	if not reset and not changes_geometry(previous, value) and previous.get("locked") == value.get("locked"):
		return
	var rigid: Dictionary = entry.rigid
	if not keep_pose:
		body.freeze = true
	if not keep_pose and (reset or value.position != previous.position):
		body.position = Vector3(value.position[0], value.position[1], value.position[2])
	if not keep_pose and (reset or value.yaw != previous.yaw):
		body.basis = Basis(Vector3.UP, deg_to_rad(float(value.yaw) - float(entry.record.yaw))) * entry.basis
	if reset or value.scale != previous.scale or value.get("stretch") != previous.get("stretch"):
		# The body faces the prop's yaw, so its own axes are the stretch axes.
		var multiplier := Vector3.ONE * float(value.scale) * EntityTypes.stretch_of(value)
		for part in rigid.parts:
			var authored_transform: Transform3D = rigid.parts[part]
			part.transform = authored_transform.scaled(multiplier) if not rigid.boxes.has(part) \
				else Transform3D(authored_transform.basis, authored_transform.origin * multiplier)
		for box in rigid.boxes:
			box.shape.size = rigid.boxes[box] * multiplier
		body.set_meta("authored_scale", value.scale)
	if not keep_pose:
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
		body.reset_physics_interpolation()
		if body.is_inside_tree():
			body.force_update_transform()
		EntityTypes.set_locked(body, value.hidden or value.get("locked", rigid.freeze))

static func valid_override(override: Variant, bounds: AABB) -> bool:
	if not override is Dictionary:
		return false
	for key in override:
		match key:
			"position":
				if not Placement.valid_coordinates(bounds, override.position): return false
			"yaw":
				if not Commands.valid_field("yaw", override.yaw): return false
			"scale":
				if not Commands.valid_field("scale", override.scale): return false
			"stretch":
				if not Commands.valid_field("stretch", override.stretch): return false
			"name":
				if not EntityTypes.valid_name(override.name): return false
			"color":
				if not Commands.valid_field("color", override.color): return false
			"hidden":
				if not override.hidden is bool or not override.hidden: return false
			"locked", "collision":
				if not override[key] is bool: return false
			_: return false
	return true
