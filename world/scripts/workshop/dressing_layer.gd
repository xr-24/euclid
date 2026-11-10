extends RefCounted
## Runtime layer for the grouped model, plinth, and collision produced by the builder.

const Placement = preload("res://scripts/workshop/scene_placement.gd")
const EntityTypes = preload("res://scripts/workshop/entity_types.gd")
const Commands = preload("res://scripts/workshop/command_registry.gd")

var _entries := {}

func attach(zone: Node3D, overrides: Dictionary) -> void:
	_entries = zone.get_meta("authored_dressing", {}) if zone else {}
	for id in overrides:
		if has(id):
			apply(id, overrides[id])

func has(id: Variant) -> bool:
	return _entries.has(id)

func records(overrides: Dictionary) -> Array:
	var result := []
	for id in _entries:
		result.append(record(id, overrides.get(id, {})))
	return result

func record(id: String, override: Dictionary) -> Dictionary:
	if not has(id):
		return {}
	var value: Dictionary = _entries[id].record.duplicate(true)
	value.merge(override.duplicate(true), true)
	value["hidden"] = override.get("hidden", false)
	value["overridden"] = not override.is_empty()
	if _entries[id].has("rigid") and not value.hidden:
		value["live_position"] = Placement.coordinates(_entries[id].node.position)
	return value

func changes_for(id: String, proposed: Dictionary, current: Dictionary) -> Dictionary:
	if proposed.is_empty():
		return current.merged({"hidden": true}, true)
	var base: Dictionary = _entries[id].record
	var result := {}
	for key in Commands.prop_fields(true):
		if proposed.has(key) and proposed[key] != base.get(key):
			result[key] = proposed[key]
	return result

static func changes_geometry(before: Dictionary, after: Dictionary) -> bool:
	for key in ["position", "yaw", "scale", "hidden"]:
		if before.get(key) != after.get(key):
			return true
	return false

func apply(id: String, override: Dictionary, previous := {}) -> void:
	var entry: Dictionary = _entries[id]
	var value := record(id, override)
	var node: Node3D = entry.node
	if entry.has("rigid"):
		_apply_rigid(node as RigidBody3D, entry, value, record(id, previous))
	else:
		node.position = Vector3(value.position[0], value.position[1], value.position[2])
		var yaw := deg_to_rad(float(value.yaw) - float(entry.record.yaw))
		var authored_basis: Basis = entry.basis
		node.basis = Basis(Vector3.UP, yaw) * authored_basis.scaled(Vector3.ONE * float(value.scale))
	node.visible = not value.hidden
	for shape in entry.shapes:
		shape.disabled = value.hidden or entry.shapes[shape]

func reset_motion(id: String) -> void:
	var entry: Dictionary = _entries[id]
	if entry.has("rigid"):
		var value := record(id, {})
		_apply_rigid(entry.node, entry, value, value, true)

static func _apply_rigid(body: RigidBody3D, entry: Dictionary, value: Dictionary, previous: Dictionary, reset := false) -> void:
	if not reset and not changes_geometry(previous, value):
		return
	var rigid: Dictionary = entry.rigid
	body.freeze = true
	if reset or value.position != previous.position:
		body.position = Vector3(value.position[0], value.position[1], value.position[2])
	if reset or value.yaw != previous.yaw:
		body.basis = Basis(Vector3.UP, deg_to_rad(float(value.yaw) - float(entry.record.yaw))) * entry.basis
	if value.scale != previous.scale:
		var multiplier := Vector3.ONE * float(value.scale)
		for part in rigid.parts:
			var authored_transform: Transform3D = rigid.parts[part]
			part.transform = authored_transform.scaled(multiplier) if not rigid.boxes.has(part) \
				else Transform3D(authored_transform.basis, authored_transform.origin * multiplier)
		for box in rigid.boxes:
			box.shape.size = rigid.boxes[box] * multiplier
		body.set_meta("authored_scale", value.scale)
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.reset_physics_interpolation()
	body.freeze = value.hidden or rigid.freeze
	if not body.freeze:
		body.sleeping = false

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
			"name":
				if not EntityTypes.valid_name(override.name): return false
			"hidden":
				if not override.hidden is bool or not override.hidden: return false
			_: return false
	return true
