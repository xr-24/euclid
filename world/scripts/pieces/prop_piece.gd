extends RefCounted
## Piece records and legacy workshop records share the physical prop factory.

const Types = preload("res://scripts/workshop/entity_types.gd")
const DoorActuator = preload("res://scripts/plugins/door_actuator.gd")
const Motion = preload("res://scripts/animation/prop_motion.gd")
const DoorLinks = preload("res://scripts/plugins/door_links.gd")

static func valid_record(record: Dictionary) -> bool:
	return Types.valid_properties(entity_record(record))

static func build(record: Dictionary) -> Node3D:
	var data := entity_record(record)
	data.position = [0, 0, 0]
	data.yaw = 0.0
	var body := Types.create(data)
	var motion := Motion.new()
	motion.name = "PropMotion"
	motion.clip = data.get("animation", {})
	body.add_child(motion)
	if data.type == "sliding_door":
		var actuator := DoorActuator.new()
		actuator.name = "DoorActuator"
		actuator.links = DoorLinks.new()
		actuator.entity_id = record.id
		actuator.travel = 2.5 * data.scale
		actuator.links.drive("piece", record.id, float(record.get("door_open", 0.0)), 2.0)
		body.add_child(actuator)
	return body

static func entity_record(record: Dictionary) -> Dictionary:
	var kind: String = record.prop_kind
	var data := {"id": record.id, "type": kind, "position": record.get("position", [0, 0, 0]),
		"yaw": record.get("rotation", [0, 0, 0])[1], "scale": record.get("prop_size", 1.0),
		"color": record.get("color", Types.TYPES[kind].color), "locked": record.get("locked", false)}
	for key in ["asset_id", "stretch", "name", "animation"]:
		if record.get(key) != null:
			data[key] = record[key]
	if record.has("behavior"):
		var binding: Dictionary = record.behavior
		var settings := {}
		for setting: Dictionary in binding.settings:
			settings[setting.key] = setting.value
		data["behavior"] = {"id": binding.id, "settings": settings}
		if not str(binding.get("target_entity", "")).is_empty():
			data.behavior["target"] = binding.target_entity
	if kind == "sliding_door":
		data.erase("stretch")
	return data

static func update_fields(node: Node3D, before: Dictionary, after: Dictionary) -> bool:
	for key in ["prop_kind", "asset_id", "color"]:
		if before.get(key) != after.get(key):
			return false
	var motion := node.get_node_or_null("PropMotion")
	if motion and before.get("animation") != after.get("animation"):
		motion.set_clip(after.get("animation") if after.get("animation") != null else {})
	if node is RigidBody3D:
		var previous := entity_record(before)
		var next := entity_record(after)
		_update_rigid(node, previous, next)
		return true
	var door := node.get_node_or_null("DoorActuator")
	if door == null or before.get("prop_size") != after.get("prop_size"):
		return false
	door.links.drive("piece", after.id, float(after.get("door_open", 0.0)), 2.0)
	return true

static func _update_rigid(node: RigidBody3D, previous: Dictionary, next: Dictionary) -> void:
	Types.update_placement(node, previous, next, true)
	if previous.locked != next.locked or Types.movable(previous) != Types.movable(next):
		Types.set_locked(node, next.locked or not Types.movable(next))
