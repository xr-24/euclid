// The Laguna-style coast round Villa Aurelia: dry coastal grassland on the bluff tops, mats of ice
// plant spilling over the edges, broken earth where the ground steepens, tawny sandstone on the
// cliff faces, a pale sand beach darkening to wet sand at the waterline. Layers are chosen by
// slope and height and broken up by large-scale noise so nothing tiles.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
#include "res://shaders/construct_fx.gdshaderinc"

uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_orm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_orm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cliff_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cliff_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cliff_orm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_orm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_noise : filter_linear_mipmap, repeat_enable;

uniform float sea_level = -80.0;
uniform float beach_top = -77.6;      // sand gives way to rock and scrub above this
uniform vec3 grass_tint : source_color = vec3(0.9, 0.95, 0.78);
uniform vec3 dry_tint : source_color = vec3(1.06, 1.0, 0.76);
uniform vec3 cliff_tint : source_color = vec3(1.12, 0.98, 0.8);
uniform vec3 chaparral : source_color = vec3(0.13, 0.16, 0.08);
uniform vec3 iceplant_green : source_color = vec3(0.24, 0.36, 0.12);
uniform vec3 iceplant_red : source_color = vec3(0.45, 0.2, 0.16);
uniform vec3 iceplant_bloom : source_color = vec3(0.85, 0.22, 0.6);
uniform float grass_scale = 6.0;
uniform float dirt_scale = 5.0;
uniform float cliff_scale = 9.0;
uniform float sand_scale = 5.0;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 unpack(vec4 t) {
	return t.xyz * 2.0 - 1.0;
}

