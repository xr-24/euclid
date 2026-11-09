extends RefCounted
## Main-thread command boundary shared by the palette and future agent adapters.
## Arguments and results contain serializable data. Each successful edit is saved before it appears.

const EntityTypes = preload("res://scripts/workshop/entity_types.gd")
const Store = preload("res://scripts/persistence/world_state_store.gd")
const Art = preload("res://scripts/rendering/zone_effects.gd")
const PropMotion = preload("res://scripts/animation/prop_motion.gd")
const PrefabLibrary = preload("res://scripts/workshop/prefab_library.gd")
const BehaviorRuntime = preload("res://scripts/plugins/behavior_runtime.gd")
const BehaviorHost = preload("res://scripts/plugins/behavior_host.gd")
const DoorLinks = preload("res://scripts/plugins/door_links.gd")
const DoorActuator = preload("res://scripts/plugins/door_actuator.gd")
const MAX_ENTITIES := 256
const MAX_UNDO := 64
const MAX_SAVE_BYTES := 9 * 1024 * 1024
const EDITABLE := ["position", "yaw", "scale", "color", "animation"]

var _path := ""
var _prefabs: PrefabLibrary
var _behaviors: BehaviorRuntime
var _links: DoorLinks
var _preview := {}
var _entities := {}
var _nodes := {}
var _history: Array[Dictionary] = []
var _root: Node3D
var _load_error := ""

func _init(path := "", prefabs: PrefabLibrary = null, behaviors: BehaviorRuntime = null) -> void:
	_path = path
	_prefabs = prefabs
	_behaviors = behaviors
	if path.is_empty() or not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_SAVE_BYTES:
		_load_error = "The Grid save could not be read."
		return
	var state: Variant = JSON.parse_string(file.get_as_text())
	if not state is Dictionary or state.get("schema_version") != 1 or not state.get("entities") is Array:
		_load_error = "The Grid save has an invalid format."
		return
	if state.entities.size() > MAX_ENTITIES:
		_load_error = "The Grid save exceeds the entity limit."
		return
	var loaded := {}
	for item in state.entities:
		if not item is Dictionary or not _valid_record(item) or loaded.has(item.id):
			_load_error = "The Grid save contains an invalid entity."
			return
		loaded[item.id] = item
	_entities = loaded

func attach(zone: Node3D) -> void:
	_nodes.clear()
	_root = null
	_preview = {}
	if zone == null:
		return
	_links = DoorLinks.new()
	_root = Node3D.new()
	_root.name = "WorkshopEntities"
	zone.add_child(_root)
	for record in _entities.values():
		_show(record)

func execute(tool: String, args := {}) -> Dictionary:
	if not is_instance_valid(_root):
		return _error("Grid tools are available in The Grid.")
	if not _load_error.is_empty():
		return _error(_load_error)
	var id: Variant = args.get("id")
	var record: Dictionary = _entities.get(id, {})
	match tool:
		"list":
			return {"ok": true, "entities": _entities.values().duplicate(true), "can_undo": not _history.is_empty()}
		"list_entities":
			var entities: Array[Dictionary] = []
			for item in _entities.values():
				entities.append({"id": item.id, "name": EntityTypes.label(item).left(64), "type": item.type,
					"position": item.position.duplicate(), "behavior": _effective(item).get("behavior", {}).get("id", "")})
			return {"ok": true, "entities": entities}
		"list_behaviors":
			if id != null and id != "" and record.is_empty():
				return _error("Select an entity first.")
			return {"ok": true, "behaviors": _behaviors.available(record.get("type", "")) if _behaviors else []}
		"set_behavior":
			if record.is_empty():
				return _error("Select an entity first.")
			return _set_behavior(id, record, args.get("behavior"))
		"inspect":
			return {"ok": true, "entity": _effective(record).duplicate(true)} if not record.is_empty() else _error("Select an entity first.")
		"list_prefabs", "save_prefab", "spawn_prefab":
			return _prefab_command(tool, args, record)
		"spawn":
			var type: Variant = args.get("type")
			if not type is String or not EntityTypes.TYPES.has(type):
				return _error("Unknown entity type.")
			if type == "imported_model" and (not EntityTypes.Assets.valid_id(args.get("asset_id")) or EntityTypes.Assets.scene(args.asset_id) == null):
				return _error("Import the model before spawning it.")
			if _entities.size() >= MAX_ENTITIES:
				return _error("The Grid is at its entity limit.")
			id = Crypto.new().generate_random_bytes(16).hex_encode()
			var proposed := {"id": id, "type": type, "position": args.get("position"), "yaw": args.get("yaw", 0.0),
				"scale": args.get("scale", 1.0), "color": args.get("color", EntityTypes.TYPES[type].color)}
			if type == "imported_model":
				proposed["asset_id"] = args.asset_id
			if args.has("animation"):
				proposed["animation"] = args.animation
			if args.has("behavior"):
				if _behaviors and args.behavior is Dictionary and _behaviors.is_provisional(str(args.behavior.get("id", ""))):
					return _error("Commit the plugin before duplicating its preview.")
				proposed["behavior"] = args.behavior
			return _edit(id, {}, proposed)
		"edit":
			if record.is_empty():
				return _error("Select an entity first.")
			var changes: Variant = args.get("changes")
			if not changes is Dictionary or changes.is_empty():
				return _error("Choose properties to edit.")
			var proposed := record.duplicate()
			for key in changes:
				if key not in EDITABLE:
					return _error("Unknown editable property.")
				proposed[key] = changes[key]
			return _edit(id, record, proposed)
		"delete":
			if record.is_empty():
				return _error("Select an entity first.")
			return _edit(id, record, {})
		"undo":
			if _history.is_empty():
				return _error("There are no edits to undo.")
			var edit: Dictionary = _history.back()
			if not _apply_records(edit.previous):
				return _error("The Grid save could not be written.")
			_restore_door_heights(edit.get("doors", {}))
			_history.pop_back()
			var previous: Dictionary = edit.previous.get(edit.id, {})
			return {"ok": true, "id": edit.id, "entity": previous.duplicate(true)}
	return _error("Unknown world tool.")

