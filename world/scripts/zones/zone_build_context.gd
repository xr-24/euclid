extends RefCounted
## A private detached root per build. No live player, UI, network or scene-tree ownership.
const Villa = preload("res://scripts/zones/villa_zone.gd")
const Shore = preload("res://scripts/zones/shore_zone.gd")
const Workstations = preload("res://scripts/zones/workstations.gd")
const Effects = preload("res://scripts/rendering/zone_effects.gd")
## Trusted code registers builders here. Unregistered zone IDs use the neutral blockout.
const BUILDERS := {"villa": Villa, "beach": Shore}
var manifest: Dictionary
var build_root: Node3D
var build_interactables: Array[Dictionary] = []
var build_agent_labels: Dictionary = {}

func _init(definitions: Dictionary) -> void:
	manifest = definitions

func build(destination: String) -> Dictionary:
	build_root = Node3D.new()
	build_root.name = "Zone_" + destination
	build_interactables = []
	build_agent_labels = {}
	var zone := _zone(destination)
	var art := false
	var builder = BUILDERS.get(destination)
	if builder != null:
		art = builder.build(self)
	if not art:
		var floor_y := -0.26 if destination == "villa" else -0.2
		_box(Vector3(0,floor_y,0), Vector3(24,0.4,24), Color("69675c") if destination == "villa" else Color(zone.color))
		# Low boundary walls preserve the horizon while keeping the player on the floor.
		for x in [-12,12]:
			_box(Vector3(x,0.55,0), Vector3(0.25,1.1,24), Color(zone.color).darkened(0.09)).visible = destination != "beach"
		for z in [-12,12]:
			_box(Vector3(0,0.55,z), Vector3(24,1.1,0.25), Color(zone.color).darkened(0.09)).visible = destination != "beach"
		if destination == "construct":
			for x in range(-10,11,2):
				_box(Vector3(x,0.006,0), Vector3(0.015,0.01,23), Color("bdc6cf"), false)
				_box(Vector3(0,0.006,x), Vector3(23,0.01,0.015), Color("bdc6cf"), false)
		elif destination == "villa":
			for x in [-8,8]:
				for z in [-7,-2,3,8]:
					_column(Vector3(x,0,z))
		else:
			var sea := _box(Vector3(0,-0.12,-85), Vector3(300,0.1,150), Color("3b9cae"), false)
			var sea_material := ShaderMaterial.new()
			sea_material.shader = load("res://shaders/water.gdshader")
			sea_material.set_shader_parameter("water_color", Color("238b9a"))
			sea.material_override = sea_material
			for x in [-8,8]:
				_box(Vector3(x,1.6,-6), Vector3(0.3,3.2,0.3), Color("81654a"))
				for angle in [0,60,120]:
					var leaf := _box(Vector3(x,3.2,-6), Vector3(4.5,0.12,0.8), Color("538b69"), false)
					leaf.rotation_degrees.y = angle
	for anchor in manifest.anchors:
		if anchor.zone == destination:
			_add_anchor(anchor)
	# Every surface gets the construct effect built in now, so nothing is swapped later.
	Effects.make_constructible(build_root)
	return {"id": destination, "root": build_root, "interactables": build_interactables, "agent_labels": build_agent_labels}

## Build on a worker thread so the world keeps running.

func _material(color: Color, emissive := false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.75
	if emissive:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 0.6
	return mat

func _box(at: Vector3, size: Vector3, color: Color, collision := true) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _material(color)
	mesh.position = at
	build_root.add_child(mesh)
	if collision:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = size
		shape.shape = box_shape
		body.add_child(shape)
		mesh.add_child(body)
	return mesh

func _label3d(text: String, at: Vector3, color := Color.WHITE, size := 45) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.position = at
	label.font_size = size
	label.modulate = color
	label.outline_size = 3
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	build_root.add_child(label)
	return label

## Instant zone change (restoring a save, tests, captures). Travel uses _shift instead.

func _column(at: Vector3) -> void:
	var asset_path := "res://assets/generated/villa_column.glb"
	if ResourceLoader.exists(asset_path):
		var asset := load(asset_path) as PackedScene
		var instance := asset.instantiate() as Node3D
		build_root.add_child(instance)
		instance.position = at
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var collision := BoxShape3D.new()
		collision.size = Vector3(0.9,4.4,0.9)
		shape.shape = collision
		shape.position.y = 2.2
		body.add_child(shape)
		instance.add_child(body)
	else:
		_box(at + Vector3(0,2.2,0), Vector3(0.65,4.4,0.65), Color("f1dfbb"))
		_box(at + Vector3(0,0.15,0), Vector3(1.1,0.3,1.1), Color("e3c99b"))

func _add_anchor(anchor: Dictionary) -> void:
	var at := Vector3(anchor.position[0],anchor.position[1],anchor.position[2])
	var item := anchor.duplicate()
	item.position = at
	build_interactables.append(item)
	if anchor.kind == "application":
		if not Workstations.workstation(self, at, str(anchor.zone)):
			_box(at + Vector3(0,0.84,0), Vector3(1.9,0.09,0.85), Color("493b30"))
			for x in [-0.82,0.82]:
				_box(at + Vector3(x,0.41,0), Vector3(0.06,0.82,0.65), Color("252d34"))
			_box(at + Vector3(0,1.27,-0.12), Vector3(1.4,0.77,0.07), Color("192a33"), false)
			var screen := _box(at + Vector3(0,1.27,-0.075), Vector3(1.29,0.65,0.012), Color("3c7b82"), false)
			screen.material_override = _material(Color("36737a"), true)
			_box(at + Vector3(0,0.902,0.2), Vector3(0.58,0.018,0.2), Color("768088"), false)
	else:
		var avatar := MeshInstance3D.new()
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.33
		capsule.height = 1.65
		avatar.mesh = capsule
		avatar.material_override = _material(Color("6a86bd"))
		avatar.position = at + Vector3(0,0.85,0)
		build_root.add_child(avatar)
		build_agent_labels[anchor.agent_id] = _label3d(anchor.label, at + Vector3(0,2.2,0), Color("d8e7ff"), 30)
		build_agent_labels[anchor.agent_id].set_meta("name", anchor.label)

func _zone(id: String) -> Dictionary:
	for item in manifest.zones:
		if item.id == id:
			return item
	return manifest.zones[0]
