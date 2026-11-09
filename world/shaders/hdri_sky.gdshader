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

vec3 pano(sampler2D tex, float yaw, vec3 dir) {
	vec2 st = vec2(mod(atan(dir.x, dir.z) - yaw, 6.2831853), acos(clamp(dir.y, -1.0, 1.0)));
	return min(textureLod(tex, st / vec2(6.2831853, 3.1415927), 0.0).rgb, vec3(clamp_value));
}

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void sky() {
	vec3 c = mix(pano(panorama_a, yaw_a, EYEDIR) * energy_a, pano(panorama_b, yaw_b, EYEDIR) * energy_b, blend);
	if (!AT_CUBEMAP_PASS && LIGHT0_ENABLED) {
		float size = max(LIGHT0_SIZE, 0.0093) * sun_disk_scale;
		float d = dot(EYEDIR, LIGHT0_DIRECTION);
		float disk = smoothstep(cos(size * 0.6), cos(size * 0.5), d);
		float halo = pow(max(d, 0.0), 900.0) * 0.6 + pow(max(d, 0.0), 60.0) * 0.08;
		c += LIGHT0_COLOR * LIGHT0_ENERGY * (disk * 60.0 + halo * 4.0) * sun_visibility;
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
