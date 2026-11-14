extends RefCounted
## Main-thread command boundary shared by the palette and future agent adapters.
## Arguments and results contain serializable data. Each successful edit is saved before it appears.

signal authored_geometry_changed

const Commands = preload("res://scripts/workshop/command_registry.gd")
const EntityTypes = preload("res://scripts/workshop/entity_types.gd")
const SceneStore = preload("res://scripts/persistence/scene_edit_store.gd")
const Art = preload("res://scripts/rendering/zone_effects.gd")
const PropMotion = preload("res://scripts/animation/prop_motion.gd")
const PrefabLibrary = preload("res://scripts/workshop/prefab_library.gd")
const BehaviorRuntime = preload("res://scripts/plugins/behavior_runtime.gd")
const BehaviorHost = preload("res://scripts/plugins/behavior_host.gd")
const DoorLinks = preload("res://scripts/plugins/door_links.gd")
const DoorActuator = preload("res://scripts/plugins/door_actuator.gd")
const Placement = preload("res://scripts/workshop/scene_placement.gd")
const PieceProps = preload("res://scripts/pieces/prop_piece.gd")
const PieceDocument = preload("res://scripts/persistence/piece_document.gd")
const PieceEditor = preload("res://scripts/pieces/piece_editor.gd")
const DressingLayer = preload("res://scripts/workshop/dressing_layer.gd")
const MAX_ENTITIES := SceneStore.MAX_ENTITIES

var _path := ""
var _prefabs: PrefabLibrary
var _behaviors: BehaviorRuntime
var _links: DoorLinks
var _pieces: PieceEditor
var _piece_props := {}
var _preview := {}
var _entities := {}
var _dressing := DressingLayer.new()
var _overrides := {}
var _nodes := {}
var _history: Array[Dictionary] = []
var _root: Node3D
var _load_error := ""
var bounds: AABB

func _init(path := "", prefabs: PrefabLibrary = null, behaviors: BehaviorRuntime = null, scene_bounds: Variant = null) -> void:
	_path = path
	bounds = Placement.workshop_bounds() if scene_bounds == null else scene_bounds
	_prefabs = prefabs
	_behaviors = behaviors
	var state := SceneStore.read(path, _valid_record, DressingLayer.valid_override.bind(bounds))
	_load_error = state.get("error", "")
	_entities = state.get("entities", {})
	_overrides = state.get("dressing", {})
	_history.assign(state.get("undo", []))

func attach(zone: Node3D, pieces: PieceEditor = null) -> void:
	_pieces = pieces
	_piece_props.clear()
	_nodes.clear()
	_root = null
	_preview = {}
	_dressing.attach(zone, _overrides)
	if zone == null:
		return
	_links = DoorLinks.new()
	_root = Node3D.new()
	_root.name = "WorkshopEntities"
	zone.add_child(_root)
	for record in _entities.values():
		_show(record)
	refresh_piece_props(zone)

func migrate_saved_props(document: PieceDocument) -> void:
	if _path.is_empty() or (_entities.is_empty() and _history.is_empty()) or not _load_error.is_empty() or not document.error.is_empty():
		return
	var active: Dictionary = _entities.duplicate()
	var records := _piece_records(active)
	var edits: Array[Dictionary] = []
	var kept: Array[Dictionary] = []
	for entry: Dictionary in _history:
		if entry.previous.is_empty() and entry.get("doors", {}).is_empty():
			kept.append(entry)
	for index in range(_history.size() - 1, -1, -1):
		var entry: Dictionary = _history[index]
		active = _updated(active, entry.previous)
		if not entry.previous.is_empty() or not entry.get("doors", {}).is_empty():
			edits.push_front({"records": _piece_records(active), "door_heights": entry.get("doors", {}), "time": entry.get("time", 0.0)})
	if (not records.is_empty() or not edits.is_empty()) and document.import_scene_props(records, edits):
		_entities.clear()
		_history = kept

static func _piece_records(entities: Dictionary) -> Array:
	return entities.values().map(func(record: Dictionary) -> Dictionary:
		return _to_piece(record, [0, record.yaw, 0]))

