#include "res://shaders/avatar_signal.gdshaderinc"

uniform vec4 core_color : source_color = vec4(1.0, 0.004, 0.048, 1.0);
uniform float signal_time = -1.0;
uniform vec2 hover_pose = vec2(0.0);
varying vec3 world_point;
varying vec3 signal_point;

void vertex() {
	VERTEX += CUSTOM0.xyz * hover_pose.x + CUSTOM1.xyz * hover_pose.y;
	float clock = signal_time < 0.0 ? TIME : signal_time;
	float wave = sin(clock * 0.65 + VERTEX.y * 10.0);
	VERTEX.x += COLOR.r * UV.y * UV.y * wave * 0.016;
	signal_point = VERTEX;
	world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float wire;
	vec4 shift = construct_fx(world_point, vec3(0.0, 1.0, 0.0), TIME, wire, CAMERA_POSITION_WORLD);
	if (shift.a < 0.5) {
		discard;
	}
	float phase = COLOR.g;
	float clock = signal_time < 0.0 ? TIME : signal_time;
	float along = UV.y;
	float width = 1.0 - smoothstep(0.18, 0.5, abs(UV.x - 0.5));
	float hair_tip = (1.0 - smoothstep(0.64, 1.0, along)) * (0.43 + 0.57 * smoothstep(0.0, 0.17, along));
	float pulse = pow(max(0.0, 0.5 + 0.5 * cos(along * 13.0 - clock * 0.7 + phase * 18.0)), 3.0);
	float head = exp(-abs(along - 0.22) * 7.0);
	float cluster = signal_noise(signal_point * vec3(29.0, 13.0, 29.0) + vec3(phase * 3.0, clock * 0.07, 0.0));
	float segments = signal_noise(vec3(phase * 37.0, along * 24.0 - clock * 0.12, 4.7));
	float breakup = smoothstep(0.42, 0.61, cluster * 0.60 + segments * 0.40);
	float fibre = hair_tip * (0.15 + pulse * 1.2 + head * 2.6) * (0.25 + phase * phase);
	float streak = sin(along * 3.1415927) * (0.11 + 0.89 * pulse) * (0.47 + phase * 0.22);
	vec3 hair_color = mix(core_color.rgb, vec3(1.0, 0.032, 0.25), 0.62);
	hair_color = mix(hair_color, vec3(1.0, 0.41, 0.58), step(0.93, phase) * head);
	vec3 line_color = mix(vec3(0.055, 0.78, 1.0), vec3(1.0, 0.014, 0.12), step(0.52, phase));
	vec3 signal_color = mix(line_color, hair_color * fibre * 1.4, COLOR.r);
	float coverage = width * COLOR.b * mix(streak * 0.84, hair_tip, COLOR.r) * breakup;
#ifdef AVATAR_DAYLIGHT
	vec3 shadow = core_color.rgb * vec3(0.14, 0.09, 0.24);
	ALBEDO = mix(shadow, clamp(signal_color, vec3(0.0), vec3(1.0)), 0.66) + shift.rgb;
	ALPHA = clamp(coverage * 1.48, 0.0, 1.0);
#else
	ALBEDO = signal_color + shift.rgb;
	ALPHA = clamp(coverage, 0.0, 1.0);
#endif
	if (ALPHA < 0.025) {
		discard;
	}
}
