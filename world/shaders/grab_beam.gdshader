shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled, fog_disabled;

uniform float strength = 0.24;

void fragment() {
	vec2 grid = abs(fract(UV * vec2(9.0, 26.0) - vec2(0.0, TIME * 1.8)) - 0.5);
	float wires = max(smoothstep(0.39, 0.48, grid.x), smoothstep(0.39, 0.48, grid.y));
	float ends = smoothstep(0.0, 0.11, UV.y) * smoothstep(1.0, 0.87, UV.y);
	ALBEDO = vec3(0.20, 0.82, 1.0);
	ALPHA = strength * ends * mix(0.09, 0.72, wires);
}
