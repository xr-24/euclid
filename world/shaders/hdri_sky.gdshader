// HDRI sky that keeps the photographed sun out of image-based lighting. The real sun comes from the
// DirectionalLight (with shadows); if the HDRI's sun stayed in the sky it would also light everything
// again through ambient light, unshadowed, and flatten every shadow. The visible background gets a
// sun disk drawn from that DirectionalLight so the sky still shows the sun where it shines from.
//
// Two panoramas (a, b) crossfade during a zone shift, and while the shift runs a blue lattice and
// falling code briefly overlay the sky.
shader_type sky;

global uniform float construct_progress;

uniform sampler2D panorama_a : filter_linear, repeat_enable;
uniform sampler2D panorama_b : filter_linear, repeat_enable;
// Turns each panorama about the vertical axis (radians), so its sun sits where the zone wants it.
uniform float yaw_a = 0.0;
uniform float yaw_b = 0.0;
uniform float energy_a = 1.0;
uniform float energy_b = 1.0;
uniform float blend : hint_range(0.0, 1.0) = 0.0;
uniform float clamp_value = 24.0;
uniform float sun_disk_scale = 1.0;
uniform float sun_visibility = 1.0;
// Where each panorama's photographed sun is (xyz) and how much to dim it (w), for when the
// atmosphere moves the sun away from where the photo had it.
uniform vec4 hide_sun_a = vec4(0.0);
uniform vec4 hide_sun_b = vec4(0.0);
// Star field brightness; it shows as the sun goes down.
uniform float stars = 0.0;
// The celestial sphere in world space, sharing the sun's daily path: the point of the celestial
// equator due toward the noon sun, the way the sky turns (where the sun sets), and the pole.
uniform vec3 star_meridian = vec3(0.0, 0.848, 0.53);
uniform vec3 star_west = vec3(1.0, 0.0, 0.0);
uniform vec3 star_axis = vec3(0.0, 0.53, -0.848);
// Local sidereal time in radians: how far the sky has turned.
uniform float star_turn = 0.0;
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.0;

// Galactic north pole, galactic centre and the direction 90 degrees of galactic longitude from
// it, in equatorial coordinates (J2000).
const vec3 GALACTIC_POLE = vec3(-0.8679, -0.1970, 0.4560);
const vec3 GALACTIC_CENTRE = vec3(-0.0549, -0.8735, -0.4838);
const vec3 GALACTIC_SIDE = vec3(0.4936, -0.4449, 0.7473);

vec3 pano(sampler2D tex, float yaw, vec3 dir, vec4 hide) {
	vec2 st = vec2(mod(atan(dir.x, dir.z) - yaw, 6.2831853), acos(clamp(dir.y, -1.0, 1.0)));
	vec3 c = min(textureLod(tex, st / vec2(6.2831853, 3.1415927), 0.0).rgb, vec3(clamp_value));
	if (hide.w > 0.0) {
		float near_sun = smoothstep(0.9975, 0.9995, dot(dir, normalize(hide.xyz)));
		c = mix(c, min(c, vec3(1.6)), near_sun * hide.w);
	}
	return c;
}

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x),
			mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x),
			mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm3(vec3 p) {
	return 0.55 * noise3(p) + 0.3 * noise3(p * 2.1 + 3.7) + 0.15 * noise3(p * 4.3 - 8.1);
}

float cloud_hash(vec2 cell) {
	vec3 p = fract(vec3(cell.xyx) * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float cloud_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(cloud_hash(cell), cloud_hash(cell + vec2(1, 0)), f.x),
		mix(cloud_hash(cell + vec2(0, 1)), cloud_hash(cell + vec2(1, 1)), f.x), f.y);
}

// A star's colour from its surface temperature: Planck's law sampled at red, green and blue,
// scaled to unit luminance and softened toward white the way the eye sees faint points.
vec3 star_tint(float kelvin) {
	vec3 l = vec3(0.61, 0.55, 0.465); // micrometres
	vec3 b = 1.0 / (l * l * l * l * l * (exp(14388.0 / (l * kelvin)) - 1.0));
	b /= dot(b, vec3(0.2126, 0.7152, 0.0722));
	return mix(vec3(1.0), b, 0.55);
}

