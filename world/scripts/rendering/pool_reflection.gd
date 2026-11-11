extends Node3D
## One pool-only mirror camera. No C# addon or second water simulation.
const Graphics = preload("res://scripts/rendering/graphics_settings.gd")
const DEFAULT_MIRROR_SIZE := Vector2i(960, 540)

var material: ShaderMaterial
var water: MeshInstance3D
var level := -0.12
var viewport: SubViewport
var mirror: Camera3D
var reflected_camera := Vector4(0,0,0,-10000)
var reflected_frames := 0
var environment_ready := false
var visibility: VisibleOnScreenNotifier3D
static var active_owner: Node

func configure(surface: ShaderMaterial, mesh: MeshInstance3D, height: float) -> void:
	material = surface
	water = mesh
	level = height
	# The mirror only sees ordinary scene geometry, never the pool itself.
	water.layers = 4
	visibility = VisibleOnScreenNotifier3D.new()
	visibility.layers = 4
	visibility.aabb = water.mesh.get_aabb().grow(0.5)
	water.add_child(visibility)

func _ready() -> void:
	if RenderingServer.get_rendering_device() == null:
		set_process(false)
		return
	process_priority = 100
	viewport = SubViewport.new()
	viewport.name = "PoolMirrorViewport"
	var balanced := Graphics.current == "balanced"
	viewport.size = DEFAULT_MIRROR_SIZE
	viewport.mesh_lod_threshold = 12.0 if balanced else 1.0
	viewport.world_3d = get_world_3d()
	viewport.use_hdr_2d = true
	viewport.use_taa = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	mirror = Camera3D.new()
	mirror.cull_mask = 1
	viewport.add_child(mirror)
	mirror.current = true
	material.set_shader_parameter("pool_reflection",viewport.get_texture())

func _process(_delta: float) -> void:
	var source := get_viewport().get_camera_3d()
	if source == null or viewport == null: return
	var active := visibility.is_on_screen() and source.global_position.y > level+0.03 and source.global_position.distance_to(water.global_position)<80
	material.set_shader_parameter("pool_reflection_enabled",active)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	if not active:
		_clear_clip_plane()
		return
	if not environment_ready and get_world_3d().environment != null:
		mirror.environment = get_world_3d().environment.duplicate()
		# Keep radiance linear in this texture; the main viewport applies exposure/tonemapping.
		mirror.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		mirror.environment.tonemap_exposure = 1.0
		mirror.environment.ssr_enabled = false
		mirror.environment.ssao_enabled = false
		mirror.environment.ssil_enabled = false
		mirror.environment.sdfgi_enabled = false
		environment_ready = true
	var source_size := get_viewport().get_visible_rect().size
	if source_size.x > 0:
		var width := DEFAULT_MIRROR_SIZE.x
		viewport.size = Vector2i(width, maxi(64, roundi(width * source_size.y / source_size.x)))
	mirror.fov = source.fov
	mirror.keep_aspect = source.keep_aspect
	mirror.near = source.near
	mirror.far = minf(source.far,180.0)
	var transform := source.global_transform
	var position := transform.origin
	position.y = 2.0*level-position.y
	var b := transform.basis
	# Reflect the up axis and reverse the right axis to retain a proper camera basis.
	# Projective texture coordinates below account for the resulting horizontal reversal.
	mirror.global_transform = Transform3D(Basis(
		Vector3(-b.x.x,b.x.y,-b.x.z),Vector3(b.y.x,-b.y.y,b.y.z),Vector3(b.z.x,-b.z.y,b.z.z)),position)
	reflected_camera = Vector4(position.x,position.y,position.z,level+0.003)
	RenderingServer.global_shader_parameter_set("construct_reflection_camera",reflected_camera)
	active_owner = self
	material.set_shader_parameter("pool_reflection_matrix",mirror.get_camera_projection()*Projection(mirror.global_transform.affine_inverse()))
	reflected_frames += 1

func _exit_tree() -> void:
	if RenderingServer.get_rendering_device() == null: return
	_clear_clip_plane()
	if material != null:
		material.set_shader_parameter("pool_reflection_enabled",false)
		material.set_shader_parameter("pool_reflection",null)

func _clear_clip_plane() -> void:
	if active_owner == self:
		RenderingServer.global_shader_parameter_set("construct_reflection_camera",Vector4(0,0,0,-10000))
		active_owner = null
