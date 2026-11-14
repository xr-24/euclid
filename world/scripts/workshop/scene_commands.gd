extends RefCounted
## Adapter from scene agent commands to the shared entity store.

const EntityTypes = preload("res://scripts/workshop/entity_types.gd")
const Commands = preload("res://scripts/workshop/command_registry.gd")

static func options(plan: Dictionary) -> Dictionary:
	var changes := {}
	var requested: Variant = plan.get("changes")
	if requested is Dictionary:
		for key in requested:
			if requested[key] != null:
				changes[key] = requested[key]
	return changes

static func execute(tools: RefCounted, plan: Dictionary, placement: Array) -> Dictionary:
	var definition := Commands.command(plan.get("tool"))
	if definition.get("service") != "scene" or definition.get("internal", false) or not Commands.valid_plan(definition, plan):
		return {"ok": false, "message": "Invalid scene command arguments."}
	plan = Commands.canonical_plan(plan)
	var target: String = plan.get("target", "")
	var changes := options(plan)
	var arguments := {}
	match definition.get("adapter", ""):
		"spawn":
			arguments = changes
			arguments["type"] = target
			if target not in Commands.built_in_props():
				arguments["type"] = "library_model"
				arguments["asset_id"] = target
			arguments["position"] = arguments.get("position", placement)
		"entity":
			arguments = {"id": target, "changes": changes}
			if changes.has("position"):
				arguments["position"] = changes.position
		"save_prefab":
			arguments = {"id": target, "name": plan.name}
		"spawn_prefab":
			arguments = {"prefab_id": target, "position": placement}
		"behavior":
			arguments = {"id": target, "behavior": _behavior(plan.behavior)}
	if definition.get("placement", false) and arguments.position.is_empty():
		return {"ok": false, "message": "Aim at solid ground or specify a position to place a prop."}
	var result: Dictionary = tools.execute(definition.local, arguments)
	if not result.ok:
		result["message"] = result.error
	else:
		result["message"] = _notice(definition, result, arguments)
	return result

static func _behavior(value: Variant) -> Variant:
	if value == null:
		return null
	var settings := {}
	for setting in value.settings:
		settings[setting.key] = setting.value
	var result := {"id": value.id, "settings": settings}
	var target: String = value.get("target_entity", "")
	if not target.is_empty():
		result["target"] = target
	return result

static func _notice(definition: Dictionary, result: Dictionary, arguments: Dictionary) -> String:
	if definition.has("verb"):
		return "%s %s." % [definition.verb, EntityTypes.label(result.entity)]
	if definition.has("output"):
		return _names(result[definition.output], "Nothing here yet.")
	match definition.get("notice", ""):
		"assets":
			var names := _names(result.assets, "")
			return "Installed props include " + names + "." if not names.is_empty() else "No scene assets are installed."
		"inspect":
			var item: Dictionary = result.entity
			var appearance: String = "original finish" if item.get("authored", false) else "color #" + item.color
			if item.get("hidden", false):
				appearance += ", hidden"
			var message := "%s at %s, yaw %s°, scale %s, %s." % [
				EntityTypes.label(item), str(item.position), str(item.yaw), str(item.scale), appearance]
			message += " Collision %s." % ("on" if item.get("collision", true) else "off")
			if not item.get("live_position", []).is_empty():
				message += " Current position %s." % str(item.live_position)
			return message
		"delete":
			return "Hid the authored prop. Use Restore defaults or Undo to bring it back." if result.entity.get("hidden", false) else "Deleted the prop. Undo is available in this scene."
		"restore": return "Restored %s to its authored placement." % EntityTypes.label(result.entity)
		"undo": return "Undid the last edit in this scene."
		"prefab_saved": return "Saved %s to the prefab library." % result.name
		"prefab_placed": return "Placed the prefab. You can edit it or undo the placement."
		"behavior":
			if arguments.behavior == null:
				return "Removed the entity’s behavior."
			return "Updated the live test link." if result.get("preview", false) else "Saved the entity’s behavior."
	return definition.description

static func _names(items: Array, empty: String) -> String:
	var names := PackedStringArray()
	for item in items:
		names.append(item.name)
	return empty if names.is_empty() else ", ".join(names)

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
