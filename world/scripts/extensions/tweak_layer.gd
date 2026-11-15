extends RefCounted
## Live tweaks: read and set any property of any node in the running world, then keep the result.
## A tweak names a node by its path from the world root and a property (a colon reaches into a
## resource the node holds, such as material_override:albedo_color). Tweaks made this session
## can be put back; kept ones live in data/tweaks.json, which applies whenever the world starts or
## an environment is built, and again when the file is hot loaded.

const FILE := "res://data/tweaks.json"
const MAX_TWEAKS := 512
const SIMPLE := [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME, TYPE_VECTOR2, TYPE_VECTOR3,
	TYPE_VECTOR4, TYPE_COLOR]

static var _world: Node
## "node|property" -> {"node", "property", "value" (JSON), "original" (Variant)}
static var _session := {}

static func attach(world: Node) -> void:
	_world = world
	_session.clear()

## A node's type, children and editable values.
static func inspect(target: String) -> Dictionary:
	var node := _node(target)
	if node == null:
		return {"ok": false, "message": "There is no node at %s." % (target if not target.is_empty() else "the world root")}
	var children := []
	for child in node.get_children():
		if children.size() >= 64:
			break
		children.append({"name": str(child.name), "type": child.get_class()})
	var values := {}
	for property in node.get_property_list():
		if values.size() >= 96:
			break
		if not property.usage & PROPERTY_USAGE_EDITOR:
			continue
		var value: Variant = node.get(property.name)
		if typeof(value) in SIMPLE:
			values[property.name] = _json(value)
		elif value is Material:
			# One level into materials, the resources tweaked most.
			for inner in value.get_property_list():
				if values.size() >= 96:
					break
				var sub: Variant = value.get(inner.name)
				if inner.usage & PROPERTY_USAGE_EDITOR and typeof(sub) in SIMPLE:
					values["%s:%s" % [property.name, inner.name]] = _json(sub)
	return {"ok": true, "message": "%s is a %s with %d children." % [_label(node), node.get_class(), node.get_child_count()],
		"target": _path(node), "type": node.get_class(), "children": children, "child_count": node.get_child_count(), "values": values}

## Set a property now. The value is converted to the property's type.
static func set_value(target: String, property: String, value: Variant) -> Dictionary:
	var node := _node(target)
	if node == null:
		return {"ok": false, "message": "There is no node at %s." % target}
	var current: Variant = node.get_indexed(NodePath(property))
	if current == null or typeof(current) not in SIMPLE:
		return {"ok": false, "message": "%s has no property %s that tweaks can set (numbers, true/false, text, vectors and colors)." % [_label(node), property]}
	var typed: Variant = _typed(value, current)
	if typed == null:
		return {"ok": false, "message": "%s takes %s." % [property, type_string(typeof(current))]}
	var key := "%s|%s" % [_path(node), property]
	if not _session.has(key):
		if _session.size() >= MAX_TWEAKS:
			return {"ok": false, "message": "Keep or discard this session's tweaks first."}
		_session[key] = {"node": _path(node), "property": property, "original": current}
	node.set_indexed(NodePath(property), typed)
	_session[key]["value"] = _json(node.get_indexed(NodePath(property)))
	return {"ok": true, "message": "Set %s of %s to %s." % [property, _label(node), JSON.stringify(_session[key].value)],
		"target": _path(node), "property": property, "value": _session[key].value}

static func session() -> Array:
	return _session.values().map(func(tweak: Dictionary) -> Dictionary:
		return {"node": tweak.node, "property": tweak.property, "value": tweak.value})

## Put every session tweak back as it was.
static func discard() -> Dictionary:
	var count := _session.size()
	for key in _session.keys():
		var tweak: Dictionary = _session[key]
		var node := _node(tweak.node)
		if node != null:
			node.set_indexed(NodePath(tweak.property), tweak.original)
	_session.clear()
	return {"ok": true, "message": "Put back %d tweak%s." % [count, "" if count == 1 else "s"]}

## The kept tweaks with this session's merged in, as the text of data/tweaks.json.
static func kept_text() -> String:
	var merged := {}
	for tweak: Dictionary in _read():
		merged["%s|%s" % [tweak.node, tweak.property]] = tweak
	for tweak: Dictionary in session():
		merged["%s|%s" % [tweak.node, tweak.property]] = tweak
	var keys := merged.keys()
	keys.sort()
	return JSON.stringify({"schema_version": 1, "about": "Property values set live with tweak_property and kept with keep_tweaks (scripts/extensions/tweak_layer.gd). Each names a node by its path from the world root. They apply when the world starts, when an environment is built, and when this file is hot loaded.",
		"tweaks": keys.map(func(key: String) -> Dictionary: return merged[key])}, "  ", false) + "\n"

