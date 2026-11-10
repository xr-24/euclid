shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;
#define AVATAR_DAYLIGHT
#include "res://shaders/construct_fx.gdshaderinc"
#include "res://shaders/avatar_filaments.gdshaderinc"
