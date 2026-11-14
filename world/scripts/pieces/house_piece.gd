extends RefCounted
## A complete single-storey home built from a room plan: foundation, floors, walls with framed doors
## and windows, ceilings with lights, a roof, entrance steps, a patio deck and furniture.
## Styles (data/pieces/house_styles.json) set finishes and proportions. The entrance faces local -Z.

const Layout = preload("res://scripts/pieces/house_layout.gd")
const Building = preload("res://scripts/pieces/building_piece.gd")
const Shapes = preload("res://scripts/pieces/shape_piece.gd")
const Finishes = preload("res://scripts/pieces/piece_material.gd")
const Furniture = preload("res://scripts/pieces/house_furniture.gd")
const Water = preload("res://scripts/pieces/water_piece.gd")
const Opening = preload("res://scripts/pieces/building_opening.gd")
const Surfaces = preload("res://scripts/pieces/finishes.gd")
const STYLES_PATH := "res://data/pieces/house_styles.json"
const LINING := 0.016
## Thickness of a room's wall covering (tile, brick, panelling) laid over the wall face.
const COVER := 0.01
## Depth of the floor between storeys, from a ceiling below to the floor finish above.
const FLOOR_DEPTH := 0.3
## Height of stair and landing guards.
const GUARD := 1.0
## Stone between the house and the pool's edge.
const WALKWAY := 1.8
const LIGHT_COLOR := Color("ffd9ae")

static var _styles := _load_styles()

static func styles() -> Dictionary:
	return _styles

static func valid_record(record: Dictionary) -> bool:
	return _styles.has(str(record.get("style", "modern"))) and Layout.problem(record).is_empty()

## The style with the record's material overrides applied.
static func style_for(record: Dictionary) -> Dictionary:
	var style: Dictionary = _styles.get(str(record.get("style", "modern")), _styles.get("modern", {})).duplicate(true)
	var overrides: Dictionary = record.get("materials", {})
	for key: String in overrides:
		# A finish name replaces the style's material; a material spec is merged over it.
		if overrides[key] is String:
			style.materials[key] = Surfaces.spec(overrides[key]).duplicate(true)
			continue
		var base: Dictionary = Surfaces.spec(style.materials.get(key, {})).duplicate(true)
		base.merge(overrides[key], true)
		style.materials[key] = base
	return style

## The style's wall rules followed by the record's; later rules win. Each rule gives a finish (a
## finishes.json name) or a material for a room ("all", a room kind or a room name) and a
## side ("all", "feature", "front", "back", "left" or "right"), optionally only up to a height.
static func wall_rules(record: Dictionary, style: Dictionary) -> Array:
	var rules: Array = style.get("walls", []).duplicate(true)
	# A record's interior material repaints the whole house, over the style's paint.
	if record.get("materials", {}).has("interior"):
		rules.append({"material": Surfaces.spec(style.materials.interior)})
	rules.append_array(record.get("walls", []))
	return rules

## The rooms and walls a record produces, for agents and editors.
static func plan(record: Dictionary) -> Dictionary:
	var style := style_for(record)
	var list := Layout.rooms(record)
	var rooms := []
	for room: Dictionary in list:
		var rect: Rect2 = room.rect
		rooms.append({"name": room.name, "kind": room.kind, "level": room.level,
			"rect": [rect.position.x, rect.position.y, rect.end.x, rect.end.y], "area": snappedf(rect.get_area(), 0.1)})
	var floors := Layout.levels(list)
	var doors := 0
	var windows := 0
	for level in floors.size():
		for wall: Dictionary in Layout.walls(record, floors[level], style, level):
			for opening: Dictionary in wall.openings:
				if opening.kind == "window":
					windows += 1
				else:
					doors += 1
	var box := Layout.bounds(list)
	return {"rooms": rooms, "footprint": [snappedf(box.size.x, 0.01), snappedf(box.size.y, 0.01)],
		"storeys": floors.size(), "doors": doors, "windows": windows}

## Height of each floor above the house's base: one ceiling height and one floor depth per storey.
static func level_height(record: Dictionary, level: int) -> float:
	return float(record.get("foundation_height", 0.3)) + level * (float(record.get("ceiling_height", 2.7)) + FLOOR_DEPTH)

