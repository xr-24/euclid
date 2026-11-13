extends RefCounted
## The command surface for the same terrain data and undo journal the world brush uses.

const Terrain = preload("res://scripts/pieces/terrain_node.gd")
const Editor = preload("res://scripts/pieces/piece_editor.gd")
const Materials = preload("res://scripts/assets/runtime_materials.gd")
const MAX_DABS := 256

static func available(editor: Editor) -> bool:
	return editor.can_edit() and editor.summaries().any(func(piece: Dictionary) -> bool: return piece.type == "terrain")

static func above_surface(editor: Editor, point: Vector3, target := "") -> Vector3:
	for piece: Dictionary in editor.summaries():
		if piece.type != "terrain" or (not target.is_empty() and piece.id != target):
			continue
		var terrain := editor.node_for(piece.id) as Terrain
		if terrain == null or not terrain.is_visible_in_tree():
			continue
		var local := terrain.local_point(point)
		if terrain.contains_point(local):
			var surface := terrain.surface_point(local)
			if surface.y > point.y:
				point.y = surface.y + 0.05
	return point

static func undo(editor: Editor, player: CharacterBody3D) -> Dictionary:
	var result := editor.execute({"tool": "undo_piece"})
	if result.ok:
		player.global_position = above_surface(editor, player.global_position)
	return result

static func execute(editor: Editor, plan: Dictionary) -> Dictionary:
	var id: String = plan.get("target", "")
	if plan.tool == "inspect_terrain":
		return _inspect(editor, id, plan.get("points", []))
	var terrain := editor.node_for(id) as Terrain
	if terrain == null or not terrain.is_visible_in_tree() or not editor.can_edit():
		return {"ok": false, "message": "Choose a visible terrain piece in the current environment."}
	var record := editor.record(id)
	var data := Terrain.Data.new()
	if not data.decode(record.get("terrain_surface", ""), record.get("terrain_paint_data", "")):
		return {"ok": false, "message": "The terrain data could not be read."}
	var mode: String = plan.brush
	var radius: float = plan.get("radius", 10.0)
	var amount: float = plan.get("strength", 0.6)
	if mode in ["smooth", "flatten", "paint"] and amount > 1.0:
		return {"ok": false, "message": "Use a strength between 0 and 1 for this brush."}
	var id_list: Array = record.get("terrain_materials", []).duplicate()
	var paint: String = plan.get("paint", "earth")
	var layer := Terrain.builtin_slot(paint)
	if mode == "paint" and layer < 0:
		if Materials.cached_images(paint).is_empty():
			return {"ok": false, "message": "Import that material before painting."}
		if paint not in id_list:
			if id_list.size() >= Terrain.Data.IMPORT_SLOTS:
				return {"ok": false, "message": "This terrain already uses five imported materials."}
			id_list.append(paint)
		layer = id_list.find(paint) + 3
	var path: Array[Vector2] = []
	for point: Array in plan.points:
		var local := terrain.local_point(Vector3(point[0], point[1], point[2]))
		if not terrain.contains_point(local):
			return {"ok": false, "message": "All brush points must be on the selected terrain."}
		path.append(local)
	var dabs: Array[Vector2] = [path[0]]
	for index in range(1, path.size()):
		var start := path[index - 1]
		var count := maxi(1, ceili(start.distance_to(path[index]) / (radius * 0.4)))
		if dabs.size() + count > MAX_DABS:
			return {"ok": false, "message": "Shorten the stroke or increase its radius."}
		for step in range(1, count + 1):
			dabs.append(start.lerp(path[index], float(step) / count))
	var level := data.surface_at(path[0], terrain.terrain_size)
	for point in dabs:
		data.dab(point, terrain.terrain_size, mode, radius, amount, layer, level)
	return editor.commit_storage(id, Terrain.storage_for(data, id_list), editor.revision, "Terrain stroke saved.")

static func _inspect(editor: Editor, id: String, points: Array) -> Dictionary:
	var terrains := editor.summaries().filter(func(piece: Dictionary) -> bool: return piece.type == "terrain")
	var result := {"ok": true, "message": "Terrain pieces: " + ", ".join(terrains.map(func(item: Dictionary) -> String: return item.name + " (" + item.id + ")")),
		"terrains": terrains, "materials": Terrain.palette() + Materials.installed().slice(0, 64)}
	if not id.is_empty():
		var terrain := editor.node_for(id) as Terrain
		if terrain == null:
			return {"ok": false, "message": "That terrain no longer exists."}
		result["size"] = [terrain.terrain_size.x, terrain.terrain_size.y]
		var at := terrain.global_position
		result["origin"] = [at.x, at.y, at.z]
		var samples := []
		for point: Array in points:
			var local := terrain.local_point(Vector3(point[0], point[1], point[2]))
			var height := terrain.surface_point(local).y
			samples.append(height if terrain.contains_point(local) else null)
		result["heights"] = samples
	return result
