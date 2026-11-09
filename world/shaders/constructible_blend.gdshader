// Constructible standard surface: alpha blended.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;
#define CFX_BLEND
#include "res://shaders/constructible.gdshaderinc"
