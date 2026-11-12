extends RefCounted
## Materials for pieces, shared between pieces with the same settings. Shared materials are
## immutable templates; the construct effect converts them per instance.

const Assets = preload("res://scripts/assets/asset_library.gd")
const DEFAULT_COLOR := Color("b8b4ac")

static var _cache := {}

static func make(spec: Dictionary) -> BaseMaterial3D:
	var key := JSON.stringify(spec, "", true)
	if _cache.has(key):
		return _cache[key]
	var tint := Color.html(str(spec.get("color", "ffffff" if spec.has("texture") else DEFAULT_COLOR.to_html(false))))
	var made: BaseMaterial3D
	if spec.has("texture"):
		var template := Assets.pbr(str(spec.texture), float(spec.get("texture_size", 2.0)), tint, tint)
		made = template.duplicate() as BaseMaterial3D
	else:
		made = StandardMaterial3D.new()
		made.albedo_color = tint
		made.roughness = float(spec.get("roughness", 0.75))
		made.metallic = float(spec.get("metallic", 0.0))
	if spec.has("emission"):
		made.emission_enabled = true
		made.emission = Color.html(str(spec.emission))
		made.emission_energy_multiplier = float(spec.get("emission_energy", 1.0))
	_cache[key] = made
	return made
