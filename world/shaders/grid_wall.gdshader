shader_type spatial;
render_mode unshaded, fog_disabled;
#include "res://shaders/construct_fx.gdshaderinc"

uniform vec4 surface_tint : source_color = vec4(1.0);

varying vec3 world_point;
varying vec3 local_point;
varying vec3 wall_normal;
varying float column_seed;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(27.13, 91.79))) * 43758.5453);
}

void vertex() {
	local_point = VERTEX + 0.5;
	column_seed = hash(MODEL_MATRIX[3].xz);
	float crest = step(0.4, VERTEX.y);
	VERTEX.y -= crest * local_point.x * (0.035 + 0.16 * column_seed);
	VERTEX.x += crest * (column_seed - 0.5) * 0.31;
	world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wall_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	float wire;
	vec4 shift = construct_fx(world_point, wall_normal, TIME, wire, CAMERA_POSITION_WORLD);
	if (shift.a < 0.5) {
		discard;
	}
	vec2 panel = vec2(abs(wall_normal.z) > abs(wall_normal.x) ? local_point.x : local_point.z, local_point.y);
	float ledge = 1.0 - smoothstep(0.004, 0.013, abs(fract(panel.y * 6.0 + column_seed) - 0.03));
	float rim = 1.0 - smoothstep(0.012, 0.033, min(panel.x, 1.0 - panel.x));
	float rail = 1.0 - smoothstep(0.007, 0.015 + fwidth(panel.x * 6.0), abs(fract(panel.x * 6.0 + 0.14) - 0.5));
	float channel = floor(panel.x * 6.0 + 0.14);
	float phase = hash(vec2(channel, column_seed * 500.0));
	float packets = smoothstep(0.77, 0.98, fract(panel.y * (4.0 + phase * 10.0) - TIME * (0.17 + phase * 0.26) + phase * 12.0));
	float marked = step(0.62, phase);
	float red_glow = exp(-abs(world_point.x + 15.0) * 0.034) * exp(-abs(world_point.z + 68.0) * 0.018);
	vec2 tile = floor(panel * vec2(14.0, 28.0));
	float corrupt = hash(tile + column_seed * 73.0);
	float fragment_band = step(0.87, corrupt) * step(0.38, fract(panel.y * 28.0));
	float distance_haze = smoothstep(43.0, 122.0, distance(world_point, CAMERA_POSITION_WORLD));
	float face = 0.38 + 0.62 * abs(wall_normal.z);
	vec3 rock = vec3(0.011, 0.004, 0.008) * face * (0.55 + column_seed * 0.8);
	rock += vec3(0.032, 0.004, 0.009) * red_glow * face;
	rock += vec3(0.026, 0.006, 0.009) * ledge;
	float lines = rim * (0.012 + phase * 0.04) + rail * marked * (0.020 + 0.80 * packets);
	lines += fragment_band * red_glow * (0.004 + 0.027 * step(0.93, fract(panel.y * 28.0)));
	vec3 backscatter = vec3(0.052, 0.005, 0.012) * distance_haze * red_glow;
	vec3 light = vec3(1.24, 0.034, 0.045) * lines * (0.35 + 0.65 * red_glow) * (1.0 - distance_haze * 0.52);
	ALBEDO = (rock + backscatter + light) * surface_tint.rgb * (1.0 - wire) + shift.rgb;
}
