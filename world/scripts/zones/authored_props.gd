extends RefCounted
## Registers a detached builder-owned prop as a single editable unit.

const Assets = preload("res://scripts/assets/asset_library.gd")
const PICK_LAYER := 1 << 19

static func stable_id(scope: String, key: String) -> String:
	return ("dressing:" + scope + ":" + key).sha256_text().left(32)

static func place(root: Node3D, scope: String, key: String, asset: String, at: Vector3, yaw: float,
		height := 0.0, scale := 1.0, label := "") -> Node3D:
	var model := Assets.place(root, asset, at, yaw, height, scale)
	if model:
		register(root, stable_id(scope, key), model, asset, yaw, {"label": label})
	return model

## Add all model parts and colliders before registering it.
static func register(root: Node3D, id: String, node: Node3D, asset: String, yaw: float, options := {}) -> void:
	var entries: Dictionary = root.get_meta("authored_dressing", {})
	if node.get_parent() == null or entries.has(id):
		push_warning("Authored prop needs a unique ID and a parent: " + id)
		return
	var point: Array = options.get("position", [node.position.x, node.position.y, node.position.z])
	var record := {"id": id, "type": "authored_dressing", "asset_id": asset, "authored": true,
		"position": point.duplicate(), "yaw": yaw, "scale": 1.0, "color": "ffffff"}
	var label: String = options.get("label", "")
	if not label.is_empty():
		record["name"] = label
	var shapes := {}
	for child in node.find_children("*", "CollisionShape3D", true, false):
		var shape := child as CollisionShape3D
		var collider := shape.get_parent() as CollisionObject3D
		if collider:
			collider.set_meta("entity_id", id)
			if options.get("placement_surface", false):
				collider.set_meta("placement_surface", true)
			shapes[shape] = shape.disabled
	if shapes.is_empty():
		var picker := _add_picker(node)
		if picker:
			picker.get_parent().set_meta("entity_id", id)
			shapes[picker] = false
	var entry := {"record": record, "node": node, "shapes": shapes, "basis": node.basis}
	if not options.get("placement_surface", false) and not node.has_node("TerminalSurface"):
		entry["physics_bounds"] = _bounds(node, Transform3D.IDENTITY)
	if node is RigidBody3D:
		var parts := {}
		var boxes := {}
		for child in node.get_children():
			if child is Node3D:
				parts[child] = child.transform
			if child is CollisionShape3D and child.shape is BoxShape3D:
				boxes[child] = child.shape.size
				child.shape = child.shape.duplicate()
		entry["rigid"] = {"parts": parts, "boxes": boxes, "freeze": node.freeze}
	entries[id] = entry
	root.set_meta("authored_dressing", entries)

static func _add_picker(node: Node3D) -> CollisionShape3D:
	var bounds := _bounds(node, Transform3D.IDENTITY)
	if not bounds.has_surface():
		return null
	var area := Area3D.new()
	area.collision_layer = PICK_LAYER
	area.collision_mask = 0
	area.monitoring = false
	area.monitorable = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = bounds.size.max(Vector3.ONE * 0.02)
	shape.shape = box
	shape.position = bounds.get_center()
	area.add_child(shape)
	node.add_child(area)
	return shape

static func _bounds(node: Node3D, relative: Transform3D) -> AABB:
	var result: AABB = relative * node.get_aabb() if node is MeshInstance3D and node.mesh else AABB()
	for child in node.get_children():
		if child is Node3D:
			var box := _bounds(child, relative * child.transform)
			if box.has_surface():
				result = result.merge(box) if result.has_surface() else box
	return result