static func build(record: Dictionary) -> Node3D:
	var root := Node3D.new()
	var style := style_for(record)
	var list := Layout.rooms(record)
	if list.is_empty():
		return root
	var floors := Layout.levels(list)
	var look := _materials(style)
	var rules := wall_rules(record, style)
	var paint := _base_finish(rules)
	if not paint.is_empty():
		look["interior"] = Finishes.make(paint)
	var splash := Surfaces.spec(record.get("backsplash", style.get("backsplash", "")))
	if not splash.is_empty():
		look["backsplash"] = Finishes.make(splash)
	look["furnishings"] = record.get("furnishings", {})
	look["style_name"] = str(record.get("style", "modern"))
	look["light_energy"] = float(record.get("light_energy", 1.0))
	look["light_color"] = Color.html(str(record.get("light_color", LIGHT_COLOR.to_html(false))))
	var floor_y := float(record.get("foundation_height", 0.3))
	var ceiling := float(record.get("ceiling_height", 2.7))
	var outer := float(style.get("exterior_wall", 0.3))
	var inner := float(style.get("interior_wall", 0.12))
	var storey := ceiling + FLOOR_DEPTH
	var top := floors.size() - 1
	# Floors, walls, ceilings and furniture hold one "Level<n>" node per storey, so a view can cut
	# the house away above any floor; each is batched on its own.
	var parts := {}
	for part: String in ["Floors", "Walls", "Ceilings", "Furniture"]:
		if part == "Furniture" and not record.get("furnish", true):
			continue
		var node := Node3D.new()
		node.name = part
		root.add_child(node)
		parts[part] = node
	var roof := Node3D.new()
	roof.name = "Roof"
	var ground_walls: Array[Dictionary] = []
	for level in floors.size():
		var rooms: Array[Dictionary] = floors[level]
		var below: Array = floors[level - 1] if level > 0 else []
		var above: Array = floors[level + 1] if level < top else []
		var y := floor_y + level * storey
		var walls := Layout.walls(record, rooms, style, level)
		if level == 0:
			ground_walls = walls
		var sides := Layout.room_sides(rooms, walls, outer, inner)
		var base := _level(parts.Floors, level, 0.0)
		if level == 0:
			_foundation(base, rooms, floor_y, outer, look)
		_floors(base, record, style, rooms, below, y, inner, look)
		var shell := _level(parts.Walls, level, y)
		for index in walls.size():
			_wall(shell, walls[index], index, ceiling, outer, inner, look, level < top)
		_ceilings(_level(parts.Ceilings, level, 0.0), rooms, above, y + ceiling, inner, look, record.get("lights", true))
		for room: Dictionary in sides:
			var info: Dictionary = rooms[room.index]
			if not Layout.stairwell(above, info).is_empty():
				_stair(shell, record, style, room, storey, look)
			elif not Layout.stairwell(below, info).is_empty():
				_guards(shell, room, look)
		if level == top:
			_roof(roof, record, style, rooms, walls, y + ceiling, outer, look)
		else:
			_terraces(roof, rooms, above, y + ceiling, storey - ceiling, outer, look)
		var focus := {}
		if parts.has("Furniture"):
			focus = Furniture.furnish(_level(parts.Furniture, level, y), sides, ceiling, look)
		_cover(shell, sides, rules, paint, focus, ceiling)
	root.add_child(roof)
	_outside(root, record, ground_walls, floor_y, outer, look)
	_grounds(root, ground_walls, floor_y, ceiling, outer, style, look)
	# Batch each part (each storey of it) separately, so the roof, ceilings or upper floors can be hidden.
	for part: Node in root.get_children():
		var levels := part.get_children().filter(func(child: Node) -> bool: return str(child.name).begins_with("Level"))
		for node: Node in (levels if not levels.is_empty() else [part]):
			if node is Node3D:
				_batch(node)
	return root

static func _level(parent: Node3D, level: int, y: float) -> Node3D:
	var node := Node3D.new()
	node.name = "Level%d" % level
	node.position.y = y
	parent.add_child(node)
	return node

## Merge the house's many still, opaque surfaces into one mesh per material so it draws in a few
## calls. Collision bodies, doors and windows that move, lights and water stay as they are.
static func _batch(root: Node3D) -> void:
	var groups := {}
	for found: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := found as MeshInstance3D
		var material := mesh.material_override as BaseMaterial3D
		if material == null or mesh.mesh == null or material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED \
				or _moves(mesh, root):
			continue
		var key := [material, mesh.cast_shadow]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(mesh)
	var index := 0
	for key: Array in groups:
		var meshes: Array = groups[key]
		if meshes.size() < 2:
			continue
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		for mesh: MeshInstance3D in meshes:
			var placed := mesh.transform
			var parent := mesh.get_parent() as Node3D
			while parent != root:
				placed = parent.transform * placed
				parent = parent.get_parent() as Node3D
			for surface in mesh.mesh.get_surface_count():
				tool.append_from(mesh.mesh, surface, placed)
		var merged := MeshInstance3D.new()
		merged.name = "Batch%d" % index
		index += 1
		merged.mesh = tool.commit()
		merged.material_override = key[0]
		merged.cast_shadow = key[1]
		root.add_child(merged)
		for mesh: MeshInstance3D in meshes:
			mesh.get_parent().remove_child(mesh)
			mesh.free()

static func _moves(node: Node, root: Node) -> bool:
	var at := node.get_parent()
	while at != null and at != root:
		if at is Opening or at is AnimatableBody3D:
			return true
		at = at.get_parent()
	return false

static func _materials(style: Dictionary) -> Dictionary:
	var look := {}
	var specs: Dictionary = style.get("materials", {})
	for key: String in specs:
		look[key] = Finishes.make(Surfaces.spec(specs[key]))
	for key in ["exterior", "interior", "ceiling", "plinth", "trim", "baseboard", "roof", "fascia", "door",
			"entry_door", "glass", "frosted", "accent"]:
		if not look.has(key):
			look[key] = Finishes.make({})
	var hardware := Finishes.make({"color": "b9bcbe", "roughness": 0.3, "metallic": 0.9})
	var muntins: bool = style.get("muntins", false)
	look["finishes"] = {"glass": {"glass": look.glass, "frame": look.trim, "muntins": muntins},
		"frosted": {"glass": look.frosted},
		"interior": {"leaf": look.door, "hardware": hardware},
		"entry": {"leaf": look.entry_door, "hardware": hardware},
		"glazed": {"leaf": look.glass, "frame": look.trim, "hardware": hardware, "muntins": muntins}}
	look["fixture"] = Finishes.make({"color": "fff4e2", "emission": "ffe2bd", "emission_energy": 2.2})
	return look

static func _foundation(root: Node3D, list: Array[Dictionary], floor_y: float, outer: float, look: Dictionary) -> void:
	var base := -0.3
	for room: Dictionary in list:
		var rect: Rect2 = (room.rect as Rect2).grow(outer * 0.5 + 0.04)
		_box(root, Vector3(rect.get_center().x, (base + floor_y - 0.05) * 0.5, rect.get_center().y),
			Vector3(rect.size.x, floor_y - 0.05 - base, rect.size.y), look.plinth)

## Each room's floor finish; upstairs, the floor structure under it too. A stairwell over a stair
## has no floor.
static func _floors(root: Node3D, record: Dictionary, style: Dictionary, list: Array[Dictionary], below: Array, floor_y: float,
		inner: float, look: Dictionary) -> void:
	for room: Dictionary in list:
		if not Layout.stairwell(below, room).is_empty():
			continue
		var rect: Rect2 = (room.rect as Rect2).grow(inner * 0.5)
		var finish := Finishes.make(floor_finish(record, style, room))
		var slab := _box(root, Vector3(rect.get_center().x, floor_y - 0.03, rect.get_center().y),
			Vector3(rect.size.x, 0.06, rect.size.y), finish)
		slab.name = "Floor_" + str(room.name).replace(" ", "")
		if not below.is_empty():
			var depth := FLOOR_DEPTH - 0.12
			_box(root, Vector3(rect.get_center().x, floor_y - 0.06 - depth * 0.5, rect.get_center().y),
				Vector3(rect.size.x, depth, rect.size.y), look.ceiling)

