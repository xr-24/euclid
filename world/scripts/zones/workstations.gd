extends RefCounted
## App furniture is a presentation of an anchor; it never launches processes.
const Assets = preload("res://scripts/assets/asset_library.gd")
const Grid = preload("res://scripts/zones/grid_zone.gd")
const Props = preload("res://scripts/zones/authored_props.gd")
const Packages = preload("res://scripts/zones/zone_packages.gd")

static func build(root: Node3D, at: Vector3, anchor: Dictionary) -> Node3D:
	var station: Node3D
	var asset := "terminal"
	var style: String = Packages.definition(anchor.zone).workstation
	if style == "grid":
		station = Grid.workstation(root, at)
	else:
		station = Node3D.new()
		station.position = at
		root.add_child(station)
		var villa := style == "villa"
		asset = "round_wooden_table_01" if villa else "outdoor_table_chair_set_01"
		var table := Assets.place(station, asset, Vector3.ZERO, 0.0 if villa else 90.0, 0.76 if villa else 0.0)
		if table:
			_laptop(station, Vector3(0, 0.76, 0.02) if villa else Vector3(0, 0.72, 0.0))
			Assets.add_static_box(station, Vector3(0, 0.38, 0) if villa else Vector3(0, 0.4, 0),
				Vector3(1.0, 0.76, 1.0) if villa else Vector3(1.7, 0.8, 0.8))
		else:
			_fallback(station)
	Props.register(root, Props.stable_id("anchor", anchor.id), station, asset, 0.0, {"label": anchor.label})
	return station

static func _laptop(root: Node3D, at: Vector3) -> void:
	var laptop := Assets.place(root, "classic_laptop", at, 0.0, 0.0, 0.52)
	if laptop == null:
		return
	var glow := OmniLight3D.new()
	glow.position = at + Vector3(0, 0.22, 0.12)
	glow.light_color = Color("bfe7ff")
	glow.light_energy = 0.35
	glow.omni_range = 1.2
	root.add_child(glow)

static func _fallback(root: Node3D) -> void:
	_box(root, Vector3(0, 0.84, 0), Vector3(1.9, 0.09, 0.85), Color("493b30"), true)
	for x in [-0.82, 0.82]:
		_box(root, Vector3(x, 0.41, 0), Vector3(0.06, 0.82, 0.65), Color("252d34"), true)
	_box(root, Vector3(0, 1.27, -0.12), Vector3(1.4, 0.77, 0.07), Color("192a33"))
	_box(root, Vector3(0, 1.27, -0.075), Vector3(1.29, 0.65, 0.012), Color("36737a"), false, true)
	_box(root, Vector3(0, 0.902, 0.2), Vector3(0.58, 0.018, 0.2), Color("768088"))

static func _box(root: Node3D, at: Vector3, size: Vector3, color: Color, solid := false, emissive := false) -> void:
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = emissive
	material.emission = color
	visual.material_override = material
	root.add_child(visual)
	if solid:
		Assets.add_static_box(root, at, size)
