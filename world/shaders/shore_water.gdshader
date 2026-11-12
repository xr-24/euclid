// Shallow-water shore surface for the cove, driven by the vendored shoreline solver.
// Adapted from shaders/water.gdshader of "Realistic Shoreline Waves" by Reboot16 (MIT, see
// res://thirdparty/shorewaves/LICENSE.txt). Construct changes: the sim grid is placed in the world
// by sim_origin with its axes swapped (solver x = world z, cross-shore; solver y = world x,
// alongshore), surface heights are offset by sea_level. One surface shader blends shared offshore
// waves into the solver field. Pool sampling excludes dry walls, ripple normals are independent
// of foam, and the construct effect is applied.
shader_type spatial;
render_mode depth_draw_never, cull_disabled, specular_schlick_ggx;
#include "res://shaders/construct_fx.gdshaderinc"
#include "res://shaders/coastal_waves.gdshaderinc"

uniform float DOMAIN_SIZE = 48.64;
uniform float GRID_RES = 608.0;
uniform vec2 sim_origin = vec2(-24.32, -55.0); // world (x, z) of the solver's (alongshore 0, cross-shore 0)
uniform float sea_level = -0.55;
uniform bool confined = false;
uniform int surface_role = 0; // 0 detailed solver patch/pool, 1 surrounding ocean, 2 horizon
uniform vec4 ocean_patch_bounds = vec4(-130.0,-170.0,130.0,30.0);
uniform float wave_time = 0.0;
uniform float wave_amp = 0.14;
uniform float wave_period = 6.0;
uniform float wave_depth = 2.5;
uniform bool shore_edge_smoothing = false;
uniform bool column_optics = false;
uniform bool pool_reflection_enabled = false;
uniform int debug_surface = 0; // diagnostic views only
uniform sampler2D pool_reflection : filter_linear, repeat_disable;
uniform mat4 pool_reflection_matrix;

uniform sampler2D tx_state : filter_linear, repeat_disable;   // r=w  g=hu  b=hv  a=hc
uniform sampler2D tx_bottom : filter_linear, repeat_disable;  // r=B
uniform sampler2D tx_derived : filter_linear, repeat_disable; // r=n.x g=n.z b=foamVis a=aeration
uniform sampler2D lace_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D flow_noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_normal_a : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_normal_b : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;

uniform vec3 absorption = vec3(1.1, 0.32, 0.42);       // Beer-Lambert per metre: clear Mediterranean teal
uniform vec3 scatter_color = vec3(0.03, 0.2, 0.2);
uniform vec3 deep_scatter = vec3(0.012, 0.075, 0.12);
uniform vec3 foam_albedo = vec3(0.62);
uniform float refraction_strength : hint_range(0.0, 0.3) = 0.06;
uniform float detail_normal_strength : hint_range(0.0, 2.0) = 0.32;
uniform float foam_strength : hint_range(0.0, 1.0) = 1.0;
uniform float foam_softness : hint_range(0.5, 2.0) = 1.0;
uniform float foam_strength_override = -1.0;
uniform float foam_softness_override = -1.0;
uniform float base_roughness : hint_range(0.0, 1.0) = 0.045;
uniform float reflection_strength = 1.0;
uniform float lace_scale_coarse : hint_range(0.1, 10.0) = 1.2;
uniform float lace_scale_fine : hint_range(0.01, 2.0) = 0.12;
uniform float flow_speed_scale : hint_range(0.0, 4.0) = 1.0;
uniform float flow_period : hint_range(0.2, 10.0) = 2.0;

varying vec3 v_world_pos;

// World xz -> solver texture coordinates (axes swapped).
vec2 sim_uv(vec2 wxz) {
	return vec2(wxz.y - sim_origin.y, wxz.x - sim_origin.x) / DOMAIN_SIZE;
}

// Ignore dry wall heights when interpolating the confined pool's wet surface.
// Ordinary bilinear filtering blends the coping into the last wet cell and lifts its edge.
vec4 wet_surface(vec2 uv) {
	vec2 cell = uv * GRID_RES - 0.5;
	vec2 base = floor(cell);
	vec2 f = fract(cell);
	vec2 sum = vec2(0.0);
	float weight = 0.0;
	for (int y = 0; y < 2; y++) {
		for (int x = 0; x < 2; x++) {
			vec2 offset = vec2(float(x), float(y));
			vec2 at = (base + offset + 0.5) / GRID_RES;
			float w = textureLod(tx_state, at, 0.0).r;
			float bed = textureLod(tx_bottom, at, 0.0).r;
			vec2 blend = mix(1.0 - f, f, offset);
			float wt = blend.x * blend.y * step(confined ? 0.01 : 0.002, w - bed);
			sum += vec2(w, bed) * wt;
			weight += wt;
		}
	}
	return vec4(sum / max(weight, 0.00001), weight, 0.0);
}