static func _wall(parent: Node3D, wall: Dictionary, index: int, ceiling: float, outer: float, inner: float, look: Dictionary,
		through := false) -> void:
	var exterior: bool = wall.exterior
	var thickness := outer if exterior else inner
	var from := float(wall.from) - (outer * 0.5 if exterior else 0.0)
	var to := float(wall.to) + (outer * 0.5 if exterior else 0.0)
	var middle := (from + to) * 0.5
	var span := to - from
	var node := Node3D.new()
	node.name = ("Exterior%d" if exterior else "Interior%d") % index
	if int(wall.axis) == 0:
		node.position = Vector3(middle, 0, float(wall.line))
	else:
		node.position = Vector3(float(wall.line), 0, middle)
		node.rotation.y = -PI * 0.5
	parent.add_child(node)
	# Outside walls run up past the floor above to meet the next storey's walls.
	var height := ceiling + ((FLOOR_DEPTH if through else 0.06) if exterior else 0.0)
	var specs := _specs(wall.openings, middle, span, height)
	var trim: Material = look.trim if exterior else look.baseboard
	Building.wall(node, span, height, thickness, look.exterior if exterior else look.interior, trim, specs, look.finishes)
	if not exterior:
		return
	# Paint the inside face: a thin lining with the same openings, framed by the wall's reveals.
	var lining := Node3D.new()
	lining.name = "Lining"
	var normal: Vector2 = wall.normal
	var depth := outer * 0.5 + LINING * 0.5
	lining.position.z = -normal.y * depth if int(wall.axis) == 0 else normal.x * depth
	node.add_child(lining)
	var inside := span - outer * 2.0
	if inside < 0.3:
		return
	var holes := []
	for spec: Dictionary in specs:
		holes.append({"kind": "archway", "offset": float(spec.offset), "width": float(spec.width),
			"height": float(spec.height), "sill": float(spec.get("sill", 0.0))})
	Building.wall(lining, inside, ceiling, LINING, look.interior, look.interior, holes)

## Opening specs for the shared wall builder, dropping windows that do not fit.
static func _specs(openings: Array, middle: float, span: float, height: float) -> Array:
	var specs := []
	for opening: Dictionary in openings:
		var spec := {"kind": opening.kind, "offset": float(opening.at) - middle, "width": float(opening.width),
			"height": float(opening.height), "motion": opening.get("motion", "hinge"), "finish": opening.get("finish", "")}
		if opening.kind == "window":
			spec["sill"] = float(opening.get("sill", 0.9))
		specs.append(spec)
	while not specs.is_empty() and not Building.valid_wall_openings(span, height, specs):
		var dropped := false
		for index in range(specs.size() - 1, -1, -1):
			if specs[index].kind == "window":
				specs.remove_at(index)
				dropped = true
				break
		if not dropped:
			specs.pop_back()
	return specs

static func _ceilings(root: Node3D, list: Array[Dictionary], above: Array, top: float, inner: float, look: Dictionary,
		lights: bool) -> void:
	for room: Dictionary in list:
		# A stair rises through the ceiling of its stairwell.
		if not Layout.stairwell(above, room).is_empty():
			continue
		var rect: Rect2 = (room.rect as Rect2).grow(inner * 0.5)
		var centre := rect.get_center()
		_box(root, Vector3(centre.x, top + 0.03, centre.y), Vector3(rect.size.x, 0.06, rect.size.y), look.ceiling)
		if not lights:
			continue
		var area := rect.get_area()
		var count := 1 if area < 14.0 else 2
		var long_x := rect.size.x >= rect.size.y
		for index in count:
			var t := (index + 0.5) / count
			var at := Vector2(lerpf(rect.position.x, rect.end.x, t), centre.y) if long_x else \
				Vector2(centre.x, lerpf(rect.position.y, rect.end.y, t))
			var fixture := MeshInstance3D.new()
			var disc := CylinderMesh.new()
			disc.top_radius = 0.16
			disc.bottom_radius = 0.16
			disc.height = 0.025
			fixture.mesh = disc
			fixture.material_override = look.fixture
			fixture.position = Vector3(at.x, top - 0.0125, at.y)
			fixture.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(fixture)
			# A wide downward spot lights the room without leaking onto the roof and eaves.
			# Shadowed, so each room's light stays in that room instead of washing through walls.
			var lamp := SpotLight3D.new()
			lamp.light_color = look.light_color
			lamp.light_energy = clampf(area / float(count) / 6.0, 1.2, 3.0) * float(look.light_energy)
			lamp.light_indirect_energy = 1.5
			lamp.light_size = 0.12
			lamp.shadow_enabled = true
			lamp.shadow_bias = 0.04
			lamp.spot_range = 4.5
			lamp.spot_angle = 78.0
			lamp.spot_attenuation = 0.8
			lamp.rotation.x = -PI * 0.5
			lamp.position = Vector3(at.x, top - 0.05, at.y)
			root.add_child(lamp)