func refresh_piece_props(zone: Node3D) -> void:
	if is_instance_valid(_root) and _root.get_parent() == zone:
		_dressing.refresh(zone, _overrides)
	if _pieces == null:
		return
	_piece_props.clear()
	for entry: Dictionary in _pieces.summaries():
		if entry.type != "prop" or not entry.parent.is_empty():
			continue
		var node := _pieces.node_for(entry.id)
		_piece_props[entry.id] = node
		var piece := _pieces.record(entry.id)
		var record := _effective(PieceProps.entity_record(piece))
		var door := node.get_node_or_null("DoorActuator") as DoorActuator
		if door:
			door.links = _links
			door.links.drive("piece", entry.id, float(piece.get("door_open", 0.0)), 2.0)
		var behavior: Variant = record.get("behavior")
		if node.get_meta("bound_behavior", {}) != (behavior if behavior != null else {}):
			_sync_behavior(node, record)
			node.set_meta("bound_behavior", behavior if behavior != null else {})

func execute(tool: String, args := {}) -> Dictionary:
	if not is_instance_valid(_root):
		return _error("Wait for the scene to finish loading.")
	if not _load_error.is_empty():
		return _error(_load_error)
	var definition := Commands.local(tool)
	if definition.is_empty() or not has_method(definition.handler):
		return _error("Unknown world tool.")
	if definition.mutates_world and not _root.get_parent().get_meta("scene_edit", true):
		return _error("This environment does not allow scene edits.")
	var result: Dictionary = call(definition.handler, args)
	if not result.get("entity", {}).is_empty() and not result.entity.has("collision"):
		result["entity"] = result.entity.merged({"collision": true})
	return result

func _list_records(_args: Dictionary) -> Dictionary:
	return {"ok": true, "entities": _records().duplicate(true), "can_undo": not _history.is_empty() or (_pieces != null and _pieces.has_undo())}

func _list_entities(_args: Dictionary) -> Dictionary:
	var entities: Array[Dictionary] = []
	for item in _records():
		var entry := {"id": item.id, "name": EntityTypes.label(item).left(64), "type": item.type,
			"position": item.position.duplicate(), "yaw": item.yaw, "scale": item.scale, "color": item.color,
			"collision": item.get("collision", true), "behavior": _effective(item).get("behavior", {}).get("id", "")}
		if item.get("authored", false):
			entry.merge({"authored": true, "hidden": item.hidden, "overridden": item.overridden})
		if item.has("live_position"):
			entry["live_position"] = item.live_position
		entities.append(entry)
	return {"ok": true, "entities": entities}

func _list_scene_assets(_args: Dictionary) -> Dictionary:
	return {"ok": true, "assets": EntityTypes.library_catalog()}

func _list_behaviors(args: Dictionary) -> Dictionary:
	var id: Variant = args.get("id")
	var record := _record(args.get("id"))
	var authored := _dressing.has(args.get("id"))
	if authored:
		return {"ok": true, "behaviors": []}
	if id != null and id != "" and record.is_empty():
		return _error("Select an entity first.")
	return {"ok": true, "behaviors": _behaviors.available(record.get("type", "")) if _behaviors else []}

func _change_behavior(args: Dictionary) -> Dictionary:
	var id: Variant = args.get("id")
	var record := _record(args.get("id"))
	var authored := _dressing.has(args.get("id"))
	if record.is_empty():
		return _error("Select an entity first.")
	if authored:
		return _error("Place a library copy to attach behaviors to this model.")
	return _set_behavior(id, record, args.get("behavior"))

func _inspect(args: Dictionary) -> Dictionary:
	var record := _record(args.get("id"))
	return {"ok": true, "entity": _effective(record).duplicate(true)} if not record.is_empty() else _error("Select an entity first.")

