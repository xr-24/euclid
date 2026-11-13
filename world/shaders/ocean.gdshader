// Sea and pool water for Forward+: Gerstner swell, refraction through the surface, depth-based
// absorption (turquoise shallows to deep blue), shoreline foam and sky/sun reflections from the
// scene's lighting. Requires a depth prepass (Forward+ default).
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, diffuse_burley, specular_schlick_ggx;
#include "res://shaders/construct_fx.gdshaderinc"

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D ripple_a : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ripple_b : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D foam_noise : filter_linear_mipmap, repeat_enable;

uniform vec3 shallow_color : source_color = vec3(0.16, 0.56, 0.54);
uniform vec3 deep_color : source_color = vec3(0.012, 0.09, 0.15);
uniform vec3 foam_color : source_color = vec3(0.92, 0.93, 0.9);
uniform float clarity = 2.2;          // metres of water before the bottom fades out
uniform float colour_depth = 6.0;     // vertical depth at which water reaches deep_color
uniform float swell = 0.16;           // Gerstner amplitude in metres
uniform float swell_speed = 1.0;
uniform float ripple_strength = 0.55;
uniform vec2 surface_flow = vec2(0.0);
uniform float ripple_scale = 7.0;     // metres per ripple tile
uniform float refraction = 0.035;
uniform float foam_width = 0.45;      // metres of depth that carry shore foam
uniform float foam_amount = 1.0;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.035;
uniform float reflection_strength = 1.0;
uniform bool pool_reflection_enabled = false;
uniform sampler2D pool_reflection : filter_linear, repeat_disable;
uniform mat4 pool_reflection_matrix;
// Where the shoreline solver runs (shore_water.gdshader) this surface steps aside, with the
// matching a continuous, level seam at the simulation boundary.
uniform bool sim_enabled = false;
uniform vec2 sim_origin = vec2(-24.32, -55.0);
uniform float sim_size = 48.64;
// The horizon is a ring, not a second displaced surface beneath the near patch.
uniform bool has_lod_hole = false;
uniform vec4 lod_hole = vec4(0.0); // min x, min z, max x, max z

varying vec3 world_pos;
varying vec2 base_xz;

vec3 gerstner(vec2 p, vec2 dir, float wavelength, float steep, float t, inout vec3 tangent, inout vec3 binormal) {
	float k = 6.28318 / wavelength;
	float c = sqrt(9.8 / k);
	vec2 d = normalize(dir);
	float f = k * (dot(d, p) - c * t);
	float a = steep / k;
	tangent += vec3(-d.x * d.x * steep * sin(f), d.x * steep * cos(f), -d.x * d.y * steep * sin(f));
	binormal += vec3(-d.x * d.y * steep * sin(f), d.y * steep * cos(f), -d.y * d.y * steep * sin(f));
	return vec3(d.x * a * cos(f), a * sin(f), d.y * a * cos(f));
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * swell_speed;
	vec3 tangent = vec3(1.0, 0.0, 0.0);
	vec3 binormal = vec3(0.0, 0.0, 1.0);
	vec3 offset = vec3(0.0);
	// Steepness is scaled by swell so the pool (swell 0) stays flat.
	float s = clamp(swell / 0.16, 0.0, 2.0);
	offset += gerstner(wp.xz, vec2(0.2, 1.0), 23.0, 0.07 * s, t, tangent, binormal);
	offset += gerstner(wp.xz, vec2(-0.45, 1.0), 11.0, 0.06 * s, t, tangent, binormal);
	// The near mesh cannot represent short waves accurately. Fine detail belongs
	// in the normal layers, not in undersampled vertex displacement.
	base_xz = wp.xz;
	if (sim_enabled) {
		vec2 rel = wp.xz - sim_origin;
		float edge = min(min(rel.x,sim_size-rel.x),rel.y);
		float taper = smoothstep(0.0,2.0,0.5-edge);
		offset *= taper;
		tangent = mix(vec3(1.0,0.0,0.0),tangent,taper);
		binormal = mix(vec3(0.0,0.0,1.0),binormal,taper);
	}
	VERTEX += offset;
	world_pos = wp + offset;
	vec3 n = normalize(cross(binormal, tangent));
	NORMAL = (inverse(MODEL_MATRIX) * vec4(n, 0.0)).xyz;
}

float linear_depth(vec2 uv, mat4 inv_proj) {
	float raw = texture(depth_tex, uv).r;
	vec4 view = inv_proj * vec4(uv * 2.0 - 1.0, raw, 1.0);
	return -view.z / view.w;
}