float edge_distance(vec2 wxz) {
	vec2 rel = wxz - sim_origin;
	return min(min(rel.x, DOMAIN_SIZE - rel.x), min(rel.y,DOMAIN_SIZE-rel.y));
}

float simulation_weight(vec2 wxz) {
	vec2 rel = wxz - sim_origin;
	// Independent smooth factors round off corners; no hard rectangular sea-state boundary.
	return smoothstep(0.5,6.0,rel.x) * smoothstep(0.5,6.0,DOMAIN_SIZE-rel.x)
		* smoothstep(0.5,12.0,rel.y) * smoothstep(0.5,2.0,DOMAIN_SIZE-rel.y);
}

vec3 ocean_field(vec2 wxz) {
	vec2 rel = wxz - sim_origin;
	vec3 field = coastal_height_slopes(rel.yx,wave_time,wave_amp,wave_period,wave_depth);
	return field * min(1.0,wave_time/max(wave_period,0.001));
}

float geometry_weight(vec2 wxz) {
	float edge = min(min(wxz.x-ocean_patch_bounds.x,ocean_patch_bounds.z-wxz.x),
		min(wxz.y-ocean_patch_bounds.y,ocean_patch_bounds.w-wxz.y));
	return smoothstep(0.0,20.0,edge);
}

float flow_lace(vec2 wxz, float scale_m, vec2 disp_m, float t) {
	float p0 = fract(t);
	float p1 = fract(t + 0.5);
	float blend = abs(2.0 * p0 - 1.0);
	vec2 uv0 = (wxz - disp_m * (p0 - 0.5)) / max(scale_m, 1e-4);
	vec2 uv1 = (wxz - disp_m * (p1 - 0.5)) / max(scale_m, 1e-4);
	return mix(texture(lace_tex, uv0).r, texture(lace_tex, uv1).r, blend);
}