func _spawn(args: Dictionary) -> Dictionary:
	var type: Variant = args.get("type")
	if not type is String or not EntityTypes.TYPES.has(type):
		return _error("Unknown entity type.")
	var type_definition: Dictionary = EntityTypes.TYPES[type]
	var source: String = type_definition.get("asset_source", "")
	var asset_id: Variant = args.get("asset_id", type_definition.get("asset_id"))
	if source == "runtime" and (not EntityTypes.Assets.valid_id(asset_id) or EntityTypes.Assets.scene(asset_id) == null):
		return _error("Import the model before spawning it.")
	if source == "library" and not EntityTypes.library_available(asset_id):
		return _error("Choose an installed model from the scene asset library.")
	if _entities.size() + _piece_prop_count() >= MAX_ENTITIES:
		return _error("This scene is at its prop limit.")
	var id := Crypto.new().generate_random_bytes(16).hex_encode()
	var proposed := {"id": id, "type": type, "position": args.get("position"), "yaw": args.get("yaw", 0.0),
		"scale": args.get("scale", 1.0), "color": args.get("color", EntityTypes.TYPES[type].color)}
	if not source.is_empty():
		proposed["asset_id"] = asset_id
	if args.has("name") and args.name != "":
		proposed["name"] = args.name.strip_edges() if args.name is String else args.name
	if args.has("stretch"):
		proposed["stretch"] = args.stretch
	if args.has("collision"):
		if not Commands.valid_field("collision", args.collision):
			return _error("Collision must be true or false.")
		proposed["collision"] = args.collision
	if args.has("animation"):
		proposed["animation"] = args.animation
	if args.has("behavior"):
		if _behaviors and args.behavior is Dictionary and _behaviors.is_provisional(str(args.behavior.get("id", ""))):
			return _error("Commit the plugin before duplicating its preview.")
		proposed["behavior"] = args.behavior
	if _pieces != null:
		if not _valid_record(proposed):
			return _error("Use a position inside this scene, a scale from 0.25 to 4, and a six-digit color.")
		var added := _pieces.apply_prop(id, _to_piece(proposed, [0, proposed.yaw, 0]))
		return {"ok": true, "id": id, "entity": _record(id)} if added.ok else _error(added.message)
	return _edit(id, {}, proposed)

func _piece_prop_count() -> int:
	return _piece_props.size()

func _edit_entity(args: Dictionary) -> Dictionary:
	var id: Variant = args.get("id")
	var record := _record(args.get("id"))
	var authored := _dressing.has(args.get("id"))
	if record.is_empty():
		return _error("Select an entity first.")
	if record.get("hidden", false):
		return _error("Restore the authored prop before editing it.")
	var changes: Variant = args.get("changes")
	if not changes is Dictionary or changes.is_empty():
		return _error("Choose properties to edit.")
	var proposed := record.duplicate()
	for key in changes:
		if authored and key not in Commands.prop_fields(true):
			return _error("Authored props support position, rotation, scale, name, color and collision edits.")
		if key != "animation" and key not in Commands.prop_fields(false):
			return _error("Unknown editable property.")
		if key == "collision" and not Commands.valid_field("collision", changes.collision):
			return _error("Collision must be true or false.")
		if key == "name" and changes.name is String:
			var name: String = changes.name.strip_edges()
			if name.is_empty():
				proposed.erase("name")
			else:
				proposed["name"] = name
		else:
			proposed[key] = changes[key]
	return _edit(id, record, proposed)

func _duplicate(args: Dictionary) -> Dictionary:
	var record := _record(args.get("id"))
	var authored := _dressing.has(args.get("id"))
	if record.is_empty():
		return _error("Select an entity first.")
	if authored:
		return _error("Place a separate copy of this model from the scene asset library.")
	var placement := record.duplicate(true)
	var offset: float = 0.8 * record.scale
	var point: Array = placement.position
	point[0] += offset if point[0] + offset <= bounds.end.x else -offset
	placement["position"] = args.get("position", point)
	return execute("spawn", placement)

func _delete(args: Dictionary) -> Dictionary:
	var id: Variant = args.get("id")
	var record := _record(args.get("id"))
	if record.is_empty() or record.get("hidden", false):
		return _error("Select an entity first.")
	return _edit(id, record, {})

