extends RefCounted
## Places library models into a zone from a dressing file: plain data listing which model goes
## where, so a zone's statuary and props can be rearranged (or a new zone furnished) without
## code. Format (world/data/dressing/*.json, documented in world/data/dressing/README.md):
##
##   {
##     "schema_version": 1,
##     "plinths": {"statue": {"size": [0.9, 0.45, 0.9], "material": "marble"}},
##     "items": [
##       {"asset": "apollo_belvedere", "position": [x, y, z], "yaw": 90,
##        "plinth": "statue", "height": 2.0, "scale": 1.0, "collision": "box"}
##     ]
##   }
##
## position is the floor point the item (or its plinth) stands on; yaw turns its front (+Z) in
## degrees about Y; height rescales the model to that many metres, scale multiplies it.
## collision is "box" (default, a box around the model) or "none". Plinths are boxes in the named
## material; finish replaces all of the model's surfaces with a named material (e.g. bronze). The
## caller supplies the materials by name. Missing models are skipped, so a dressing
## still loads after a licence folder is removed.

const AssetLibrary = preload("res://scripts/asset_library.gd")

## Returns how many items were placed.
static func apply(root: Node3D, path: String, materials := {}) -> int:
	if not FileAccess.file_exists(path):
		return 0
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		push_warning("SceneDressing: %s is not valid JSON" % path)
		return 0
	var plinths: Dictionary = data.get("plinths", {})
	var placed := 0
	for item in data.get("items", []):
		if place_item(root, item, plinths, materials):
			placed += 1
	return placed

static func place_item(root: Node3D, item: Dictionary, plinths := {}, materials := {}) -> bool:
	var id := str(item.get("asset", ""))
	if not AssetLibrary.has(id):
		return false
	var p: Array = item.get("position", [0, 0, 0])
	var at := Vector3(p[0], p[1], p[2])
	var yaw := float(item.get("yaw", 0.0))
	var plinth: Dictionary = plinths.get(str(item.get("plinth", "")), {})
	if not plinth.is_empty():
		var s: Array = plinth.size
		var box := Vector3(s[0], s[1], s[2])
		_plinth(root, at, box, yaw, materials.get(str(plinth.get("material", "")), null))
		at.y += box.y
	var node := AssetLibrary.instance(id)
	var scale := float(item.get("scale", 1.0))
	var natural := AssetLibrary.size(id)
	if item.has("height") and natural.y > 0.0:
		scale *= float(item.height) / natural.y
	node.scale = Vector3.ONE * scale
	node.position = at
	node.rotation_degrees.y = yaw
	node.name = id
	var finish: Variant = materials.get(str(item.get("finish", "")))
	if finish is Material:
		for child in node.find_children("*", "MeshInstance3D", true, false):
			(child as MeshInstance3D).material_override = finish
	root.add_child(node)
	if str(item.get("collision", "box")) == "box":
		_collider(root, at, natural * scale, yaw)
	return true

static func _plinth(root: Node3D, at: Vector3, size: Vector3, yaw: float, material: Material) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	mesh.position = at + Vector3(0, size.y * 0.5, 0)
	mesh.rotation_degrees.y = yaw
	root.add_child(mesh)
	_collider(root, at, size, yaw)

static func _collider(root: Node3D, base: Vector3, size: Vector3, yaw: float) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = base + Vector3(0, size.y * 0.5, 0)
	body.rotation_degrees.y = yaw
	root.add_child(body)
