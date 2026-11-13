extends RefCounted

const Scatter = preload("res://scripts/scatter.gd")

static func build(record: Dictionary) -> Node3D:
	var root := Node3D.new()
	var transforms := []
	for item: Dictionary in record.model_instances:
		var p: Array = item.position
		var r: Array = item.rotation
		var s: Array = item.size
		var basis := Basis.from_euler(Vector3(deg_to_rad(r[0]), deg_to_rad(r[1]), deg_to_rad(r[2])))
		transforms.append(Transform3D(basis.scaled(Vector3(s[0], s[1], s[2])), Vector3(p[0], p[1], p[2])))
	Scatter.instance_many(root, record.asset_id, transforms, float(record.get("range", 90)), record.get("shadows", false))
	return root