void fragment() {
	float cfx_wire;
	vec4 cfx = construct_fx(wpos, normalize(wnrm), TIME, cfx_wire, CAMERA_POSITION_WORLD);
	if (cfx.a < 0.5) {
		discard;
	}
	vec3 n = normalize(wnrm);
	float macro = texture(macro_noise, wpos.xz / 110.0).r;
	float macro2 = texture(macro_noise, wpos.xz / 27.0 + 0.37).r;
	float macro3 = texture(macro_noise, wpos.xz / 7.0 + 0.71).r;

	// Bluff-top grassland (planar), two scales mixed against tiling.
	vec2 guv = wpos.xz / grass_scale;
	vec3 grass = texture(grass_albedo, guv).rgb * mix(grass_tint, dry_tint, smoothstep(0.3, 0.75, macro));
	grass = mix(grass, texture(grass_albedo, guv * 0.31 + 0.27).rgb * dry_tint, 0.35);
	vec3 g_orm = texture(grass_orm, guv).rgb;
	vec3 g_n = unpack(texture(grass_normal, guv));

	// Broken earth (planar).
	vec2 duv = wpos.xz / dirt_scale;
	vec3 dirt = texture(dirt_albedo, duv).rgb * vec3(1.08, 0.97, 0.86);
	vec3 d_orm = texture(dirt_orm, duv).rgb;
	vec3 d_n = unpack(texture(dirt_normal, duv));

	// Sandstone cliffs: projected from the two horizontal axes, weighted by the face direction.
	vec2 wx = pow(abs(n.xz), vec2(4.0));
	wx /= max(wx.x + wx.y, 1e-4);
	vec3 cp = wpos / cliff_scale;
	vec3 cliff = (texture(cliff_albedo, cp.zy).rgb * wx.x + texture(cliff_albedo, cp.xy).rgb * wx.y) * cliff_tint;
	cliff *= mix(0.86, 1.08, macro2);  // banding in the sandstone
	vec3 c_orm = texture(cliff_orm, cp.zy).rgb * wx.x + texture(cliff_orm, cp.xy).rgb * wx.y;
	vec3 c_nx = unpack(texture(cliff_normal, cp.zy));
	vec3 c_nz = unpack(texture(cliff_normal, cp.xy));

	// Beach sand (planar), darkening and smoothing toward the waterline.
	vec2 suv = wpos.xz / sand_scale;
	vec3 sand = texture(sand_albedo, suv).rgb * vec3(1.06, 1.02, 0.94);
	vec3 s_orm = texture(sand_orm, suv).rgb;
	vec3 s_n = unpack(texture(sand_normal, suv));
	float wet = 1.0 - smoothstep(sea_level + 0.15, sea_level + 0.9, wpos.y);
	sand = mix(sand, sand * vec3(0.55, 0.52, 0.5), wet);
	s_orm.g = mix(s_orm.g, 0.25, wet);

	// Layer weights.
	float slope = 1.0 - n.y;
	float steep = smoothstep(0.3, 0.48, slope + (macro2 - 0.5) * 0.18);
	float rough = smoothstep(0.12, 0.3, slope + (macro3 - 0.5) * 0.22) * (1.0 - steep);
	float beach = 1.0 - smoothstep(beach_top - 0.4, beach_top + 0.6 + macro3 * 0.8, wpos.y);
	beach *= 1.0 - steep * 0.85;
	// Ice plant: dense mats on the bluff edges and the gentler parts of the slopes.
	float ice_zone = smoothstep(0.08, 0.2, slope) * (1.0 - smoothstep(0.5, 0.62, slope)) * step(beach_top + 1.5, wpos.y);
	float ice = ice_zone * smoothstep(0.42, 0.58, macro2 + (macro - 0.5) * 0.5);

	vec3 albedo = mix(grass, dirt, rough);
	vec3 orm = mix(g_orm, d_orm, rough);
	vec3 tn = mix(g_n, d_n, rough);
	vec3 ice_col = mix(iceplant_green, iceplant_red, smoothstep(0.55, 0.8, macro3));
	ice_col = mix(ice_col, iceplant_bloom, smoothstep(0.82, 0.9, texture(macro_noise, wpos.xz / 1.3).r) * 0.8);
	albedo = mix(albedo, ice_col * (0.75 + macro3 * 0.5), ice * 0.92);
	orm = mix(orm, vec3(1.0, 0.45, 0.0), ice);
	// Chaparral and coastal sage: dark grey-green scrub covering much of the hills, so they read
	// right from a distance where the scattered bushes have faded out.
	float scrub = smoothstep(0.42, 0.58, macro + (macro2 - 0.5) * 0.45) * (1.0 - smoothstep(0.35, 0.5, slope)) * step(beach_top + 3.0, wpos.y);
	vec3 scrub_col = chaparral * mix(0.7, 1.35, macro3) * mix(vec3(1.0), vec3(1.25, 1.15, 0.9), smoothstep(0.6, 0.9, macro2));
	albedo = mix(albedo, scrub_col, scrub * 0.85 * (1.0 - ice));
	orm = mix(orm, vec3(0.8, 0.9, 0.0), scrub * 0.85);
	albedo = mix(albedo, cliff, steep);
	orm = mix(orm, c_orm, steep);
	albedo = mix(albedo, sand, beach);
	orm = mix(orm, s_orm, beach);
	tn = mix(tn, s_n, beach);

	// Normals: planar layers perturb around the surface normal; the cliff uses its projections.
	vec3 planar_n = normalize(vec3(n.x + tn.x * 0.8, n.y, n.z - tn.y * 0.8));
	vec3 cliff_n = normalize(n + vec3(0.0, c_nx.y, c_nx.x) * wx.x * 0.9 + vec3(c_nz.x, c_nz.y, 0.0) * wx.y * 0.9);
	vec3 world_n = normalize(mix(planar_n, cliff_n, steep));

	ALBEDO = albedo * (1.0 - cfx_wire * 0.85);
	ROUGHNESS = orm.g;
	AO = orm.r;
	AO_LIGHT_AFFECT = 0.25;
	NORMAL = normalize((VIEW_MATRIX * vec4(world_n, 0.0)).xyz);
	EMISSION = cfx.rgb;
}
