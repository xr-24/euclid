extends RefCounted
## A model from the installed library or an imported (runtime) asset, with optional collision
## from its own meshes. A missing model leaves an empty marker so the document still loads.

const Library = preload("res://scripts/asset_library.gd")
const Runtime = preload("res://scripts/assets/runtime_assets.gd")
const Shared = preload("res://scripts/assets/asset_library.gd")

static func build(record: Dictionary) -> Node3D:
	var id := str(record.asset_id)
	var model: Node3D = null
	if record.source == "library":
		model = Library.instance(id)
	elif Runtime.valid_id(id):
		var packed := Runtime.scene(id)
		if packed != null:
			model = packed.instantiate() as Node3D
	if model == null:
		var missing := Node3D.new()
		missing.set_meta("asset_unavailable", true)
		return missing
	if record.get("collision", false):
		for child: Node in model.find_children("*", "MeshInstance3D", true, false):
			Shared.add_mesh_collision(child as MeshInstance3D)
	return model
