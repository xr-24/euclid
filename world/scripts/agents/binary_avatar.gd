extends Node3D

const AVATAR_SHADER = preload("res://shaders/binary_avatar.gdshader")
const AVATAR_DAYLIGHT_SHADER = preload("res://shaders/binary_avatar_daylight.gdshader")
const AvatarMesh = preload("res://scripts/agents/avatar_mesh.gd")
const FILAMENT_SHADER = preload("res://shaders/avatar_filaments.gdshader")
const FILAMENT_DAYLIGHT_SHADER = preload("res://shaders/avatar_filaments_daylight.gdshader")
const AvatarFilaments = preload("res://scripts/agents/avatar_filaments.gd")
const AvatarHover = preload("res://scripts/agents/avatar_hover.gd")
const HOVER_HEIGHT := 1.46
const FOLLOW_DISTANCE := 3.3
const FOLLOW_SPEED := 5.4
const COMMAND_DISTANCE := 3.8
const TINT := Color("ff0e49")
const HIGHLIGHT := Color("ff4669")
var tint := TINT
var highlight := HIGHLIGHT
var slot := 0
var mode := "follow"
var _parked_zone := ""
var _parked_at := Vector3.ZERO
var _projection: MeshInstance3D
var _last_player_position := Vector3.ZERO
var _daylight := false
static var _filaments: ArrayMesh

static func projection(color := TINT, daylight := false, accent := HIGHLIGHT) -> MeshInstance3D:
	var shader := ShaderMaterial.new()
	shader.shader = AVATAR_DAYLIGHT_SHADER if daylight else AVATAR_SHADER
	shader.set_shader_parameter("core_color", color)
	shader.set_shader_parameter("highlight_color", accent)
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
	signals.name = "Filaments"
	var signal_material := ShaderMaterial.new()
	signal_material.shader = FILAMENT_DAYLIGHT_SHADER if daylight else FILAMENT_SHADER
	signal_material.set_shader_parameter("core_color", color)
	signal_material.set_shader_parameter("highlight_color", accent)
	if _filaments == null:
		_filaments = AvatarFilaments.build(points)
	signals.mesh = _filaments
	signals.skin = model.skin
	signals.skeleton = NodePath("../ProjectionRig")
	signals.extra_cull_margin = 0.24
	signals.material_override = signal_material
	signals.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.add_child(signals)
	visual.move_child(signals, 0)
	return visual

func _ready() -> void:
	_projection = projection(tint, false, highlight)
	add_child(_projection)
	hide()

func animation_player() -> MeshInstance3D:
	return _projection

func arrive(zone: String, player: CharacterBody3D, daylight := false, occupied: Array[Vector3] = []) -> void:
	if daylight != _daylight:
		_daylight = daylight
		var body := _projection.material_override as ShaderMaterial
		var filaments := (_projection.get_node("Filaments") as MeshInstance3D).material_override as ShaderMaterial
		body.shader = AVATAR_DAYLIGHT_SHADER if daylight else AVATAR_SHADER
		filaments.shader = FILAMENT_DAYLIGHT_SHADER if daylight else FILAMENT_SHADER
		for material in [body, filaments]:
			material.set_shader_parameter("core_color", tint)
			material.set_shader_parameter("highlight_color", highlight)
	_last_player_position = player.global_position
	if _parked_zone.is_empty():
		_parked_zone = zone
		_parked_at = _near_player(player, occupied)
	visible = mode == "follow" or _parked_zone == zone
	if visible:
		global_position = _near_player(player, occupied) if mode == "follow" else _parked_at

func can_command(camera: Camera3D, player: CharacterBody3D) -> bool:
	if not is_visible_in_tree():
		return false
	var eye := camera.global_position
	var offset := global_position - eye
	if offset.length_squared() > COMMAND_DISTANCE * COMMAND_DISTANCE or -camera.global_basis.z.dot(offset.normalized()) < 0.62:
		return false
	var query := PhysicsRayQueryParameters3D.create(eye, global_position)
	query.exclude = [player.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func set_mode(next: String, zone: String, player: CharacterBody3D, occupied: Array[Vector3] = []) -> void:
	if not visible:
		global_position = _near_player(player, occupied)
		show()
	_last_player_position = player.global_position
	mode = next
	if mode == "stay":
		_parked_zone = zone
		_parked_at = global_position

func tick(player: CharacterBody3D, delta: float, occupied: Array[Vector3] = []) -> void:
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
		global_position = _near_player(player, occupied)
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
	if player.get_world_3d().direct_space_state.intersect_ray(query).is_empty() and _room(next, occupied):
		global_position = next

func _near_player(player: CharacterBody3D, occupied: Array[Vector3] = []) -> Vector3:
	var origin := player.global_position + Vector3.UP * HOVER_HEIGHT
	var space := player.get_world_3d().direct_space_state
	var angle := [0.0, -0.57, 0.57, -1.25, 1.25, -2.0, 2.0, PI][slot % 8] as float
	for step in 12:
		var offset := (player.global_basis * Vector3.FORWARD).rotated(Vector3.UP, angle + TAU * step / 12.0) * FOLLOW_DISTANCE
		var query := PhysicsRayQueryParameters3D.create(origin, origin + offset)
		query.exclude = [player.get_rid()]
		if _room(origin + offset, occupied) and space.intersect_ray(query).is_empty():
			return origin + offset
	return origin + Vector3.UP * (0.8 + slot * 1.1)

static func _room(point: Vector3, occupied: Array[Vector3]) -> bool:
	return occupied.all(func(other: Vector3) -> bool: return point.distance_squared_to(other) >= 1.44)
