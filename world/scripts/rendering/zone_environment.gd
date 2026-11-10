extends RefCounted
## Zone lighting and atmosphere; independent of geometry and simulation.
const Packages = preload("res://scripts/zones/zone_packages.gd")
const Assets = preload("res://scripts/assets/asset_library.gd")
static var _cache := {}

static func apply_environment(env: Environment, sun: DirectionalLight3D, zone: String) -> void:
	var state := zone_state(zone)
	_setup_features(env, sun, state)
	apply_state(env, sun, state, state, 1.0)

## Everything about a zone's look that can be blended during a shift.

static func zone_state(zone: String) -> Dictionary:
	var s := Packages.environment(zone)
	var hdri_path := Assets.PH + "hdri/" + str(s.get("hdri", ""))
	var elevation: float = s.get("sun_elevation", 40.0)
	s.yaw = 0.0
	if s.has("hdri") and ResourceLoader.exists(hdri_path):
		s.panorama = Assets.get_resource(hdri_path)
		# Rotate the panorama so its photographed sun sits at the authored azimuth.
		var sun_data := _hdri_sun(str(s.hdri))
		elevation = sun_data.get("elevation_deg", elevation)
		s.yaw = deg_to_rad(s.sun_azimuth - float(sun_data.get("u", 0.0)) * 360.0)
	else:
		s.panorama = _gradient_sky(s.get("sky_colors", Packages.environment("construct").sky_colors))
	var az := deg_to_rad(s.sun_azimuth)
	var el := deg_to_rad(elevation)
	s.to_sun = Vector3(sin(az) * cos(el), sin(el), cos(az) * cos(el))
	return s

## Blend between two zone states (t = 0 is a, 1 is b) for skies, sun, exposure and fog.

static func apply_state(env: Environment, sun: DirectionalLight3D, a: Dictionary, b: Dictionary, t: float) -> void:
	var sky_mat := env.sky.sky_material as ShaderMaterial
	if sky_mat == null or sky_mat.shader.resource_path != "res://shaders/hdri_sky.gdshader":
		sky_mat = ShaderMaterial.new()
		sky_mat.shader = Assets.get_resource("res://shaders/hdri_sky.gdshader")
		env.sky.sky_material = sky_mat
	sky_mat.set_shader_parameter("panorama_a", a.panorama)
	sky_mat.set_shader_parameter("panorama_b", b.panorama)
	sky_mat.set_shader_parameter("yaw_a", a.yaw)
	sky_mat.set_shader_parameter("yaw_b", b.yaw)
	sky_mat.set_shader_parameter("energy_a", a.sky_energy)
	sky_mat.set_shader_parameter("energy_b", b.sky_energy)
	sky_mat.set_shader_parameter("blend", t)
	var to_sun: Vector3 = (a.to_sun as Vector3).slerp(b.to_sun, t).normalized()
	sun.basis = Basis.looking_at(-to_sun, Vector3.UP if absf(to_sun.y) < 0.99 else Vector3.FORWARD)
	sun.light_color = (a.sun_color as Color).lerp(b.sun_color, t)
	sun.light_energy = lerpf(a.sun_energy, b.sun_energy, t)
	sun.directional_shadow_max_distance = lerpf(a.shadow_distance, b.shadow_distance, t)
	env.tonemap_exposure = lerpf(a.exposure, b.exposure, t)
	env.volumetric_fog_density = lerpf(a.fog_density, b.fog_density, t)
	env.volumetric_fog_albedo = (a.fog_albedo as Color).lerp(b.fog_albedo, t)
	env.volumetric_fog_anisotropy = lerpf(a.fog_anisotropy, b.fog_anisotropy, t)
	# Aerial perspective (the shore uses it so headlands and horizon recede into haze).
	env.fog_density = lerpf(a.get("haze", 0.0), b.get("haze", 0.0), t)
	env.fog_light_color = (a.get("haze_color", Color.WHITE) as Color).lerp(b.get("haze_color", Color.WHITE), t)

static func _setup_features(env: Environment, sun: DirectionalLight3D, state: Dictionary) -> void:
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.08
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_energy = 0.9
	env.fog_sun_scatter = 0.35
	env.fog_aerial_perspective = 0.55
	env.fog_sky_affect = 0.0
	sun.light_angular_distance = 0.5
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = true
	sun.shadow_normal_bias = 1.2
	sun.light_volumetric_fog_energy = 1.4
	if RenderingServer.get_current_rendering_method() != "forward_plus":
		return
	env.sdfgi_enabled = true
	env.sdfgi_use_occlusion = true
	env.sdfgi_read_sky_light = true
	env.sdfgi_cascades = 4
	env.sdfgi_min_cell_size = state.sdfgi_cell # a change rebuilds GI for the new zone
	env.sdfgi_bounce_feedback = 0.45
	env.sdfgi_energy = 1.0
	env.ssao_enabled = true
	env.ssao_radius = 0.9
	env.ssao_intensity = 1.3
	env.ssao_detail = 0.6
	env.ssil_enabled = true
	env.ssil_radius = 2.5
	env.ssil_intensity = 0.6
	env.ssr_enabled = true
	env.ssr_max_steps = 72
	env.ssr_fade_in = 0.12
	env.ssr_fade_out = 2.5
	env.ssr_depth_tolerance = 0.25
	env.glow_enabled = true
	env.glow_intensity = 0.32
	env.glow_bloom = 0.015
	env.glow_hdr_threshold = 1.1
	env.volumetric_fog_enabled = true
	env.volumetric_fog_length = 90.0
	env.volumetric_fog_sky_affect = 0.0
	env.volumetric_fog_ambient_inject = 0.35

static func _hdri_sun(file: String) -> Dictionary:
	if not _cache.has("sun_json"):
		var path := Assets.PH + "hdri/sun.json"
		_cache["sun_json"] = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else {}
	return (_cache["sun_json"] as Dictionary).get(file, {})

## A small HDR panorama painted from four colours (zenith, horizon, ground horizon, nadir), used
## for the hub and as the fallback when a zone's HDRI is missing.

static func _gradient_sky(colors: Array) -> ImageTexture:
	var key := "gradient" + str(colors)
	if _cache.has(key):
		return _cache[key]
	var image := Image.create(4, 128, false, Image.FORMAT_RGBF)
	for y in 128:
		var v := y / 127.0 # 0 = straight up, 1 = straight down
		var c: Color
		if v < 0.5:
			c = (colors[1] as Color).lerp(colors[0], pow(1.0 - v * 2.0, 0.6))
		else:
			c = (colors[2] as Color).lerp(colors[3], pow((v - 0.5) * 2.0, 0.5))
		for x in 4:
			image.set_pixel(x, y, c.srgb_to_linear())
	var texture := ImageTexture.create_from_image(image)
	_cache[key] = texture
	return texture


# ---------------------------------------------------------------- construct / deconstruct


## Rebuild GI after a zone replacement, while the transition still covers the change.

static func rebuild_gi(env: Environment, tree: SceneTree, zone: String) -> void:
	if not env.sdfgi_enabled:
		return
	env.sdfgi_min_cell_size = zone_state(zone).sdfgi_cell
	env.sdfgi_enabled = false
	tree.process_frame.connect(func() -> void: env.sdfgi_enabled = true, CONNECT_ONE_SHOT)