void fragment() {
	if (has_lod_hole && world_pos.x > lod_hole.x && world_pos.z > lod_hole.y
			&& world_pos.x < lod_hole.z && world_pos.z < lod_hole.w) {
		discard;
	}
	float cfx_wire;
	vec4 cfx = construct_fx((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz, normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz), TIME, cfx_wire, CAMERA_POSITION_WORLD);
	if (cfx.a < 0.5) {
		discard;
	}
	if (sim_enabled) {
		vec2 rel = base_xz - sim_origin;
		if (rel.x > 0.0 && rel.x < sim_size && rel.y > 0.0 && rel.y < sim_size) {
			float edge = min(min(rel.x, sim_size - rel.x), rel.y);
			if (edge >= 0.5) {
				discard;
			}
		}
	}
	// Seen from below when the camera is under the surface (FRONT_FACING is unreliable on
	// this displaced, double-sided mesh).
	if (CAMERA_POSITION_WORLD.y < world_pos.y) {
		// Seen from below while swimming.
		vec3 above = textureLod(screen_tex, SCREEN_UV, 1.5).rgb;
		ALBEDO = vec3(0.0);
		SPECULAR = 0.0;
		ROUGHNESS = 1.0;
		EMISSION = mix(above * vec3(0.5, 0.8, 0.8), shallow_color * 0.5, 0.4) + cfx.rgb;
	} else {
		// Two scrolling ripple layers, faded with distance to avoid shimmering.
		float t = TIME;
		vec2 flow = (MODEL_MATRIX * vec4(surface_flow.x, 0.0, surface_flow.y, 0.0)).xz;
		vec2 uv = (world_pos.xz - flow * t) / ripple_scale;
		vec3 na = texture(ripple_a, uv + vec2(0.012, 0.018) * t).xyz * 2.0 - 1.0;
		vec3 nb = texture(ripple_b, uv * 1.9 + vec2(-0.017, 0.009) * t).xyz * 2.0 - 1.0;
		vec3 n = normalize(vec3(na.xy + nb.xy, na.z * nb.z));
		float dist = length(world_pos - CAMERA_POSITION_WORLD);
		float detail = ripple_strength * mix(1.0, 0.25, smoothstep(30.0, 220.0, dist));
		NORMAL_MAP = vec3(n.xy * detail * 0.5 + 0.5, 1.0);

		// Thickness of water along the view ray and vertical depth to the bottom.
		float surface = -VERTEX.z;
		float scene = linear_depth(SCREEN_UV, INV_PROJECTION_MATRIX);
		vec2 offset_uv = SCREEN_UV + n.xy * refraction * clamp((scene - surface) * 0.5, 0.0, 1.0);
		float scene_offset = linear_depth(offset_uv, INV_PROJECTION_MATRIX);
		if (scene_offset < surface) { // never refract things in front of the water
			offset_uv = SCREEN_UV;
			scene_offset = scene;
		}
		float thickness = max(scene_offset - surface, 0.0);
		vec3 view_dir = normalize(world_pos - CAMERA_POSITION_WORLD);
		float vertical = thickness * abs(view_dir.y);

		vec3 behind = textureLod(screen_tex, offset_uv, 0.0).rgb;
		float transmit = exp(-thickness / clarity);
		vec3 body = mix(shallow_color, deep_color, smoothstep(0.0, colour_depth, vertical));
		// Light that went through the water keeps a tint of the body colour.
		vec3 transmitted = behind * mix(vec3(1.0), body * 2.2, 1.0 - transmit) * transmit;

		// Shore foam: lapping bands driven by depth, broken up by noise.
		float shore_depth = max(scene - surface, 0.0) * abs(view_dir.y);
		float shore = 1.0 - smoothstep(0.0, foam_width, shore_depth);
		float noise = texture(foam_noise, world_pos.xz * 0.11 + vec2(t * 0.01, 0.0)).r;
		float bands = 0.5 + 0.5 * sin(shore_depth * 16.0 - t * 1.4 + noise * 7.0);
		float foam = foam_amount * shore * smoothstep(0.55, 0.9, bands * 0.6 + noise * 0.45 + shore * 0.3);
		foam = clamp(foam + foam_amount * smoothstep(0.9, 1.0, shore) * 0.5 * noise, 0.0, 1.0) * 0.85;

		ALBEDO = mix(body * (1.0 - transmit) * 0.35, foam_color, foam);
		EMISSION = transmitted * (1.0 - foam);
		if (pool_reflection_enabled) {
			vec4 projected = pool_reflection_matrix * vec4(world_pos, 1.0);
			vec2 mirror_uv = projected.xy / max(projected.w, 0.001) * vec2(0.5, -0.5) + 0.5;
			mirror_uv += n.xy * detail * 0.008;
			if (projected.w > 0.0 && all(greaterThan(mirror_uv, vec2(0.001))) && all(lessThan(mirror_uv, vec2(0.999)))) {
				float fresnel = 0.02 + 0.98 * pow(1.0 - clamp(dot(VIEW, NORMAL), 0.0, 1.0), 5.0);
				EMISSION = mix(EMISSION, texture(pool_reflection, mirror_uv).rgb,
					fresnel * (1.0 - foam) * reflection_strength);
			}
		}
		ROUGHNESS = mix(roughness_value, 0.85, foam);
		METALLIC = 0.0;
		SPECULAR = mix(0.5, 0.2, foam) * reflection_strength;
		ALBEDO *= 1.0 - cfx_wire * 0.85;
		EMISSION += cfx.rgb;
	}
}
