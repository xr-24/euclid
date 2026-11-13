extends RefCounted
## Material recipes for imported geometry. Mesh names select a recipe from the piece record.

const Assets = preload("res://scripts/assets/asset_library.gd")

static func make(rule: Dictionary) -> Material:
	var style: String = rule.get("style", "pbr")
	var tint := _color(rule.get("tint", [1, 1, 1]))
	var fallback := Color.html(rule.get("fallback", "ffffff"))
	if style == "pbr" and rule.has("texture"):
		return Assets.pbr(rule.texture, float(rule.get("tile", 3)), tint, fallback)
	if style == "fresco":
		var mat := ShaderMaterial.new()
		mat.shader = Assets.get_resource("res://shaders/fresco.gdshader")
		var plaster := Assets.texture_set("red_plaster_weathered")
		if not plaster.is_empty():
			mat.set_shader_parameter("plaster_albedo", plaster.albedo)
			mat.set_shader_parameter("plaster_normal", plaster.normal)
		mat.set_shader_parameter("frieze", rule.get("frieze", false))
		mat.set_shader_parameter("period", float(rule.get("period", 2.9166667)))
		mat.set_shader_parameter("offset", float(rule.get("offset", 0)))
		return mat
	if style in ["coastal_terrain", "wet_sand"]:
		return _landscape(rule, style)
	if rule.is_empty():
		return null
	var standard := StandardMaterial3D.new()
	standard.albedo_color = tint if rule.has("tint") else fallback
	standard.roughness = float(rule.get("roughness", 0.8))
	standard.metallic = float(rule.get("metallic", 0))
	if style in ["foliage", "foliage_core"]:
		var path := "res://assets/generated/" + str(rule.get("texture", ""))
		if ResourceLoader.exists(path + ".png"):
			standard.albedo_texture = Assets.get_resource(path + ".png")
		if style == "foliage":
			if ResourceLoader.exists(path + "_n.png"):
				standard.normal_enabled = true
				standard.normal_texture = Assets.get_resource(path + "_n.png")
				standard.normal_scale = 0.7
			standard.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			standard.alpha_scissor_threshold = 0.45
			standard.cull_mode = BaseMaterial3D.CULL_DISABLED
			standard.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		else:
			standard.uv1_triplanar = true
			standard.uv1_scale = Vector3.ONE * float(rule.get("tile", 3))
	return standard

static func _landscape(rule: Dictionary, style: String) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = Assets.get_resource("res://shaders/coast_terrain.gdshader" if style == "coastal_terrain" else "res://shaders/shore_terrain.gdshader")
	var layers := ["grass", "dirt", "cliff", "sand"] if style == "coastal_terrain" else ["dry", "wet", "rock"]
	var textures: Array = rule.get("textures", [])
	for index in mini(layers.size(), textures.size()):
		var texture := Assets.texture_set(textures[index])
		for channel in ["albedo", "normal", "orm"]:
			if texture.has(channel):
				mat.set_shader_parameter(layers[index] + "_" + channel, texture[channel])
	mat.set_shader_parameter("macro_noise", Assets.noise_texture(9 if style == "coastal_terrain" else 3,
		0.01 if style == "coastal_terrain" else 0.008, false, 256))
	mat.set_shader_parameter("sea_level", float(rule.get("sea_level", 0)))
	if style == "coastal_terrain":
		mat.set_shader_parameter("beach_top", float(rule.get("beach_top", 0)))
	return mat

static func _color(values: Array) -> Color:
	return Color(values[0], values[1], values[2])
