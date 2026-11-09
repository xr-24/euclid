// Shore terrain: dry wind-rippled sand, darker glossy wet sand near the waterline and rock on
// steep headlands. Everything is mapped in world space, so the Blender terrain needs no UVs.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
#include "res://shaders/construct_fx.gdshaderinc"

uniform sampler2D dry_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dry_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dry_orm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wet_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wet_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wet_orm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_orm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_noise : filter_linear_mipmap, repeat_enable;

uniform float sea_level = -0.55;
// Shoreline solver (optional): wetness memory, stranded foam and the water surface for caustics.
uniform bool sim_enabled = false;
uniform bool shore_contact_foam = false;
uniform sampler2D tx_derived : hint_default_black, filter_linear, repeat_disable;
uniform vec2 sim_origin = vec2(-24.32, -55.0);
uniform float sim_size = 48.64;
uniform sampler2D tx_ground : hint_default_black, filter_linear, repeat_disable; // r=wetness g=stranded foam
uniform sampler2D tx_state : hint_default_black, filter_linear, repeat_disable;  // r=water surface (above sea level)
uniform sampler2D lace_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D caustics_tex : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform float dry_scale = 9.0;
uniform float wet_scale = 2.4;
uniform float rock_scale = 5.0;
uniform vec3 dry_tint : source_color = vec3(1.08, 1.0, 0.86);
uniform vec3 wet_tint : source_color = vec3(0.8, 0.74, 0.64);
uniform vec3 rock_tint : source_color = vec3(0.92, 0.88, 0.8);

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Tangent-space normal for a planar XZ projection, applied to the geometric normal (whiteout blend).
vec3 apply_xz(vec3 base, vec3 ts, float strength) {
	ts.xy *= strength;
	return normalize(vec3(base.x + ts.x, base.y * ts.z, base.z - ts.y));
}

vec4 triplanar(sampler2D tex, vec3 p, vec3 w) {
	return texture(tex, p.zy) * w.x + texture(tex, p.xz) * w.y + texture(tex, p.xy) * w.z;
}