func _restore_dressing(args: Dictionary) -> Dictionary:
	var id: Variant = args.get("id")
	var authored := _dressing.has(args.get("id"))
	if not authored:
		return _error("Select a prop from the original scene dressing.")
	var result := _edit_dressing(id, {})
	if result.ok:
		_dressing.reset_motion(id)
		result["entity"] = _record(id)
	return result

func _undo(_args: Dictionary) -> Dictionary:
	var last_prop_edit := float(_history[-1].get("time", 0.0)) if not _history.is_empty() else -INF
	if _pieces != null and _pieces.has_undo() and _pieces.undo_timestamp() >= last_prop_edit:
		var result := _pieces.execute({"tool": "undo_piece"})
		return {"ok": true, "id": "", "entity": {}} if result.ok else _error(result.message)
	if _history.is_empty():
		return _error("There are no edits to undo.")
	var edit: Dictionary = _history.back()
	var history := _history.slice(0, _history.size() - 1)
	if not _commit(edit.previous, edit.get("dressing", {}), history):
		return _error("The scene prop save could not be written.")
	_restore_door_heights(edit.get("doors", {}))
	var previous := _record(edit.id)
	return {"ok": true, "id": edit.id, "entity": previous.duplicate(true)}

func validate_action(targets: Array) -> Dictionary:
	return _prepare_action(targets)

func run_action(targets: Array) -> Dictionary:
	var edit := _prepare_action(targets)
	if not edit.ok:
		return edit
	if edit.next.is_empty() and edit.doors == edit.openings:
		return {"ok": true}
	var piece_targets: Array = edit.next.keys() + edit.doors.keys()
	if _pieces != null and piece_targets.any(func(id: String) -> bool: return _piece_props.has(id)):
		if not piece_targets.all(func(id: String) -> bool: return _piece_props.has(id)):
			return _error("This action needs the remaining older props moved into Pieces.")
		var updates := {}
		for id in edit.next:
			var piece := _prop_piece(id)
			var rotation: Array = piece.get("rotation", [0, 0, 0]).duplicate()
			rotation[1] = edit.next[id].yaw
			updates[id] = _to_piece(edit.next[id], rotation)
		var result := _pieces.update_props(updates, edit.doors)
		if not result.ok:
			return _error(result.message)
		_restore_door_heights(edit.openings)
		return {"ok": true}
	var history := _with_undo({"id": "", "previous": edit.previous, "doors": edit.doors})
	if not _commit(edit.next, {}, history):
		return _error("The scene prop save could not be written.")
	_restore_door_heights(edit.openings)
	return {"ok": true}

func _prepare_action(targets: Array) -> Dictionary:
	if not is_instance_valid(_root) or not _load_error.is_empty():
		return _error("The Grid is unavailable for workshop edits.")
	if not _root.get_parent().get_meta("scene_edit", true):
		return _error("This environment does not allow scene edits.")
	var previous := {}
	var next := {}
	var doors := {}
	var openings := {}
	for target in targets:
		var id: String = target.id
		var record := _record(id)
		if record.is_empty() or not is_instance_valid(scene_node(id)) or _dressing.has(id):
			return _error("A workshop action target is missing. Restore it before running this action.")
		var proposed := record.duplicate(true)
		proposed.merge(target.changes, true)
		if not _valid_record(proposed):
			return _error("The workshop action contains invalid entity properties.")
		if proposed != record:
			previous[id] = record
			next[id] = proposed
		if target.close_door or (EntityTypes.TYPES[record.type].factory == "door" and proposed != record):
			var door := _door(id)
			if door == null:
				return _error("A workshop action door target is unavailable.")
			doors[id] = door.opening_height()
			openings[id] = 0.0 if target.close_door else doors[id]
	return {"ok": true, "previous": previous, "next": next, "doors": doors, "openings": openings}

func _door(id: String) -> DoorActuator:
	var node := scene_node(id)
	return node.get_node_or_null("DoorActuator") as DoorActuator if is_instance_valid(node) else null

