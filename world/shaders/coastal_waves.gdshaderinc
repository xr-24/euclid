// Shared by the surface and the GPU wavemaker. Solver coordinates are (world z, world x).
// A dominant incoming swell with small, narrowly spread secondary components avoids a
// crossed, equally strong wave lattice. Heights, slopes and boundary momentum share phases.
vec4 coastal_component(vec2 p, float t, float amp, float period, float depth,
		float amp_fraction, float period_fraction, float phase, float angle) {
	float omega = 6.28318530718 / (period * period_fraction);
	float k = omega * omega / (9.81 * sqrt(tanh(omega * omega * depth / 9.81)));
	vec2 direction = vec2(cos(angle),sin(angle));
	float argument = omega * t - k * dot(direction,p) + phase;
	float a = amp * amp_fraction;
	return vec4(a*sin(argument), -a*k*cos(argument)*direction, omega/k);
}

vec3 coastal_forcing(vec4 wave, float angle) {
	return vec3(wave.x, wave.x*wave.w*vec2(cos(angle),sin(angle)));
}

vec3 coastal_height_slopes(vec2 p, float t, float amp, float period, float depth) {
	return coastal_component(p,t,amp,period,depth,1.0,1.0,0.0,0.0).xyz
		+ coastal_component(p,t,amp,period,depth,0.18,0.72,2.1,0.13).xyz
		+ coastal_component(p,t,amp,period,depth,0.10,1.4,4.4,-0.09).xyz
		+ coastal_component(p,t,amp,period,depth,0.06,0.86,1.3,0.06).xyz;
}

vec3 coastal_incident(vec2 p, float t, float amp, float period, float depth) {
	return coastal_forcing(coastal_component(p,t,amp,period,depth,1.0,1.0,0.0,0.0),0.0)
		+ coastal_forcing(coastal_component(p,t,amp,period,depth,0.18,0.72,2.1,0.13),0.13)
		+ coastal_forcing(coastal_component(p,t,amp,period,depth,0.10,1.4,4.4,-0.09),-0.09)
		+ coastal_forcing(coastal_component(p,t,amp,period,depth,0.06,0.86,1.3,0.06),0.06);
}