static func _roof(root: Node3D, record: Dictionary, style: Dictionary, list: Array[Dictionary], walls: Array[Dictionary],
		top: float, outer: float, look: Dictionary) -> void:
	var kind := str(record.get("roof", "style"))
	if kind == "style":
		kind = str(style.get("roof", "flat"))
	if kind == "none":
		return
	if kind == "gable" and not Layout.is_rectangle(list):
		kind = "flat"
	var base := top + 0.06
	if kind == "gable":
		_gable(root, Layout.bounds(list).grow(outer * 0.5), base, float(style.get("roof_pitch", 0.6)),
			float(style.get("eaves", 0.45)), look)
		return
	var eaves := float(style.get("eaves", 0.5)) if kind == "flat" else 0.0
	var slab := 0.3
	for room: Dictionary in list:
		var rect: Rect2 = (room.rect as Rect2).grow(outer * 0.5 + eaves)
		_box(root, Vector3(rect.get_center().x, base + slab * 0.5, rect.get_center().y),
			Vector3(rect.size.x, slab, rect.size.y), look.fascia)
		var membrane := rect.grow(-0.08) if eaves > 0.0 else (room.rect as Rect2).grow(outer * 0.5 - 0.02)
		_box(root, Vector3(membrane.get_center().x, base + slab + 0.01, membrane.get_center().y),
			Vector3(membrane.size.x, 0.02, membrane.size.y), look.roof, false)
	if kind != "parapet":
		return
	var rise := 0.55
	for wall: Dictionary in walls:
		if not wall.exterior:
			continue
		var from := float(wall.from) - outer * 0.5
		var to := float(wall.to) + outer * 0.5
		var middle := (from + to) * 0.5
		var length := to - from
		var y := base + slab + rise * 0.5
		var size := Vector3(length, rise, outer) if int(wall.axis) == 0 else Vector3(outer, rise, length)
		var at := Vector3(middle, y, float(wall.line)) if int(wall.axis) == 0 else Vector3(float(wall.line), y, middle)
		_box(root, at, size, look.exterior)
		var cap := Vector3(size.x + (0.06 if int(wall.axis) == 1 else 0.0), 0.05, size.z + (0.06 if int(wall.axis) == 0 else 0.0))
		_box(root, at + Vector3(0, rise * 0.5 + 0.025, 0), cap, look.fascia, false)
		if style.get("vigas", false) and int(wall.axis) == 0:
			var normal: Vector2 = wall.normal
			var count := int(length / 1.1)
			for beam in count:
				var x := from + 0.55 + beam * (length - 1.1) / maxf(count - 1, 1)
				var viga := MeshInstance3D.new()
				var log := CylinderMesh.new()
				log.top_radius = 0.1
				log.bottom_radius = 0.11
				log.height = 0.6
				viga.mesh = log
				viga.material_override = look.accent
				viga.rotation.x = PI * 0.5
				viga.position = Vector3(x, base + 0.12, float(wall.line) + normal.y * (outer * 0.5 + 0.22))
				root.add_child(viga)

## A U-shaped stair rising one storey inside a stairwell: a first flight from the open side (where
## the hall is) to a landing at the back, and a second flight returning to arrive on the same side.
static func _stair(parent: Node3D, record: Dictionary, style: Dictionary, room: Dictionary, rise: float, look: Dictionary) -> void:
	var entry := _stair_entry(room)
	var clear: Dictionary = room.clear
	var normal: Vector2 = entry.normal
	var inward := Vector3(-normal.x, 0, -normal.y)
	var axis := int(entry.axis)
	var low := float(clear.x0) if axis == 0 else float(clear.z0)
	var high := float(clear.x1) if axis == 0 else float(clear.z1)
	var depth := float(clear.z1) - float(clear.z0) if axis == 0 else float(clear.x1) - float(clear.x0)
	var width := high - low
	var middle := (low + high) * 0.5
	var holder := Node3D.new()
	holder.name = "Stair"
	holder.position = (Vector3(middle, 0, float(entry.face)) if axis == 0 else Vector3(float(entry.face), 0, middle))
	holder.rotation.y = atan2(inward.x, inward.z)
	parent.add_child(holder)
	# Plan positions along the entry side map to local X with this sign.
	var local_x := Vector3(cos(holder.rotation.y), 0, -sin(holder.rotation.y))
	var sign := local_x.x if axis == 0 else local_x.z
	var risers := ceili(rise / 0.185)
	var riser := rise / risers
	var first := ceili(risers * 0.5)
	var second := risers - first
	var flight := minf(1.2, (width - 0.04) * 0.5)
	var tread := clampf((depth - flight) / first, 0.2, 0.3)
	var landing := first * tread
	var lift := first * riser
	var a_x := (low + flight * 0.5 - middle) * sign
	var b_x := (high - flight * 0.5 - middle) * sign
	var finish := Finishes.make(floor_finish(record, style, room))
	var up := Building.build_steps({"width": flight, "rise": lift, "run": landing, "count": first}, finish)
	up.position = Vector3(a_x, 0, landing)
	holder.add_child(up)
	_box(holder, Vector3(0, lift * 0.5, (landing + depth) * 0.5), Vector3(width, lift, depth - landing), finish)
	var gap := landing - second * tread
	var back := Building.build_steps({"width": flight, "rise": rise - lift, "run": second * tread, "count": second}, finish)
	back.position = Vector3(b_x, lift, gap)
	back.rotation.y = PI
	holder.add_child(back)
	# Closed underneath the second flight, and a short landing at the top where it stops short.
	_box(holder, Vector3(b_x, lift * 0.5, (gap + landing) * 0.5), Vector3(flight, lift, second * tread), look.interior)
	if gap > 0.01:
		_box(holder, Vector3(b_x, rise - FLOOR_DEPTH * 0.5, gap * 0.5), Vector3(flight, FLOOR_DEPTH, gap), finish)

## The stairwell side open to the hall, where the stair starts and arrives: the side with the most
## wall-free length.
static func _stair_entry(room: Dictionary) -> Dictionary:
	var best: Dictionary = room.sides[0]
	var most := -1.0
	for side: Dictionary in room.sides:
		var open := float(side.high) - float(side.low)
		for span: Array in side.solid:
			open -= maxf(0.0, minf(float(side.high), float(span[1])) - maxf(float(side.low), float(span[0])))
		if open > most + 0.01:
			most = open
			best = side
	return best

