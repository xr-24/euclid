extends RefCounted
## A point (omni) or spot light. Spot lights shine along the piece's -Z.

static func build(record: Dictionary) -> Node3D:
	var light: Light3D
	if record.kind == "spot":
		var spot := SpotLight3D.new()
		spot.spot_range = float(record.get("range", 10.0))
		spot.spot_angle = float(record.get("angle", 35.0))
		light = spot
	else:
		var omni := OmniLight3D.new()
		omni.omni_range = float(record.get("range", 10.0))
		light = omni
	light.light_color = Color.html(str(record.get("color", "ffffff")))
	light.light_energy = float(record.get("energy", 1.0))
	light.shadow_enabled = bool(record.get("shadows", false))
	return light