func _restore_door_heights(doors: Dictionary) -> void:
	for id in doors:
		var door := _door(id)
		if door:
			door.set_opening_height(doors[id])

func _set_behavior(id: String, record: Dictionary, request: Variant) -> Dictionary:
	var proposed := record.duplicate()
	if request == null:
		if _preview.get("entity") == id:
			finish_behavior_preview(_preview.draft, false)
			return {"ok": true, "id": id, "entity": record.duplicate(true)}
		proposed.erase("behavior")
	else:
		if not _behaviors:
			return _error("The behavior registry is unavailable.")
		var configured := _configure_behavior(record, request)
		if configured.is_empty():
			return _error("Choose a supported behavior, settings in range, and a compatible target in this space.")
		if _behaviors.is_provisional(configured.id):
			return _error("Commit the plugin in Workbench before attaching it elsewhere.") if _preview.get("entity") != id \
				else preview_behavior(_preview.draft, id, configured)
		if _preview.get("entity") == id:
			finish_behavior_preview(_preview.draft, false)
		proposed["behavior"] = configured
	return _edit(id, record, proposed)

func _configure_behavior(record: Dictionary, request: Variant) -> Dictionary:
	var configured := _behaviors.registry.configure(record.type, request)
	if configured.is_empty() or not _behaviors.available(record.type).any(func(item: Dictionary) -> bool: return item.id == configured.id):
		return {}
	if _behaviors.registry.definition(configured.id).output == "door_open" \
			and EntityTypes.TYPES.get(_record(configured.get("target", "")).get("type"), {}).get("factory") != "door":
		return {}
	return configured

func preview_behavior(draft_id: String, id: String, request: Dictionary) -> Dictionary:
	var record := _record(id)
	var node := scene_node(id)
	if record.is_empty() or node == null:
		return _error("The source entity is unavailable in this Grid space.")
	var configured := _configure_behavior(record, request)
	if configured.is_empty():
		return _error("The plugin requires a compatible source and target in this Grid space.")
	if not _preview.is_empty() and (_preview.draft != draft_id or _preview.entity != id):
		return _error("Finish the current behavior binding preview first.")
	_preview = {"draft": draft_id, "entity": id, "behavior": configured}
	_sync_behavior(node, _effective(record))
	return {"ok": true, "id": id, "entity": _effective(record).duplicate(true), "preview": true}

func behavior_preview_id() -> String:
	return _preview.get("draft", "")

func finish_behavior_preview(draft_id: String, keep: bool) -> Dictionary:
	if _preview.is_empty() or _preview.draft != draft_id:
		return {"ok": true}
	var pending := _preview
	_preview = {}
	var record := _record(pending.entity)
	var node := scene_node(pending.entity)
	if record.is_empty() or node == null:
		return {"ok": true}
	if keep and not _configure_behavior(record, pending.behavior).is_empty():
		var proposed := record.duplicate()
		proposed.behavior = pending.behavior
		var result := _edit(pending.entity, record, proposed)
		if result.ok:
			return result
	_sync_behavior(node, record)
	return _error("The plugin was committed, but its test link could not be saved.") if keep else {"ok": true}

func _effective(record: Dictionary) -> Dictionary:
	if not _preview.is_empty() and _preview.entity == record.id:
		var effective := record.duplicate()
		effective.behavior = _preview.behavior
		return effective
	return record

func _list_prefabs(_args: Dictionary) -> Dictionary:
	return _prefabs.list() if _prefabs else _error("The prefab library is unavailable.")

func _save_prefab(args: Dictionary) -> Dictionary:
	var id: Variant = args.get("id")
	if _dressing.has(id):
		return _error("Place a library copy to save this model as a prefab.")
	if not _prefabs:
		return _error("The prefab library is unavailable.")
	var record := _record(id)
	if record.is_empty():
		return _error("Select an entity to save as a prefab.")
	return _prefabs.save(args.get("name"), record)

func _spawn_prefab(args: Dictionary) -> Dictionary:
	if not _prefabs:
		return _error("The prefab library is unavailable.")
	var result := _prefabs.get_prefab(args.get("prefab_id"))
	if not result.ok:
		return result
	var placement: Dictionary = result.prefab.properties
	placement["position"] = args.get("position")
	return execute("spawn", placement)

