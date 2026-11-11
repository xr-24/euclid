shader_type canvas_item;
// A faint dark veil behind the wrist face so its light reads over a bright sky, fading out at
// the edges so it never looks like a solid card.

uniform float opacity = 0.45;

void fragment() {
	vec2 edge = min(UV, 1.0 - UV);
	float fade = smoothstep(0.0, 0.08, edge.x) * smoothstep(0.0, 0.12, edge.y);
	COLOR = vec4(0.0, 0.016, 0.035, opacity * fade);
}