// One star per occupied cell of a grid over the celestial sphere. Magnitudes follow the real
// count of stars, N(brighter than m) ~ 10^(0.5 m), between the layer's bounds (lo and hi are
// 10^(0.5 m) at its brightest and faintest).
vec3 star_layer(vec3 v, float cells, float chance, float lo, float hi, float scint, float time) {
	vec3 p = v * cells;
	vec3 cell = floor(p);
	vec3 h = hash33(cell);
	if (h.x > chance) {
		return vec3(0.0);
	}
	vec3 j = hash33(cell + 17.31);
	vec3 star = normalize(cell + 0.5 + (j - 0.5) * 0.5);
	float d = length(v - star); // radians, near the star
	vec3 q = abs(fract(p) - 0.5);
	float window = 1.0 - smoothstep(0.4, 0.5, max(q.x, max(q.y, q.z)));
	float magnitude = 2.0 * log(mix(lo, hi, h.y)) / 2.302585;
	// Flux rises 2.5x per magnitude; compressed somewhat so Sirius blooms without blinding.
	float flux = 0.4 * pow(10.0, -0.28 * (magnitude - 6.5));
	float point = exp(-d * d / 9.8e-7) + 0.03 * step(magnitude, 2.5) * exp(-d * d / 6.5e-6);
	// Most naked-eye stars are cool orange giants or hot blue-white stars; few are as hot as Rigel.
	float kelvin = exp(mix(log(3000.0), log(25000.0), pow(h.z, 1.4)));
	// Scintillation: turbulence makes stars flicker, far more near the horizon.
	float twinkle = 1.0 + scint * (0.6 * sin(time * (6.0 + 9.0 * j.x) + h.y * 60.0)
		+ 0.4 * sin(time * (11.0 + 13.0 * j.y) + h.z * 90.0));
	return star_tint(kelvin) * flux * point * window * max(twinkle, 0.15);
}

// The night sky in direction dir: the Milky Way and about six thousand naked-eye stars, dimmed
// and reddened by the air toward the horizon. A negative time (the radiance cubemap) gives only
// the diffuse glow.
vec3 night_sky(vec3 dir, float time) {
	// World direction -> equatorial coordinates (hour angle, then right ascension by sidereal time).
	float a = dot(dir, star_meridian);
	float b = dot(dir, star_west);
	float ct = cos(star_turn);
	float st = sin(star_turn);
	vec3 v = vec3(ct * a + st * b, st * a - ct * b, dot(dir, star_axis));
	// The Milky Way: a band along the galactic plane, brightest toward the bulge in Sagittarius,
	// broken by clumps of stars and dark dust lanes along its middle.
	float sb = dot(v, GALACTIC_POLE);
	float towards = dot(v, GALACTIC_CENTRE);
	float l = atan(dot(v, GALACTIC_SIDE), towards);
	float plane = exp(-sb * sb / 0.02);
	float bulge = exp(-l * l / 0.45 - sb * sb / 0.03);
	float lanes = smoothstep(0.45, 0.75, fbm3(v * 16.0 + 5.0)) * exp(-sb * sb / 0.003);
	float milky = (plane * (0.4 + 0.6 * fbm3(v * 9.0)) * (0.55 + 0.45 * towards) + bulge * 0.9) * (1.0 - 0.8 * lanes);
	vec3 light = mix(vec3(0.72, 0.8, 1.0), vec3(1.0, 0.84, 0.66), bulge) * milky * 0.03;
	// Extinction through the airmass toward each altitude, stronger in blue.
	float alt = max(dir.y, 0.0);
	float airmass = 1.0 / (alt + 0.025 * exp(-11.0 * alt));
	vec3 extinction = exp(-vec3(0.11, 0.18, 0.3) * (airmass - 1.0));
	if (time < 0.0) {
		return light * extinction;
	}
	float scint = mix(0.1, 0.55, 1.0 - smoothstep(0.05, 0.6, alt));
	// Bright stars (to magnitude 3) on a coarse grid; fainter ones (to 6.5) crowd toward the band.
	light += star_layer(v, 56.0, 0.0028, 0.186, 31.6, scint, time);
	float crowding = 0.55 + 1.5 * plane * (1.0 - 0.8 * lanes) + bulge;
	light += star_layer(v, 200.0, 0.0125 * crowding, 31.6, 1778.0, scint, time);
	return light * extinction;
}

