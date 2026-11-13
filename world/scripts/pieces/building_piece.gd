extends RefCounted
## A room footprint with walkable floors, wall openings, a roof and optional steps.
## The plan is measured from the floor surface at the piece origin.

const Shapes = preload("res://scripts/pieces/shape_piece.gd")
const Finishes = preload("res://scripts/pieces/piece_material.gd")
const Opening = preload("res://scripts/pieces/building_opening.gd")
const SIDES := ["front", "right", "back", "left"]
const FRAME := 0.055

static func valid_record(record: Dictionary) -> bool:
	var dims: Array = record.footprint
	var openings: Dictionary = record.get("openings", {})
	for side in openings:
		var spec: Dictionary = openings[side]
		var kind: String = spec.get("kind", "none")
		if kind == "none":
			continue
		var span: float = dims[0 if side in ["front", "back"] else 1]
		var width := float(spec.get("width", 1.1 if kind == "door" else 1.35))
		var height := float(spec.get("height", 2.05 if kind == "door" else 1.05))
		var sill := 0.0 if kind == "door" else float(spec.get("sill", 0.92))
		var center := float(spec.get("offset", 0.0))
		if absf(center) + width * 0.5 > span * 0.5 - 0.08 or height + sill > record.wall_height - 0.08:
			return false
		if spec.get("motion", "hinge") == "slide" and maxf(span * 0.5 - center, span * 0.5 + center) < width * 1.5 + 0.06:
			return false
	var steps: Dictionary = record.get("steps", {})
	if steps.get("enabled", false):
		return absf(float(steps.get("offset", 0))) + float(steps.get("width", 1.35)) * 0.5 <= float(dims[0]) * 0.5
	return true

static func build(record: Dictionary) -> Node3D:
	var root := Node3D.new()
	var footprint := Vector2(record.footprint[0], record.footprint[1])
	var height := float(record.wall_height)
	var thickness := float(record.get("wall_thickness", 0.16))
	var surface: Dictionary = record.get("material", {})
	var floor := Finishes.make(record.get("floor_material", {"color": "595864", "roughness": 0.75}))
	var wall := Finishes.make(surface)
	var roof := Finishes.make(record.get("roof_material", {"color": "535866", "roughness": 0.8}))
	var trim := Finishes.make({"color": "35424a", "roughness": 0.5})
	if record.get("floor", true):
		_box(root, Vector3(0, -0.09, 0), Vector3(footprint.x, 0.18, footprint.y), floor)
	if record.get("walls", true):
		var walls: Dictionary = record.get("openings", {})
		for index in SIDES.size():
			var side := Node3D.new()
			side.name = SIDES[index].capitalize()
			var direction := Vector3.FORWARD.rotated(Vector3.UP, -index * PI * 0.5)
			side.position = Vector3(direction.x * (footprint.x - thickness) * 0.5, 0,
				direction.z * (footprint.y - thickness) * 0.5)
			side.rotation.y = -index * PI * 0.5
			root.add_child(side)
			var span := footprint.x if index % 2 == 0 else footprint.y
			_wall(side, span, height, thickness, wall, trim, walls.get(SIDES[index], {}))
	var roof_kind: String = record.get("roof", "flat")
	if roof_kind == "flat":
		_box(root, Vector3(0, height + 0.09, 0), Vector3(footprint.x + 0.3, 0.18, footprint.y + 0.3), roof)
	elif roof_kind == "gable":
		_gable(root, footprint, height, float(record.get("roof_rise", 1.15)), roof, wall)
	var steps: Dictionary = record.get("steps", {})
	if steps.get("enabled", false):
		var stairs := build_steps(steps, floor)
		stairs.position = Vector3(float(steps.get("offset", 0)), -float(steps.get("rise", 0.6)), -footprint.y * 0.5)
		root.add_child(stairs)
	return root

static func update_fields(node: Node3D, before: Dictionary, after: Dictionary) -> bool:
	var previous := before.duplicate(true)
	var next := after.duplicate(true)
	for record in [previous, next]:
		for key in ["position", "rotation", "scale", "name", "hidden", "children"]:
			record.erase(key)
		for opening: Dictionary in record.get("openings", {}).values():
			opening.erase("open")
	if previous != next:
		return false
	for side in SIDES:
		var was: bool = before.get("openings", {}).get(side, {}).get("open", false)
		var opened: bool = after.get("openings", {}).get(side, {}).get("open", false)
		if was != opened:
			var part := node.get_node_or_null(NodePath(side.capitalize() + "/Opening")) as Opening
			if part:
				part.set_open(opened)
	return true

