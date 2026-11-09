#[compute]
#version 450

// Construct addition (not part of the original package): disturb the water around a point.
// Pushes momentum (mu, mv per metre of depth) into the water around (cx, cy), and optionally
// raises a volume-neutral splash: the Mexican-hat profile (1 - 2r^2) exp(-2r^2) integrates to zero
// over the plane, so pokes never add or remove water.

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(rgba32f, set = 0, binding = 0) uniform restrict image2D img_state;
layout(rgba32f, set = 0, binding = 1) uniform restrict readonly image2D img_bottom;

layout(push_constant) uniform Push {
	float cx;      // centre, cells (solver x)
	float cy;      // centre, cells (solver y)
	float radius;  // cells
	float dh;      // splash height (m), volume neutral
	float mu;      // momentum along solver x (m/s)
	float mv;      // momentum along solver y (m/s)
	float pad0;
	float pad1;
} pc;

void main() {
	int N = imageSize(img_state).x;
	ivec2 id = ivec2(gl_GlobalInvocationID.xy);
	if (id.x >= N || id.y >= N) {
		return;
	}
	vec2 d = vec2(id) + 0.5 - vec2(pc.cx, pc.cy);
	float r2 = dot(d, d) / max(pc.radius * pc.radius, 1e-4);
	if (r2 > 6.0) {
		return;
	}
	vec4 q = imageLoad(img_state, id);
	float B = imageLoad(img_bottom, id).r;
	float h = q.x - B;
	if (h < 0.01) {
		return;
	}
	float g = exp(-2.0 * r2);
	q.x = max(q.x + pc.dh * (1.0 - 2.0 * r2) * g, B + 0.002);
	float hn = q.x - B;
	q.y += pc.mu * g * hn;
	q.z += pc.mv * g * hn;
	imageStore(img_state, id, q);
}