## After a keep: the session's tweaks now live in the file's draft.
static func forget_session() -> void:
	_session.clear()

## Apply the kept tweaks to whatever nodes exist now. Missing nodes are skipped.
static func apply_kept() -> int:
	var applied := 0
	if _world == null or not is_instance_valid(_world):
		return 0
	for tweak: Dictionary in _read():
		var node := _node(str(tweak.node))
		if node == null:
			continue
		var current: Variant = node.get_indexed(NodePath(str(tweak.property)))
		var typed: Variant = _typed(tweak.get("value"), current) if current != null else null
		if typed != null:
			node.set_indexed(NodePath(str(tweak.property)), typed)
			applied += 1
	return applied

## Hot loading: a new tweaks file applies at once.
static func _hot_changed(paths: PackedStringArray) -> void:
	if FILE in paths:
		apply_kept()

static func _read() -> Array:
	# A hot load can leave the file empty where it did not exist before.
	var text := FileAccess.get_file_as_string(FILE) if FileAccess.file_exists(FILE) else ""
	var json := JSON.new()
	if text.strip_edges().is_empty() or json.parse(text) != OK:
		return []
	var data: Variant = json.data
	if not data is Dictionary or data.get("schema_version") != 1 or not data.get("tweaks") is Array:
		return []
	return data.tweaks.filter(func(tweak: Variant) -> bool:
		return tweak is Dictionary and tweak.get("node") is String and tweak.get("property") is String and tweak.has("value")).slice(0, MAX_TWEAKS)

static func _node(target: String) -> Node:
	if _world == null or not is_instance_valid(_world):
		return null
	if target.is_empty():
		return _world
	return _world.get_node_or_null(NodePath(target))

static func _path(node: Node) -> String:
	return "" if node == _world else str(_world.get_path_to(node))

static func _label(node: Node) -> String:
	return "the world" if node == _world else str(node.name)

static func _typed(value: Variant, current: Variant) -> Variant:
	match typeof(current):
		TYPE_BOOL:
			return value if value is bool else null
		TYPE_INT, TYPE_FLOAT:
			if not (value is float or value is int):
				return null
			return int(value) if typeof(current) == TYPE_INT else float(value)
		TYPE_STRING, TYPE_STRING_NAME:
			return str(value) if value is String else null
		TYPE_COLOR:
			if value is String:
				return Color.from_string(value, current) if Color.html_is_valid(value) else null
			if value is Array and value.size() in [3, 4] and value.all(func(item: Variant) -> bool: return item is float or item is int):
				return Color(value[0], value[1], value[2], value[3] if value.size() == 4 else current.a)
		TYPE_VECTOR2, TYPE_VECTOR3, TYPE_VECTOR4:
			var size: int = {TYPE_VECTOR2: 2, TYPE_VECTOR3: 3, TYPE_VECTOR4: 4}[typeof(current)]
			if value is Array and value.size() == size and value.all(func(item: Variant) -> bool: return item is float or item is int):
				return [Vector2(value[0], value[1]), Vector3(value[0], value[1], value[2]),
					Vector4(value[0], value[1], value[2], value[3]) if size == 4 else Vector4()][size - 2]
	return null

static func _json(value: Variant) -> Variant:
	match typeof(value):
		TYPE_FLOAT:
			return snappedf(value, 0.0001)
		TYPE_STRING_NAME:
			return str(value)
		TYPE_COLOR:
			return [snappedf(value.r, 0.0001), snappedf(value.g, 0.0001), snappedf(value.b, 0.0001), snappedf(value.a, 0.0001)]
		TYPE_VECTOR2:
			return [snappedf(value.x, 0.0001), snappedf(value.y, 0.0001)]
		TYPE_VECTOR3:
			return [snappedf(value.x, 0.0001), snappedf(value.y, 0.0001), snappedf(value.z, 0.0001)]
		TYPE_VECTOR4:
			return [snappedf(value.x, 0.0001), snappedf(value.y, 0.0001), snappedf(value.z, 0.0001), snappedf(value.w, 0.0001)]
	return value