## Guards around a stairwell on the floor above the stair, leaving the top of the stair open.
static func _guards(parent: Node3D, room: Dictionary, look: Dictionary) -> void:
	var entry := _stair_entry(room)
	var clear: Dictionary = room.clear
	var axis_entry := int(entry.axis)
	var low_entry := float(clear.x0) if axis_entry == 0 else float(clear.z0)
	var high_entry := float(clear.x1) if axis_entry == 0 else float(clear.z1)
	var flight := minf(1.2, (high_entry - low_entry - 0.04) * 0.5)
	for side: Dictionary in room.sides:
		var spans := [[float(side.low), float(side.high)]]
		for span: Array in side.solid:
			spans = Layout._cut(spans, float(span[0]), float(span[1]))
		if side == entry:
			spans = Layout._cut(spans, high_entry - flight - 0.02, high_entry + 0.01)
		var normal: Vector2 = side.normal
		var inward := Vector3(-normal.x, 0, -normal.y)
		for span: Array in spans:
			var length: float = span[1] - span[0]
			if length < 0.1:
				continue
			var middle: float = (span[0] + span[1]) * 0.5
			var at := (Vector3(middle, 0, float(side.face)) if int(side.axis) == 0 else Vector3(float(side.face), 0, middle)) + inward * 0.03
			var guard := Node3D.new()
			guard.name = "Guard"
			guard.position = at
			guard.rotation.y = atan2(inward.x, inward.z)
			parent.add_child(guard)
			_box(guard, Vector3(0, GUARD - 0.025, 0), Vector3(length, 0.05, 0.05), look.trim)
			_box(guard, Vector3(0, 0.08, 0), Vector3(length, 0.04, 0.04), look.trim, false)
			var posts := maxi(1, ceili(length / 1.2))
			for index in posts + 1:
				_box(guard, Vector3(-length * 0.5 + length * index / posts, GUARD * 0.5, 0), Vector3(0.04, GUARD, 0.04), look.trim, false)
			_box(guard, Vector3(0, (GUARD + 0.1) * 0.5, 0), Vector3(length, GUARD - 0.15, 0.012), look.glass)

## Flat roofs over rooms that have no floor above them, level with the next floor: a terrace.
static func _terraces(root: Node3D, list: Array[Dictionary], above: Array, ceiling_y: float, depth: float, outer: float,
		look: Dictionary) -> void:
	for room: Dictionary in list:
		if Layout.supported(above, room.rect):
			continue
		var rect: Rect2 = (room.rect as Rect2).grow(outer * 0.5)
		var bottom := ceiling_y + 0.06
		var top := ceiling_y + depth - 0.08
		_box(root, Vector3(rect.get_center().x, (bottom + top) * 0.5, rect.get_center().y), Vector3(rect.size.x, top - bottom, rect.size.y), look.fascia)
		_box(root, Vector3(rect.get_center().x, top + 0.01, rect.get_center().y), Vector3(rect.size.x - 0.04, 0.02, rect.size.y - 0.04), look.roof, false)

static func _gable(root: Node3D, box: Rect2, base: float, pitch: float, eaves: float, look: Dictionary) -> void:
	var along_x := box.size.x >= box.size.y
	var half := (box.size.y if along_x else box.size.x) * 0.5
	var length := (box.size.x if along_x else box.size.y) + eaves * 2.0
	var angle := atan(pitch)
	var run := half + eaves
	var slope := run / cos(angle)
	var centre := box.get_center()
	var thickness := 0.16
	for side: float in [-1.0, 1.0]:
		var drop := eaves * pitch
		var mid_y := base - drop + (half * pitch + drop) * 0.5 + thickness * 0.5
		var offset := side * run * 0.5
		var panel := _box(root, Vector3.ZERO, Vector3(length, thickness, slope) if along_x else Vector3(slope, thickness, length), look.roof)
		if along_x:
			panel.position = Vector3(centre.x, mid_y, centre.y + offset)
			panel.rotation.x = side * angle
		else:
			panel.position = Vector3(centre.x + offset, mid_y, centre.y)
			panel.rotation.z = -side * angle
		var fascia := Vector3(length, 0.2, 0.04) if along_x else Vector3(0.04, 0.2, length)
		var edge := Vector3(centre.x, base - drop - 0.02, centre.y + side * (run + 0.02)) if along_x else \
			Vector3(centre.x + side * (run + 0.02), base - drop - 0.02, centre.y)
		_box(root, edge, fascia, look.fascia, false)
	# Gable ends: wall-coloured triangles closing the attic over each end wall.
	for end: float in [-1.0, 1.0]:
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var top := base + half * pitch
		var points: Array[Vector3] = []
		if along_x:
			var x := centre.x + end * box.size.x * 0.5
			points = [Vector3(x, base, centre.y - half), Vector3(x, top, centre.y), Vector3(x, base, centre.y + half)]
		else:
			var z := centre.y + end * box.size.y * 0.5
			points = [Vector3(centre.x - half, base, z), Vector3(centre.x, top, z), Vector3(centre.x + half, base, z)]
		var both: Array[Vector3] = points.duplicate()
		var back := points.duplicate()
		back.reverse()
		both.append_array(back)
		for point: Vector3 in both:
			surface.set_uv(Vector2(point.x + point.z, point.y))
			surface.add_vertex(point)
		surface.generate_normals()
		var gable := MeshInstance3D.new()
		gable.mesh = surface.commit()
		gable.material_override = look.exterior
		root.add_child(gable)
	# Close the gap between the wall tops and the roof slope along the eaves.
	var soffit := Vector3(length, 0.04, eaves + 0.02) if along_x else Vector3(eaves + 0.02, 0.04, length)
	for side: float in [-1.0, 1.0]:
		var at := Vector3(centre.x, base - 0.02, centre.y + side * (half + eaves * 0.5)) if along_x else \
			Vector3(centre.x + side * (half + eaves * 0.5), base - 0.02, centre.y)
		_box(root, at, soffit, look.fascia, false)

