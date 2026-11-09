shader_type spatial;
render_mode unshaded;
#include "res://shaders/construct_fx.gdshaderinc"

uniform float floor_spacing = 2.0;

float grid_lines(vec2 point, float spacing, float width) {
	vec2 cell = point / spacing;
	vec2 footprint = max(fwidth(cell), vec2(0.0001));
	vec2 distance_to_line = abs(fract(cell + 0.5) - 0.5);
	vec2 ink = 1.0 - smoothstep(vec2(width), vec2(width) + footprint, distance_to_line);
	ink *= 1.0 - smoothstep(vec2(0.10), vec2(0.5), footprint);
	return max(ink.x, ink.y);
}

void fragment() {
	vec3 point = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float wire;
	vec4 effect = construct_fx(point, vec3(0.0, 1.0, 0.0), TIME, wire, CAMERA_POSITION_WORLD);
	if (effect.a < 0.5) {
		discard;
	}
	float distance_to_eye = length(point - CAMERA_POSITION_WORLD);
	vec2 block = floor(point.xz / vec2(4.0, 8.0));
	float tile = fract(sin(dot(block, vec2(32.47, 71.41))) * 2419.82);
	float fine = grid_lines(point.xz, floor_spacing, 0.0028) * (1.0 - smoothstep(17.0, 62.0, distance_to_eye));
	float major = grid_lines(point.xz, floor_spacing * 4.0, 0.0021) * (1.0 - smoothstep(45.0, 135.0, distance_to_eye));
	float grain = 0.5 + 0.5 * sin(point.x * 3.1 + sin(point.z * 7.2)) * sin(point.z * 11.7);
	vec3 surface = vec3(0.011, 0.007, 0.013) * (0.7 + tile * 0.55 + grain * 0.11);
	vec3 traces = vec3(0.35, 0.017, 0.028) * (fine * 0.063 + major * 0.087 * tile);
	ALBEDO = (surface + traces) * (1.0 - wire) + effect.rgb;
}
