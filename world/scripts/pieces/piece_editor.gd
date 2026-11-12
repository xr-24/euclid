extends RefCounted
## One editor for the palette and registered commands. The document is committed before node changes.

signal changed
const Types = preload("res://scripts/pieces/piece_types.gd")
const Builder = preload("res://scripts/pieces/piece_builder.gd")
const Placement = preload("res://scripts/workshop/scene_placement.gd")
const EntityTypes = preload("res://scripts/workshop/entity_types.gd")
const Commands = preload("res://scripts/workshop/command_registry.gd")
const Document = preload("res://scripts/persistence/piece_document.gd")
const Effects = preload("res://scripts/rendering/zone_effects.gd")
const PAGE_SIZE := 64

var _layer: Node3D
var _document: Document
var _displayed: Array
var _appearance := Callable()
var bounds: AABB
var revision := 0
var _editable := false

func attach(layer: Node3D, document: Document, can_edit: bool, area: AABB, displayed: Variant = null) -> void:
	_layer = layer
	_document = document
	_displayed = document.pieces if displayed == null else displayed
	_appearance = Callable()
	_editable = can_edit
	bounds = area
	revision += 1
	changed.emit()

## A source preview can project alternate visual fields without changing the saved document.
func set_appearance(project: Callable) -> void:
	_appearance = project
	if is_instance_valid(_layer):
		_sync_display()
		revision += 1

func _sync_display() -> void:
	var next: Array = _appearance.call(_document.pieces) if _appearance.is_valid() else _document.pieces
	if next != _displayed:
		Builder.sync(_layer, _displayed, next)
		_displayed = next
		var side: float = _layer.get_parent().get_meta("construct_side", 0.0) if _layer.get_parent() else 0.0
		if side != 0.0:
			Effects.set_side(_layer, side)

func can_edit() -> bool:
	return is_instance_valid(_layer) and _editable and _document.error.is_empty()

func node_for(id: String) -> Node3D:
	if not is_instance_valid(_layer) or id.is_empty():
		return null
	return _layer.find_child("Piece_" + id, true, false) as Node3D

func fields(type: String) -> Dictionary:
	return Types.common().merged(Types.types()[type].fields)

func record(id: String) -> Dictionary:
	if _document == null:
		return {}
	return _find(_document.pieces, id).get("piece", {}).duplicate(true)

func summaries() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	if _document:
		_summaries(_document.pieces, "", items)
	return items

func execute(plan: Dictionary, placement: Array = []) -> Dictionary:
	var definition := Commands.command(plan.get("tool"))
	if definition.get("handler") != "_piece_command" or not Commands.valid_plan(definition, plan):
		return _failure("Invalid piece command arguments.")
	if not is_instance_valid(_layer):
		return _failure("Wait for the environment to finish loading.")
	if definition.mutates_world and not can_edit():
		return _failure(_document.error if not _document.error.is_empty() else "This environment does not allow piece edits.")
	var id: String = plan.get("target", "")
	match plan.tool:
		"list_piece_types":
			var types := Types.types().duplicate(true)
			for type in types:
				types[type].erase("script")
			return {"ok": true, "message": "Registered pieces: " + ", ".join(types.keys()),
				"types": types, "common": Types.common().duplicate(true), "models": EntityTypes.library_catalog()}
		"list_pieces":
			return _list(id, int(plan.get("offset", 0)))
		"undo_piece":
			if _document.history.is_empty():
				return _failure("There are no piece edits to undo.")
			return _save(_document.history[-1].pieces, _document.history.slice(0, -1), "", "Piece edit undone.")
	var next: Array = _document.pieces.duplicate(true)
	var entry := _find(next, id)
	var values: Dictionary = plan.get("piece_values", {})
	match plan.tool:
		"add_piece":
			var type: String = id
			id = "piece-" + Crypto.new().generate_random_bytes(8).hex_encode()
			var parent: String = plan.get("parent", "")
			var level := next
			if not parent.is_empty():
				var container := _find(next, parent)
				if container.is_empty():
					return _failure("The parent piece no longer exists.")
				if not container.piece.has("children"):
					container.piece["children"] = []
				level = container.piece.children
			var piece: Dictionary = Types.types()[type].get("defaults", {}).duplicate(true)
			piece.merge(values.duplicate(true), true)
			piece.merge({"id": id, "type": type})
			if parent.is_empty() and not piece.has("position"):
				if placement.is_empty():
					return _failure("Aim at a surface or provide a position.")
				piece["position"] = placement
			if not _valid_position(piece.get("position", [0, 0, 0]), parent):
				return _failure("Place the piece inside this environment's bounds.")
			level.append(piece)
		"edit_piece":
			if entry.is_empty():
				return _failure("That piece no longer exists.")
			if values.has("position") and not _valid_position(values.position, entry.parent):
				return _failure("Place the piece inside this environment's bounds.")
			var previous: Dictionary = entry.piece
			var updated := previous.merged(values.duplicate(true), true)
			for key in values:
				if previous.get(key) is Dictionary and values[key] is Dictionary:
					updated[key] = previous[key].merged(values[key], true)
			entry.level[entry.index] = updated
		"remove_piece":
			if entry.is_empty():
				return _failure("That piece no longer exists.")
			entry.level.remove_at(entry.index)
	var undo: Array[Dictionary] = _document.history.duplicate()
	undo.append({"pieces": _document.pieces})
	return _save(next, undo, id, {"add_piece": "Piece added.", "edit_piece": "Piece updated.", "remove_piece": "Piece removed."}[plan.tool])

