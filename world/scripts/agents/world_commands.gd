extends RefCounted
## Trusted command handlers receive the application coordinator as their explicit host.

const SceneCommands = preload("res://scripts/workshop/scene_commands.gd")
const Packages = preload("res://scripts/zones/zone_packages.gd")
const Commands = preload("res://scripts/workshop/command_registry.gd")
const Atmosphere = preload("res://scripts/rendering/atmosphere.gd")
const TerrainTools = preload("res://scripts/pieces/terrain_tools.gd")

var _world: Node3D

func _init(world: Node3D) -> void:
	_world = world

func execute(definition: Dictionary, plan: Dictionary) -> Dictionary:
	if not has_method(definition.handler):
		return {"ok": false, "message": "The registered world handler is unavailable."}
	return await call(definition.handler, plan)

func _run_registered_action(plan: Dictionary) -> Dictionary:
	return _world._run_registered_action(plan)

func _piece_command(plan: Dictionary) -> Dictionary:
	if plan.tool == "undo_piece":
		return TerrainTools.undo(_world.pieces, _world.player)
	var placement: Array = []
	if plan.tool == "add_piece" and not plan.has("parent") and not plan.get("piece_values", {}).has("position"):
		placement = _world._scene_spawn_position()
	return _world.pieces.execute(plan, placement)

func _terrain_command(plan: Dictionary) -> Dictionary:
	var result := TerrainTools.execute(_world.pieces, plan)
	if result.ok and plan.tool == "terrain_brush":
		var player: CharacterBody3D = _world.player
		player.global_position = TerrainTools.above_surface(_world.pieces, player.global_position, plan.target)
	return result

func _inspect_player_rig(plan: Dictionary) -> Dictionary:
	return _world.player_rig.inspect(plan.get("target", ""))

func _preview_player_rig(plan: Dictionary) -> Dictionary:
	var slot: String = plan.get("target", "")
	return _world.player_rig.preview("rest" if slot.is_empty() else slot, plan)

func _finish_player_rig(plan: Dictionary) -> Dictionary:
	return _world.player_rig.finish(Commands.command(plan.tool).mode == "save")

func _inspect_atmosphere(_plan: Dictionary) -> Dictionary:
	return _world.atmosphere.inspect(_world.zone_id)

func _preview_atmosphere(plan: Dictionary) -> Dictionary:
	if _world.shifting:
		return {"ok": false, "message": "Wait for the environment to finish loading."}
	# The planner fills every field it knows; take only atmosphere settings that were given.
	var changes := {}
	for key in plan:
		if (key in Atmosphere.FIELDS or key == "reset") and plan[key] != null:
			changes[key] = plan[key]
	return _world.atmosphere.preview(_world.zone_id, changes)

func _finish_atmosphere(plan: Dictionary) -> Dictionary:
	return _world.atmosphere.finish(Commands.command(plan.tool).mode == "save")

func _list_registered_actions(_plan: Dictionary) -> Dictionary:
	var catalog: Array = _world._workshop_action_catalog()
	var labels := PackedStringArray()
	for entry in catalog:
		labels.append(entry.label)
	return {"ok": true, "message": ", ".join(labels) if not labels.is_empty() else "Enter a Grid space to find workshop actions.", "tools": catalog}

func _list_assets(_plan: Dictionary) -> Dictionary:
	var listed: Dictionary = await _world.asset_client.list_assets()
	listed["message"] = JSON.stringify(listed.get("assets", [])) if listed.get("ok", false) else listed.get("message", "Asset listing failed.")
	return listed

func _spawn_asset(plan: Dictionary) -> Dictionary:
	var requested_zone: Node3D = _world.zone_root
	# Capture placement before a download so camera movement cannot change it.
	var properties := SceneCommands.options(plan)
	var position: Array = plan.get("position", properties.get("position", []))
	if position.is_empty():
		position = _world._scene_spawn_position()
	if position.is_empty():
		return {"ok": false, "message": "Aim at solid ground or specify a position before importing a model."}
	_world._console_notice("Finding and preparing the model…")
	var imported: Dictionary = await _world.asset_client.ensure_asset(plan.target, _world._world_context(), plan.get("preserve_rig", false))
	if not imported.get("ok", false):
		return {"ok": false, "message": imported.get("message", "The model could not be imported.")}
	if not is_instance_valid(requested_zone) or _world.zone_root != requested_zone or _world.shifting:
		return {"ok": false, "message": "The model is cached. Spawn it again in your current environment."}
	properties.merge({"type": "imported_model", "asset_id": imported.asset.asset_id, "position": position,
		"scale": plan.get("scale", properties.get("scale", 1.0))}, true)
	var result: Dictionary = _world.world_tools.execute("spawn", properties)
	result["zone"] = _world.zone_id
	result["message"] = "Spawned %s. %s — %s. %s" % [imported.asset.title, imported.asset.author,
		imported.asset.license_label, imported.asset.get("credit", "")] if result.ok else result.error
	return result

func _list_environments(_plan: Dictionary) -> Dictionary:
	var context: Dictionary = _world._world_context()
	var labels := PackedStringArray()
	for zone in context.environments:
		labels.append(zone.name)
	return {"ok": true, "message": "Available environments: " + ", ".join(labels) + ".", "context": context}

func _travel_command(plan: Dictionary) -> Dictionary:
	if _world.shifting:
		return {"ok": false, "message": "A world shift is in progress."}
	var target: String = plan.target
	var zone: Dictionary = _world._zone(target)
	if zone.id != target:
		return {"ok": false, "message": "That environment is no longer in the catalog."}
	await _world._shift(target)
	return {"ok": _world.zone_id == target, "message": "You’re in %s." % zone.name, "environment": _world.zone_id}

func _create_environment(plan: Dictionary) -> Dictionary:
	if _world.shifting or _world.building:
		return {"ok": false, "message": "Wait for the current environment to finish loading."}
	var created: Dictionary = _world.environment_library.create(plan.target, _world.manifest.zones, plan.get("template", ""))
	if created.ok:
		_world.manifest.zones.append(created.zone)
		Packages.register_zone(created.zone)
	return created

func _companion_mode(plan: Dictionary) -> Dictionary:
	var mode: String = Commands.command(plan.tool).mode
	var peer: String = plan.agent_peer
	_world._activate_agent(peer)
	_world.agent_presence.set_mode(peer, mode, _world.zone_id, _world.player)
	return {"ok": true, "message": "I’ll follow you." if mode == "follow" else "I’ll stay here.", "mode": mode}

func _unsupported_command(_plan: Dictionary) -> Dictionary:
	return {"ok": false, "message": "I couldn’t match that request to an available Euclid command."}