func _edit(id: String, previous: Dictionary, proposed: Dictionary, from_grab := false) -> Dictionary:
	var piece := _prop_piece(id)
	if not piece.is_empty():
		return _edit_prop_piece(piece, proposed, from_grab)
	if _dressing.has(id):
		return _edit_dressing(id, _dressing.changes_for(id, proposed, _overrides.get(id, {})), from_grab)
	if not proposed.is_empty() and not _valid_record(proposed):
		return _error("Use a position inside this scene, a scale from 0.25 to 4, a six-digit color, and a printable name.")
	if proposed == previous:
		return {"ok": true, "id": id, "entity": previous.duplicate(true)}
	var next := proposed.duplicate(true)
	if not _commit({id: next}, {}, _with_undo({"id": id, "previous": {id: previous}}), from_grab):
		return _error("The scene prop save could not be written.")
	return {"ok": true, "id": id, "entity": next.duplicate(true)}

func _edit_dressing(id: String, proposed: Dictionary, from_grab := false) -> Dictionary:
	if not DressingLayer.valid_override(proposed, bounds):
		return _error("Use a position inside this scene, a scale from 0.25 to 4, a six-digit color, and a printable name.")
	var previous: Dictionary = _overrides.get(id, {})
	if proposed != previous:
		var history := _with_undo({"id": id, "previous": {}, "dressing": {id: previous}})
		if not _commit({}, {id: proposed.duplicate(true)}, history, from_grab):
			return _error("The scene prop save could not be written.")
	return {"ok": true, "id": id, "entity": _record(id)}

func _prop_piece(id: Variant) -> Dictionary:
	return _pieces.record(id) if _piece_props.has(id) else {}

func _edit_prop_piece(piece: Dictionary, proposed: Dictionary, from_grab: bool) -> Dictionary:
	var id: String = piece.id
	if proposed.is_empty():
		var removed := _pieces.apply_prop(id, {}, true)
		return {"ok": true, "id": id, "entity": {}} if removed.ok else _error(removed.message)
	if not _valid_record(proposed):
		return _error("Use a position inside this scene, a scale from 0.25 to 4, and a six-digit color.")
	var rotation: Array = piece.get("rotation", [0, 0, 0]).duplicate()
	rotation[1] = proposed.yaw
	if from_grab:
		var body := _pieces.node_for(id) as RigidBody3D
		if body:
			var turn := body.rotation_degrees
			rotation = [turn.x, turn.y, turn.z]
	var updates := _to_piece(proposed, rotation)
	# Optional fields cleared by the workshop must be removed from the same piece record.
	for key in ["name", "stretch", "animation", "behavior"]:
		if not updates.has(key) and piece.has(key):
			updates[key] = null
	var result := _pieces.apply_prop(id, updates)
	return {"ok": true, "id": id, "entity": _record(id)} if result.ok else _error(result.message)

static func _to_piece(entity: Dictionary, rotation: Array) -> Dictionary:
	var record := {"id": entity.id, "type": "prop", "prop_kind": entity.type, "position": entity.position,
		"rotation": rotation, "prop_size": entity.scale, "color": entity.color, "locked": entity.get("locked", false)}
	for key in ["asset_id", "name", "stretch", "animation", "collision"]:
		if entity.has(key):
			record[key] = entity[key]
	if entity.has("behavior"):
		var binding: Dictionary = entity.behavior
		var settings := []
		for key in binding.settings:
			settings.append({"key": key, "value": binding.settings[key]})
		record["behavior"] = {"id": binding.id, "settings": settings}
		if binding.has("target"):
			record.behavior["target_entity"] = binding.target
	return record

func _record(id: Variant) -> Dictionary:
	var piece := _prop_piece(id)
	if not piece.is_empty():
		return PieceProps.entity_record(piece)
	return _dressing.record(id, _overrides.get(id, {})) if _dressing.has(id) else _entities.get(id, {})