static func _wall(root: Node3D, span: float, height: float, depth: float, surface: Material, trim: Material, spec: Dictionary) -> void:
	var kind: String = spec.get("kind", "none")
	if kind == "none":
		_section(root, -span * 0.5, span * 0.5, 0.0, height, depth, surface)
		return
	var width := float(spec.get("width", 1.1 if kind == "door" else 1.35))
	var high := float(spec.get("height", 2.05 if kind == "door" else 1.05))
	var sill := 0.0 if kind == "door" else float(spec.get("sill", 0.92))
	var center := float(spec.get("offset", 0.0))
	var left := center - width * 0.5
	var right := center + width * 0.5
	_section(root, -span * 0.5, left, 0.0, height, depth, surface)
	_section(root, right, span * 0.5, 0.0, height, depth, surface)
	_section(root, left, right, sill + high, height, depth, surface)
	if sill > 0:
		_section(root, left, right, 0.0, sill, depth, surface)
	for x in [left + FRAME * 0.5, right - FRAME * 0.5]:
		_box(root, Vector3(x, sill + high * 0.5, 0), Vector3(FRAME, high, depth + 0.06), trim)
	_box(root, Vector3(center, sill + high - FRAME * 0.5, 0), Vector3(width, FRAME, depth + 0.06), trim)
	if kind == "window":
		_box(root, Vector3(center, sill + FRAME * 0.5, 0), Vector3(width, FRAME, depth + 0.11), trim)
	var opening := Opening.new()
	opening.name = "Opening"
	opening.position = Vector3(left + FRAME, sill + (FRAME if kind == "window" else 0.02), 0)
	root.add_child(opening)
	opening.configure(kind, spec.get("motion", "hinge"), width - FRAME * 2.0, high - FRAME * 2.0,
		depth, spec.get("open", false), 1.0 if center <= 0.0 else -1.0)

static func _section(root: Node3D, x0: float, x1: float, y0: float, y1: float, depth: float, material: Material) -> void:
	_box(root, Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, 0), Vector3(x1 - x0, y1 - y0, depth), material)

static func _gable(root: Node3D, dims: Vector2, base: float, rise: float, material: Material, wall: Material) -> void:
	var run := dims.x * 0.5 + 0.15
	var slope := atan2(rise, run)
	for side in [-1.0, 1.0]:
		var panel := _box(root, Vector3(side * run * 0.5, base + rise * 0.5, 0),
			Vector3(Vector2(run, rise).length(), 0.14, dims.y + 0.3), material)
		panel.rotation.z = -side * slope
	var half := dims.x * 0.5
	var end_rise := rise * half / run
	for end in [-1.0, 1.0]:
		var z: float = end * dims.y * 0.5
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var tri := [Vector3(-half, base, z), Vector3(0, base + end_rise, z), Vector3(half, base, z)]
		var reverse := tri.duplicate()
		reverse.reverse()
		for v: Vector3 in tri + reverse:
			surface.set_uv(Vector2(v.x, v.y))
			surface.add_vertex(v)
		surface.generate_normals()
		var panel := MeshInstance3D.new()
		panel.mesh = surface.commit()
		panel.material_override = wall
		root.add_child(panel)
		panel.create_trimesh_collision()

static func build_steps(spec: Dictionary, finish: Material) -> Node3D:
	var root := Node3D.new()
	var width := float(spec.get("width", 1.35))
	var rise := float(spec.get("rise", 0.6))
	var run := float(spec.get("run", 1.25))
	var count := int(spec.get("count", 4))
	for index in count:
		var length := run / count
		var y := rise * float(index + 1) / count
		var z := -run + length * (index + 0.5)
		_box(root, Vector3(0, y * 0.5, z), Vector3(width, y, length), finish, false)
	# A continuous ramp lets the ordinary player controller walk up the visible treads.
	var solid := StaticBody3D.new()
	var ramp := ConvexPolygonShape3D.new()
	var corners := PackedVector3Array()
	for x in [-width * 0.5, width * 0.5]:
		for point in [Vector3(x, 0.0, -run), Vector3(x, -0.08, -run), Vector3(x, 0, 0), Vector3(x, rise, 0)]:
			corners.append(point)
	ramp.points = corners
	var collision := CollisionShape3D.new()
	collision.shape = ramp
	solid.add_child(collision)
	root.add_child(solid)
	return root

static func _box(parent: Node3D, position: Vector3, size: Vector3, material: Material, collision := true) -> Node3D:
	var part := Shapes.build({"size": [size.x, size.y, size.z], "shape": "box", "collision": collision})
	(part.get_node("Mesh") as MeshInstance3D).material_override = material
	part.position = position
	parent.add_child(part)
	return part
