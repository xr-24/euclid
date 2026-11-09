extends RefCounted

const FLOOR_SHADER = preload("res://shaders/grid_floor.gdshader")
const Backdrop = preload("res://scripts/zones/grid_backdrop.gd")
const PLAYABLE_HALF_SIZE := 64.0

## Builds only into the detached zone root. Editing is attached separately on the main thread.
static func build(root: Node3D) -> bool:
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(640, 640)
	var material := ShaderMaterial.new()
	material.shader = FLOOR_SHADER
	var floor_visual := MeshInstance3D.new()
	floor_visual.mesh = floor_mesh
	floor_visual.material_override = material
	floor_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(floor_visual)

	var floor_body := StaticBody3D.new()
	floor_body.name = "GridFloor"
	root.add_child(floor_body)
	_box_collider(floor_body, Vector3(0, -0.2, 0), Vector3(128, 0.4, 128))
	for edge in [-PLAYABLE_HALF_SIZE, PLAYABLE_HALF_SIZE]:
		_box_collider(floor_body, Vector3(edge, 0.6, 0), Vector3(0.2, 1.2, 128))
		_box_collider(floor_body, Vector3(0, 0.6, edge), Vector3(128, 1.2, 0.2))

	Backdrop.build(root)
	return true

static func workstation(root: Node3D, at: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = "GridTerminal"
	body.position = at
	root.add_child(body)
	var casing := _material(Color("24191e"))
	var light := _material(Color("41141b"), Color("ff4a42"), 0.85)
	var display := _material(Color("1b0b10"), Color("40121a"), 0.42)
	_box_mesh(body, Vector3(0, 0.06, 0), Vector3(1.15, 0.12, 0.72), casing)
	_box_mesh(body, Vector3(0, 0.57, 0), Vector3(0.52, 0.94, 0.37), casing)
	_box_mesh(body, Vector3(0, 0.57, 0.191), Vector3(0.028, 0.9, 0.012), light)
	_box_mesh(body, Vector3(0, 1.27, 0), Vector3(1.36, 0.64, 0.15), casing)
	_box_mesh(body, Vector3(0, 1.27, 0.077), Vector3(1.27, 0.56, 0.012), display)
	_box_mesh(body, Vector3(0, 1.52, 0.085), Vector3(1.18, 0.012, 0.01), light)
	_box_collider(body, Vector3(0, 0.8, 0), Vector3(1.15, 1.6, 0.42))

static func _box_mesh(root: Node3D, at: Vector3, size: Vector3, material: Material) -> void:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(instance)

static func _material(color: Color, emission := Color.BLACK, energy := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = energy > 0.0
	material.emission = emission
	material.emission_energy_multiplier = energy
	return material

static func _box_collider(body: StaticBody3D, at: Vector3, size: Vector3) -> void:
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collider.shape = box
	collider.position = at
	body.add_child(collider)