func _records() -> Array:
	var records := _entities.values() + _dressing.records(_overrides)
	for id: String in _piece_props:
		records.append(PieceProps.entity_record(_pieces.record(id)))
	return records

func _with_undo(edit: Dictionary) -> Array[Dictionary]:
	var history := _history.duplicate()
	history.append(edit.merged({"time": Time.get_unix_time_from_system()}))
	return SceneStore.trimmed(history)

static func _updated(layer: Dictionary, updates: Dictionary) -> Dictionary:
	var next := layer.duplicate()
	for id in updates:
		if updates[id].is_empty():
			next.erase(id)
		else:
			next[id] = updates[id]
	return next

func _commit(records: Dictionary, dressing: Dictionary, history: Array[Dictionary], from_grab := false) -> bool:
	var previous := _entities
	var previous_overrides := _overrides
	var next := _updated(_entities, records)
	var overrides := _updated(_overrides, dressing)
	if next.size() > MAX_ENTITIES or overrides.size() > SceneStore.MAX_DRESSING or not SceneStore.write(_path, next, overrides, history):
		return false
	_entities = next
	_overrides = overrides
	_history = history
	for id in records:
		_sync_record(id, previous.get(id, {}), records[id], from_grab)
	var geometry_changed := false
	for id in dressing:
		if _dressing.has(id):
			var override: Dictionary = overrides.get(id, {})
			var old_override: Dictionary = previous_overrides.get(id, {})
			_dressing.apply(id, override, old_override, from_grab)
			geometry_changed = geometry_changed or DressingLayer.changes_geometry(old_override, override)
	# A grab is already visible while moving. Resetting SDFGI here blanks the whole view.
	if geometry_changed and not from_grab:
		authored_geometry_changed.emit()
	return true

func _sync_record(id: String, previous: Dictionary, record: Dictionary, keep_pose: bool) -> void:
	if record.is_empty() and _preview.get("entity") == id:
		_preview = {}
	if _nodes.has(id):
		var body := _nodes[id] as RigidBody3D
		if body and _can_sync_rigid(previous, record):
			EntityTypes.update_placement(body, previous, record, keep_pose)
			return
		if not record.is_empty() and _same_placement(previous, record):
			EntityTypes.set_collision(_nodes[id], record.get("collision", true))
			var player := animation_player(id)
			if player:
				var clip: Dictionary = record.get("animation", {})
				if previous.get("animation", {}) != clip and player.clip != clip:
					player.set_clip(clip)
				if previous.get("behavior") != record.get("behavior"):
					_sync_behavior(_nodes[id], _effective(record))
				if body:
					EntityTypes.set_locked(body, record.get("locked", false) or not EntityTypes.movable(record))
				return
		_nodes[id].free()
		_nodes.erase(id)
	if not record.is_empty():
		_show(record)

static func _same_placement(a: Dictionary, b: Dictionary) -> bool:
	for key in ["type", "asset_id", "position", "yaw", "scale", "stretch", "color", "locked"]:
		if a.get(key) != b.get(key):
			return false
	return true

static func _can_sync_rigid(before: Dictionary, after: Dictionary) -> bool:
	return not after.is_empty() and EntityTypes.movable(before) and EntityTypes.movable(after) \
		and before.type == after.type and before.get("asset_id") == after.get("asset_id") and before.color == after.color

func _show(record: Dictionary) -> void:
	var entity := EntityTypes.create(record)
	Art.make_constructible(entity)
	var motion := PropMotion.new()
	motion.name = "PropMotion"
	motion.clip = record.get("animation", {})
	entity.add_child(motion)
	if EntityTypes.TYPES[record.type].factory == "door":
		var door := DoorActuator.new()
		door.name = "DoorActuator"
		door.links = _links
		door.entity_id = record.id
		door.travel = 2.5 * record.scale
		entity.add_child(door)
	_sync_behavior(entity, _effective(record))
	_root.add_child(entity)
	_nodes[record.id] = entity

