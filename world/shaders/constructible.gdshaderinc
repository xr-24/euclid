// A compact StandardMaterial3D replacement with the construct effect built in. world_art.gd converts
// every BaseMaterial3D in a zone (imported glTF materials, code-made PBR materials, blockout colours)
// into this shader, copying the parameters across, so the whole zone can unravel and assemble.
// Variants (cull mode, alpha scissor, blending) are the small .gdshader files that include this.

#include "res://shaders/construct_fx.gdshaderinc"

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_vertex_color = false;
uniform sampler2D normal_tex : hint_roughness_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool has_normal = false;
uniform float normal_scale = 1.0;
uniform float roughness : hint_range(0.0, 1.0) = 1.0;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float specular : hint_range(0.0, 1.0) = 0.5;
uniform sampler2D roughness_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 roughness_channel = vec4(0.0, 1.0, 0.0, 0.0);
uniform sampler2D metallic_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 metallic_channel = vec4(0.0, 0.0, 1.0, 0.0);
uniform sampler2D ao_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 ao_channel = vec4(1.0, 0.0, 0.0, 0.0);
uniform bool has_ao = false;
uniform float ao_light_affect = 0.0;
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_energy = 0.0;
uniform sampler2D emission_tex : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 uv1_scale = vec3(1.0);
uniform vec3 uv1_offset = vec3(0.0);
uniform bool triplanar = false;
uniform float triplanar_sharpness = 1.0;
uniform float alpha_scissor_threshold = 0.5;

varying vec3 tp_pos;
varying vec3 tp_weights;

void vertex() {
	UV = UV * uv1_scale.xy + uv1_offset.xy;
	if (triplanar) { // world-space triplanar, matching BaseMaterial3D's convention
		TANGENT = normalize(vec3(0.0, 0.0, -1.0) * abs(NORMAL.x) + vec3(1.0, 0.0, 0.0) * abs(NORMAL.y) + vec3(1.0, 0.0, 0.0) * abs(NORMAL.z));
		BINORMAL = normalize(vec3(0.0, 1.0, 0.0) * abs(NORMAL.x) + vec3(0.0, 0.0, -1.0) * abs(NORMAL.y) + vec3(0.0, 1.0, 0.0) * abs(NORMAL.z));
		tp_weights = pow(abs(mat3(MODEL_MATRIX) * NORMAL), vec3(triplanar_sharpness));
		tp_weights /= dot(tp_weights, vec3(1.0));
		tp_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz * uv1_scale + uv1_offset;
		tp_pos *= vec3(1.0, -1.0, 1.0);
	}
}

vec4 sample_map(sampler2D tex, vec2 uv) {
	if (triplanar) {
		return texture(tex, tp_pos.xy) * tp_weights.z + texture(tex, tp_pos.xz) * tp_weights.y
			+ texture(tex, tp_pos.zy * vec2(-1.0, 1.0)) * tp_weights.x;
	}
	return texture(tex, uv);
}

void fragment() {
	float cfx_wire;
	vec4 cfx = construct_fx((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz, normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz), TIME, cfx_wire, CAMERA_POSITION_WORLD);
	if (cfx.a < 0.5) {
		discard;
	}
	vec4 base = sample_map(albedo_tex, UV) * albedo;
	if (use_vertex_color) {
		base *= COLOR;
	}
	ALBEDO = base.rgb * (1.0 - cfx_wire * 0.85);
	ROUGHNESS = roughness * dot(sample_map(roughness_tex, UV), roughness_channel);
	METALLIC = metallic * dot(sample_map(metallic_tex, UV), metallic_channel);
	SPECULAR = specular;
	if (has_normal) {
		NORMAL_MAP = sample_map(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}
	if (has_ao) {
		AO = dot(sample_map(ao_tex, UV), ao_channel);
		AO_LIGHT_AFFECT = ao_light_affect;
	}
	EMISSION = emission_color * emission_energy * sample_map(emission_tex, UV).rgb + cfx.rgb;
#ifdef CFX_SCISSOR
	ALPHA = base.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor_threshold;
#endif
#ifdef CFX_BLEND
	ALPHA = base.a;
#endif
}