## Entrance steps with a landing, and a timber deck outside a patio door.
static func _outside(root: Node3D, record: Dictionary, walls: Array[Dictionary], floor_y: float, outer: float, look: Dictionary) -> void:
	for wall: Dictionary in walls:
		if not wall.exterior:
			continue
		var normal: Vector2 = wall.normal
		for opening: Dictionary in wall.openings:
			var along := float(opening.at)
			var face := float(wall.line) + outer * 0.5 * (normal.y if int(wall.axis) == 0 else normal.x)
			var point := Vector2(along, face) if int(wall.axis) == 0 else Vector2(face, along)
			var turn := atan2(-normal.x, -normal.y)
			if opening.get("entrance", false):
				var landing := 1.3
				var width := float(opening.width) + 1.0
				var stoop := Node3D.new()
				stoop.name = "Entrance"
				stoop.position = Vector3(point.x, 0, point.y)
				stoop.rotation.y = turn
				root.add_child(stoop)
				_box(stoop, Vector3(0, (floor_y - 0.3) * 0.5, -landing * 0.5), Vector3(width, floor_y + 0.3, landing), look.plinth)
				if floor_y >= 0.12:
					var count := ceili(floor_y / 0.17)
					var steps := Building.build_steps({"width": width, "rise": floor_y, "run": 0.3 * count, "count": count}, look.plinth)
					steps.position.z = -landing
					stoop.add_child(steps)
			elif opening.get("patio", false) and record.get("pool", false):
				_pool_terrace(root, record, Vector3(point.x, 0, point.y), turn, float(opening.width), floor_y)
			elif opening.get("patio", false):
				var deck := Node3D.new()
				deck.name = "Deck"
				deck.position = Vector3(point.x, 0, point.y)
				deck.rotation.y = turn
				root.add_child(deck)
				var width := float(opening.width) + 2.4
				var depth := 3.2
				_box(deck, Vector3(0, floor_y - 0.06, -depth * 0.5), Vector3(width, 0.1, depth), look.accent)
				for post_x: float in [-width * 0.5 + 0.15, 0.0, width * 0.5 - 0.15]:
					_box(deck, Vector3(post_x, (floor_y - 0.11) * 0.5 - 0.1, -depth + 0.15), Vector3(0.12, floor_y + 0.09, 0.12), look.accent, false)
				if floor_y >= 0.2:
					var count := ceili(floor_y / 0.17)
					var steps := Building.build_steps({"width": 1.6, "rise": floor_y - 0.01, "run": 0.3 * count, "count": count}, look.accent)
					steps.position.z = -depth
					deck.add_child(steps)

## Where the pool sits, in the house's own space: the terrace outside the patio door.
static func pool_frame(record: Dictionary) -> Dictionary:
	if not record.get("pool", false):
		return {}
	var style := style_for(record)
	var list := Layout.rooms(record)
	if list.is_empty():
		return {}
	var outer := float(style.get("exterior_wall", 0.3))
	for wall: Dictionary in Layout.walls(record, list, style):
		if not wall.exterior:
			continue
		for opening: Dictionary in wall.openings:
			if opening.get("patio", false):
				var normal: Vector2 = wall.normal
				var axis := int(wall.axis)
				var face := float(wall.line) + outer * 0.5 * (normal.y if axis == 0 else normal.x)
				var point := Vector2(float(opening.at), face) if axis == 0 else Vector2(face, float(opening.at))
				var size: Array = record.get("pool_size", [8.0, 4.0])
				var floor_y := float(record.get("foundation_height", 0.3))
				var out := WALKWAY + float(size[1]) * 0.5
				var centre := point + normal * out
				# Water size in plan X and Z: the first pool_size value runs along the wall.
				var water := Vector2(size[0], size[1]) if axis == 0 else Vector2(size[1], size[0])
				return {"point": point, "normal": normal, "turn": atan2(-normal.x, -normal.y), "centre": centre,
					"water": water, "along": float(size[0]), "out": float(size[1]), "top": floor_y - 0.02,
					"depth": float(record.get("pool_depth", 1.5)), "door": float(opening.width)}
	return {}

## The ground a parent terrain removes for the pool basin.
static func terrain_cut(record: Dictionary) -> Dictionary:
	var frame := pool_frame(record)
	if frame.is_empty() or record.get("hidden", false):
		return {}
	var at: Array = record.get("position", [0, 0, 0])
	var turn: Array = record.get("rotation", [0, 0, 0])
	var scale: Array = record.get("scale", [1, 1, 1])
	var yaw := deg_to_rad(float(turn[1]))
	var centre: Vector2 = frame.centre
	var local := Basis(Vector3.UP, yaw) * Vector3(centre.x * float(scale[0]), 0, centre.y * float(scale[2]))
	var water: Vector2 = frame.water
	return {"center": Vector2(float(at[0]) + local.x, float(at[2]) + local.z),
		"half": (water * 0.5 + Vector2.ONE * Water.RIM) * Vector2(scale[0], scale[2]), "angle": -yaw,
		"bottom": float(at[1]) + (float(frame.top) - float(frame.depth) - 0.12) * float(scale[1])}

