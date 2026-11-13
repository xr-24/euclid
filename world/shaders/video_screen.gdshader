shader_type spatial;
render_mode unshaded;
#include "res://shaders/construct_fx.gdshaderinc"

uniform sampler2D video_frame : source_color, filter_linear, repeat_disable, hint_default_black;
uniform bool has_video = false;
uniform float screen_aspect = 1.7778;
uniform float video_aspect = 1.7778;

void fragment() {
	float wire;
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec4 effect = construct_fx(world_pos, normalize(mat3(INV_VIEW_MATRIX) * NORMAL), TIME, wire, CAMERA_POSITION_WORLD);
	if (effect.a < 0.5) { discard; }
	vec2 uv = (UV - 0.5) * max(vec2(screen_aspect / video_aspect, video_aspect / screen_aspect), vec2(1.0)) + 0.5;
	vec3 pixels = vec3(0.012, 0.021, 0.032);
	if (has_video && all(greaterThanEqual(uv, vec2(0.0))) && all(lessThanEqual(uv, vec2(1.0)))) {
		pixels = texture(video_frame, uv).rgb;
	}
	ALBEDO = pixels * (1.0 - wire) + effect.rgb;
}
