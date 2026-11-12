extends RefCounted
## Each builder registers one visible water body with its bounds and shared surface materials.

const Store = preload("res://scripts/persistence/world_state_store.gd")
const COMMON := {"reflection_strength": ["Reflectivity", 0.0, 1.0, 1.0]}
const COAST_LINKS := {"reflection_strength": "reflection_strength", "scatter_color": "shallow_color",
	"deep_scatter": "deep_color", "foam_albedo": "foam_color", "base_roughness": "roughness_value",
	"refraction_strength": "refraction"}
const FOAM_OVERRIDES := {"foam_strength": "foam_strength_override", "foam_softness": "foam_softness_override"}
const SIM := {
	"scatter_color": ["Shallow color", "2c7c7c"], "deep_scatter": ["Deep color", "1d4d61"],
	"foam_albedo": ["Foam color", "cecece"], "absorption": ["Absorption RGB", 0.0, 4.0, [1.1, 0.32, 0.42]],
	"base_roughness": ["Roughness", 0.0, 1.0, 0.045], "detail_normal_strength": ["Ripple detail", 0.0, 1.0, 0.32],
	"refraction_strength": ["Refraction", 0.0, 0.06, 0.06], "foam_strength": ["Foam amount", 0.0, 1.0, 1.0],
	"foam_softness": ["Foam softness", 0.5, 2.0, 1.0], "lace_scale_coarse": ["Coarse foam scale", 0.1, 10.0, 1.2],
	"lace_scale_fine": ["Fine foam scale", 0.01, 2.0, 0.12], "flow_speed_scale": ["Foam flow", 0.0, 4.0, 1.0],
	"flow_period": ["Foam flow period", 0.2, 10.0, 2.0],
}
const SIMPLE := {
	"shallow_color": ["Shallow color", "298f8a"], "deep_color": ["Deep color", "031726"], "foam_color": ["Foam color", "ebece5"],
	"roughness_value": ["Roughness", 0.0, 1.0, 0.035], "clarity": ["Clarity", 0.05, 8.0, 2.2],
	"colour_depth": ["Color depth", 0.1, 16.0, 6.0], "ripple_strength": ["Ripple detail", 0.0, 1.0, 0.55],
	"ripple_scale": ["Ripple scale", 0.2, 15.0, 7.0], "refraction": ["Refraction", 0.0, 0.06, 0.035],
	"foam_amount": ["Foam amount", 0.0, 2.0, 1.0], "foam_width": ["Foam width", 0.05, 2.0, 0.45],
	"swell": ["Swell (m)", 0.0, 0.3, 0.16], "swell_speed": ["Swell speed", 0.0, 3.0, 1.0],
}

var _path: String
var _saved := {}
var _bodies := {}
var _zone := ""
var _root: Node3D

func _init(path: String) -> void:
	_path = path
	var file := FileAccess.open(path, FileAccess.READ) if not path.is_empty() else null
	if file and file.get_length() < 262144:
		var data: Variant = JSON.parse_string(file.get_as_text())
		if data is Dictionary and data.get("version") == 1 and data.get("bodies") is Dictionary:
			_saved = data.bodies

static func register(root: Node3D, id: String, label: String, rect: Rect2, height: float,
		materials: Array, radius := 0.0, outer: Array = []) -> void:
	if materials.is_empty():
		return
	var bodies: Dictionary = root.get_meta("editable_water", {})
	var primary: ShaderMaterial = materials[0]
	var sim := primary.shader.resource_path.ends_with("/shore_water.gdshader")
	var rules := COMMON.merged(SIM if sim else SIMPLE)
	var defaults := {}
	var bindings := {}
	for key in rules:
		var current: Variant = primary.get_shader_parameter(key)
		if current is Vector3:
			current = Color(current.x, current.y, current.z).linear_to_srgb().to_html(false) if rules[key].size() == 2 else [current.x, current.y, current.z]
		elif current is Color:
			current = current.to_html(false)
		defaults[key] = current if current != null else rules[key].back()
		var uniform_name: String = FOAM_OVERRIDES.get(key, key) if sim else key
		bindings[key] = materials.map(func(material: ShaderMaterial) -> Dictionary: return _binding(material, uniform_name, sim))
		if COAST_LINKS.has(key):
			for material: ShaderMaterial in outer:
				bindings[key].append(_binding(material, COAST_LINKS[key], false))
	bodies[id] = {"label": label, "rect": rect, "height": height, "rules": rules, "primary": primary,
		"defaults": defaults, "bindings": bindings, "radius": radius, "sim": sim}
	root.set_meta("editable_water", bodies)

