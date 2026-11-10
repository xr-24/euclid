extends RefCounted
## Adapter from scene agent commands to the shared entity store.

const EntityTypes = preload("res://scripts/workshop/entity_types.gd")
const ACTIONS := ["list_scene_assets", "spawn_prop", "inspect_entity", "edit_entity", "duplicate_entity", "delete_entity", "undo_scene"]
const SCOPED := ACTIONS + ["list_entities", "spawn_asset", "save_prefab", "spawn_prefab", "list_behaviors", "set_behavior",
	"inspect_animation", "preview_animation", "save_animation", "discard_animation"]
const OPERATIONS := {"inspect_entity": "inspect", "edit_entity": "edit", "duplicate_entity": "duplicate",
	"delete_entity": "delete", "undo_scene": "undo", "list_scene_assets": "list_scene_assets"}

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
			result["message"] = "%s at %s, yaw %s°, scale %s, color #%s." % [
				EntityTypes.label(item), str(item.position), str(item.yaw), str(item.scale), item.color]
		"delete_entity": result["message"] = "Deleted the prop. Undo is available in this scene."
		"undo_scene": result["message"] = "Undid the last edit in this scene."
		_:
			var verb: String = {"spawn_prop": "Placed", "edit_entity": "Updated", "duplicate_entity": "Duplicated"}[plan.tool]
			result["message"] = "%s %s." % [verb, EntityTypes.label(result.entity)]
	return result
