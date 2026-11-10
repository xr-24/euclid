extends RefCounted
## Adapter from scene agent commands to the shared entity store.

const EntityTypes = preload("res://scripts/workshop/entity_types.gd")
const ACTIONS := ["list_scene_assets", "spawn_prop", "inspect_entity", "edit_entity", "duplicate_entity", "delete_entity", "restore_dressing", "undo_scene"]
const SCOPED := ACTIONS + ["list_entities", "spawn_asset", "save_prefab", "spawn_prefab", "list_behaviors", "set_behavior",
	"inspect_animation", "preview_animation", "save_animation", "discard_animation"]
const OPERATIONS := {"inspect_entity": "inspect", "edit_entity": "edit", "duplicate_entity": "duplicate",
	"delete_entity": "delete", "restore_dressing": "restore_dressing", "undo_scene": "undo", "list_scene_assets": "list_scene_assets"}

static func options(plan: Dictionary) -> Dictionary:
	var changes := {}
	var requested: Variant = plan.get("changes")
	if requested is Dictionary:
		for key in requested:
			if requested[key] != null:
				changes[key] = requested[key]
	return changes

static func execute(tools: RefCounted, plan: Dictionary, placement: Array) -> Dictionary:
	var target: String = plan.get("target", "")
	var changes := options(plan)
	var result: Dictionary
	if plan.tool == "spawn_prop":
		var type := target
		if target not in ["traffic_cone", "pressure_plate", "sliding_door"]:
			type = "library_model"
			changes["asset_id"] = target
		changes["type"] = type
		changes["position"] = changes.get("position", placement)
		if changes.position is Array and changes.position.is_empty():
			return {"ok": false, "message": "Aim at solid ground or specify a position to place a prop."}
		result = tools.execute("spawn", changes)
	else:
		var arguments := {"id": target, "changes": changes}
		if changes.has("position"):
			arguments["position"] = changes.position
		result = tools.execute(OPERATIONS[plan.tool], arguments)
	if not result.ok:
		result["message"] = result.error
		return result
	match plan.tool:
		"list_scene_assets":
			var names := PackedStringArray()
			for asset in result.assets:
				names.append(asset.name)
			result["message"] = "Installed props include " + ", ".join(names) + "." if not names.is_empty() else "No scene assets are installed."
		"inspect_entity":
			var item: Dictionary = result.entity
			var appearance: String = "original finish" if item.get("authored", false) else "color #" + item.color
			if item.get("hidden", false):
				appearance += ", hidden"
			result["message"] = "%s at %s, yaw %s°, scale %s, %s." % [
				EntityTypes.label(item), str(item.position), str(item.yaw), str(item.scale), appearance]
			if not item.get("live_position", []).is_empty():
				result["message"] += " Current position %s." % str(item.live_position)
		"delete_entity":
			result["message"] = "Hid the authored prop. Use Restore defaults or Undo to bring it back." if result.entity.get("hidden", false) \
				else "Deleted the prop. Undo is available in this scene."
		"restore_dressing": result["message"] = "Restored %s to its authored placement." % EntityTypes.label(result.entity)
		"undo_scene": result["message"] = "Undid the last edit in this scene."
		_:
			var verb: String = {"spawn_prop": "Placed", "edit_entity": "Updated", "duplicate_entity": "Duplicated"}[plan.tool]
			result["message"] = "%s %s." % [verb, EntityTypes.label(result.entity)]
	return result

static func planning_entities(entities: Array, request: String, player_at: Vector3) -> Array:
	var terms := request.to_lower().split(" ", false)
	var ranked := []
	for entry in entities:
		var name: String = entry.name.to_lower()
		var coords: Array = entry.get("live_position", [])
		if coords.is_empty():
			coords = entry.position
		var point := Vector3(coords[0], coords[1], coords[2])
		var matches := 0
		for word in terms:
			var term := word.strip_edges().trim_suffix(".").trim_suffix(",")
			if term.length() >= 3 and (term in name or term == entry.id):
				matches += 1
		ranked.append({"entry": entry, "matches": matches, "distance": player_at.distance_squared_to(point)})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.matches != b.matches:
			return a.matches > b.matches
		return a.distance < b.distance)
	return ranked.slice(0, 64).map(func(item: Dictionary) -> Dictionary: return item.entry)
