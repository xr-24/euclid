#[compute]
#version 450

// Construct addition (not part of the original package): sample the water at up to 8 points
// (cell coordinates) for buoyancy and swimming. Writes (surface w, bed B, hu, hv) per probe.

layout(local_size_x = 8, local_size_y = 1, local_size_z = 1) in;

layout(rgba32f, set = 0, binding = 0) uniform restrict readonly image2D img_state;
layout(rgba32f, set = 0, binding = 1) uniform restrict readonly image2D img_bottom;
layout(std430, set = 0, binding = 2) restrict writeonly buffer Probes {
	vec4 v[8];
} probes;

layout(push_constant) uniform Push {
	vec2 p[8];
} pc;

void main() {
	uint k = gl_GlobalInvocationID.x;
	if (k >= 8u) {
		return;
	}
	ivec2 N = imageSize(img_state);
	ivec2 c = clamp(ivec2(floor(pc.p[k])), ivec2(0), N - 1);
	vec4 q = imageLoad(img_state, c);
	float B = imageLoad(img_bottom, c).r;
	probes.v[k] = vec4(q.x, B, q.y, q.z);
}