func _sync_behavior(entity: Node3D, record: Dictionary) -> void:
	var old := entity.get_node_or_null("BehaviorHost")
	if old:
		old.free()
	if not _behaviors or not record.has("behavior"):
		return
	var configured := _behaviors.registry.configure(record.type, record.behavior)
	if not configured.is_empty():
		configured.settings.make_read_only()
		var host := BehaviorHost.new()
		host.name = "BehaviorHost"
		host.runtime = _behaviors
		host.behavior = configured
		host.links = _links
		host.entity_id = record.id
		host.output = _behaviors.registry.definition(configured.id).output
		entity.add_child(host)

func animation_targets() -> Array[Dictionary]:
	var targets: Array[Dictionary] = []
	if is_instance_valid(_root):
		for record in _records():
			var player := animation_player(record.id)
			if player:
				var channels := ["offset", "rotation"]
				if player.rig:
					channels.append("joint_rotation")
				targets.append({"id": record.id, "name": EntityTypes.label(record).left(64), "channels": channels})
	return targets

func animation_player(id: String) -> Node:
	var entity := scene_node(id)
	if is_instance_valid(entity) and not entity.has_meta("asset_unavailable"):
		return entity.get_node_or_null("PropMotion")
	return null

func _valid_record(record: Dictionary) -> bool:
	return SceneStore.valid_id(record.get("id")) \
		and EntityTypes.valid_properties(record) \
		and Placement.valid_coordinates(bounds, record.get("position"))

func scene_node(id: String) -> Node3D:
	if _piece_props.has(id):
		return _piece_props[id]
	return _dressing.scene_node(id) if _dressing.has(id) else _nodes.get(id) as Node3D

## A prop's absolute yaw as it stands now, for tools that turn it from where it is.
func live_yaw(id: String) -> float:
	var record := _record(id)
	var recorded := float(record.get("yaw", 0.0))
	if _dressing.has(id):
		return _dressing.live_yaw(id, recorded)
	var node := scene_node(id)
	if node is RigidBody3D:
		return wrapf(rad_to_deg(node.basis.orthonormalized().get_euler().y), -180.0, 180.0)
	return recorded

func can_toggle_lock(id: String) -> bool:
	if _dressing.has(id):
		return _dressing.can_unlock(id)
	var record := _record(id)
	return not record.is_empty() and EntityTypes.movable(record)

## The wrist changes motion at the live pose, independently of the collider.
func set_prop_physics(id: String, enabled: bool) -> Dictionary:
	var node := scene_node(id)
	if not is_instance_valid(node) or not can_toggle_lock(id):
		return _error("Physics is unavailable for this prop.")
	return _commit_live_pose(id, node, {"locked": not enabled, "yaw": live_yaw(id),
		"position": Placement.coordinates(node.position)})

## Saves a placement already previewed on the node and hands its live pose back to physics.
func commit_grab(id: String, node: Node3D, changes: Dictionary) -> Dictionary:
	# Dropping an authored decoration for the first time has always made it land as a solid prop.
	if changes.get("locked", true) == false and _dressing.has(id) and not node is RigidBody3D \
			and not _overrides.get(id, {}).has("collision"):
		changes = changes.merged({"collision": true})
	return _commit_live_pose(id, node, changes)

func _commit_live_pose(id: String, node: Node3D, changes: Dictionary) -> Dictionary:
	if not is_instance_valid(_root) or not _root.get_parent().get_meta("scene_edit", true) or not _load_error.is_empty():
		return _error("Scene edits are unavailable.")
	if scene_node(id) != node:
		return _error("The prop changed during the grab.")
	var record := _record(id)
	if record.is_empty() or record.get("hidden", false):
		return _error("Select a visible prop first.")
	var next := record.merged(changes, true)
	var result := _edit(id, record, next, true)
	if result.ok:
		# A grab may have temporarily frozen the body even if the saved lock value is unchanged.
		var body := scene_node(id) as RigidBody3D
		if body:
			if body.is_inside_tree():
				body.force_update_transform()
			if changes.has("locked"):
				EntityTypes.set_locked(body, changes.locked)
	return result

static func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
