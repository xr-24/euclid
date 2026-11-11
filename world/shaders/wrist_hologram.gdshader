shader_type canvas_item;
render_mode blend_add;
// The wrist computer's face as projected light: a slight colour fringe, scanlines every third
// pixel, flicker (glow) and, now and then, one thin band torn sideways.

uniform float glow = 1.0;
uniform float time = 0.0;

void fragment() {
	vec2 uv = UV;
	vec2 texel = TEXTURE_PIXEL_SIZE;
	float band = floor(uv.y * 90.0);
	float tear = step(0.996, fract(sin(band * 12.9898 + floor(time * 9.0) * 78.233) * 43758.5453));
	uv.x += tear * texel.x * 5.0;
	vec4 base = texture(TEXTURE, uv);
	float red = texture(TEXTURE, uv + vec2(texel.x * 0.75, 0.0)).r;
	float blue = texture(TEXTURE, uv - vec2(texel.x * 0.75, 0.0)).b;
	float scan = 0.88 + 0.12 * sin(FRAGCOORD.y * 2.0943951);
	COLOR = vec4(vec3(red, base.g, blue) * scan * glow, 1.0);
}
