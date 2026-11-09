// Object-space corruption shared by body splats, hair and rooted scan trails.
float signal_hash(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float signal_noise(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(signal_hash(cell), signal_hash(cell + vec3(1, 0, 0)), f.x),
		mix(signal_hash(cell + vec3(0, 1, 0)), signal_hash(cell + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(signal_hash(cell + vec3(0, 0, 1)), signal_hash(cell + vec3(1, 0, 1)), f.x),
		mix(signal_hash(cell + vec3(0, 1, 1)), signal_hash(cell + vec3(1)), f.x), f.y), f.z);
}

float signal_integrity(vec3 p, float clock) {
	float region = signal_noise(p * vec3(9.0, 5.4, 7.0) + vec3(4.7, 1.1, 8.3));
	float clusters = signal_noise(p * 29.0 + vec3(1.3, 9.7, 3.1));
	float reform = signal_noise(p * 5.0 + vec3(1.8, clock * 0.095, -clock * 0.055));
	float shoulders = exp(-abs(p.y - 0.49) * 28.0) * smoothstep(0.09, 0.22, abs(p.x));
	float field = region * 0.56 + clusters * 0.21 + reform * 0.23;
	float fragmented = smoothstep(0.40, 0.57, field + shoulders * 0.11);
	float legs = mix(0.16, 1.0, smoothstep(-1.05, -0.35, p.y));
	return fragmented * legs;
}
