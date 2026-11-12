extends RefCounted
## Construct/deconstruct material conversion and per-instance transition state.
const Assets = preload("res://scripts/assets/asset_library.gd")
static var _converted := {}
const CFX_SHADERS := {
	"opaque": "res://shaders/constructible_opaque.gdshader",
	"opaque_double": "res://shaders/constructible_double.gdshader",
	"scissor": "res://shaders/constructible_scissor.gdshader",
	"scissor_double": "res://shaders/constructible_scissor.gdshader",
	"blend": "res://shaders/constructible_blend.gdshader",
}
const CFX_CHANNELS := [Vector4(1, 0, 0, 0), Vector4(0, 1, 0, 0), Vector4(0, 0, 1, 0), Vector4(0, 0, 0, 1), Vector4(0.333333, 0.333333, 0.333333, 0)]


static func make_constructible(root: Node, cache := true) -> void:
	var converted := _converted if cache else {}
	var meshes := root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		meshes.push_front(root)
	for node in meshes:
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		if mi.material_override:
			mi.material_override = _constructible(mi.material_override, converted)
		else:
			for i in mi.mesh.get_surface_count():
				var mat := mi.get_active_material(i)
				if mat:
					mi.set_surface_override_material(i, _constructible(mat, converted))

## Which side of the shift front a zone is on: -1 unravels, +1 assembles, 0 normal. Surfaces that
## cannot take the effect (text) are hidden while a shift runs.

static func set_side(root: Node, side: float) -> void:
	root.set_meta("construct_side", side)
	for node in root.find_children("*", "GeometryInstance3D", true, false):
		var gi := node as GeometryInstance3D
		var fx := gi is MeshInstance3D and (gi as MeshInstance3D).mesh != null
		if fx:
			var mi := gi as MeshInstance3D
			fx = _has_fx(mi.material_override) if mi.material_override else \
				(mi.mesh.get_surface_count() > 0 and _has_fx(mi.get_active_material(0)))
		if fx:
			gi.set_instance_shader_parameter("construct_side", side)
		elif side != 0.0:
			if not gi.has_meta("cfx_hidden"):
				gi.set_meta("cfx_hidden", gi.visible)
			gi.visible = false
		elif gi.has_meta("cfx_hidden"):
			gi.visible = gi.get_meta("cfx_hidden")
			gi.remove_meta("cfx_hidden")

## Re-learn global illumination for the zone now in place (called mid-shift, under the effect).

static func _has_fx(mat: Material) -> bool:
	return mat is ShaderMaterial and (mat as ShaderMaterial).shader != null and "construct" in (mat as ShaderMaterial).shader.code

static func _constructible(mat: Material, converted: Dictionary) -> Material:
	if converted.has(mat):
		return converted[mat]
	var out: Material = mat
	if mat is BaseMaterial3D:
		out = _convert(mat as BaseMaterial3D)
	converted[mat] = out
	return out

static func _convert(m: BaseMaterial3D) -> ShaderMaterial:
	var variant := "opaque"
	match m.transparency:
		BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR, BaseMaterial3D.TRANSPARENCY_ALPHA_HASH:
			variant = "scissor"
		BaseMaterial3D.TRANSPARENCY_ALPHA, BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS:
			variant = "blend"
	if variant != "blend" and m.cull_mode == BaseMaterial3D.CULL_DISABLED:
		variant += "_double"
	var sm := ShaderMaterial.new()
	sm.shader = Assets.get_resource(CFX_SHADERS[variant])
	sm.render_priority = m.render_priority
	sm.set_shader_parameter("albedo", m.albedo_color)
	if m.albedo_texture:
		sm.set_shader_parameter("albedo_tex", m.albedo_texture)
	sm.set_shader_parameter("use_vertex_color", m.vertex_color_use_as_albedo)
	if m.normal_enabled and m.normal_texture:
		sm.set_shader_parameter("has_normal", true)
		sm.set_shader_parameter("normal_tex", m.normal_texture)
		sm.set_shader_parameter("normal_scale", m.normal_scale)
	sm.set_shader_parameter("roughness", m.roughness)
	sm.set_shader_parameter("metallic", m.metallic)
	sm.set_shader_parameter("specular", m.metallic_specular)
	if m is ORMMaterial3D and (m as ORMMaterial3D).orm_texture:
		var orm: Texture2D = (m as ORMMaterial3D).orm_texture
		for pair in [["roughness", 1], ["metallic", 2], ["ao", 0]]:
			sm.set_shader_parameter(pair[0] + "_tex", orm)
			sm.set_shader_parameter(pair[0] + "_channel", CFX_CHANNELS[pair[1]])
		sm.set_shader_parameter("has_ao", true)
	else:
		if m.roughness_texture:
			sm.set_shader_parameter("roughness_tex", m.roughness_texture)
			sm.set_shader_parameter("roughness_channel", CFX_CHANNELS[m.roughness_texture_channel])
		if m.metallic_texture:
			sm.set_shader_parameter("metallic_tex", m.metallic_texture)
			sm.set_shader_parameter("metallic_channel", CFX_CHANNELS[m.metallic_texture_channel])
		if m.ao_enabled and m.ao_texture:
			sm.set_shader_parameter("has_ao", true)
			sm.set_shader_parameter("ao_tex", m.ao_texture)
			sm.set_shader_parameter("ao_channel", CFX_CHANNELS[m.ao_texture_channel])
	sm.set_shader_parameter("ao_light_affect", m.ao_light_affect)
	if m.emission_enabled:
		sm.set_shader_parameter("emission_color", m.emission)
		sm.set_shader_parameter("emission_energy", m.emission_energy_multiplier)
		if m.emission_texture:
			sm.set_shader_parameter("emission_tex", m.emission_texture)
	sm.set_shader_parameter("uv1_scale", m.uv1_scale)
	sm.set_shader_parameter("uv1_offset", m.uv1_offset)
	sm.set_shader_parameter("triplanar", m.uv1_triplanar)
	sm.set_shader_parameter("triplanar_sharpness", m.uv1_triplanar_sharpness)
	sm.set_shader_parameter("alpha_scissor_threshold", m.alpha_scissor_threshold)
	return sm
