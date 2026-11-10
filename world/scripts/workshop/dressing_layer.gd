extends RefCounted
## Runtime layer for the grouped model, plinth, and collision produced by the builder.

const Placement = preload("res://scripts/workshop/scene_placement.gd")
const EntityTypes = preload("res://scripts/workshop/entity_types.gd")
const PROPERTIES := ["position", "yaw", "scale", "name"]

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
	return value

func changes_for(id: String, proposed: Dictionary, current: Dictionary) -> Dictionary:
	if proposed.is_empty():
		return current.merged({"hidden": true}, true)
	var base: Dictionary = _entries[id].record
	var result := {}
	for key in PROPERTIES:
		if proposed.has(key) and proposed[key] != base.get(key):
			result[key] = proposed[key]
	return result

static func changes_geometry(before: Dictionary, after: Dictionary) -> bool:
	for key in ["position", "yaw", "scale", "hidden"]:
		if before.get(key) != after.get(key):
			return true
	return false

func apply(id: String, override: Dictionary) -> void:
	var entry: Dictionary = _entries[id]
	var value := record(id, override)
	var node: Node3D = entry.node
	node.position = Vector3(value.position[0], value.position[1], value.position[2])
	node.rotation_degrees.y = value.yaw
	node.scale = Vector3.ONE * value.scale
	node.visible = not value.hidden
	for shape in entry.shapes:
		shape.disabled = value.hidden or entry.shapes[shape]

static func valid_override(override: Variant, bounds: AABB) -> bool:
	if not override is Dictionary:
		return false
	for key in override:
		match key:
			"position":
				if not Placement.valid_coordinates(bounds, override.position): return false
			"yaw":
				if not EntityTypes.number_between(override.yaw, -360.0, 360.0): return false
			"scale":
				if not EntityTypes.number_between(override.scale, 0.25, 4.0): return false
			"name":
				if not EntityTypes.valid_name(override.name): return false
			"hidden":
				if not override.hidden is bool or not override.hidden: return false
			_: return false
	return true