## A stone terrace at floor level outside the patio door, with an in-ground pool set into it.
static func _pool_terrace(root: Node3D, record: Dictionary, point: Vector3, turn: float, door: float, floor_y: float) -> void:
	var frame := pool_frame(record)
	if frame.is_empty():
		return
	var terrace := Node3D.new()
	terrace.name = "PoolTerrace"
	terrace.position = point
	terrace.rotation.y = turn
	root.add_child(terrace)
	var finish := pool_finishes(record)
	var stone := Finishes.make(finish.deck)
	var along := float(frame.along)
	var out := float(frame.out)
	var top := float(frame.top)
	var hole := Vector2(along, out) + Vector2.ONE * Water.RIM * 2.0
	var width := maxf(along + 3.0, door + 2.4)
	var depth := WALKWAY + out + 1.4
	var centre_z := -(WALKWAY + out * 0.5)
	# Four slabs around the pool opening, from the ground up to the terrace surface.
	var near := WALKWAY - Water.RIM
	var far := depth - (WALKWAY + out + Water.RIM)
	_box(terrace, Vector3(0, top * 0.5, -near * 0.5), Vector3(width, top, near), stone)
	_box(terrace, Vector3(0, top * 0.5, -(depth - far * 0.5)), Vector3(width, top, far), stone)
	var side := (width - hole.x) * 0.5
	for sign: float in [-1.0, 1.0]:
		_box(terrace, Vector3(sign * (hole.x + side) * 0.5, top * 0.5, centre_z), Vector3(side, top, hole.y), stone)
	var pool := Water.build({"id": "pool", "water_kind": "pool", "water_size": [along, out], "basin_mode": "excavated",
		"basin_depth": float(frame.depth), "basin_material": finish.basin, "waterline_material": finish.waterline,
		"coping_material": finish.coping,
		"water_id": str(record.get("id", "house")) + "_pool", "name": "Pool"})
	pool.position = Vector3(0, top, centre_z)
	terrace.add_child(pool)
	if top >= 0.2:
		var count := ceili(top / 0.17)
		var steps := Building.build_steps({"width": 1.6, "rise": top, "run": 0.3 * count, "count": count}, stone)
		steps.position = Vector3(width * 0.5 - 1.2, 0, -depth)
		terrace.add_child(steps)
	# Two loungers along the far edge.
	var lounger := Finishes.make({"color": "e9e4da", "roughness": 0.9})
	var frame_finish := Finishes.make({"color": "2a2c2f", "roughness": 0.4, "metallic": 0.4})
	for index in 2:
		var x := -width * 0.5 + 0.9 + index * 0.9
		_box(terrace, Vector3(x, top + 0.2, -(depth - 1.05)), Vector3(0.65, 0.12, 1.9), lounger, false)
		_box(terrace, Vector3(x, top + 0.07, -(depth - 1.05)), Vector3(0.6, 0.14, 1.8), frame_finish, false)
		var back := _box(terrace, Vector3(x, top + 0.42, -(depth - 0.3)), Vector3(0.65, 0.1, 0.7), lounger, false)
		back.rotation.x = 0.9

## Gravel around the walls, stepping stones to the entrance, porch lights and, for styles with an
## accent, cladding around the front door.
static func _grounds(root: Node3D, walls: Array[Dictionary], floor_y: float, ceiling: float, outer: float,
		style: Dictionary, look: Dictionary) -> void:
	var grounds := Node3D.new()
	grounds.name = "Grounds"
	root.add_child(grounds)
	var gravel := Finishes.make({"texture": "gravel_ground_01", "texture_size": 1.6, "color": "c9c3b8"})
	var paver := Finishes.make({"color": "a9a49b", "roughness": 0.9})
	for wall: Dictionary in walls:
		if not wall.exterior:
			continue
		var normal: Vector2 = wall.normal
		var axis := int(wall.axis)
		var from := float(wall.from) - outer * 0.5 - 0.6
		var to := float(wall.to) + outer * 0.5 + 0.6
		var line := float(wall.line) + (normal.y if axis == 0 else normal.x) * (outer * 0.5 + 0.34)
		var length := to - from
		var size := Vector3(length, 0.04, 0.6) if axis == 0 else Vector3(0.6, 0.04, length)
		var at := Vector3((from + to) * 0.5, 0.0, line) if axis == 0 else Vector3(line, 0.0, (from + to) * 0.5)
		_box(grounds, at, size, gravel, false)
		for opening: Dictionary in wall.openings:
			if not opening.get("entrance", false):
				continue
			var turn := atan2(-normal.x, -normal.y)
			var face := float(wall.line) + outer * 0.5 * (normal.y if axis == 0 else normal.x)
			var door := Node3D.new()
			door.name = "FrontDoor"
			door.position = Vector3(float(opening.at), 0, face) if axis == 0 else Vector3(face, 0, float(opening.at))
			door.rotation.y = turn
			grounds.add_child(door)
			var count := ceili(floor_y / 0.17) if floor_y >= 0.12 else 0
			var start := 1.3 + 0.3 * count + 0.25
			for index in 5:
				_box(door, Vector3(0, 0.02, -(start + index * 0.75)), Vector3(1.3, 0.05, 0.55), paver, false)
			for side: float in [-1.0, 1.0]:
				var x := side * (float(opening.width) * 0.5 + 0.32)
				_box(door, Vector3(x, floor_y + 2.0, -0.07), Vector3(0.12, 0.26, 0.12), look.trim, false)
				_box(door, Vector3(x, floor_y + 1.9, -0.07), Vector3(0.1, 0.02, 0.1), look.fixture, false)
			if style.get("materials", {}).has("accent") and style.get("accent_cladding", false):
				# Plan positions along the wall, mapped onto the door node's local X.
				var sign := cos(turn) if axis == 0 else -sin(turn)
				var reach := float(opening.width) * 0.5 + 1.25
				var low := -reach
				var high := reach
				for other: Dictionary in wall.openings:
					if other == opening:
						continue
					var offset := (float(other.at) - float(opening.at)) * sign
					var edge := float(other.width) * 0.5 + 0.12
					if offset > 0.0:
						high = minf(high, offset - edge)
					else:
						low = maxf(low, offset + edge)
				var ends := [(float(wall.from) - outer * 0.5 - float(opening.at)) * sign,
					(float(wall.to) + outer * 0.5 - float(opening.at)) * sign]
				low = maxf(low, minf(ends[0], ends[1]))
				high = minf(high, maxf(ends[0], ends[1]))
				var panel := Node3D.new()
				panel.position = Vector3((low + high) * 0.5, floor_y, -0.018)
				door.add_child(panel)
				Building.wall(panel, high - low, ceiling + 0.06, 0.036, look.accent, look.accent,
					[{"kind": "archway", "offset": -(low + high) * 0.5, "width": float(opening.width) + 0.1,
						"height": float(opening.height) + 0.05}])

## The pool's surfaces: the style's "pool" finishes with the record's pool_finish laid over them.
static func pool_finishes(record: Dictionary) -> Dictionary:
	var style := style_for(record)
	var chosen: Dictionary = {"basin": "pool_tile_white", "waterline": "pool_waterline_glass", "coping": "paving_granite",
		"deck": "paving_granite"}
	chosen.merge(style.get("pool", {}), true)
	chosen.merge(record.get("pool_finish", {}), true)
	var result := {}
	for part: String in chosen:
		result[part] = Surfaces.spec(chosen[part])
	return result

