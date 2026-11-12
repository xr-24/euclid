extends RefCounted
## Art direction for the villa and the shore, zone environments and the construct/deconstruct shift.
##
## Physically based materials from CC0 Poly Haven scans, HDRI skies with the sun aligned to the
## DirectionalLight, and per-zone post-processing that can blend from one zone to the next. Every asset is optional: if a file is missing the
## affected piece is skipped and world.gd keeps its original blockout, so the world always runs.
## Asset sources and the build steps are described in docs/asset-pipeline.md.

const Packages = preload("res://scripts/zones/zone_packages.gd")
const Water = preload("res://scripts/simulation/water_system.gd")
const WaterAssets = preload("res://scripts/assets/asset_library.gd")
const Graphics = preload("res://scripts/rendering/graphics_settings.gd")
const AssetLibrary = preload("res://scripts/asset_library.gd")
const PH := "res://assets/thirdparty/polyhaven/"

static var _cache := {}
static var _resources := {}

## Called once on the main thread at startup.
static func init(_world: Node3D) -> void:
	WaterAssets.initialize()
	AssetLibrary.load_catalog()

## load() with a cache that keeps resources alive between visits, so a zone builds instantly the
## second time (and after the startup warm-up). Thread-safe enough for one builder at a time.
static func res(path: String) -> Resource:
	if not _resources.has(path):
		_resources[path] = load(path)
	return _resources[path]

## Where the player appears in each zone when it is loaded directly (or a shift cannot keep them
## where they stand). Zone builders register theirs; anything else starts near the origin.

static func spawn(zone: String) -> Dictionary:
	return Packages.spawn(zone)


# ---------------------------------------------------------------- materials and models

## Albedo, normal and ORM maps of a downloaded texture set, at whichever resolution was fetched.
static func texture_set(id: String) -> Dictionary:
	if _cache.has(id):
		return _cache[id]
	var base := PH + "textures/%s/%s_" % [id, id]
	for res in ["2k", "4k", "1k"]:
		var maps := {"albedo": base + "diff_%s.jpg" % res, "normal": base + "nor_gl_%s.jpg" % res, "orm": base + "arm_%s.jpg" % res}
		if maps.values().all(func(path: String) -> bool: return ResourceLoader.exists(path)):
			for map in maps:
				maps[map] = res(maps[map])
			_cache[id] = maps
			return maps
	return {}

## World-space triplanar PBR material, so it works on any mesh regardless of UVs.
static func pbr(id: String, size_m: float, tint := Color.WHITE, fallback := Color(0.7, 0.7, 0.7)) -> BaseMaterial3D:
	var maps := texture_set(id)
	if maps.is_empty():
		var plain := StandardMaterial3D.new()
		plain.albedo_color = fallback
		plain.roughness = 0.75
		return plain
	var mat := ORMMaterial3D.new()
	mat.albedo_texture = maps.albedo
	mat.albedo_color = tint
	mat.normal_enabled = true
	mat.normal_texture = maps.normal
	mat.orm_texture = maps.orm
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_triplanar_sharpness = 6.0
	mat.uv1_scale = Vector3.ONE / size_m
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return mat

static func model(id: String) -> Node3D:
	if AssetLibrary.has(id):
		return AssetLibrary.instance(id)
	var path := PH + "models/%s.glb" % id
	if not ResourceLoader.exists(path):
		return null
	return (res(path) as PackedScene).instantiate() as Node3D

## Instance a Poly Haven model; height (metres) rescales it uniformly when given.
static func place(parent: Node3D, id: String, at: Vector3, yaw_deg := 0.0, height := 0.0, scale := 1.0) -> Node3D:
	var node := model(id)
	if node == null:
		return null
	parent.add_child(node)
	if height > 0.0:
		var box := bounds(node)
		if box.size.y > 0.0:
			scale = height / box.size.y
	node.scale = Vector3.ONE * scale
	node.position = at
	node.rotation_degrees.y = yaw_deg
	return node

