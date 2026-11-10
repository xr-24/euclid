shader_type canvas_item;
render_mode blend_add, unshaded;
// Phosphor bloom for the text panels. Reads the panel as already drawn, blurs it through the
// screen mipmaps and adds the light back, so bright text, carets and effects glow together.

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform vec4 tint : source_color = vec4(0.36, 0.86, 1.0, 1.0);
uniform float strength = 1.1;
uniform float threshold = 0.03;
uniform float saturation = 0.45;
uniform vec2 rect_size = vec2(1200.0, 800.0);
uniform float edge = 18.0;

void fragment() {
	vec3 bloom = textureLod(screen_texture, SCREEN_UV, 1.0).rgb * 0.42
		+ textureLod(screen_texture, SCREEN_UV, 2.0).rgb * 0.32
		+ textureLod(screen_texture, SCREEN_UV, 3.0).rgb * 0.22
		+ textureLod(screen_texture, SCREEN_UV, 4.0).rgb * 0.14;
	bloom = max(bloom - vec3(threshold), vec3(0.0));
	// Pull dim halos toward the phosphor colour so they read as cyan light, not grey haze.
	float energy = dot(bloom, vec3(0.3, 0.5, 0.2));
	vec3 glow = mix(bloom, tint.rgb * energy * 1.6, saturation);
	// Fade at the panel border so the world behind the panel does not bleed in.
	vec2 px = UV * rect_size;
	float inset = min(min(px.x, px.y), min(rect_size.x - px.x, rect_size.y - px.y));
	COLOR = vec4(glow * strength * smoothstep(0.0, edge, inset), 1.0);
}