## The floor finish of a room: the style's floor for its kind, then the record's floors rules.
static func floor_finish(record: Dictionary, style: Dictionary, room: Dictionary) -> Dictionary:
	var floors: Dictionary = style.get("floors", {})
	var finish: Variant = floors.get(room.kind, floors.get("default", {}))
	for rule: Dictionary in record.get("floors", []):
		if _rule_room(rule, room):
			finish = rule.get("material", rule.get("finish", finish))
	return Surfaces.spec(finish)

# --- Wall coverings ------------------------------------------------------------------------------

## The finish every interior wall is painted with: the last rule for all rooms and all sides.
static func _base_finish(rules: Array) -> Dictionary:
	var paint := {}
	for rule: Dictionary in rules:
		if str(rule.get("room", "all")) == "all" and str(rule.get("side", "all")) == "all" and not rule.has("height"):
			var spec := _rule_spec(rule)
			if not spec.is_empty():
				paint = spec
	return paint

static func _rule_spec(rule: Dictionary) -> Dictionary:
	return Surfaces.spec(rule.get("material", rule.get("finish", "")))

static func _rule_room(rule: Dictionary, room: Dictionary) -> bool:
	var want := str(rule.get("room", "all")).to_lower()
	return want == "all" or want == str(room.kind) or want == str(room.name).to_lower()

static func _rule_side(rule: Dictionary, side: Dictionary, feature: Variant) -> bool:
	var normal: Vector2 = side.normal
	match str(rule.get("side", "all")):
		"all": return true
		"feature": return side == feature
		"front": return normal.y < -0.5
		"back": return normal.y > 0.5
		"left": return normal.x < -0.5
		"right": return normal.x > 0.5
	return false

## Lays each room's own finishes over its wall faces where they differ from the house's paint: a
## full-height covering, and a lower band (wainscot, splash tiles) in front of it.
static func _cover(parent: Node3D, rooms: Array[Dictionary], rules: Array, paint: Dictionary, focus: Dictionary, ceiling: float) -> void:
	var holder := Node3D.new()
	holder.name = "Coverings"
	parent.add_child(holder)
	for room: Dictionary in rooms:
		var feature: Variant = focus.get(room.index, _feature_side(room))
		for side: Dictionary in room.sides:
			var full := paint
			var band := {}
			var band_height := 0.0
			for rule: Dictionary in rules:
				if not _rule_room(rule, room) or not _rule_side(rule, side, feature):
					continue
				var spec := _rule_spec(rule)
				if spec.is_empty():
					continue
				if rule.has("height"):
					band = spec
					band_height = clampf(float(rule.height), 0.05, ceiling)
				else:
					full = spec
					band = {}
			if not full.recursive_equal(paint, 4):
				_clad(holder, side, ceiling, Finishes.make(full), 0.0)
			if not band.is_empty():
				_clad(holder, side, band_height, Finishes.make(band), COVER)

## A room's feature wall when no furniture claimed one: the side with the most unbroken wall.
static func _feature_side(room: Dictionary) -> Variant:
	var best: Variant = null
	var most := 0.0
	for side: Dictionary in room.sides:
		var length := 0.0
		for span: Array in side.free:
			length += float(span[1]) - float(span[0])
		if length > most:
			most = length
			best = side
	return best

## Covers one side of a room up to `height`, leaving its doors and windows open.
static func _clad(holder: Node3D, side: Dictionary, height: float, material: Material, offset: float) -> void:
	var normal: Vector2 = side.normal
	var inward := Vector3(-normal.x, 0, -normal.y)
	var turn := atan2(inward.x, inward.z)
	for span: Array in side.solid:
		var a := maxf(float(side.low), float(span[0]))
		var b := minf(float(side.high), float(span[1]))
		if b - a < 0.05:
			continue
		# Holes along the span, in plan positions, clipped to it and merged where they overlap.
		var holes := []
		for opening: Dictionary in side.openings:
			var half := float(opening.width) * 0.5
			var low := maxf(a, float(opening.at) - half)
			var high := minf(b, float(opening.at) + half)
			var sill := float(opening.get("sill", 0.0))
			if high - low < 0.02 or sill >= height - 0.02:
				continue
			holes.append([low, high, sill, minf(height, sill + float(opening.height))])
		holes.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
		var pieces := []
		var at := a
		for hole: Array in holes:
			if hole[0] > at:
				pieces.append([at, hole[0], 0.0, height])
			if hole[2] > 0.01:
				pieces.append([maxf(at, hole[0]), hole[1], 0.0, hole[2]])
			if hole[3] < height - 0.01:
				pieces.append([maxf(at, hole[0]), hole[1], hole[3], height])
			at = maxf(at, hole[1])
		if b > at:
			pieces.append([at, b, 0.0, height])
		for piece: Array in pieces:
			var length: float = piece[1] - piece[0]
			var rise: float = piece[3] - piece[2]
			if length < 0.01 or rise < 0.01:
				continue
			var middle: float = (piece[0] + piece[1]) * 0.5
			var point := Vector3(middle, 0, float(side.face)) if int(side.axis) == 0 else Vector3(float(side.face), 0, middle)
			var part := _box(holder, point + inward * (offset + COVER * 0.5 + 0.0005) + Vector3(0, (piece[2] + piece[3]) * 0.5, 0),
				Vector3(length, rise, COVER), material, false)
			part.rotation.y = turn

static func _box(parent: Node3D, at: Vector3, size: Vector3, material: Material, collision := true) -> Node3D:
	var part := Shapes.build({"size": [size.x, size.y, size.z], "shape": "box", "collision": collision})
	(part.get_node("Mesh") as MeshInstance3D).material_override = material
	part.position = at
	parent.add_child(part)
	return part

static func _load_styles() -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(STYLES_PATH))
	if not value is Dictionary or value.get("version") != 1 or not value.get("styles") is Dictionary:
		push_error("Invalid house styles: " + STYLES_PATH)
		return {}
	return value.styles