static func bounds(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		var local := (node.global_transform.affine_inverse() * mi.global_transform) * mi.get_aabb() if node.is_inside_tree() else mi.get_aabb()
		box = local if first else box.merge(local)
		first = false
	return box

static func static_box(parent: Node3D, at: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = at
	parent.add_child(body)

static func noise_texture(seed: int, frequency: float, normal_map: bool, size := 512) -> ImageTexture:
	var key := "noise%d_%f_%s" % [seed, frequency, normal_map]
	if _cache.has(key):
		return _cache[key]
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_octaves = 4
	var image := noise.get_seamless_image(size, size, false, false, 0.15, true)
	if normal_map:
		image.convert(Image.FORMAT_RGBA8)
		image.bump_map_to_normal_map(6.0)
	image.generate_mipmaps()
	var texture := ImageTexture.create_from_image(image)
	_cache[key] = texture
	return texture

static func water_material(sea: bool) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = res("res://shaders/ocean.gdshader")
	mat.set_shader_parameter("ripple_a", noise_texture(11, 0.012, true))
	mat.set_shader_parameter("ripple_b", noise_texture(23, 0.02, true))
	mat.set_shader_parameter("foam_noise", noise_texture(5, 0.02, false))
	if not sea: # a shallow, clear courtyard pool over dark stone
		mat.set_shader_parameter("swell", 0.0)
		mat.set_shader_parameter("ripple_scale", 1.6)
		mat.set_shader_parameter("ripple_strength", 0.25)
		mat.set_shader_parameter("clarity", 0.6)
		mat.set_shader_parameter("colour_depth", 0.6)
		mat.set_shader_parameter("shallow_color", Color("4f9c98"))
		mat.set_shader_parameter("deep_color", Color("123c44"))
		mat.set_shader_parameter("foam_amount", 0.0)
		mat.set_shader_parameter("refraction", 0.012)
	return mat


# ---------------------------------------------------------------- environment

## Configure sky, sun and post-processing for a zone at once. edits are the environment's saved
## or previewed atmosphere edits (rendering/atmosphere.gd).
static func apply_environment(world: Node3D, zone: String, edits := {}) -> void:
	var state := zone_state(zone, edits)
	_setup_features(world, state)
	apply_state(world, state, state, 1.0)
	Graphics.apply_zone(world, zone)

## Everything about a zone's look that can be blended during a shift.
static func zone_state(zone: String, edits := {}) -> Dictionary:
	var s := Packages.environment(zone)
	_apply_edits(s, edits)
	var hdri_path := PH + "hdri/" + str(s.get("hdri", ""))
	var elevation: float = s.get("sun_elevation", 40.0)
	var photo_elevation := elevation
	s.yaw = 0.0
	if s.has("hdri") and ResourceLoader.exists(hdri_path):
		s.panorama = res(hdri_path)
		# Rotate the panorama so its photographed sun sits at the authored azimuth.
		var sun_data := _hdri_sun(str(s.hdri))
		photo_elevation = sun_data.get("elevation_deg", elevation)
		elevation = photo_elevation
		s.yaw = deg_to_rad(s.sun_azimuth - float(sun_data.get("u", 0.0)) * 360.0)
	else:
		s.panorama = _gradient_sky(s.get("sky_colors", Packages.environment("construct").sky_colors))
	s.hide_photo_sun = Vector4.ZERO
	if edits.has("sun_elevation"):
		elevation = float(edits.sun_elevation)
		# A sun moved off the photographed one: dim the photo's sun so only the drawn one shows.
		if s.has("hdri") and absf(elevation - photo_elevation) > 1.0:
			var hidden := _direction(s.sun_azimuth, photo_elevation)
			hidden.w = 1.0
			s.hide_photo_sun = hidden
		# Below the horizon the sun stops lighting and the sky darkens to night.
		var daylight := smoothstep(-10.0, 8.0, elevation)
		s.sun_energy *= smoothstep(-4.0, 3.0, elevation)
		s.sky_energy *= lerpf(0.03, 1.0, daylight)
		s.ambient = float(s.get("ambient", 1.0)) * lerpf(0.25, 1.0, daylight)
	var to_sun := _direction(s.sun_azimuth, elevation)
	s.to_sun = Vector3(to_sun.x, to_sun.y, to_sun.z)
	return s

static func _direction(azimuth: float, elevation: float) -> Vector4:
	var az := deg_to_rad(azimuth)
	var el := deg_to_rad(elevation)
	return Vector4(sin(az) * cos(el), sin(el), cos(az) * cos(el), 0.0)

## Atmosphere edits (field names from rendering/atmosphere.gd) over a package's environment.
static func _apply_edits(s: Dictionary, edits: Dictionary) -> void:
	for key in edits:
		var value: Variant = edits[key]
		match key:
			"sky":
				if value == "gradient":
					s.erase("hdri")
				else:
					s["hdri"] = value
			"sun_color":
				s["sun_color"] = Color(value)
			"fog_color":
				s["fog_albedo"] = Color(value)
			"haze_color":
				s["haze_color"] = Color(value)
			"fog_direction":
				s["fog_anisotropy"] = float(value)
			"sun_elevation":
				s["sun_elevation"] = float(value)
			_:
				s[key] = float(value)

## Blend between two zone states (t = 0 is a, 1 is b) for skies, sun, exposure and fog.
static func apply_state(world: Node3D, a: Dictionary, b: Dictionary, t: float) -> void:
	var env: Environment = world.environment
	var sun: DirectionalLight3D = world.sun
	var sky_mat := env.sky.sky_material as ShaderMaterial
	if sky_mat == null or sky_mat.shader.resource_path != "res://shaders/hdri_sky.gdshader":
		sky_mat = ShaderMaterial.new()
		sky_mat.shader = res("res://shaders/hdri_sky.gdshader")
		env.sky.sky_material = sky_mat
	sky_mat.set_shader_parameter("panorama_a", a.panorama)
	sky_mat.set_shader_parameter("panorama_b", b.panorama)
	sky_mat.set_shader_parameter("yaw_a", a.yaw)
	sky_mat.set_shader_parameter("yaw_b", b.yaw)
	sky_mat.set_shader_parameter("energy_a", a.sky_energy)
	sky_mat.set_shader_parameter("energy_b", b.sky_energy)
	sky_mat.set_shader_parameter("sun_visibility", lerpf(a.get("sky_sun_visibility", 1.0), b.get("sky_sun_visibility", 1.0), t))
	sky_mat.set_shader_parameter("hide_sun_a", a.get("hide_photo_sun", Vector4.ZERO))
	sky_mat.set_shader_parameter("hide_sun_b", b.get("hide_photo_sun", Vector4.ZERO))
	sky_mat.set_shader_parameter("stars", lerpf(a.get("stars", 0.0), b.get("stars", 0.0), t))
	env.ambient_light_energy = lerpf(a.get("ambient", 1.0), b.get("ambient", 1.0), t)
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

static func _setup_features(world: Node3D, state: Dictionary) -> void:
	var env: Environment = world.environment
	var sun: DirectionalLight3D = world.sun
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
		var path := PH + "hdri/sun.json"
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

const CFX_SHADERS := {
	"opaque": "res://shaders/constructible_opaque.gdshader",
	"opaque_double": "res://shaders/constructible_double.gdshader",
	"scissor": "res://shaders/constructible_scissor.gdshader",
	"scissor_double": "res://shaders/constructible_scissor.gdshader",
	"blend": "res://shaders/constructible_blend.gdshader",
}
const CFX_CHANNELS := [Vector4(1, 0, 0, 0), Vector4(0, 1, 0, 0), Vector4(0, 0, 1, 0), Vector4(0, 0, 0, 1), Vector4(0.333333, 0.333333, 0.333333, 0)]

## Give every surface in a freshly built zone the construct effect, permanently: standard
## materials become the constructible shader with the same textures and settings. Doing this once
## at build time (off the main thread) means nothing is swapped or recompiled when a shift ends.
static func make_constructible(root: Node) -> void:
	var converted := {}
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		if mi.material_override:
			mi.material_override = _constructible(mi.material_override, converted)
		else:
			for i in mi.mesh.get_surface_count():
				var mat := mi.get_active_material(i)
				if mat:
					mi.set_surface_override_material(i, _constructible(mat, converted))
	# Scattered plants and rocks: give each multimesh its own copy of the mesh with converted materials.
	var meshes := {}
	for node in root.find_children("*", "MultiMeshInstance3D", true, false):
		var mm := (node as MultiMeshInstance3D).multimesh
		if mm == null or mm.mesh == null:
			continue
		if not meshes.has(mm.mesh):
			var copy := mm.mesh.duplicate() as Mesh
			for i in copy.get_surface_count():
				var mat := copy.surface_get_material(i)
				if mat:
					copy.surface_set_material(i, _constructible(mat, converted))
			meshes[mm.mesh] = copy
		mm.mesh = meshes[mm.mesh]

## Which side of the shift front a zone is on: -1 unravels, +1 assembles, 0 normal. Surfaces that
## cannot take the effect (text) are hidden while a shift runs.
static func set_side(root: Node, side: float) -> void:
	for node in root.find_children("*", "GeometryInstance3D", true, false):
		var gi := node as GeometryInstance3D
		var fx := false
		if gi is MeshInstance3D and (gi as MeshInstance3D).mesh != null:
			var mi := gi as MeshInstance3D
			fx = _has_fx(mi.material_override) if mi.material_override else \
				(mi.mesh.get_surface_count() > 0 and _has_fx(mi.get_active_material(0)))
		elif gi is MultiMeshInstance3D and (gi as MultiMeshInstance3D).multimesh and (gi as MultiMeshInstance3D).multimesh.mesh:
			var mesh := (gi as MultiMeshInstance3D).multimesh.mesh
			fx = mesh.get_surface_count() > 0 and _has_fx(mesh.surface_get_material(0))
		if fx:
			gi.set_instance_shader_parameter("construct_side", side)
		elif side != 0.0:
			if not gi.has_meta("cfx_hidden"):
				gi.set_meta("cfx_hidden", gi.visible)
			gi.visible = false
		elif gi.has_meta("cfx_hidden"):
			gi.visible = gi.get_meta("cfx_hidden")
			gi.remove_meta("cfx_hidden")

## Rebuild cached lighting after a zone shift or a change to authored geometry.
static func rebuild_gi(world: Node3D, zone: String) -> void:
	var env: Environment = world.environment
	if not env.sdfgi_enabled:
		return
	env.sdfgi_min_cell_size = zone_state(zone).sdfgi_cell
	env.sdfgi_enabled = false
	var finished := world.get_tree().process_frame if RenderingServer.get_rendering_device() == null else RenderingServer.frame_post_draw
	finished.connect(func() -> void: env.sdfgi_enabled = true, CONNECT_ONE_SHOT | CONNECT_DEFERRED)

static func _has_fx(mat: Material) -> bool:
	return mat is ShaderMaterial and (mat as ShaderMaterial).shader != null and "construct" in (mat as ShaderMaterial).shader.code

static func _constructible(mat: Material, converted: Dictionary) -> Material:
	if converted.has(mat):
		return converted[mat]
	var out: Material = mat
	if mat is BaseMaterial3D:
		out = _convert(mat as BaseMaterial3D)
	converted[mat] = out
	return out

static func _convert(m: BaseMaterial3D) -> ShaderMaterial:
	var variant := "opaque"
	match m.transparency:
		BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR, BaseMaterial3D.TRANSPARENCY_ALPHA_HASH:
			variant = "scissor"
		BaseMaterial3D.TRANSPARENCY_ALPHA, BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS:
			variant = "blend"
	if variant != "blend" and m.cull_mode == BaseMaterial3D.CULL_DISABLED:
		variant += "_double"
	var sm := ShaderMaterial.new()
	sm.shader = res(CFX_SHADERS[variant])
	sm.render_priority = m.render_priority
	sm.set_shader_parameter("albedo", m.albedo_color)
	if m.albedo_texture:
		sm.set_shader_parameter("albedo_tex", m.albedo_texture)
	sm.set_shader_parameter("use_vertex_color", m.vertex_color_use_as_albedo)
	if m.normal_enabled and m.normal_texture:
		sm.set_shader_parameter("has_normal", true)
		sm.set_shader_parameter("normal_tex", m.normal_texture)
		sm.set_shader_parameter("normal_scale", m.normal_scale)
	sm.set_shader_parameter("roughness", m.roughness)
	sm.set_shader_parameter("metallic", m.metallic)
	sm.set_shader_parameter("specular", m.metallic_specular)
	if m is ORMMaterial3D and (m as ORMMaterial3D).orm_texture:
		var orm: Texture2D = (m as ORMMaterial3D).orm_texture
		for pair in [["roughness", 1], ["metallic", 2], ["ao", 0]]:
			sm.set_shader_parameter(pair[0] + "_tex", orm)
			sm.set_shader_parameter(pair[0] + "_channel", CFX_CHANNELS[pair[1]])
		sm.set_shader_parameter("has_ao", true)
	else:
		if m.roughness_texture:
			sm.set_shader_parameter("roughness_tex", m.roughness_texture)
			sm.set_shader_parameter("roughness_channel", CFX_CHANNELS[m.roughness_texture_channel])
		if m.metallic_texture:
			sm.set_shader_parameter("metallic_tex", m.metallic_texture)
			sm.set_shader_parameter("metallic_channel", CFX_CHANNELS[m.metallic_texture_channel])
		if m.ao_enabled and m.ao_texture:
			sm.set_shader_parameter("has_ao", true)
			sm.set_shader_parameter("ao_tex", m.ao_texture)
			sm.set_shader_parameter("ao_channel", CFX_CHANNELS[m.ao_texture_channel])
	sm.set_shader_parameter("ao_light_affect", m.ao_light_affect)
	if m.emission_enabled:
		sm.set_shader_parameter("emission_color", m.emission)
		sm.set_shader_parameter("emission_energy", m.emission_energy_multiplier)
		if m.emission_texture:
			sm.set_shader_parameter("emission_tex", m.emission_texture)
	sm.set_shader_parameter("uv1_scale", m.uv1_scale)
	sm.set_shader_parameter("uv1_offset", m.uv1_offset)
	sm.set_shader_parameter("triplanar", m.uv1_triplanar)
	sm.set_shader_parameter("triplanar_sharpness", m.uv1_triplanar_sharpness)
	sm.set_shader_parameter("alpha_scissor_threshold", m.alpha_scissor_threshold)
	return sm


## Probe water, move floaters and apply disturbances through the shared water system.
static func water_tick(world: Node3D, delta: float) -> Dictionary:
	return Water.tick(world.zone_root, world.player, delta)
