#include "res://shaders/avatar_signal.gdshaderinc"

uniform vec4 core_color : source_color = vec4(1.0, 0.004, 0.048, 1.0);
// A nonnegative value freezes the effect for reproducible rendered comparisons.
uniform float signal_time = -1.0;

varying vec3 world_point;
varying vec3 point_color;
varying float visibility;

void vertex() {
	float clock = signal_time < 0.0 ? TIME : signal_time;
	vec3 p = VERTEX;
	vec3 n = normalize(COLOR.rgb * 2.0 - 1.0);
	float seed = COLOR.a;
	float integrity = signal_integrity(p, clock);
	// Deterministic point dropout gives true holes instead of a transparent skin.
	float survival = fract(seed * 127.31 + 0.27);
#ifdef AVATAR_DAYLIGHT
	visibility = smoothstep(survival - 0.045, survival + 0.045, integrity * 0.91);
#else
	visibility = smoothstep(survival - 0.045, survival + 0.045, integrity * 0.79);
#endif
	float shoulder = exp(-abs(p.y - 0.49) * 26.0) * smoothstep(0.11, 0.20, abs(p.x));
	float facing = abs(dot(n, normalize(CAMERA_POSITION_WORLD - (MODEL_MATRIX * vec4(p, 1.0)).xyz)));
	float contour = pow(1.0 - facing, 2.0);
	float flash = smoothstep(0.985, 1.0, seed);
	float sparkle = 0.67 + 0.33 * sin(clock * (0.6 + seed) + seed * 73.0);
	float brightness = (0.32 + pow(seed, 3.8) * 2.2 + flash * 2.1)
		* (0.65 + contour * 1.2 + shoulder * 5.0) * sparkle;
	float face = smoothstep(0.64, 0.75, p.y) * smoothstep(0.045, 0.13, p.z);
	brightness *= 1.0 - face * 0.87;
	point_color = mix(core_color.rgb * vec3(0.72, 0.24, 0.42),
		mix(core_color.rgb, vec3(1.0, 0.015, 0.20), shoulder * 0.55 + flash * 0.34), seed * seed) * brightness;
	point_color = mix(point_color, vec3(1.0, 0.16, 0.32) * brightness,
		shoulder * smoothstep(0.72, 0.99, seed) * 0.65);
	// Sparse points peel into vertical echoes. The anatomical carrier is never visible.
	float displaced = step(0.990, fract(seed * 97.17)) * smoothstep(0.28, 0.68, integrity);
	p.y += displaced * (0.015 + 0.065 * sin(clock * 0.55 + seed * 126.0));
	world_point = (MODEL_MATRIX * vec4(p, 1.0)).xyz;
	vec4 view_point = MODELVIEW_MATRIX * vec4(p, 1.0);
	float diameter = mix(0.0024, 0.0043, pow(seed, 1.5));
	// Keep distant samples legible without filling the missing regions.
	float pixel_size = 2.0 * abs(view_point.z) / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
#ifdef AVATAR_DAYLIGHT
	diameter = max(diameter * 1.42, pixel_size * 2.3);
#else
	diameter = max(diameter, pixel_size * 1.05);
#endif
	view_point.xy += (UV - 0.5) * diameter * vec2(1.0, 1.0 + displaced * 4.0);
	POSITION = PROJECTION_MATRIX * view_point;
}

void fragment() {
	float radius = length((UV - 0.5) * 2.0);
	float edge = max(fwidth(radius), 0.08);
	float dot_mask = 1.0 - smoothstep(0.72 - edge, 0.95 + edge, radius);
	if (visibility * dot_mask < 0.025) {
		discard;
	}
	float wire;
	vec4 shift = construct_fx(world_point, vec3(0.0, 1.0, 0.0), TIME, wire, CAMERA_POSITION_WORLD);
	if (shift.a < 0.5) {
		discard;
	}
#ifdef AVATAR_DAYLIGHT
	// A dark edge gives each point contrast on pale stone, sand, and sky.
	vec3 shadow = mix(vec3(0.036, 0.002, 0.019), core_color.rgb * 0.14, 0.6);
	vec3 highlight = mix(core_color.rgb, vec3(1.0, 0.76, 0.86), 0.18);
	float intensity = clamp(length(point_color) * 0.42, 0.0, 1.0);
	float core = 1.0 - smoothstep(0.34, 0.76, radius);
	vec3 pigment = mix(shadow, highlight, core * intensity);
	ALBEDO = pigment * (1.0 - wire) + shift.rgb;
	ALPHA = clamp(dot_mask * visibility * 1.48, 0.0, 1.0);
#else
	ALBEDO = point_color * (1.0 - wire) + shift.rgb;
	ALPHA = dot_mask * visibility;
#endif
}
