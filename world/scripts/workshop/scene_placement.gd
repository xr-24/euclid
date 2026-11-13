extends RefCounted
## Editable scene bounds and the shared camera-to-surface placement rule.

const Packages = preload("res://scripts/zones/zone_packages.gd")
static var GRID := Packages.bounds("construct")
static var VILLA := Packages.bounds("villa")
static var BEACH := Packages.bounds("beach")
const Props = preload("res://scripts/zones/authored_props.gd")

static func bounds_for(zone: String) -> AABB:
	return Packages.bounds(zone)

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
		if _floor(hit, bounds.grow(0.001)) and hit.normal.y > 0.9:
			return {"selected": selected, "point": (hit.position as Vector3).clamp(bounds.position, bounds.end)}
		var point := _ground_below(state, player, ahead.clamp(bounds.position, bounds.end), bounds)
		return {"selected": selected, "point": point}
	if not _floor(hit, bounds):
		hit = _ray(state, player, ahead + Vector3.UP * 2.0, ahead + Vector3.DOWN * 8.0)
	return {"selected": selected, "point": hit.position if _floor(hit, bounds) else Vector3.INF}

static func _ground_below(state: PhysicsDirectSpaceState3D, player: CharacterBody3D, at: Vector3, bounds: AABB) -> Vector3:
	var from := Vector3(at.x, maxf(at.y + 2.0, bounds.end.y + 0.1), at.z)
	var to := Vector3(at.x, bounds.position.y - 1.0, at.z)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var excluded: Array[RID] = [player.get_rid()]
	for attempt in 8:
		query.exclude = excluded
		var hit := state.intersect_ray(query)
		if hit.is_empty():
			break
		if _floor(hit, bounds.grow(0.001)):
			return (hit.position as Vector3).clamp(bounds.position, bounds.end)
		excluded.append(hit.rid)
	return Vector3.INF

static func aim_at(player: CharacterBody3D, camera: Camera3D, pixel: Vector2, reach: float, from_inside := false) -> Dictionary:
	var from := camera.project_ray_origin(pixel)
	var direction := camera.project_ray_normal(pixel)
	var to := from + direction * reach
	var state := camera.get_world_3d().direct_space_state
	var hit := _ray(state, player, from, to, false, from_inside)
	if from_inside and not hit.is_empty() and hit.normal == Vector3.ZERO and _entity(hit).is_empty():
		hit = _ray(state, player, from, to)
	var point: Vector3 = hit.get("position", to)
	var picker := _ray(state, player, from, point, true, from_inside) if point != from else {}
	if not picker.is_empty() and not _entity(picker).is_empty():
		hit = picker
		point = picker.position
	var collider := hit.get("collider") as Node
	return {"id": _entity(hit), "piece": _piece(hit), "point": point, "from": from, "direction": direction,
		"interaction": collider.get_meta("piece_interaction", null) if collider and collider.has_meta("piece_interaction") else null}

static func _piece(hit: Dictionary) -> String:
	var node := hit.get("collider") as Node
	while node:
		if node.has_meta("piece_id"):
			return str(node.get_meta("piece_id"))
		node = node.get_parent()
	return ""

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

static func _ray(state: PhysicsDirectSpaceState3D, player: CharacterBody3D, from: Vector3, to: Vector3,
		areas := false, from_inside := false) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [player.get_rid()]
	query.collide_with_areas = areas
	query.collide_with_bodies = not areas
	query.hit_from_inside = from_inside
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
