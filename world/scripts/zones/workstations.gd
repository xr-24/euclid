extends RefCounted
## App furniture is a presentation of an anchor; it never launches processes.
const Assets = preload("res://scripts/assets/asset_library.gd")

static func workstation(context: RefCounted, at: Vector3, zone: String) -> bool:
	var root: Node3D = context.build_root
	if zone == "villa":
		if Assets.place(root, "round_wooden_table_01", at, 0.0, 0.76) == null:
			return false
		_laptop(root, at + Vector3(0, 0.76, 0.02), 0.0)
		Assets.add_static_box(root, at + Vector3(0, 0.38, 0), Vector3(1.0, 0.76, 1.0))
		return true
	if zone == "beach":
		if Assets.place(root, "outdoor_table_chair_set_01", at, 90.0) == null:
			return false
		_laptop(root, at + Vector3(0, 0.72, 0.0), 0.0) # bistro table top height
		Assets.add_static_box(root, at + Vector3(0, 0.4, 0), Vector3(1.7, 0.8, 0.8))
		return true
	return false

static func _laptop(root: Node3D, at: Vector3, yaw_deg: float) -> void:
	var laptop := Assets.place(root, "classic_laptop", at, yaw_deg, 0.0, 0.52)
	if laptop == null:
		return
	var glow := OmniLight3D.new()
	glow.position = at + Vector3(0, 0.22, 0.12)
	glow.light_color = Color("bfe7ff")
	glow.light_energy = 0.35
	glow.omni_range = 1.2
	root.add_child(glow)
