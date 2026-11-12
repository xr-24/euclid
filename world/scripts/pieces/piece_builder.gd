extends RefCounted
## Builds a tree of piece records into nodes. A factory makes each piece's node; the builder owns
## its transform, visibility, children and the metadata that lets editors find it again.

const Types = preload("res://scripts/pieces/piece_types.gd")
const Effects = preload("res://scripts/rendering/zone_effects.gd")
const LAYER := "EnvironmentPieces"

## Builds every piece under parent. Returns false, building nothing, if any record is invalid.
static func build(parent: Node3D, pieces: Variant) -> bool:
	if not Types.valid_tree(pieces):
		return false
	for record: Dictionary in pieces:
		_build(parent, record)
	return true

## Keep unrelated nodes and the children of a changed piece in place during a live edit.
static func sync(parent: Node3D, before: Array, after: Array) -> void:
	var previous := {}
	for record: Dictionary in before:
		previous[record.id] = record
	for record: Dictionary in after:
		var old: Dictionary = previous.get(record.id, {})
		previous.erase(record.id)
		if old == record:
			continue
		var node := parent.get_node_or_null("Piece_" + str(record.id)) as Node3D
		if node == null:
			_build(parent, record, true)
			continue
		var rebuilt: bool = old.type != record.type or Types.types()[record.type].fields.keys().any(
			func(key: String) -> bool: return old.get(key) != record.get(key))
		if rebuilt:
			var replacement := _make(record)
			parent.remove_child(node)
			Effects.make_constructible(replacement, false)
			parent.add_child(replacement)
			for child in node.get_children():
				if child.has_meta("piece_id"):
					node.remove_child(child)
					replacement.add_child(child)
			node.free()
			node = replacement
		else:
			_apply(node, record)
		sync(node, old.get("children", []), record.get("children", []))
	for id in previous:
		parent.get_node("Piece_" + id).free()

static func transform_of(record: Dictionary) -> Transform3D:
	var at := _vector(record.get("position", [0.0, 0.0, 0.0]))
	var turn := _vector(record.get("rotation", [0.0, 0.0, 0.0]))
	var size := _vector(record.get("scale", [1.0, 1.0, 1.0]))
	var basis := Basis.from_euler(Vector3(deg_to_rad(turn.x), deg_to_rad(turn.y), deg_to_rad(turn.z)))
	return Transform3D(basis * Basis.from_scale(size), at)

static func _build(parent: Node3D, record: Dictionary, live := false) -> Node3D:
	var node := _make(record)
	if live:
		Effects.make_constructible(node, false)
	parent.add_child(node)
	for child: Dictionary in record.get("children", []):
		_build(node, child, live)
	return node

static func _make(record: Dictionary) -> Node3D:
	var factory := Types.factory(str(record.type))
	var made: Variant = factory.call("build", record) if factory != null else null
	var node: Node3D = made if made is Node3D else Node3D.new()
	node.name = "Piece_" + str(record.id)
	node.set_meta("piece_id", record.id)
	node.set_meta("piece_type", record.type)
	_apply(node, record)
	return node

static func _apply(node: Node3D, record: Dictionary) -> void:
	node.transform = transform_of(record)
	node.visible = not record.get("hidden", false)
	node.process_mode = Node.PROCESS_MODE_INHERIT if node.visible else Node.PROCESS_MODE_DISABLED

static func _vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))
