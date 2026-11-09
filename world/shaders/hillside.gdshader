// Hillside round the villa: sun-dried Mediterranean grass on gentle ground, bare earth and rock on
// steep slopes, broken up by large-scale variation so the hills don't tile.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
#include "res://shaders/construct_fx.gdshaderinc"

uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_orm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_orm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_noise : filter_linear_mipmap, repeat_enable;
uniform vec3 grass_tint : source_color = vec3(1.05, 0.98, 0.72);
uniform vec3 dry_tint : source_color = vec3(1.2, 1.0, 0.62);
uniform float grass_scale = 7.0;
uniform float dirt_scale = 5.0;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float cfx_wire;
	vec4 cfx = construct_fx(wpos, normalize(wnrm), TIME, cfx_wire, CAMERA_POSITION_WORLD);
	if (cfx.a < 0.5) {
		discard;
	}
	vec3 n = normalize(wnrm);
	float macro = texture(macro_noise, wpos.xz / 90.0).r;
	float macro2 = texture(macro_noise, wpos.xz / 23.0 + 0.4).r;
	vec2 guv = wpos.xz / grass_scale;
	vec3 grass = texture(grass_albedo, guv).rgb * mix(grass_tint, dry_tint, smoothstep(0.35, 0.75, macro));
	grass = mix(grass, texture(grass_albedo, guv * 0.27 + 0.3).rgb * dry_tint, 0.3);
	vec3 g_orm = texture(grass_orm, guv).rgb;
	vec3 g_n = texture(grass_normal, guv).xyz * 2.0 - 1.0;
	vec3 w = pow(abs(n), vec3(5.0));
	w /= (w.x + w.y + w.z);
	vec3 dp = wpos / dirt_scale;
	vec3 dirt = (texture(dirt_albedo, dp.zy) * w.x + texture(dirt_albedo, dp.xz) * w.y + texture(dirt_albedo, dp.xy) * w.z).rgb;
	vec3 d_orm = (texture(dirt_orm, dp.zy) * w.x + texture(dirt_orm, dp.xz) * w.y + texture(dirt_orm, dp.xy) * w.z).rgb;
	float steep = smoothstep(0.22, 0.42, (1.0 - n.y) + (macro2 - 0.5) * 0.3);
	vec3 albedo = mix(grass, dirt * vec3(1.05, 0.95, 0.85), steep);
	vec3 orm = mix(g_orm, d_orm, steep);
	vec3 world_n = normalize(vec3(n.x + g_n.x * (1.0 - steep) * 0.8, n.y, n.z - g_n.y * (1.0 - steep) * 0.8));
	ALBEDO = albedo * (1.0 - cfx_wire * 0.85);
	ROUGHNESS = orm.g;
	AO = orm.r;
	AO_LIGHT_AFFECT = 0.2;
	NORMAL = normalize((VIEW_MATRIX * vec4(world_n, 0.0)).xyz);
	EMISSION = cfx.rgb;
}
