extends RefCounted
## Editable scene bounds and the shared camera-to-surface placement rule.

const GRID := AABB(Vector3(-60, 0, -60), Vector3(120, 12, 120))
const VILLA := AABB(Vector3(-120, -90, -120), Vector3(240, 170, 225))
const BEACH := AABB(Vector3(-74, -16, -94), Vector3(148, 61, 143))
const Props = preload("res://scripts/zones/authored_props.gd")

static func bounds_for(zone: String) -> AABB:
	match zone:
		"villa": return VILLA
		"beach": return BEACH
		_: return GRID

static func contains(bounds: AABB, point: Vector3) -> bool:
	return point.is_finite() and point == point.clamp(bounds.position, bounds.end)

static func pick(player: CharacterBody3D, camera: Camera3D, bounds: AABB, grid: bool, aim: bool) -> Dictionary:
	var direction := -camera.global_basis.z
	var state := camera.get_world_3d().direct_space_state
	var ray_end := camera.global_position + direction * 24.0
	var hit := _ray(state, player, camera.global_position, ray_end) if aim else {}
	var selected := _entity(hit)
	if aim:
		var picker := _ray(state, player, camera.global_position, hit.get("position", ray_end), true)
		if not picker.is_empty():
			selected = _entity(picker)
	var ahead := player.global_position + Vector3(direction.x, 0, direction.z).normalized() * 3.0
	if grid:
		if not hit.is_empty() and hit.collider is Node and hit.collider.name == "GridFloor" and hit.normal.y > 0.9:
			ahead = hit.position
		ahead.y = 0.0
		return {"selected": selected, "point": ahead.clamp(bounds.position, bounds.end)}
	if not _floor(hit, bounds):
		hit = _ray(state, player, ahead + Vector3.UP * 2.0, ahead + Vector3.DOWN * 8.0)
	return {"selected": selected, "point": hit.position if _floor(hit, bounds) else Vector3.INF}

static func coordinates(point: Vector3) -> Array:
	return [point.x, point.y, point.z] if point.is_finite() else []

static func valid_coordinates(bounds: AABB, point: Variant) -> bool:
	if not point is Array or point.size() != 3:
		return false
	for axis in 3:
		var value: Variant = point[axis]
		if not (value is int or value is float) or not is_finite(float(value)) or value < bounds.position[axis] or value > bounds.end[axis]:
			return false
	return true

static func _ray(state: PhysicsDirectSpaceState3D, player: CharacterBody3D, from: Vector3, to: Vector3, areas := false) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [player.get_rid()]
	query.collide_with_areas = areas
	query.collide_with_bodies = not areas
	if areas:
		query.collision_mask = Props.PICK_LAYER
	return state.intersect_ray(query)

static func _entity(hit: Dictionary) -> String:
	var collider := hit.get("collider") as Node
	return str(collider.get_meta("entity_id")) if collider and collider.has_meta("entity_id") else ""

static func _floor(hit: Dictionary, bounds: AABB) -> bool:
	return not hit.is_empty() and hit.collider is StaticBody3D \
		and (_entity(hit).is_empty() or hit.collider.get_meta("placement_surface", false)) \
		and hit.normal.y >= 0.65 and contains(bounds, hit.position)
