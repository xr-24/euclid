extends RefCounted
## Draws decorative boxes in one batch. Instance positions are relative to the piece.

const MaterialFactory = preload("res://scripts/pieces/piece_material.gd")

static func build(record: Dictionary) -> Node3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.mesh = mesh
	batch.instance_count = record.instances.size()
	for index in record.instances.size():
		var item: Dictionary = record.instances[index]
		var rotation := _vector(item.rotation) * (PI / 180.0)
		var basis := Basis.from_euler(rotation).scaled_local(_vector(item.size))
		batch.set_instance_transform(index, Transform3D(basis, _vector(item.position)))
	var visual := MultiMeshInstance3D.new()
	visual.name = "Boxes"
	visual.multimesh = batch
	_apply_look(visual, record)
	var root := Node3D.new()
	root.add_child(visual)
	return root

static func update_fields(node: Node3D, old: Dictionary, record: Dictionary) -> bool:
	if old.instances != record.instances:
		return false
	_apply_look(node.get_node("Boxes"), record)
	return true

static func _apply_look(visual: MultiMeshInstance3D, record: Dictionary) -> void:
	visual.scale.y = float(record.get("height_scale", 1.0))
	visual.material_override = MaterialFactory.make(record.get("material", {}))
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if record.get("cast_shadow", true) \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

static func _vector(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))