static func _binding(material: ShaderMaterial, uniform_name: String, sim: bool) -> Dictionary:
	return {"material": material, "uniform": uniform_name, "base": material.get_shader_parameter(uniform_name), "linear_color": sim}

func attach(root: Node3D, zone: String) -> void:
	_root = root
	_zone = zone
	_bodies = root.get_meta("editable_water", {})
	for id in _bodies:
		_apply(id)

func pick(aim: Dictionary) -> String:
	if not is_instance_valid(_root):
		return ""
	var start := _root.to_local(aim.from)
	var end := _root.to_local(aim.point)
	var closest := 1.0
	var selected := ""
	for id in _bodies:
		var body: Dictionary = _bodies[id]
		if is_equal_approx(start.y, end.y):
			continue
		var t := (float(body.height) - start.y) / (end.y - start.y)
		if t < 0 or t >= closest:
			continue
		var point := start.lerp(end, t)
		var xz := Vector2(point.x, point.z)
		if body.rect.has_point(xz) and (body.radius <= 0 or xz.distance_to(body.rect.get_center()) <= body.radius):
			selected = id
			closest = t
	return selected

func inspect(id: String) -> Dictionary:
	var body: Dictionary = _bodies.get(id, {})
	if body.is_empty():
		return {}
	var values: Dictionary = body.defaults.duplicate()
	if body.sim:
		for key in FOAM_OVERRIDES:
			var foam: Variant = body.primary.get_shader_parameter(key)
			if foam != null:
				values[key] = foam
	return {"label": body.label, "rules": body.rules, "values": values.merged(_overrides(id), true)}

func edit(id: String, key: String, input: String) -> String:
	if not _bodies.has(id):
		return "That water body is no longer in this scene."
	var overrides := _overrides(id)
	if key.is_empty():
		overrides.clear()
	else:
		var rule: Array = _bodies[id].rules.get(key, [])
		if rule.is_empty():
			return "That setting is unavailable."
		var value: Variant = input.strip_edges().trim_prefix("#")
		if rule.size() == 4:
			if rule[3] is Array:
				value = Array(input.replace(",", " ").split(" ", false)).map(func(part: String) -> Variant:
					return part.to_float() if part.is_valid_float() else null)
			else:
				value = input.to_float() if input.is_valid_float() else null
		if not _valid(rule, value):
			return "Enter RGB hex." if rule.size() == 2 else "Use values from %s to %s." % [rule[1], rule[2]]
		overrides[key] = value
	var next := _saved.duplicate()
	next[_key(id)] = overrides
	if not _path.is_empty() and Store.write_json(_path, {"version": 1, "bodies": next}) != OK:
		return "Could not save water settings."
	_saved = next
	_apply(id)
	return ""

func _key(id: String) -> String:
	return _zone + "/" + id

func _overrides(id: String) -> Dictionary:
	var values: Variant = _saved.get(_key(id), {})
	var result := {}
	if values is Dictionary:
		for key in values:
			if _bodies[id].rules.has(key) and _valid(_bodies[id].rules[key], values[key]):
				result[key] = values[key]
	return result

func _apply(id: String) -> void:
	var body: Dictionary = _bodies[id]
	var values := _overrides(id)
	var previous: Dictionary = body.get("applied", {})
	for key in body.rules:
		if not values.has(key):
			if previous.has(key):
				for binding: Dictionary in body.bindings[key]:
					binding.material.set_shader_parameter(binding.uniform, binding.base)
			continue
		for binding: Dictionary in body.bindings[key]:
			binding.material.set_shader_parameter(binding.uniform, _shader_value(values[key], binding.linear_color))
	body["applied"] = values

static func _shader_value(value: Variant, linear_color: bool) -> Variant:
	if value is String:
		var color := Color.html(value)
		if not linear_color:
			return color
		color = color.srgb_to_linear()
		return Vector3(color.r, color.g, color.b)
	if value is Array:
		return Vector3(value[0], value[1], value[2])
	return value

static func _valid(rule: Array, value: Variant) -> bool:
	if rule.size() == 2:
		return value is String and value.length() == 6 and Color.html_is_valid(value)
	if rule[3] is Array:
		return value is Array and value.size() == 3 and value.all(func(part: Variant) -> bool: return _number(part, rule[1], rule[2]))
	return _number(value, rule[1], rule[2])

static func _number(value: Variant, lo: float, hi: float) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and value >= lo and value <= hi