func _valid_position(position: Array, parent: String) -> bool:
	if not Commands.valid_field("position", position):
		return false
	var point := Vector3(position[0], position[1], position[2])
	var anchor := node_for(parent)
	if anchor:
		point = _layer.to_local(anchor.to_global(point))
	return Placement.contains(bounds, point)

func _list(id: String, offset: int) -> Dictionary:
	if not id.is_empty():
		var found := _find(_document.pieces, id)
		if found.is_empty():
			return _failure("That piece no longer exists.")
		var piece: Dictionary = found.piece.duplicate()
		var children: int = piece.get("children", []).size()
		piece.erase("children")
		return {"ok": true, "message": "Piece " + id, "piece": piece.duplicate(true), "parent": found.parent, "child_count": children}
	var items := summaries()
	var page := items.slice(offset, offset + PAGE_SIZE)
	var labels := PackedStringArray()
	for item in page.slice(0, 24):
		labels.append("%s (%s)" % [item.name, item.id])
	var message := "%d pieces in this environment." % items.size()
	if not labels.is_empty():
		message += " " + ", ".join(labels)
	return {"ok": true, "message": message, "pieces": page, "total": items.size(),
		"next_offset": offset + PAGE_SIZE if offset + PAGE_SIZE < items.size() else null,
		"can_undo": not _document.history.is_empty()}

func _save(next: Array, undo: Array[Dictionary], id: String, message: String) -> Dictionary:
	if next != _document.pieces:
		if not Types.valid_tree(next):
			return _failure("Check the selected piece type's required fields and field values.")
		if not _document.save(next, undo):
			return _failure("The environment piece document could not be saved.")
		_sync_display()
		revision += 1
		changed.emit()
	return {"ok": true, "message": message, "id": id}

static func _find(level: Array, id: String, parent := "") -> Dictionary:
	for index in level.size():
		var piece: Dictionary = level[index]
		if piece.id == id:
			return {"level": level, "index": index, "piece": piece, "parent": parent}
		var child := _find(piece.get("children", []), id, piece.id)
		if not child.is_empty():
			return child
	return {}

static func _summaries(level: Array, parent: String, items: Array[Dictionary]) -> void:
	for piece: Dictionary in level:
		items.append({"id": piece.id, "type": piece.type, "name": piece.get("name", piece.id), "parent": parent})
		_summaries(piece.get("children", []), piece.id, items)

static func _failure(message: String) -> Dictionary:
	return {"ok": false, "message": message}
