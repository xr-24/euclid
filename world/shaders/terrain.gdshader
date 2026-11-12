shader_type spatial;
#include "res://shaders/construct_fx.gdshaderinc"

uniform sampler2D base_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform sampler2D sand_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform sampler2D base_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D base_orm : filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform sampler2D sand_orm : filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform sampler2D rock_orm : filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform vec3 base_tint : source_color = vec3(1.0);
uniform vec3 sand_tint : source_color = vec3(1.0);
uniform vec3 rock_tint : source_color = vec3(1.0);
uniform vec3 tile_size = vec3(3.0, 3.5, 4.0);
varying vec3 terrain_weights;

void vertex() {
	terrain_weights = COLOR.rgb;
}

void fragment() {
	vec3 world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 world_normal = normalize(mat3(INV_VIEW_MATRIX) * NORMAL);
	float wire;
	vec4 effect = construct_fx(world, world_normal, TIME, wire, CAMERA_POSITION_WORLD);
	if (effect.a < 0.5) { discard; }
	vec3 weights = max(terrain_weights, vec3(0.0));
	weights /= max(0.001, weights.x + weights.y + weights.z);
	vec3 albedo = vec3(0.0);
	vec3 mapped_normal = vec3(0.0);
	vec2 ao_rough = vec2(0.0);
	vec2 dx = dFdx(world.xz);
	vec2 dy = dFdy(world.xz);
	if (weights.x > 0.0) {
		vec2 uv = world.xz / tile_size.x;
		albedo += weights.x * base_tint * textureGrad(base_albedo, uv, dx / tile_size.x, dy / tile_size.x).rgb;
		mapped_normal += weights.x * textureGrad(base_normal, uv, dx / tile_size.x, dy / tile_size.x).rgb;
		ao_rough += weights.x * textureGrad(base_orm, uv, dx / tile_size.x, dy / tile_size.x).rg;
	}
	if (weights.y > 0.0) {
		vec2 uv = world.xz / tile_size.y;
		albedo += weights.y * sand_tint * textureGrad(sand_albedo, uv, dx / tile_size.y, dy / tile_size.y).rgb;
		mapped_normal += weights.y * textureGrad(sand_normal, uv, dx / tile_size.y, dy / tile_size.y).rgb;
		ao_rough += weights.y * textureGrad(sand_orm, uv, dx / tile_size.y, dy / tile_size.y).rg;
	}
	if (weights.z > 0.0) {
		vec2 uv = world.xz / tile_size.z;
		albedo += weights.z * rock_tint * textureGrad(rock_albedo, uv, dx / tile_size.z, dy / tile_size.z).rgb;
		mapped_normal += weights.z * textureGrad(rock_normal, uv, dx / tile_size.z, dy / tile_size.z).rgb;
		ao_rough += weights.z * textureGrad(rock_orm, uv, dx / tile_size.z, dy / tile_size.z).rg;
	}
	ALBEDO = albedo * (1.0 - wire);
	EMISSION = effect.rgb;
	NORMAL_MAP = mapped_normal;
	NORMAL_MAP_DEPTH = 0.65;
	AO = ao_rough.x;
	ROUGHNESS = ao_rough.y;
}
