extends Node3D

const AVATAR_SHADER = preload("res://shaders/binary_avatar.gdshader")
const AvatarMesh = preload("res://scripts/agents/avatar_mesh.gd")
const FILAMENT_SHADER = preload("res://shaders/avatar_filaments.gdshader")
const AvatarFilaments = preload("res://scripts/agents/avatar_filaments.gd")
const AvatarHover = preload("res://scripts/agents/avatar_hover.gd")
const HOVER_HEIGHT := 1.46
const FOLLOW_DISTANCE := 3.3
const FOLLOW_SPEED := 5.4
var mode := "follow"
var _parked_zone := ""
var _parked_at := Vector3.ZERO
var _projection: MeshInstance3D
var _last_player_position := Vector3.ZERO

static func projection(tint := Color("ff0e49")) -> MeshInstance3D:
	var shader := ShaderMaterial.new()
	shader.shader = AVATAR_SHADER
	shader.set_shader_parameter("core_color", tint)
	var visual := AvatarHover.new()
	var model := AvatarMesh.build()
	var points: ArrayMesh = model.mesh
	visual.mesh = points
	visual.add_child(model.rig)
	visual.skin = model.skin
	visual.skeleton = NodePath("ProjectionRig")
	visual.extra_cull_margin = 0.24
	visual.material_override = shader
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var signals := MeshInstance3D.new()
	var signal_material := ShaderMaterial.new()
	signal_material.shader = FILAMENT_SHADER
	signal_material.set_shader_parameter("core_color", tint)
	signals.mesh = AvatarFilaments.build(points)
	signals.skin = model.skin
	signals.skeleton = NodePath("../ProjectionRig")
	signals.extra_cull_margin = 0.24
	signals.material_override = signal_material
	signals.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.add_child(signals)
	visual.move_child(signals, 0)
	return visual

func _ready() -> void:
	_projection = projection()
	add_child(_projection)
	hide()

func animation_player() -> MeshInstance3D:
	return _projection

func arrive(zone: String, player: CharacterBody3D) -> void:
	_last_player_position = player.global_position
	if _parked_zone.is_empty():
		_parked_zone = zone
		_parked_at = _near_player(player)
	visible = mode == "follow" or _parked_zone == zone
	if visible:
		global_position = _near_player(player) if mode == "follow" else _parked_at

func set_mode(next: String, zone: String, player: CharacterBody3D) -> void:
	if not visible:
		global_position = _near_player(player)
		show()
	_last_player_position = player.global_position
	mode = next
	if mode == "stay":
		_parked_zone = zone
		_parked_at = global_position

func tick(player: CharacterBody3D, delta: float) -> void:
	if not visible:
		return
	var facing := player.global_position - global_position
	if facing.x * facing.x + facing.z * facing.z > 0.2:
		_projection.rotation.y = lerp_angle(_projection.rotation.y, atan2(facing.x, facing.z) + 0.24, 1.0 - exp(-5.0 * delta))
	if mode != "follow":
		return
	var player_position := player.global_position
	var teleported := player_position.distance_squared_to(_last_player_position) > 144.0
	_last_player_position = player_position
	if teleported:
		global_position = _near_player(player)
		return
	var horizontal := Vector3(facing.x, 0, facing.z)
	var excess := maxf(horizontal.length() - FOLLOW_DISTANCE, 0.0)
	var step := minf(excess, minf(FOLLOW_SPEED, excess * 4.0) * delta)
	var next := global_position + horizontal.normalized() * step
	var height_error := player_position.y + HOVER_HEIGHT - global_position.y
	if absf(height_error) > 0.18:
		next.y += clampf(height_error, -2.8 * delta, 2.8 * delta)
	if next.is_equal_approx(global_position):
		return
	var query := PhysicsRayQueryParameters3D.create(global_position, next)
	query.exclude = [player.get_rid()]
	if player.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		global_position = next

static func _near_player(player: CharacterBody3D) -> Vector3:
	var origin := player.global_position + Vector3.UP * HOVER_HEIGHT
	var space := player.get_world_3d().direct_space_state
	for offset in [Vector3(-1.55, 0, 2.9), Vector3(1.55, 0, 2.9), Vector3(-1.55, 0, -2.9), Vector3(1.55, 0, -2.9)]:
		var query := PhysicsRayQueryParameters3D.create(origin, origin + offset)
		query.exclude = [player.get_rid()]
		if space.intersect_ray(query).is_empty():
			return origin + offset
	return origin
