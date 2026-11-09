// The "construct / deconstruct" zone shift, shared by every surface in a zone.
//
// A sphere grows from construct_origin. Geometry that is leaving (construct_side = -1) survives
// only outside the sphere; arriving geometry (construct_side = +1) only inside it. In a band
// around the front, surfaces are reduced to a glowing blue world-space lattice and streams of
// binary digits: on leaving geometry the 1s and 0s pour down the surface as it unravels, on
// arriving geometry they climb up it as it assembles. The front is broken up per lattice cell so
// it advances in blocky digital steps instead of a clean sphere.
// construct_side = 0 (the default) leaves a surface untouched and costs one branch.

global uniform vec3 construct_origin;
global uniform float construct_radius;
global uniform vec4 construct_reflection_camera;
instance uniform float construct_side = 0.0;

const float CFX_BAND = 3.6;
const float CFX_DENSITY = 2.0; // lattice lines per metre
const vec3 CFX_BLUE = vec3(0.12, 0.5, 1.0);
const vec3 CFX_ICE = vec3(0.75, 0.92, 1.0);
const vec2 CFX_GLYPH = vec2(0.085, 0.13); // glyph cell size in metres (width, height)

float cfx_hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

// Coverage of a "0" (oval ring) or "1" (stem, flag and foot) in a glyph cell, uv in 0..1.
float cfx_digit(vec2 uv, bool one) {
	vec2 p = (uv - 0.5) * 2.0;
	float d;
	if (one) {
		float stem = max(abs(p.x - 0.08) - 0.13, abs(p.y) - 0.72);
		vec2 f = p - vec2(-0.2, 0.52);
		float flag = max(abs(f.x * 0.6 + f.y * 0.8) - 0.11, abs(f.x * 0.8 - f.y * 0.6) - 0.26);
		float foot = max(abs(p.x - 0.08) - 0.38, abs(p.y + 0.72) - 0.1);
		d = min(min(stem, flag), foot);
	} else {
		d = abs(length(p * vec2(1.25, 0.95)) - 0.62) - 0.13;
	}
	float aa = fwidth(d) + 1e-4;
	return 1.0 - smoothstep(-aa, aa, d);
}

// Streams of binary digits on the surface. dir = +1 pours down, -1 climbs up. Returns coverage;
// head (0..1) is how close the glyph is to the bright leading digit of its stream.
float cfx_glyphs(vec3 wpos, vec3 wnrm, float time, float dir, out float head) {
	vec3 an = abs(wnrm);
	// Surface coordinates: (across, along) the direction digits travel.
	vec2 sp = an.y > max(an.x, an.z) ? wpos.xz : (an.x > an.z ? wpos.zy : wpos.xy);
	float col = floor(sp.x / CFX_GLYPH.x);
	float hc = cfx_hash(vec3(col, 7.13, floor(sp.y / 9.0)));
	float speed = (1.2 + hc * 2.4) * CFX_GLYPH.y * 6.0;
	float v = sp.y + dir * time * speed;
	float row = floor(v / CFX_GLYPH.y);
	vec2 uv = vec2(fract(sp.x / CFX_GLYPH.x), fract(v / CFX_GLYPH.y));
	// Each stream is a bright head trailing fading digits; streams repeat down the column.
	float phase = fract(row * 0.055 * -dir + hc * 13.7);
	head = pow(phase, 6.0);
	float trail = smoothstep(0.35, 1.0, phase);
	bool one = cfx_hash(vec3(col, row, floor(time * 4.0 + hc * 9.0))) > 0.5;
	float active = step(0.3, hc);
	return cfx_digit(uv, one) * trail * active;
}

// rgb: emission to add; a: 0 = discard this fragment. wire returns how far the surface has turned
// into lattice (0 solid .. 1 pure lattice), to darken albedo underneath.
vec4 construct_fx(vec3 wpos, vec3 wnrm, float time, out float wire, vec3 camera_position) {
	wire = 0.0;
	// Clip the pool floor and submerged geometry only in the mirror camera.
	// Main, underwater, shadow and zone-transition views retain their usual coverage.
	if (construct_reflection_camera.w > -1000.0
			&& distance(camera_position,construct_reflection_camera.xyz)<0.02
			&& wpos.y < construct_reflection_camera.w) {
		return vec4(0.0);
	}
	if (construct_side == 0.0) {
		return vec4(0.0, 0.0, 0.0, 1.0);
	}
	vec3 cell = floor(wpos * 1.25);
	float jitter = (cfx_hash(cell) - 0.5) * 1.6;
	float rel = distance(wpos, construct_origin) + jitter - construct_radius; // > 0: beyond the front
	// Distance into the surviving side: leaving geometry survives beyond the front, arriving inside.
	float s = construct_side < 0.0 ? rel : -rel;
	if (s < 0.0) {
		return vec4(0.0);
	}
	if (s > CFX_BAND) {
		return vec4(0.0, 0.0, 0.0, 1.0);
	}
	float t = s / CFX_BAND; // 0 at the front, 1 where the surface is solid again
	// Lattice lines on the two axes that run along the surface.
	vec3 f = abs(fract(wpos * CFX_DENSITY) - 0.5);
	vec3 n = abs(wnrm);
	vec3 lines = smoothstep(vec3(0.44), vec3(0.49), f) * (1.0 - smoothstep(vec3(0.6), vec3(0.9), n));
	float lattice = max(max(lines.x, lines.y), lines.z);
	float head;
	float digits = cfx_glyphs(wpos, wnrm, time, construct_side < 0.0 ? 1.0 : -1.0, head);
	float flicker = 0.8 + 0.2 * sin(time * 37.0 + cfx_hash(cell) * 40.0);
	float keep = max(lattice, digits);
	// Inside the band only lattice and digits survive, thinning out toward the solid side.
	float solid_in = smoothstep(0.6, 1.0, t);
	if (keep < 0.3 && solid_in < cfx_hash(cell + floor(time * 12.0))) {
		return vec4(0.0);
	}
	wire = 1.0 - solid_in;
	vec3 glow = CFX_BLUE * lattice * 5.5 * flicker * (1.0 - t * 0.7);
	glow += mix(CFX_BLUE * 1.4, CFX_ICE * 2.2, head) * digits * 6.0 * (1.0 - t * 0.45);
	glow += CFX_ICE * 12.0 * (1.0 - smoothstep(0.0, 0.06, t)); // white-hot leading edge
	glow += CFX_BLUE * 0.45 * (1.0 - solid_in);
	return vec4(glow, 1.0);
}