func validate_action(targets: Array) -> Dictionary:
	return _prepare_action(targets)

func run_action(targets: Array) -> Dictionary:
	var edit := _prepare_action(targets)
	if not edit.ok:
		return edit
	if edit.next.is_empty() and edit.doors == edit.openings:
		return {"ok": true}
	if not _apply_records(edit.next):
		return _error("The Grid save could not be written.")
	_restore_door_heights(edit.openings)
	_remember({"id": "", "previous": edit.previous, "doors": edit.doors})
	return {"ok": true}

func _prepare_action(targets: Array) -> Dictionary:
	if not is_instance_valid(_root) or not _load_error.is_empty():
		return _error("The Grid is unavailable for workshop edits.")
	var previous := {}
	var next := {}
	var doors := {}
	var openings := {}
	for target in targets:
		var id: String = target.id
		var record: Dictionary = _entities.get(id, {})
		if record.is_empty() or not is_instance_valid(_nodes.get(id)):
			return _error("A workshop action target is missing. Restore it before running this action.")
		var proposed := record.duplicate(true)
		proposed.merge(target.changes, true)
		if not _valid_record(proposed):
			return _error("The workshop action contains invalid entity properties.")
		if proposed != record:
			previous[id] = record
			next[id] = proposed
		if target.close_door or (record.type == "sliding_door" and proposed != record):
			var door := _door(id)
			if door == null:
				return _error("A workshop action door target is unavailable.")
			doors[id] = door.opening_height()
			openings[id] = 0.0 if target.close_door else doors[id]
	return {"ok": true, "previous": previous, "next": next, "doors": doors, "openings": openings}

func _door(id: String) -> DoorActuator:
	var node := _nodes.get(id) as Node3D
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
			and _entities.get(configured.get("target", ""), {}).get("type") != "sliding_door":
		return {}
	return configured

func preview_behavior(draft_id: String, id: String, request: Dictionary) -> Dictionary:
	var record: Dictionary = _entities.get(id, {})
	if record.is_empty() or not is_instance_valid(_nodes.get(id)):
		return _error("The source entity is unavailable in this Grid space.")
	var configured := _configure_behavior(record, request)
	if configured.is_empty():
		return _error("The plugin requires a compatible source and target in this Grid space.")
	if not _preview.is_empty() and (_preview.draft != draft_id or _preview.entity != id):
		return _error("Finish the current behavior binding preview first.")
	_preview = {"draft": draft_id, "entity": id, "behavior": configured}
	_sync_behavior(_nodes[id], _effective(record))
	return {"ok": true, "id": id, "entity": _effective(record).duplicate(true), "preview": true}

func behavior_preview_id() -> String:
	return _preview.get("draft", "")

func finish_behavior_preview(draft_id: String, keep: bool) -> Dictionary:
	if _preview.is_empty() or _preview.draft != draft_id:
		return {"ok": true}
	var pending := _preview
	_preview = {}
	var record: Dictionary = _entities.get(pending.entity, {})
	if record.is_empty() or not is_instance_valid(_nodes.get(pending.entity)):
		return {"ok": true}
	if keep and not _configure_behavior(record, pending.behavior).is_empty():
		var proposed := record.duplicate()
		proposed.behavior = pending.behavior
		var result := _edit(pending.entity, record, proposed)
		if result.ok:
			return result
	_sync_behavior(_nodes[pending.entity], record)
	return _error("The plugin was committed, but its test link could not be saved.") if keep else {"ok": true}

