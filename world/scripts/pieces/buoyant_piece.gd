extends RefCounted
## A floating physics model. It uses the same probe and drag as other water bodies.

const Water = preload("res://scripts/simulation/water_system.gd")

static func build(record: Dictionary) -> Node3D:
	var parent := Node3D.new()
	var body := Water.create_floater(parent, record.asset_id, Vector3.ZERO,
		float(record.get("model_height", 1.0)), float(record.get("mass", 40.0)))
	if body == null:
		return parent
	parent.remove_child(body)
	parent.free()
	body.set_meta("water_floater", true)
	body.set_meta("legacy_prop", {"asset": record.asset_id, "label": record.get("name", "")})
	return body
