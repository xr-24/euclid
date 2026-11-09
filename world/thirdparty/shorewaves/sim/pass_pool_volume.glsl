#[compute]
#version 450
// Construct closed-pool inventory correction. Uses the existing occasional debug reduction,
// not an additional full-state CPU readback. All cells project in parallel, preserving velocity.
layout(local_size_x=16,local_size_y=16,local_size_z=1) in;
layout(rgba32f,set=0,binding=0) uniform restrict image2D state;
layout(rgba32f,set=0,binding=1) uniform restrict readonly image2D bottom;
layout(push_constant) uniform Push { float ratio; float pad0; float pad1; float pad2; } pc;
void main() {
    ivec2 at = ivec2(gl_GlobalInvocationID.xy);
    if (any(greaterThanEqual(at,imageSize(state)))) { return; }
    float b = imageLoad(bottom,at).r;
    if (b >= 0.0) { return; }
    vec4 q = imageLoad(state,at);
    q.x = b+max(q.x-b,0.0)*pc.ratio;
    q.yzw *= pc.ratio;
    imageStore(state,at,q);
}