func _effective(record: Dictionary) -> Dictionary:
	if not _preview.is_empty() and _preview.entity == record.id:
		var effective := record.duplicate()
		effective.behavior = _preview.behavior
		return effective
	return record

func _prefab_command(tool: String, args: Dictionary, record: Dictionary) -> Dictionary:
	if not _prefabs:
		return _error("The prefab library is unavailable.")
	match tool:
		"list_prefabs":
			return _prefabs.list()
		"save_prefab":
			if record.is_empty():
				return _error("Select an entity to save as a prefab.")
			return _prefabs.save(args.get("name"), record)
		"spawn_prefab":
			var result := _prefabs.get_prefab(args.get("prefab_id"))
			if not result.ok:
				return result
			var placement: Dictionary = result.prefab.properties
			placement["position"] = args.get("position")
			return execute("spawn", placement)
	return _error("Unknown prefab tool.")

func _edit(id: String, previous: Dictionary, proposed: Dictionary) -> Dictionary:
	if not proposed.is_empty() and not _valid_record(proposed):
		return _error("Use a position within The Grid, a scale from 0.25 to 4, and a six-digit color.")
	if proposed == previous:
		return {"ok": true, "id": id, "entity": previous.duplicate(true)}
	var next := proposed.duplicate(true)
	if not _apply_records({id: next}):
		return _error("The Grid save could not be written.")
	_remember({"id": id, "previous": {id: previous}})
	return {"ok": true, "id": id, "entity": next.duplicate(true)}

func _remember(edit: Dictionary) -> void:
	_history.append(edit)
	if _history.size() > MAX_UNDO:
		_history.pop_front()

func _apply_records(records: Dictionary) -> bool:
	if records.is_empty():
		return true
	var previous := _entities
	var next := _entities.duplicate()
	for id in records:
		if records[id].is_empty():
			next.erase(id)
		else:
			next[id] = records[id]
	if not _path.is_empty() and Store.write_json(_path, {"schema_version": 1, "entities": next.values()}) != OK:
		return false
	_entities = next
	for id in records:
		_sync_record(id, previous.get(id, {}), records[id])
	return true

func _sync_record(id: String, previous: Dictionary, record: Dictionary) -> void:
	if record.is_empty() and _preview.get("entity") == id:
		_preview = {}
	if _nodes.has(id):
		if not record.is_empty() and _same_placement(previous, record):
			var player := animation_player(id)
			if player:
				var clip: Dictionary = record.get("animation", {})
				if previous.get("animation", {}) != clip and player.clip != clip:
					player.set_clip(clip)
				if previous.get("behavior") != record.get("behavior"):
					_sync_behavior(_nodes[id], _effective(record))
				return
		_nodes[id].free()
		_nodes.erase(id)
	if not record.is_empty():
		_show(record)

static func _same_placement(a: Dictionary, b: Dictionary) -> bool:
	for key in ["type", "asset_id", "position", "yaw", "scale", "color"]:
		if a.get(key) != b.get(key):
			return false
	return true

func _show(record: Dictionary) -> void:
	var entity := EntityTypes.create(record)
	Art.make_constructible(entity)
	var motion := PropMotion.new()
	motion.name = "PropMotion"
	motion.clip = record.get("animation", {})
	entity.add_child(motion)
	if record.type == "sliding_door":
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
		for record in _entities.values():
			var player := animation_player(record.id)
			if player:
				var channels := ["offset", "rotation"]
				if player.rig:
					channels.append("joint_rotation")
				targets.append({"id": record.id, "name": EntityTypes.label(record).left(64), "channels": channels})
	return targets

func animation_player(id: String) -> Node:
	var entity := _nodes.get(id) as Node3D
	if is_instance_valid(entity) and not entity.has_meta("asset_unavailable"):
		return entity.get_node("PropMotion")
	return null

static func _valid_record(record: Dictionary) -> bool:
	var id: Variant = record.get("id")
	var point: Variant = record.get("position")
	return id is String and id.length() == 32 and id.is_valid_hex_number() \
		and EntityTypes.valid_properties(record) \
		and point is Array and point.size() == 3 \
		and EntityTypes.number_between(point[0], -60.0, 60.0) and EntityTypes.number_between(point[1], 0.0, 12.0) \
		and EntityTypes.number_between(point[2], -60.0, 60.0)

static func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
