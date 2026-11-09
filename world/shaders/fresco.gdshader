// Pompeian wall painting for the villa's porticoes, in the manner of the Getty Villa's peristyle:
// a black dado with faux-marble veining, a main zone of cinnabar-red panels in thin cream frames
// separated by narrow black bands carrying ochre candelabra lines, an ochre cornice line and a
// pale upper zone. Painted procedurally in world space over a scanned weathered-plaster texture,
// so the paint picks up its stains, cracks and relief. The frieze variant is a black band with an
// ochre meander, for the entablature.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
#include "res://shaders/construct_fx.gdshaderinc"

uniform sampler2D plaster_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D plaster_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float period = 2.9167;   // one bay between columns, metres
uniform float offset = 0.0;      // where a bay starts along the wall
uniform float floor_y = 0.15;
uniform bool frieze = false;

varying vec3 wpos;
varying vec3 wnrm;

const vec3 CINNABAR = vec3(0.42, 0.055, 0.035);
const vec3 BLACK = vec3(0.03, 0.027, 0.025);
const vec3 OCHRE = vec3(0.7, 0.46, 0.13);
const vec3 CREAM = vec3(0.83, 0.76, 0.6);

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float line(float d, float w) {
	float aa = fwidth(d) + 1e-4;
	return 1.0 - smoothstep(w - aa, w + aa, abs(d));
}

void fragment() {
	float cfx_wire;
	vec4 cfx = construct_fx(wpos, normalize(wnrm), TIME, cfx_wire, CAMERA_POSITION_WORLD);
	if (cfx.a < 0.5) {
		discard;
	}
	vec3 n = normalize(wnrm);
	float u = abs(n.x) > abs(n.z) ? wpos.z : wpos.x;
	float v = wpos.y - floor_y;
	vec2 tuv = vec2(u, v) / 2.4;
	vec3 tex = texture(plaster_albedo, tuv).rgb;
	float grime = clamp(dot(tex, vec3(0.333)) / 0.5, 0.55, 1.35);
	vec3 tn = texture(plaster_normal, tuv).xyz * 2.0 - 1.0;

	vec3 c;
	if (frieze) {
		// Running meander: a stepped key pattern in ochre on black.
		vec2 m = vec2(u * 2.2, v * 2.2);
		vec2 cell = fract(m);
		float key = max(line(cell.y - 0.2, 0.06) * step(0.2, cell.x), line(cell.x - 0.8, 0.06) * step(0.2, cell.y));
		key = max(key, line(cell.y - 0.8, 0.06) * step(cell.x, 0.8));
		c = mix(BLACK, OCHRE, key * 0.85);
	} else {
		float x = (fract((u - offset) / period) - 0.5) * period; // metres from the middle of the bay
		float half_w = period * 0.5;
		if (v < 0.9) {
			// Dado: black with dull red marbling and an ochre line along its top.
			float vein = smoothstep(0.62, 0.7, abs(sin(u * 3.1 + sin(v * 7.0 + u) * 1.7 + tex.r * 4.0)));
			c = mix(BLACK, vec3(0.22, 0.05, 0.035), vein * 0.6);
			c = mix(c, OCHRE, line(v - 0.86, 0.025));
		} else if (v < 4.0) {
			if (abs(x) > half_w - 0.3) {
				// Black separating band with a thin ochre candelabrum down its middle.
				c = BLACK;
				float stem = line(abs(x) - (half_w - 0.15), 0.012);
				float bead = line(fract(v * 1.6) - 0.5, 0.06) * line(abs(x) - (half_w - 0.15), 0.05);
				c = mix(c, OCHRE, max(stem, bead) * 0.9);
			} else {
				c = CINNABAR;
				// Thin cream frame inset from the panel edges.
				float pw = half_w - 0.3;
				float fx = line(abs(x) - (pw - 0.16), 0.012) * step(v, 3.84) * step(1.06, v);
				float fy = (line(v - 1.06, 0.012) + line(v - 3.84, 0.012)) * step(abs(x), pw - 0.16);
				c = mix(c, CREAM, clamp(fx + fy, 0.0, 1.0));
				// A small floating vignette in the middle of each panel.
				float ring = line(length(vec2(x, (v - 2.45) * 0.8)) - 0.26, 0.012);
				float dot_c = 1.0 - smoothstep(0.05, 0.07, length(vec2(x, (v - 2.45) * 0.8)));
				c = mix(c, OCHRE, max(ring, dot_c * 0.7));
			}
		} else if (v < 4.12) {
			c = OCHRE;
		} else {
			c = mix(CREAM, CREAM * 0.92, smoothstep(0.4, 0.6, tex.g));
			c = mix(c, CINNABAR, line(v - 4.6, 0.02));
		}
	}
	ALBEDO = c * grime * (1.0 - cfx_wire * 0.85);
	ROUGHNESS = 0.62;
	SPECULAR = 0.35;
	// Plaster relief: the scan's normal on the wall plane.
	vec3 t_axis = abs(n.x) > abs(n.z) ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
	vec3 world_n = normalize(n + (t_axis * tn.x + vec3(0.0, 1.0, 0.0) * tn.y) * 0.6);
	NORMAL = normalize((VIEW_MATRIX * vec4(world_n, 0.0)).xyz);
	EMISSION = cfx.rgb;
}