void sky() {
	vec3 c = mix(pano(panorama_a, yaw_a, EYEDIR, hide_sun_a) * energy_a, pano(panorama_b, yaw_b, EYEDIR, hide_sun_b) * energy_b, blend);
	float cloud = 0.0;
	if (cloud_cover > 0.001 && EYEDIR.y > 0.0) {
		vec2 p = EYEDIR.xz / max(EYEDIR.y + 0.24, 0.24) * 4.0;
		if (!AT_CUBEMAP_PASS) {
			p += vec2(TIME * 0.012, TIME * 0.004);
		}
		vec2 warp = vec2(cloud_noise(p * 0.63 + 12.0), cloud_noise(p * 0.65 - 16.0)) - 0.5;
		p += warp * 1.4;
		float n = 0.56 * cloud_noise(p) + 0.29 * cloud_noise(p * 2.13 + 7.0)
			+ 0.15 * cloud_noise(p * 4.32 - 11.0);
		float edge = mix(0.84, 0.20, cloud_cover);
		cloud = smoothstep(edge - 0.07, edge + 0.13, n) * smoothstep(0.0, 0.12, EYEDIR.y);
		float daylight = LIGHT0_ENABLED ? smoothstep(-0.16, 0.16, LIGHT0_DIRECTION.y) : 1.0;
		vec3 gray = mix(vec3(0.015, 0.019, 0.027), vec3(0.42, 0.49, 0.58), daylight);
		c = mix(c, gray * (0.74 + n * 0.54), cloud * 0.93);
	}
	if (stars > 0.0 && EYEDIR.y > -0.02) {
		// The night sky fades in as the sun sets.
		float night = LIGHT0_ENABLED ? 1.0 - smoothstep(-0.12, 0.08, LIGHT0_DIRECTION.y) : 1.0;
		float horizon = smoothstep(-0.02, 0.04, EYEDIR.y);
		float fade = stars * night * horizon * (1.0 - cloud);
		if (fade > 0.0) {
			c += night_sky(EYEDIR, AT_CUBEMAP_PASS ? -1.0 : TIME) * fade;
		}
	}
	if (!AT_CUBEMAP_PASS && LIGHT0_ENABLED) {
		float size = max(LIGHT0_SIZE, 0.0093) * sun_disk_scale;
		float d = dot(EYEDIR, LIGHT0_DIRECTION);
		float disk = smoothstep(cos(size * 0.6), cos(size * 0.5), d);
		float halo = pow(max(d, 0.0), 900.0) * 0.6 + pow(max(d, 0.0), 60.0) * 0.08;
		c += LIGHT0_COLOR * LIGHT0_ENERGY * (disk * 60.0 + halo * 4.0) * sun_visibility * (1.0 - cloud);
	}
	if (!AT_CUBEMAP_PASS && construct_progress > 0.0) {
		float k = sin(construct_progress * 3.1415927);
		vec2 ll = vec2(atan(EYEDIR.x, EYEDIR.z) / 6.2831853 * 72.0, acos(clamp(EYEDIR.y, -1.0, 1.0)) / 3.1415927 * 36.0);
		vec2 g = abs(fract(ll) - 0.5);
		float lattice = smoothstep(0.46, 0.5, max(g.x, g.y));
		float col = hash2(vec2(floor(ll.x * 2.0), 3.0));
		float drop = fract(ll.y * 0.08 - TIME * (0.4 + col) + col * 9.0);
		float rain = step(0.7, col) * smoothstep(0.82, 1.0, drop) * step(0.5, hash2(floor(ll * vec2(2.0, 4.0)) + floor(TIME * 8.0)));
		c *= 1.0 - k * 0.55;
		c += vec3(0.12, 0.5, 1.0) * (lattice * 0.6 + rain * 2.4) * k;
	}
	COLOR = c;
}