vec3 scene_world_position(vec2 uv, mat4 inv_proj, mat4 inv_view) {
	vec4 position = inv_proj*vec4(uv*2.0-1.0,texture(depth_tex,uv).r,1.0);
	position /= max(position.w,0.000001);
	return (inv_view*vec4(position.xyz,1.0)).xyz;
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 suv = clamp(sim_uv(wp.xz), vec2(0.0), vec2(1.0));
	vec4 surface = wet_surface(suv);
	float h = max(surface.x-surface.y,0.0);
	float w = surface.x;
	if (!confined) { w = mix(ocean_field(wp.xz).x,w,simulation_weight(wp.xz)); }
	// Never raise dry mesh vertices to the terrain/wall height. Terrain depth and the wet
	// fragment mask hide them, rather than stretching a sheet up the bank.
	if (confined && surface.z < 0.001) { w = -0.05; }
	if (!confined) { w *= geometry_weight(wp.xz); }
	if (surface_role == 2) { w = 0.0; } // coarse horizon carries wave normals, never aliased geometry
	VERTEX.y = sea_level - MODEL_MATRIX[3].y + w;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Explicitly use the transparent pass: opaque water can enter the scene depth
	// buffer that adjacent sections sample, turning their join into a colour/depth seam.
	ALPHA = 1.0;
	vec2 suv = clamp(sim_uv(v_world_pos.xz),vec2(0.0),vec2(1.0));
	vec4 surface = wet_surface(suv);
	float sim_weight = confined ? 1.0 : simulation_weight(v_world_pos.xz);
	if (confined && surface.z < 0.02) { discard; }
	if (!confined) {
		float edge = edge_distance(v_world_pos.xz);
		if (surface_role == 0 && edge < 0.5) { discard; }
		if (surface_role == 1 && edge >= 0.5) { discard; }
		if (surface_role == 2 && geometry_weight(v_world_pos.xz) > 0.0) { discard; }
		if (sim_weight > 0.999 && surface.z < 0.02) { discard; }
	}
	float cfx_wire;
	vec4 cfx = construct_fx((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz, normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz), TIME, cfx_wire, CAMERA_POSITION_WORLD);
	if (cfx.a < 0.5) {
		discard;
	}
	// Seen from below when the camera is under the surface (FRONT_FACING is unreliable on
	// this displaced, double-sided mesh).
	if (CAMERA_POSITION_WORLD.y < v_world_pos.y) {
		// Seen from below while swimming: the bright, rippling underside of the surface.
		vec3 above = textureLod(screen_tex, SCREEN_UV, 1.5).rgb;
		ALBEDO = vec3(0.0);
		SPECULAR = 0.0;
		ROUGHNESS = 1.0;
		EMISSION = mix(above * vec3(0.55, 0.85, 0.85), scatter_color * 2.0, 0.35) + cfx.rgb;
	} else {

		vec4 st = texture(tx_state, suv);
		float h = max(surface.x-surface.y,0.0);
		vec4 der = texture(tx_derived, suv);
		float foam_vis = clamp(der.b, 0.0, 1.0)*sim_weight;
		float aeration = clamp(der.a, 0.0, 1.0)*sim_weight;
		float shore = mix(1.0,smoothstep(0.0, 0.02, h),sim_weight);

		// Solver vectors are (cross-shore, alongshore) = (world z, world x).
		vec2 nxz = clamp(der.gr, -1.0, 1.0);
		float ny = sqrt(max(1.0 - dot(nxz, nxz), 0.0));
		vec3 n_world = normalize(vec3(nxz.x, max(ny, 0.05), nxz.y));
		if (!confined) {
			vec3 field = ocean_field(v_world_pos.xz);
			vec2 gradient = mix(field.zy,-nxz/max(ny,0.15),sim_weight);
			vec2 weight_gradient = vec2(
				simulation_weight(v_world_pos.xz+vec2(0.1,0.0))-simulation_weight(v_world_pos.xz-vec2(0.1,0.0)),
				simulation_weight(v_world_pos.xz+vec2(0.0,0.1))-simulation_weight(v_world_pos.xz-vec2(0.0,0.1)))/0.2;
			gradient += weight_gradient*(surface.x-field.x);
			n_world = normalize(vec3(-gradient.x,1.0,-gradient.y));
		}

		vec2 mom = st.bg; // world (x, z) momentum
		vec2 vel = mom / max(h, 0.02);
		vec2 disp = vel * flow_speed_scale * flow_period * 0.5;
		float dlen = length(disp);
		disp *= min(dlen, 0.35) / max(dlen, 1e-5);
		vec2 pn = texture(flow_noise_tex, v_world_pos.xz / 9.7).rg;
		float t_flow = TIME / max(flow_period, 1e-3) + pn.r;

		// Smooth independent ripple normals; cellular foam must not double as a height field.
		vec2 uv_a = v_world_pos.xz / 3.7 + TIME * vec2(0.014, -0.009);
		mat2 rotate_b = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
		vec2 uv_b = rotate_b * v_world_pos.xz / 2.3 + TIME * vec2(-0.011, 0.007);
		vec2 na = texture(detail_normal_a, uv_a).rg * 2.0 - 1.0;
		vec2 nb = texture(detail_normal_b, uv_b).rg * 2.0 - 1.0;
		vec2 ripple = na + transpose(rotate_b) * nb * 0.55;
		float distance_fade = 1.0 - smoothstep(25.0, 110.0, distance(CAMERA_POSITION_WORLD, v_world_pos));
		n_world = normalize(n_world + vec3(ripple.x, 0.0, ripple.y) * detail_normal_strength * distance_fade);
		NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);

		vec3 view_ray = normalize(v_world_pos-CAMERA_POSITION_WORLD);
		vec3 scene_position = scene_world_position(SCREEN_UV,INV_PROJECTION_MATRIX,INV_VIEW_MATRIX);
		float thickness = clamp(dot(scene_position-v_world_pos,view_ray),0.0,100.0);
		// Distort by the wave normal's deviation from a flat surface. Using the full
		// view-space normal also offsets perfectly flat water with camera pitch,
		// pulling the bank/pier across the surface and exposing rectangular cutouts.
		vec3 flat_normal = normalize((VIEW_MATRIX * vec4(0.0,1.0,0.0,0.0)).xyz);
		vec2 distortion = (NORMAL.xy-flat_normal.xy)*refraction_strength;
		distortion *= min(1.0,0.004/max(length(distortion),0.00001));
		vec2 ruv = SCREEN_UV + distortion * clamp(thickness, 0.0, 1.0) * shore;
		ruv = clamp(ruv, vec2(0.001), vec2(0.999));
		if (refraction_strength>0.0) {
			vec3 refracted_position = scene_world_position(ruv,INV_PROJECTION_MATRIX,INV_VIEW_MATRIX);
			if (dot(refracted_position-v_world_pos,view_ray)<-0.01) { ruv = SCREEN_UV; }
		}
		vec3 refr_rgb = textureLod(screen_tex, ruv, aeration * 4.0 * shore).rgb;

		float optical_depth = max(v_world_pos.y-scene_position.y,0.0);
		float optical_length = thickness;
		if (column_optics) {
			// At a low view angle the depth ray jumps from the near shelf to the
			// distant seabed. Keep local column optics across the entire cove and
			// extend them beyond its border before fading to distant scene depth.
			vec2 closest = clamp(v_world_pos.xz,sim_origin,sim_origin+vec2(DOMAIN_SIZE));
			float optics_weight = 1.0-smoothstep(0.0,20.0,distance(v_world_pos.xz,closest));
			optical_depth = mix(optical_depth,h,optics_weight);
			optical_length = mix(optical_length,h/max(abs(view_ray.y),0.15),optics_weight);
		}
		vec3 trans = exp(-absorption * optical_length * 1.35);
		trans *= exp(-aeration * 8.0 * optical_length);
		vec3 base_scat = mix(scatter_color, deep_scatter, smoothstep(1.5, 6.0, optical_depth));
		vec3 scat = mix(base_scat, vec3(0.55, 0.80, 0.72), aeration * 0.7);
		trans = mix(vec3(1.0), trans, shore);
		vec3 water_col = refr_rgb * trans + scat * (1.0 - trans);

		float strength = foam_strength_override >= 0.0 ? foam_strength_override : foam_strength;
		float softness = foam_softness_override >= 0.0 ? foam_softness_override : foam_softness;
		float fv = pow(foam_vis, 1.5) * 0.8 * smoothstep(0.0005, 0.006, h) * strength;
		float lace_c = flow_lace(v_world_pos.xz, lace_scale_coarse, disp, t_flow);
		float lace_f = flow_lace(v_world_pos.xz, lace_scale_fine, disp, t_flow + pn.g);
		float lace = 0.72 * lace_c + 0.28 * lace_f;
		float foam_mask = smoothstep(1.0 - fv, 1.0 - fv + 0.38 * softness, lace) * 0.94;

		float fres = 0.02 + 0.98 * pow(1.0 - clamp(dot(VIEW, NORMAL), 0.0, 1.0), 5.0);
		fres *= shore * (1.0 - foam_mask) * reflection_strength;

		vec3 reflection_col = vec3(0.0);
		float planar = 0.0;
		if (pool_reflection_enabled) {
			vec4 projected = pool_reflection_matrix * vec4(v_world_pos,1.0);
			vec2 reflection_uv = projected.xy / max(projected.w,0.001) * vec2(0.5,-0.5) + 0.5;
			reflection_uv += n_world.xz * 0.008;
			if (projected.w>0.0 && all(greaterThan(reflection_uv,vec2(0.001))) && all(lessThan(reflection_uv,vec2(0.999)))) {
				reflection_col = texture(pool_reflection,reflection_uv).rgb;
				planar = 1.0;
			}
		}
		float contact = 1.0;
		if (shore_edge_smoothing) {
			float vertical_depth = thickness*abs(normalize(v_world_pos-CAMERA_POSITION_WORLD).y);
			float aa = max(fwidth(vertical_depth)*1.5,0.008);
			contact = smoothstep(0.0,0.022+aa,vertical_depth);
		}
		vec3 water_light = water_col * (1.0 - fres) * (1.0 - foam_mask) + reflection_col * fres * planar;
		EMISSION = water_light + cfx.rgb;
		ALBEDO = foam_albedo * foam_mask * (1.0 - cfx_wire * 0.85);
		ALBEDO *= contact;
		SPECULAR = 0.25 * (1.0-planar) * contact * reflection_strength;
		ROUGHNESS = mix(base_roughness, 0.85, max(foam_mask, aeration * 0.5));
		if (debug_surface != 0) {
			ALBEDO = vec3(0.0);
			SPECULAR = 0.0;
			if (debug_surface == 1) { EMISSION = n_world * 0.5 + 0.5; }
			if (debug_surface == 2) { EMISSION = vec3(optical_depth/8.0); }
			if (debug_surface == 3) { EMISSION = vec3(sim_weight,foam_vis,aeration); }
		}
	}
}