void fragment() {
	float cfx_wire;
	vec4 cfx = construct_fx((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz, normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz), TIME, cfx_wire, CAMERA_POSITION_WORLD);
	if (cfx.a < 0.5) {
		discard;
	}
	vec3 n = normalize(wnrm);
	float macro = texture(macro_noise, wpos.xz / 37.0).r;
	float macro2 = texture(macro_noise, wpos.xz / 11.0 + 0.3).r;

	// Dry sand: two scales of the same scan hide tiling; macro noise varies the tone.
	vec2 duv = wpos.xz / dry_scale;
	vec3 dry = texture(dry_albedo, duv).rgb * mix(0.86, 1.08, macro) * dry_tint;
	dry = mix(dry, texture(dry_albedo, duv * 0.31 + 0.17).rgb * dry_tint, 0.35);
	vec3 dry_n = texture(dry_normal, duv).xyz * 2.0 - 1.0;
	vec3 dry_orm_v = texture(dry_orm, duv).rgb;

	vec2 wuv = wpos.xz / wet_scale;
	vec3 wet = texture(wet_albedo, wuv).rgb * wet_tint * mix(0.9, 1.05, macro2);
	vec3 wet_n = texture(wet_normal, wuv).xyz * 2.0 - 1.0;
	vec3 wet_orm_v = texture(wet_orm, wuv).rgb;

	vec3 w = pow(abs(n), vec3(6.0));
	w /= (w.x + w.y + w.z);
	vec3 rp = wpos / rock_scale;
	vec3 rock = triplanar(rock_albedo, rp, w).rgb * rock_tint;
	vec3 rock_orm_v = triplanar(rock_orm, rp, w).rgb;
	// Whiteout-blended triplanar normal (Ben Golus), in world space.
	vec3 tnx = texture(rock_normal, rp.zy).xyz * 2.0 - 1.0;
	vec3 tny = texture(rock_normal, rp.xz).xyz * 2.0 - 1.0;
	vec3 tnz = texture(rock_normal, rp.xy).xyz * 2.0 - 1.0;
	tnx = vec3(tnx.xy + n.zy, abs(tnx.z) * n.x);
	tny = vec3(tny.xy + n.xz, abs(tny.z) * n.y);
	tnz = vec3(tnz.xy + n.xy, abs(tnz.z) * n.z);
	vec3 rock_world = normalize(tnx.zyx * w.x + tny.xzy * w.y + tnz.xyz * w.z);

	// Wetness: the swash zone just above the sea is darkest and glossy, fading up the beach.
	float elevation = wpos.y - sea_level;
	float above = elevation + (macro2 - 0.5) * 0.25;
	float wet_mask = 1.0 - smoothstep(0.05, 0.75, above);
	float damp = 1.0 - smoothstep(0.0, 2.2, above);
	float stranded = 0.0;
	float water_depth = 0.0;
	float contact_foam = 0.0;
	if (sim_enabled) {
		vec2 rel = wpos.xz - sim_origin;
		vec2 suv = vec2(rel.y, rel.x) / sim_size; // solver axes: (cross-shore, alongshore)
		float inside = smoothstep(0.0, 4.0, min(min(rel.x, sim_size - rel.x), min(rel.y, sim_size - rel.y)));
		if (inside > 0.0) {
			vec4 ground = texture(tx_ground, clamp(suv, 0.0, 1.0));
			// Where the solver runs, sand is wet only where water has actually been (dries over ~45 s).
			float sim_wet = max(clamp(ground.r, 0.0, 1.0), 1.0 - smoothstep(-0.05, 0.08, above));
			wet_mask = mix(wet_mask, sim_wet, inside);
			stranded = clamp(ground.g, 0.0, 1.0) * inside;
			water_depth = max(sea_level + texture(tx_state, clamp(suv, 0.0, 1.0)).r - wpos.y, 0.0) * inside;
			if (shore_contact_foam) {
				float signed_depth = sea_level + texture(tx_state,clamp(suv,0.0,1.0)).r-wpos.y;
				float edge_noise = texture(lace_tex,wpos.xz/0.43 + vec2(TIME*0.016,-TIME*0.012)).r;
				signed_depth += (edge_noise-0.5)*0.014;
				float aa = max(fwidth(signed_depth),0.004);
				float edge = smoothstep(-0.025-aa,0.005+aa,signed_depth)*(1.0-smoothstep(0.025,0.10,signed_depth));
				contact_foam = edge * clamp(texture(tx_derived,clamp(suv,0.0,1.0)).b,0.0,1.0) * inside;
			}
		}
	}
	// Rock on steep ground and across the raised headlands either side of the cove; the dunes
	// behind the beach stay sand.
	float slope = 1.0 - n.y;
	float headland = smoothstep(17.0, 25.0, abs(wpos.x) + (macro - 0.5) * 6.0);
	float rock_mask = smoothstep(0.16, 0.34, slope + (macro - 0.5) * 0.25) * smoothstep(-1.5, 0.6, wpos.y);
	rock_mask = max(rock_mask, headland * smoothstep(0.2, 1.4, wpos.y + (macro2 - 0.5) * 1.2));

	vec3 sand = mix(dry, wet, wet_mask);
	sand *= mix(1.0, 0.82, damp * (1.0 - wet_mask));
	vec3 albedo = mix(sand, rock, rock_mask);
	vec3 orm = mix(mix(dry_orm_v, wet_orm_v, wet_mask), rock_orm_v, rock_mask);
	// Damp colour lasts up the beach; a reflective water film belongs at the swash line.
	float sheen = wet_mask * (1.0 - smoothstep(0.04, 0.30, elevation));
	float dry_roughness = mix(0.86, 0.98, dry_orm_v.g);
	float wet_roughness = mix(0.44, 0.62, wet_orm_v.g);
	float rough = mix(mix(dry_roughness, wet_roughness, sheen), rock_orm_v.g, rock_mask);
	// Below the waterline the sand is saturated and smooth.
	float under = 1.0 - smoothstep(-0.2, 0.05, above);
	albedo *= mix(1.0, 0.72, under);
	rough = mix(rough, 0.5, under);

	// Ripples come and go in patches, softer where the sand is damp or trampled.
	float ripple_amount = mix(0.35, 1.0, smoothstep(0.3, 0.7, macro)) * (1.0 - damp * 0.6);
	dry_n.xy *= ripple_amount;
	vec3 sand_n = normalize(mix(dry_n, wet_n, wet_mask));
	vec3 world_n = apply_xz(n, sand_n, 1.0 - rock_mask);
	world_n = normalize(mix(world_n, rock_world, rock_mask));

	// Foam lace stranded by the backwash.
	float lace = texture(lace_tex, wpos.xz / 1.1).r;
	float foam_line = stranded * smoothstep(0.55, 0.85, lace);
	foam_line = max(foam_line,contact_foam*smoothstep(0.3,0.72,lace)*0.75);
	albedo = mix(albedo, vec3(0.86, 0.87, 0.84), foam_line * (1.0 - rock_mask));
	rough = mix(rough, 0.8, foam_line);
	// Underwater caustics in the shallows.
	vec3 caustic = vec3(0.0);
	if (water_depth > 0.01) {
		vec2 c1 = wpos.xz / 1.7 + vec2(TIME * 0.021, TIME * -0.013);
		vec2 c2 = wpos.xz / 2.3 + vec2(TIME * -0.017, TIME * 0.011);
		caustic = min(texture(caustics_tex, c1).rgb, texture(caustics_tex, c2).rgb);
		caustic *= smoothstep(0.02, 0.15, water_depth) * exp(-1.5 * water_depth) * 1.2;
	}

	ALBEDO = albedo;
	EMISSION = caustic * albedo;
	ROUGHNESS = rough;
	AO = orm.r;
	AO_LIGHT_AFFECT = 0.25;
	SPECULAR = mix(mix(0.14, 0.35, sheen), mix(0.5, 0.65, wet_mask), rock_mask);
	NORMAL = normalize((VIEW_MATRIX * vec4(world_n, 0.0)).xyz);
	ALBEDO *= 1.0 - cfx_wire * 0.85;
	EMISSION += cfx.rgb;
}
