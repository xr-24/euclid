extends RefCounted
## Data contract for world content. Theme data cannot select scripts or execute commands.
const Packages = preload("res://scripts/zones/zone_packages.gd")

static func read(path: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		push_error("Could not parse world manifest: " + json.get_error_message())
		return {}
	var errors := validate(json.data)
	if not errors.is_empty():
		push_error("Invalid world manifest: " + "; ".join(errors))
		return {}
	var manifest: Dictionary = json.data
	for id in Packages.ids():
		if not manifest.zones.any(func(zone: Dictionary) -> bool: return zone.id == id):
			var package := Packages.definition(id)
			manifest.zones.append({"id": id, "name": package.get("name", id.capitalize()),
				"description": package.get("description", ""), "color": package.get("color", "071217")})
	for zone in manifest.zones:
		Packages.register_zone(zone)
	return manifest

static func validate(data: Variant) -> PackedStringArray:
	var errors := PackedStringArray()
	if not data is Dictionary or data.get("schema_version") != 1:
		return ["Expected a version 1 world manifest"]
	if not data.get("zones") is Array or data.zones.is_empty() or not data.get("anchors") is Array:
		return ["Expected zones and anchors arrays, with at least one zone"]
	var zones := {}
	for zone in data.zones:
		if not zone is Dictionary or not _id(zone.get("id")) or not zone.get("name") is String:
			errors.append("Zone requires a stable id and display name")
			continue
		if zones.has(zone.id): errors.append("Duplicate zone id: " + zone.id)
		zones[zone.id] = true
	for field in ["startup_zone", "workshop_zone", "benchmark_zone"]:
		if data.has(field) and (not _id(data[field]) or not zones.has(data[field])):
			errors.append("Unknown environment in " + field)
	var anchors := {}
	for anchor in data.anchors:
		if not anchor is Dictionary or not _id(anchor.get("id")):
			errors.append("Anchor requires a stable id")
			continue
		if anchors.has(anchor.id): errors.append("Duplicate anchor id: " + anchor.id)
		anchors[anchor.id] = true
		if not zones.has(anchor.get("zone")): errors.append("Anchor references an unknown zone: " + anchor.id)
		var position = anchor.get("position")
		if not position is Array or position.size() != 3:
			errors.append("Anchor requires a 3D position: " + anchor.id)
		else:
			for value in position:
				if not (value is float or value is int) or not is_finite(float(value)):
					errors.append("Anchor position must contain finite numbers: " + anchor.id)
		if not anchor.get("label") is String: errors.append("Anchor requires a display label: " + anchor.id)
		match anchor.get("kind"):
			"application":
				if not _id(anchor.get("app_id")): errors.append("Application anchor requires app_id: " + anchor.id)
			"agent":
				if not _id(anchor.get("agent_id")): errors.append("Agent anchor requires agent_id: " + anchor.id)
			_: errors.append("Unsupported anchor kind: " + anchor.id)
	return errors

static func _id(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length() > 100:
		return false
	for character in value:
		if not character.to_lower() in "abcdefghijklmnopqrstuvwxyz0123456789._-":
			return false
	return true
