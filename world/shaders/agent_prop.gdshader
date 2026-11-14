shader_type spatial;
// Holographic props agents conjure while they work: a page of text, a keyboard, a terminal,
// a lens, an orb. Additive light in the agent's tint; materialize dissolves them in and out.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 tint : source_color = vec4(1.0, 0.28, 0.41, 1.0);
uniform vec4 accent : source_color = vec4(1.0, 0.74, 0.33, 1.0);
uniform float materialize : hint_range(0.0, 1.0) = 1.0;
// 0 panel, 1 page of text, 2 keyboard, 3 terminal, 4 lens disc, 5 orb shell
uniform int pattern = 0;
uniform float seed = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float frame(vec2 uv, float width) {
	vec2 edge = min(uv, 1.0 - uv);
	return 1.0 - step(width, min(edge.x, edge.y));
}

void fragment() {
	vec2 uv = UV;
	float glow = 0.0;
	float bright = 0.0;
	if (pattern == 1) {
		// Lines of text, with a reading band sweeping down the page.
		float rows = 15.0;
		float row = floor(uv.y * rows);
		float inside = fract(uv.y * rows);
		float length = 0.3 + 0.6 * hash(vec2(row, seed));
		float text = step(0.32, inside) * step(inside, 0.62) * step(0.1, uv.x) * step(uv.x, 0.1 + 0.8 * length);
		float words = step(0.18, fract(uv.x * 9.0 + hash(vec2(row, seed + 3.0))));
		float band = smoothstep(0.09, 0.0, abs(uv.y - fract(TIME * 0.12 + seed)));
		glow = 0.07 + text * words * (0.38 + band * 0.7) + band * 0.06 + frame(uv, 0.015) * 0.5;
		bright = band * text;
	} else if (pattern == 2) {
		// Keys light as they are struck.
		vec2 grid = vec2(13.0, 4.0);
		vec2 cell = floor(uv * grid);
		vec2 inside = fract(uv * grid);
		float key = step(0.12, inside.x) * step(inside.x, 0.88) * step(0.14, inside.y) * step(inside.y, 0.86);
		float struck = step(0.9, hash(cell + floor(TIME * 9.0) + seed));
		glow = 0.04 + key * (0.16 + struck * 0.9) + frame(uv, 0.02) * 0.45;
		bright = key * struck;
	} else if (pattern == 3) {
		// Terminal output scrolling up under a prompt.
		float rows = 12.0;
		float scroll = uv.y + TIME * 0.18;
		float row = floor(scroll * rows);
		float inside = fract(scroll * rows);
		float length = 0.15 + 0.75 * hash(vec2(row, seed));
		float text = step(0.3, inside) * step(inside, 0.65) * step(0.06, uv.x) * step(uv.x, 0.06 + 0.86 * length);
		float bar = step(0.9, uv.y) * 0.25;
		glow = 0.08 + text * 0.45 * step(uv.y, 0.88) + bar + frame(uv, 0.012) * 0.6;
	} else if (pattern == 4) {
		float d = length(uv - 0.5) * 2.0;
		float ring = smoothstep(0.08, 0.0, abs(d - 0.92));
		float sweep = smoothstep(0.92, 1.0, cos(atan(uv.y - 0.5, uv.x - 0.5) - TIME * 2.2)) * step(d, 0.92);
		glow = (step(d, 0.92) * 0.07 + ring * 0.8 + sweep * 0.25);
		bright = ring;
	} else if (pattern == 5) {
		float rim = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.2);
		float bands = step(0.86, fract(uv.y * 8.0 + TIME * 0.3)) + step(0.92, fract(uv.x * 12.0 - TIME * 0.2));
		glow = rim * 0.9 + bands * 0.18 + 0.03;
		bright = rim;
	} else {
		glow = 0.6;
	}
	// Dissolve: blocks switch on as materialize rises, brightest where they are arriving.
	float n = hash(floor(uv * 36.0) + seed);
	float shown = step(n, materialize * 1.08 - 0.04);
	float arriving = shown * smoothstep(0.12, 0.0, materialize * 1.08 - 0.04 - n) * (1.0 - step(0.999, materialize));
	float scan = 0.85 + 0.15 * sin(uv.y * 240.0 + TIME * 7.0);
	vec3 color = mix(tint.rgb, accent.rgb, clamp(bright, 0.0, 1.0));
	ALBEDO = (color * glow * scan + accent.rgb * arriving * 0.8) * shown;
}
