extends RefCounted
## Materials for pieces, shared between pieces with the same settings. Shared materials are
## immutable templates; the construct effect converts them per instance.

const Assets = preload("res://scripts/assets/asset_library.gd")
const DEFAULT_COLOR := Color("b8b4ac")
const STYLES := {
	"lattice": preload("res://shaders/grid_floor.gdshader"),
	"fractured_panels": preload("res://shaders/grid_wall.gdshader"),
}

static var _cache := {}
static var _mutex := Mutex.new()

static func make(spec: Dictionary) -> Material:
	var key := JSON.stringify(spec, "", true)
	_mutex.lock()
	var cached := _cache.get(key) as Material
	_mutex.unlock()
	if cached:
		return cached
	var style: String = spec.get("style", "standard")
	var made: Material
	if STYLES.has(style):
		var shader_material := ShaderMaterial.new()
		shader_material.shader = STYLES[style]
		shader_material.set_shader_parameter("surface_tint", Color.html(spec.get("color", "ffffff")))
		if style == "lattice":
			shader_material.set_shader_parameter("floor_spacing", float(spec.get("line_spacing", 2.0)))
		made = shader_material
	else:
		made = _standard(spec)
	_mutex.lock()
	if _cache.size() >= 256:
		_cache.erase(_cache.keys()[0])
	if not _cache.has(key):
		_cache[key] = made
	var template: Material = _cache[key]
	_mutex.unlock()
	return template

static func _standard(spec: Dictionary) -> BaseMaterial3D:
	var tint := Color.html(str(spec.get("color", "ffffff" if spec.has("texture") else DEFAULT_COLOR.to_html(false))))
	var made: BaseMaterial3D
	if spec.has("texture"):
		var template := Assets.pbr(str(spec.texture), float(spec.get("texture_size", 2.0)), tint, tint)
		made = template.duplicate() as BaseMaterial3D
	else:
		made = StandardMaterial3D.new()
		made.albedo_color = tint
		made.roughness = 0.75
	if spec.has("roughness"):
		made.roughness = float(spec.roughness)
	if spec.has("metallic"):
		made.metallic = float(spec.metallic)
	if spec.has("emission"):
		made.emission_enabled = true
		made.emission = Color.html(str(spec.emission))
		made.emission_energy_multiplier = float(spec.get("emission_energy", 1.0))
	return made
