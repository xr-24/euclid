extends RefCounted
## Project-owned environment packages. Runtime saves refer to package IDs.

const DIRECTORY := "res://data/zones"
const Commands = preload("res://scripts/workshop/command_registry.gd")
const PieceTypes = preload("res://scripts/pieces/piece_types.gd")
const PieceDocument = preload("res://scripts/persistence/piece_document.gd")
static var _world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
static var _packages := _load_packages()
static var _aliases := {}

static func ids() -> Array:
	return _packages.keys()

static func startup_zone() -> String:
	return _world.get("startup_zone", _world.zones[0].id)

static func workshop_zone() -> String:
	return _world.get("workshop_zone", startup_zone())

static func definition(id: String) -> Dictionary:
	return _packages.get(_aliases.get(id, id), _packages.get(startup_zone(), {}))

static func has(id: Variant) -> bool:
	return id is String and _packages.has(id)

static func register_zone(zone: Dictionary) -> void:
	var package: String = zone.get("package", workshop_zone() if zone.get("template") == "grid" else zone.id)
	if _packages.has(package):
		_aliases[zone.id] = package

static func spawn(id: String) -> Dictionary:
	var state: Dictionary = definition(id).spawn
	return {"position": vector(state.position), "yaw": float(state.yaw)}

static func bounds(id: String) -> AABB:
	var corners: Array = definition(id).bounds
	return AABB(vector(corners[0]), vector(corners[1]))

static func piece_bounds(id: String) -> AABB:
	var package := definition(id)
	var corners: Array = package.get("piece_bounds", package.bounds)
	return AABB(vector(corners[0]), vector(corners[1]))

static func environment(id: String) -> Dictionary:
	var profile: Dictionary = definition(id).environment.duplicate(true)
	for key in profile:
		if key.ends_with("_color") or key == "fog_albedo":
			profile[key] = Color(profile[key])
	if profile.has("sky_colors"):
		profile.sky_colors = profile.sky_colors.map(func(value: String) -> Color: return Color(value))
	return profile

static func views(id: String, group: String) -> Array:
	var package := definition(id)
	var result := []
	for key in package.get(group + "_views", []):
		var view: Dictionary = package.views[key]
		result.append([key, vector(view.position), vector(view.target)])
	return result

static func vector(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])

static func valid(value: Variant) -> bool:
	if not value is Dictionary or value.get("schema_version") != 1 or not value.get("id") is String \
			or not value.get("capabilities") is Dictionary \
			or not value.get("spawn") is Dictionary or not value.get("environment") is Dictionary \
			or not value.get("views") is Dictionary or not value.get("bounds") is Array or value.bounds.size() != 2:
		return false
	if RegEx.create_from_string("^[a-z][a-z0-9_-]{0,63}$").search(value.id) == null \
			or not value.capabilities.get("workshop") is bool or not value.capabilities.get("scene_edit") is bool \
			or not value.get("water") is Array or not value.water.all(func(item: Variant) -> bool: return item is String) \
			or not value.get("layers") is Dictionary or not value.get("graphics") is Dictionary \
			or value.get("workstation") not in ["grid", "villa", "beach"] or not _number(value.get("capture_warmup")) \
			or value.capture_warmup < 0 or value.capture_warmup > 120:
		return false
	if not PieceTypes.valid_tree(value.get("pieces")) or value.has("builder"):
		return false
	var geometry: Variant = value.get("required_geometry", [])
	if not geometry is Array or not geometry.all(func(id: Variant) -> bool:
		return id is String and id.is_valid_identifier()):
		return false
	if not PieceDocument.valid_revision(value.get("piece_revision", 0)):
		return false
	if value.has("piece_replacements") and not PieceTypes.valid_tree(value.piece_replacements):
		return false
	if value.has("piece_bounds") and not _valid_bounds(value.piece_bounds):
		return false
	var bindings: Variant = value.get("piece_appearance", {})
	if not bindings is Dictionary:
		return false
	for binding: Variant in bindings.values():
		if not binding is Dictionary or not binding.get("id") is String or not binding.get("path") is Array:
			return false
		if binding.path.is_empty() or binding.path.size() > 2 or not binding.path.all(_binding_key):
			return false
	for spec in [["name", 96], ["description", 180]]:
		if value.has(spec[0]) and (not value[spec[0]] is String or value[spec[0]].length() > spec[1]):
			return false
	var fallback: Variant = value.get("fallback")
	if not fallback is Dictionary or fallback.get("style") not in ["grid", "columns", "coast", "plain"] \
			or not _number(fallback.get("floor_y")) or not fallback.get("walls") is bool:
		return false
	var profile: Dictionary = value.environment
	for key in ["sun_azimuth", "sun_energy", "sky_energy", "exposure", "fog_density", "fog_anisotropy", "shadow_distance", "sdfgi_cell"]:
		if not _number(profile.get(key)):
			return false
	for key in ["sun_color", "fog_albedo"]:
		if not profile.get(key) is String or not Color.html_is_valid(profile[key]):
			return false
	for entry in [["time_mode", "time_mode"], ["time_of_day", "time_of_day"], ["day_length", "day_length"],
			["cloud_cover", "weather_amount"], ["rain", "weather_amount"], ["eye_adaptation", "eye_adaptation"],
			["bounce_light", "bounce_light"], ["contrast", "contrast"]]:
		if profile.has(entry[0]) and not Commands.valid_field(entry[1], profile[entry[0]]):
			return false
	if not profile.get("hdri") is String and not profile.get("sky_colors") is Array:
		return false
	if profile.has("sky_colors") and (profile.sky_colors.size() != 4 or not profile.sky_colors.all(
			func(color: Variant) -> bool: return color is String and Color.html_is_valid(color))):
		return false
	for path in value.layers.values():
		if not path is String or not path.begins_with("res://data/") or ".." in path or path.get_extension() != "json":
			return false
	for coordinates in value.bounds + [value.spawn.get("position")]:
		if not _valid_vector(coordinates):
			return false
	if not _number(value.spawn.get("yaw")) \
			or vector(value.bounds[1]).x <= 0 or vector(value.bounds[1]).y <= 0 or vector(value.bounds[1]).z <= 0:
		return false
	for view in value.views.values():
		if not view is Dictionary or not _valid_vector(view.get("position")) or not _valid_vector(view.get("target")):
			return false
	for group in ["capture_views", "benchmark_views"]:
		if not value.get(group) is Array or not value[group].all(func(key: Variant) -> bool: return value.views.has(key)):
			return false
	if value.benchmark_views.is_empty():
		return false
	return true

static func _binding_key(value: Variant) -> bool:
	return value is String and value.is_valid_identifier()

static func _valid_bounds(value: Variant) -> bool:
	if not value is Array or value.size() != 2 or not value.all(_valid_vector):
		return false
	var size := vector(value[1])
	return size.x > 0.0 and size.y > 0.0 and size.z > 0.0

static func _valid_vector(value: Variant) -> bool:
	return value is Array and value.size() == 3 and value.all(_number)

static func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

static func _load_packages() -> Dictionary:
	var result := {}
	for folder in DirAccess.get_directories_at(DIRECTORY):
		var path := DIRECTORY.path_join(folder).path_join("zone.json")
		if not FileAccess.file_exists(path):
			continue
		var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not valid(value) or value.id != folder:
			push_error("Invalid environment package: " + path)
			continue
		result[value.id] = value
	return result
