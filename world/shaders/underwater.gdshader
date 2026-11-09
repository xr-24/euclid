// Full-screen view from under the water: the scene wobbles, blurs a little and fades into a
// blue-green haze, with soft light shafts from the surface.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec3 tint : source_color = vec3(0.06, 0.32, 0.36);

void fragment() {
	vec2 uv = SCREEN_UV;
	uv += vec2(sin(uv.y * 28.0 + TIME * 1.7), cos(uv.x * 23.0 + TIME * 1.3)) * 0.004;
	vec3 scene = textureLod(screen_tex, uv, 1.5).rgb;
	float shafts = 0.5 + 0.5 * sin(uv.x * 40.0 + sin(uv.x * 7.0 + TIME * 0.6) * 3.0 + TIME * 0.4);
	shafts *= smoothstep(0.9, 0.0, uv.y) * 0.18;
	vec3 col = mix(scene * vec3(0.55, 0.85, 0.85), tint, 0.55) + tint * shafts * 2.0;
	float vignette = smoothstep(1.1, 0.35, length(uv - 0.5));
	COLOR = vec4(col * mix(0.55, 1.0, vignette), 1.0);
}
