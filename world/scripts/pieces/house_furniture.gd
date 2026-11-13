extends RefCounted
## Furniture and fittings for house rooms, made from simple solids with real proportions and
## finishes. Each room kind places its pieces against the walls that are free of doors and windows.

const Layout = preload("res://scripts/pieces/house_layout.gd")
const Shapes = preload("res://scripts/pieces/shape_piece.gd")
const Finishes = preload("res://scripts/pieces/piece_material.gd")
const Library = preload("res://scripts/asset_library.gd")
const CHOICES := "res://data/pieces/house_furnishings.json"

const LOOK := {
	"fabric": {"color": "8d877e", "roughness": 1.0},
	"fabric_dark": {"color": "4a4d52", "roughness": 1.0},
	"cushion": {"color": "c9bfae", "roughness": 1.0},
	"linen": {"color": "f1eee7", "roughness": 1.0},
	"throw": {"color": "8f9a8a", "roughness": 1.0},
	"wood": {"texture": "oak_wood_planks", "texture_size": 0.9, "color": "d8b48c"},
	"dark_wood": {"texture": "dark_wooden_planks", "texture_size": 0.9, "color": "b08a6c"},
	"lacquer": {"color": "f3f1ec", "roughness": 0.35},
	"cabinet": {"color": "d9d4ca", "roughness": 0.45},
	"stone": {"color": "ebe8e2", "roughness": 0.22},
	"steel": {"color": "c9cbcc", "roughness": 0.28, "metallic": 0.85},
	"black": {"color": "16181a", "roughness": 0.3, "metallic": 0.2},
	"screen": {"color": "07080a", "roughness": 0.08, "metallic": 0.4},
	"porcelain": {"color": "fbfbf9", "roughness": 0.12},
	"mirror": {"color": "d6e0e3", "roughness": 0.02, "metallic": 1.0},
	"shower_glass": {"color": "d8e6e8", "alpha": 0.18, "roughness": 0.03},
	"rug": {"color": "b8ac98", "roughness": 1.0},
	"rug_dark": {"color": "5f5a54", "roughness": 1.0},
	"shade": {"color": "f4ead8", "roughness": 0.9, "emission": "ffd8a8", "emission_energy": 0.6},
	"pot": {"color": "6e5f52", "roughness": 0.8},
	"leaf": {"color": "4f6b3e", "roughness": 0.9},
	"tile": {"color": "e6e3dc", "roughness": 0.25},
	"canvas": {"color": "efe9df", "roughness": 0.95},
	"paint_a": {"color": "c46a4a", "roughness": 0.9},
	"paint_b": {"color": "3f5d6e", "roughness": 0.9},
	"paint_c": {"color": "d9b66a", "roughness": 0.9},
}

static var _choices := _load_choices()

static func furnish(root: Node3D, list: Array[Dictionary], walls: Array[Dictionary], ceiling: float, outer: float,
		inner: float, look: Dictionary) -> void:
	var finish := {"style": str(look.get("style_name", "modern"))}
	for key: String in LOOK:
		finish[key] = Finishes.make(LOOK[key])
	finish["baseboard"] = look.baseboard
	var rooms := Layout.room_sides(list, walls, outer, inner)
	for room: Dictionary in rooms:
		var node := Node3D.new()
		node.name = str(room.name).replace(" ", "")
		root.add_child(node)
		_skirting(node, room, finish)
		match str(room.kind):
			"bedroom":
				_bedroom(node, room, finish, room.index == _largest(rooms, "bedroom"))
			"living":
				_living(node, room, finish)
			"kitchen":
				_kitchen(node, room, finish, ceiling)
			"dining":
				_dining(node, room, finish)
			"bathroom":
				_bathroom(node, room, finish, ceiling)
			"office":
				_office(node, room, finish)
			"hall":
				_hall(node, room, finish)

static func _largest(rooms: Array[Dictionary], kind: String) -> int:
	var best := -1
	var area := 0.0
	for room: Dictionary in rooms:
		var clear: Dictionary = room.clear
		var size := (float(clear.x1) - float(clear.x0)) * (float(clear.z1) - float(clear.z0))
		if room.kind == kind and size > area:
			best = room.index
			area = size
	return best

## Baseboards along every wall, broken at doors and floor-length windows.
static func _skirting(node: Node3D, room: Dictionary, finish: Dictionary) -> void:
	for side: Dictionary in room.sides:
		for span: Array in side.skirting:
			var length: float = span[1] - span[0]
			if length < 0.1:
				continue
			var spot := _on_wall(side, (span[0] + span[1]) * 0.5)
			spot.add(node, _box(Vector3(length, 0.09, 0.016), Vector3(0, 0.045, 0.008), finish.baseboard, false))

# --- Rooms -------------------------------------------------------------------------------------

static func _bedroom(node: Node3D, room: Dictionary, f: Dictionary, main: bool) -> void:
	var width := 1.8 if main else 1.4
	var length := 2.1
	var spot := _best(room, width + 1.2, true, true)
	if spot.is_empty():
		spot = _best(room, width + 0.1, false, false)
	if spot.is_empty():
		return
	var place := _on_wall(spot.side, spot.centre)
	var bed := Node3D.new()
	place.add(node, bed)
	_part(bed, Vector3(width + 0.12, 1.05, 0.08), Vector3(0, 0.525, 0.04), f.dark_wood)
	_part(bed, Vector3(width + 0.06, 0.3, length), Vector3(0, 0.17, length * 0.5 + 0.08), f.dark_wood)
	_part(bed, Vector3(width, 0.24, length - 0.06), Vector3(0, 0.44, length * 0.5 + 0.08), f.linen, false)
	_part(bed, Vector3(width + 0.04, 0.05, length * 0.62), Vector3(0, 0.575, length * 0.62 * 0.5 + 0.08 + length * 0.38), f.linen, false)
	_part(bed, Vector3(width + 0.06, 0.06, 0.5), Vector3(0, 0.6, length - 0.25 + 0.08), f.throw, false)
	var pillows := 2 if width > 1.5 else 1
	for index in pillows:
		var x := (index - (pillows - 1) * 0.5) * (width * 0.48)
		var pillow := _part(bed, Vector3(width / pillows - 0.18, 0.11, 0.36), Vector3(x, 0.63, 0.3), f.cushion, false)
		pillow.rotation.x = -0.35
	for side_x: float in [-1.0, 1.0]:
		if spot.length < width + 1.1:
			break
		var x := side_x * (width * 0.5 + 0.34)
		var stand := _model(bed, "nightstand", f, Vector3(x, 0, 0.27))
		if stand == null:
			_part(bed, Vector3(0.48, 0.5, 0.4), Vector3(x, 0.25, 0.22), f.wood)
		_lamp(bed, Vector3(x, float(stand.get_meta("height")) if stand else 0.5, 0.22), f)
	_part(bed, Vector3(width + 0.6, 0.012, length + 0.6), Vector3(0, 0.006, length * 0.5 + 0.35), f.rug, false)
	if _model(bed, "art", f, Vector3(0, 1.2, 0.05), 0.0, int(room.index)) == null:
		_art(bed, Vector3(0, 1.62, 0), Vector2(minf(width, 1.2), 0.6), f, int(room.index))
	# A wardrobe on another wall.
	var closet := _best(room, 1.9, false, false, [spot.side])
	if not closet.is_empty():
		var wardrobe := Node3D.new()
		_on_wall(closet.side, closet.centre).add(node, wardrobe)
		if _model(wardrobe, "storage", f, Vector3(0, 0, 0.32)) != null:
			return
		_part(wardrobe, Vector3(1.8, 2.25, 0.6), Vector3(0, 1.125, 0.3), f.lacquer)
		for door_x: float in [-0.45, 0.45]:
			_part(wardrobe, Vector3(0.012, 0.35, 0.02), Vector3(door_x * 0.06 / 0.45, 1.15, 0.61), f.black, false)
		_part(wardrobe, Vector3(0.006, 2.2, 0.004), Vector3(0, 1.125, 0.602), f.cabinet, false)

static func _living(node: Node3D, room: Dictionary, f: Dictionary) -> void:
	var clear: Dictionary = room.clear
	var spot := _best(room, 2.4, true, true)
	if spot.is_empty():
		# Open plans may have windows on every wall: a low console still fits under them.
		spot = _best(room, 2.2, false, true, [], true, 0.5)
	if spot.is_empty():
		spot = _best(room, 1.8, false, false)
	var media_wall := not spot.is_empty()
	if spot.is_empty():
		# Glass and doors on every wall: float the seating in the room, facing the widest view.
		spot = _focus(room)
	if spot.is_empty():
		return
	var place := _on_wall(spot.side, spot.centre)
	if media_wall:
		var media := Node3D.new()
		place.add(node, media)
		if _model(media, "media_unit", f, Vector3(0, 0, 0.3)) == null:
			_part(media, Vector3(2.0, 0.42, 0.42), Vector3(0, 0.21, 0.21), f.wood)
			_part(media, Vector3(1.96, 0.012, 0.004), Vector3(0, 0.21, 0.422), f.dark_wood, false)
		if not _window_above(spot, 0.75):
			_part(media, Vector3(1.45, 0.83, 0.045), Vector3(0, 1.25, 0.03), f.screen, false)
		else:
			_part(media, Vector3(1.2, 0.7, 0.06), Vector3(0, 0.77, 0.3), f.screen, false)
	var depth := _depth(spot.side, clear)
	var gap := clampf(depth - 1.25, 2.2, 3.2)
	var sofa := Node3D.new()
	place.add(node, sofa)
	sofa.position += place.inward * (gap + 0.95)
	sofa.rotation.y += PI
	if _model(sofa, "sofa", f) == null:
		_sofa(sofa, 2.3, f)
	var table := Node3D.new()
	place.add(node, table)
	table.position += place.inward * (gap * 0.55 + 0.35)
	if _model(table, "coffee_table", f) == null:
		_part(table, Vector3(1.15, 0.05, 0.6), Vector3(0, 0.38, 0), f.wood)
		_part(table, Vector3(1.05, 0.33, 0.5), Vector3(0, 0.175, 0), f.dark_wood)
	# An armchair beside the table, turned toward it, when one is installed.
	var chair := Node3D.new()
	place.add(node, chair)
	chair.position += place.inward * (gap * 0.55 + 0.35) + place.along * 1.75
	chair.rotation.y += -PI * 0.5
	_model(chair, "armchair", f)
	var rug := Node3D.new()
	place.add(node, rug)
	rug.position += place.inward * (gap * 0.55 + 0.5)
	_part(rug, Vector3(2.8, 0.012, 2.0), Vector3(0, 0.006, 0), f.rug, false)
	# A floor lamp and a plant beside the sofa.
	var lamp := Node3D.new()
	place.add(node, lamp)
	lamp.position += place.inward * (gap + 0.75) + place.along * 1.45
	_part(lamp, Vector3(0.3, 0.03, 0.3), Vector3(0, 0.015, 0), f.black)
	_cylinder(lamp, 0.015, 1.45, Vector3(0, 0.74, 0), f.black)
	_cylinder(lamp, 0.2, 0.3, Vector3(0, 1.5, 0), f.shade, 0.16)
	var pot := place.point + place.inward * 0.45 - place.along * 1.55
	if _model(node, "plant", f, pot) == null:
		_plant(node, pot, f)
	var gallery := _best(room, 1.6, false, true, [spot.side])
	if not gallery.is_empty():
		var wall := Node3D.new()
		_on_wall(gallery.side, gallery.centre).add(node, wall)
		if _model(wall, "art", f, Vector3(0, 1.0, 0.05), 0.0, int(room.index) + 1) == null:
			_art(wall, Vector3(0, 1.5, 0), Vector2(1.3, 0.9), f, int(room.index) + 1)

static func _sofa(sofa: Node3D, width: float, f: Dictionary) -> void:
	# Built facing +Z with its back at z = -0.45.
	_part(sofa, Vector3(width, 0.2, 0.9), Vector3(0, 0.18, 0), f.fabric)
	_part(sofa, Vector3(width, 0.05, 0.9), Vector3(0, 0.055, 0), f.black, false)
	for index in 3:
		var x := (index - 1) * (width - 0.36) / 3.0
		_part(sofa, Vector3((width - 0.38) / 3.0 - 0.02, 0.16, 0.66), Vector3(x, 0.36, 0.09), f.cushion, false)
		_part(sofa, Vector3((width - 0.38) / 3.0 - 0.02, 0.42, 0.18), Vector3(x, 0.62, -0.29), f.cushion, false)
	_part(sofa, Vector3(width, 0.62, 0.18), Vector3(0, 0.51, -0.36), f.fabric)
	for side_x: float in [-1.0, 1.0]:
		_part(sofa, Vector3(0.18, 0.58, 0.9), Vector3(side_x * (width * 0.5 - 0.09), 0.37, 0), f.fabric)

static func _kitchen(node: Node3D, room: Dictionary, f: Dictionary, ceiling: float) -> void:
	var clear: Dictionary = room.clear
	var spot := _best(room, 2.4, false, true, [], true)
	if spot.is_empty():
		spot = _best(room, 1.8, false, false)
	if spot.is_empty():
		return
	var length := minf(float(spot.length) - 0.05, 4.8)
	var place := _on_wall(spot.side, spot.centre)
	var run := Node3D.new()
	place.add(node, run)
	var fridge := length >= 3.0
	var counter := length - (0.92 if fridge else 0.0)
	var start := -length * 0.5 + (0.92 if fridge else 0.0)
	var mid := start + counter * 0.5
	_part(run, Vector3(counter, 0.1, 0.56), Vector3(mid, 0.05, 0.25), f.black, false)
	_part(run, Vector3(counter, 0.76, 0.58), Vector3(mid, 0.48, 0.29), f.cabinet)
	_part(run, Vector3(counter + 0.02, 0.04, 0.64), Vector3(mid, 0.88, 0.32), f.stone)
	var doors := int(counter / 0.6)
	for index in doors:
		var x := start + (index + 0.5) * counter / doors
		_part(run, Vector3(counter / doors - 0.006, 0.7, 0.008), Vector3(x, 0.47, 0.584), f.cabinet, false)
		_part(run, Vector3(0.16, 0.012, 0.02), Vector3(x, 0.8, 0.598), f.steel, false)
	# Sink under the window if there is one, otherwise left of centre; cooktop to the right.
	var sink_x := mid - counter * 0.2
	for opening: Dictionary in spot.side.openings:
		if opening.kind == "window":
			var local := (float(opening.at) - float(spot.centre)) * place.sign
			if local > start + 0.4 and local < start + counter - 0.4:
				sink_x = local
	_part(run, Vector3(0.6, 0.012, 0.42), Vector3(sink_x, 0.902, 0.3), f.steel, false)
	_cylinder(run, 0.014, 0.32, Vector3(sink_x, 1.06, 0.08), f.steel)
	_part(run, Vector3(0.03, 0.03, 0.18), Vector3(sink_x, 1.22, 0.16), f.steel, false)
	var cook_x := clampf(sink_x + 1.3 * (1.0 if sink_x < mid else -1.0), start + 0.35, start + counter - 0.35)
	_part(run, Vector3(0.6, 0.008, 0.52), Vector3(cook_x, 0.904, 0.3), f.screen, false)
	if not _window_above(spot, 1.4):
		_part(run, Vector3(counter, 0.72, 0.36), Vector3(mid, 1.86, 0.18), f.cabinet)
		_part(run, Vector3(counter, 0.02, 0.36), Vector3(mid, 1.49, 0.18), f.black, false)
		_part(run, Vector3(counter - 0.01, 0.62, 0.01), Vector3(mid, 1.14, 0.005), f.tile, false)
	if fridge:
		_part(run, Vector3(0.88, 2.02, 0.7), Vector3(-length * 0.5 + 0.45, 1.01, 0.35), f.steel)
		_part(run, Vector3(0.02, 0.7, 0.03), Vector3(-length * 0.5 + 0.85, 1.3, 0.715), f.black, false)
	# An island when the room is deep enough, and a dining table when it is large.
	var depth := _depth(spot.side, clear)
	var across := _width(spot.side, clear)
	if depth >= 3.6:
		var island := Node3D.new()
		place.add(node, island)
		island.position += place.inward * 1.85
		var island_length := minf(2.2, counter)
		_part(island, Vector3(island_length, 0.86, 0.85), Vector3(0, 0.43, 0), f.wood)
		_part(island, Vector3(island_length + 0.1, 0.04, 1.0), Vector3(0, 0.88, 0.07), f.stone)
		for index in 3:
			var x := (index - 1) * island_length / 3.0
			var stool := Node3D.new()
			island.add_child(stool)
			stool.position = Vector3(x, 0, 0.75)
			stool.rotation.y = PI
			if _model(stool, "bar_stool", f) != null:
				continue
			_cylinder(stool, 0.18, 0.04, Vector3(0, 0.66, 0), f.wood)
			_cylinder(stool, 0.018, 0.64, Vector3(0, 0.32, 0), f.black)
			_cylinder(stool, 0.17, 0.02, Vector3(0, 0.01, 0), f.black)
		if depth >= 5.0 and across >= 3.2:
			var dining := Node3D.new()
			place.add(node, dining)
			dining.position += place.inward * (depth - 1.25)
			_table(dining, 1.8, 0.9, 6, f)

static func _dining(node: Node3D, room: Dictionary, f: Dictionary) -> void:
	var clear: Dictionary = room.clear
	var table := Node3D.new()
	node.add_child(table)
	table.position = Vector3((float(clear.x0) + float(clear.x1)) * 0.5, 0, (float(clear.z0) + float(clear.z1)) * 0.5)
	var long_x := float(clear.x1) - float(clear.x0) >= float(clear.z1) - float(clear.z0)
	table.rotation.y = 0.0 if long_x else PI * 0.5
	_table(table, 1.8, 0.9, 6, f)

static func _table(table: Node3D, length: float, width: float, seats: int, f: Dictionary) -> void:
	_part(table, Vector3(length, 0.04, width), Vector3(0, 0.74, 0), f.wood)
	for corner_x: float in [-1.0, 1.0]:
		for corner_z: float in [-1.0, 1.0]:
			_part(table, Vector3(0.05, 0.72, 0.05), Vector3(corner_x * (length * 0.5 - 0.08), 0.36, corner_z * (width * 0.5 - 0.08)), f.black)
	var per_side := seats / 2
	for index in per_side:
		var x := (index - (per_side - 1) * 0.5) * (length / per_side)
		for side_z: float in [-1.0, 1.0]:
			var chair := Node3D.new()
			table.add_child(chair)
			chair.position = Vector3(x, 0, side_z * (width * 0.5 + 0.22))
			chair.rotation.y = 0.0 if side_z < 0.0 else PI
			if _model(chair, "dining_chair", f) == null:
				_chair(chair, f)
	var pendant := Node3D.new()
	table.add_child(pendant)
	_cylinder(pendant, 0.005, 0.9, Vector3(0, 2.2, 0), f.black)
	_cylinder(pendant, 0.22, 0.18, Vector3(0, 1.7, 0), f.shade, 0.06)

static func _chair(chair: Node3D, f: Dictionary) -> void:
	# Faces +Z, like library models.
	_part(chair, Vector3(0.44, 0.05, 0.44), Vector3(0, 0.46, 0), f.wood)
	_part(chair, Vector3(0.44, 0.42, 0.04), Vector3(0, 0.7, -0.2), f.wood)
	for leg_x: float in [-0.19, 0.19]:
		for leg_z: float in [-0.19, 0.19]:
			_part(chair, Vector3(0.035, 0.44, 0.035), Vector3(leg_x, 0.22, leg_z), f.black, false)

static func _bathroom(node: Node3D, room: Dictionary, f: Dictionary, ceiling: float) -> void:
	var clear: Dictionary = room.clear
	# Tiled wet walls to door height.
	for side: Dictionary in room.sides:
		for span: Array in side.free:
			var length: float = span[1] - span[0]
			if length > 0.2:
				_on_wall(side, (span[0] + span[1]) * 0.5).add(node, _box(Vector3(length, 1.2, 0.012), Vector3(0, 0.6, 0.006), f.tile, false))
	var used: Array = []
	var vanity := _best(room, 1.1, false, false)
	if not vanity.is_empty():
		used.append(vanity.side)
		var unit := Node3D.new()
		_on_wall(vanity.side, vanity.centre).add(node, unit)
		_part(unit, Vector3(1.0, 0.5, 0.48), Vector3(0, 0.6, 0.24), f.wood)
		_part(unit, Vector3(1.02, 0.03, 0.5), Vector3(0, 0.865, 0.25), f.stone)
		_cylinder(unit, 0.2, 0.12, Vector3(0, 0.94, 0.27), f.porcelain)
		_cylinder(unit, 0.012, 0.22, Vector3(0, 1.0, 0.06), f.steel)
		_part(unit, Vector3(0.8, 0.9, 0.02), Vector3(0, 1.6, 0.012), f.mirror, false)
		_part(unit, Vector3(0.84, 0.94, 0.012), Vector3(0, 1.6, 0.005), f.black, false)
	var bath := _best(room, 1.6, false, false, used)
	if not bath.is_empty() and float(bath.length) >= 1.7 and _depth(bath.side, clear) >= 1.8:
		used.append(bath.side)
		var tub := Node3D.new()
		var place := _on_wall(bath.side, bath.centre)
		place.add(node, tub)
		var long := minf(1.7, float(bath.length) - 0.02)
		_part(tub, Vector3(long, 0.56, 0.75), Vector3(0, 0.28, 0.375), f.porcelain)
		_part(tub, Vector3(long - 0.16, 0.02, 0.6), Vector3(0, 0.56, 0.37), f.mirror, false)
		_part(tub, Vector3(long, 1.0, 0.012), Vector3(0, 1.4, 0.006), f.tile, false)
	else:
		var shower := _best(room, 0.95, false, false, used)
		if not shower.is_empty():
			used.append(shower.side)
			var stall := Node3D.new()
			_on_wall(shower.side, shower.centre).add(node, stall)
			_part(stall, Vector3(0.9, 0.05, 0.9), Vector3(0, 0.025, 0.45), f.porcelain)
			_part(stall, Vector3(0.9, 2.0, 0.012), Vector3(0, 1.05, 0.9), f.shower_glass, false)
			_part(stall, Vector3(0.9, 2.1, 0.012), Vector3(0, 1.05, 0.006), f.tile, false)
			_cylinder(stall, 0.1, 0.01, Vector3(0, 2.05, 0.2), f.steel)
	var toilet := _best(room, 0.75, false, false, used)
	if toilet.is_empty():
		toilet = _best(room, 0.75, false, false)
	if not toilet.is_empty():
		var bowl := Node3D.new()
		_on_wall(toilet.side, float(toilet.centre)).add(node, bowl)
		_part(bowl, Vector3(0.38, 0.38, 0.17), Vector3(0, 0.6, 0.1), f.porcelain)
		_part(bowl, Vector3(0.36, 0.38, 0.5), Vector3(0, 0.19, 0.4), f.porcelain)
		_part(bowl, Vector3(0.38, 0.03, 0.52), Vector3(0, 0.395, 0.41), f.porcelain, false)

static func _office(node: Node3D, room: Dictionary, f: Dictionary) -> void:
	var spot := _best(room, 1.5, false, true)
	if spot.is_empty():
		return
	var desk := Node3D.new()
	_on_wall(spot.side, spot.centre).add(node, desk)
	_part(desk, Vector3(1.4, 0.035, 0.7), Vector3(0, 0.74, 0.35), f.wood)
	for leg_x: float in [-0.66, 0.66]:
		_part(desk, Vector3(0.04, 0.72, 0.64), Vector3(leg_x, 0.36, 0.35), f.black)
	var chair := Node3D.new()
	desk.add_child(chair)
	chair.position = Vector3(0, 0, 1.0)
	chair.rotation.y = PI
	if _model(chair, "dining_chair", f) == null:
		_chair(chair, f)
	var shelf := _best(room, 1.4, false, false, [spot.side])
	if not shelf.is_empty():
		var books := Node3D.new()
		_on_wall(shelf.side, shelf.centre).add(node, books)
		_model(books, "bookshelf", f, Vector3(0, 0, 0.25))

static func _hall(node: Node3D, room: Dictionary, f: Dictionary) -> void:
	var clear: Dictionary = room.clear
	var long_x := float(clear.x1) - float(clear.x0) >= float(clear.z1) - float(clear.z0)
	var length := (float(clear.x1) - float(clear.x0) if long_x else float(clear.z1) - float(clear.z0)) - 1.2
	if length < 1.0:
		return
	var runner := Node3D.new()
	node.add_child(runner)
	runner.position = Vector3((float(clear.x0) + float(clear.x1)) * 0.5, 0, (float(clear.z0) + float(clear.z1)) * 0.5)
	runner.rotation.y = 0.0 if long_x else PI * 0.5
	_part(runner, Vector3(minf(length, 5.0), 0.01, 0.8), Vector3(0, 0.005, 0), f.rug_dark, false)
	var gallery := _best(room, 1.2, false, true)
	if not gallery.is_empty():
		var wall := Node3D.new()
		_on_wall(gallery.side, gallery.centre).add(node, wall)
		_art(wall, Vector3(0, 1.5, 0), Vector2(0.7, 0.9), f, int(room.index) + 2)

# --- Placement ----------------------------------------------------------------------------------

## The longest free stretch of wall in a room at least `need` long. prefer_inner favours interior
## walls, solid_only skips walls with windows, low_windows allows walls whose windows sit high.
static func _best(room: Dictionary, need: float, prefer_inner: bool, solid_only: bool, skip: Array = [],
		low_windows := false, sill := 0.95) -> Dictionary:
	var best := {}
	var score := -INF
	for side: Dictionary in room.sides:
		if skip.has(side):
			continue
		var windows: Array = side.openings.filter(func(o: Dictionary) -> bool: return o.kind == "window")
		var high: bool = windows.all(func(o: Dictionary) -> bool: return float(o.get("sill", 0.0)) >= sill)
		var spans: Array = side.free
		if solid_only and not windows.is_empty():
			if not (low_windows and high):
				continue
			spans = side.skirting
		for span: Array in spans:
			var length: float = span[1] - span[0]
			if length < need:
				continue
			var value := length + (2.0 if prefer_inner and side.openings.is_empty() else 0.0)
			if value > score:
				score = value
				best = {"side": side, "centre": (span[0] + span[1]) * 0.5, "length": length}
	return best

## The side with the most wall, whatever is in it: the side a floating seating group faces.
static func _focus(room: Dictionary) -> Dictionary:
	var best := {}
	var most := 0.0
	for side: Dictionary in room.sides:
		var length := 0.0
		for span: Array in side.solid:
			length += float(span[1]) - float(span[0])
		if length > most:
			most = length
			best = {"side": side, "centre": (float(side.low) + float(side.high)) * 0.5, "length": float(side.high) - float(side.low)}
	return best

static func _window_above(spot: Dictionary, height: float) -> bool:
	var half := float(spot.length) * 0.5
	for opening: Dictionary in spot.side.openings:
		if opening.kind == "window" and absf(float(opening.at) - float(spot.centre)) < half + float(opening.width) * 0.5 \
				and float(opening.get("sill", 0.0)) + float(opening.height) > height:
			return true
	return false

## Clear distance from a wall face to the opposite side of the room.
static func _depth(side: Dictionary, clear: Dictionary) -> float:
	return float(clear.z1) - float(clear.z0) if int(side.axis) == 0 else float(clear.x1) - float(clear.x0)

static func _width(side: Dictionary, clear: Dictionary) -> float:
	return float(clear.x1) - float(clear.x0) if int(side.axis) == 0 else float(clear.z1) - float(clear.z0)

class WallSpot:
	var point: Vector3
	var inward: Vector3
	var along: Vector3
	var turn: float
	var sign: float

	## Adds a node at this spot, turned so its local +Z points into the room.
	func add(parent: Node3D, child: Node3D) -> void:
		child.position = point + Basis(Vector3.UP, turn) * child.position
		child.rotation.y = turn
		parent.add_child(child)

static func _on_wall(side: Dictionary, at: float) -> WallSpot:
	var spot := WallSpot.new()
	var normal: Vector2 = side.normal
	var inward := Vector3(-normal.x, 0, -normal.y)
	spot.inward = inward
	spot.turn = atan2(inward.x, inward.z)
	spot.along = Vector3(cos(spot.turn), 0, -sin(spot.turn))
	spot.point = Vector3(at, 0, float(side.face)) if int(side.axis) == 0 else Vector3(float(side.face), 0, at)
	# Local +X runs along the wall; "sign" maps plan positions along the side to local X.
	spot.sign = spot.along.x if int(side.axis) == 0 else spot.along.z
	return spot

# --- Library models -----------------------------------------------------------------------------

## A library model for a furniture slot (house_furnishings.json), fitted to the slot, standing at
## `at` and facing +Z then `turn`. Returns its holder, whose "height" meta is the fitted height,
## or null when no model for the slot is installed, so the caller can build a stand-in.
static func _model(parent: Node3D, slot: String, f: Dictionary, at := Vector3.ZERO, turn := 0.0, pick := 0) -> Node3D:
	var rule: Dictionary = _choices.get("slots", {}).get(slot, {})
	var options: Dictionary = rule.get("models", {})
	var ids: Array = options.get(str(f.get("style", "")), options.get("default", []))
	var installed := ids.filter(func(id: Variant) -> bool: return Library.has(str(id)))
	if installed.is_empty():
		return null
	var id := str(installed[pick % installed.size()])
	var model := Library.instance(id)
	if model == null:
		return null
	var size := Library.size(id)
	var spin := deg_to_rad(float(_choices.get("turn", {}).get(id, 0.0)))
	if absf(sin(spin)) > 0.7:
		size = Vector3(size.z, size.y, size.x)
	var target: Array = rule.get("size", [1, 1, 1])
	var fit := 1.0
	if size.x > 0.0 and size.y > 0.0 and size.z > 0.0:
		fit = minf(1.0, minf(float(target[0]) / size.x, minf(float(target[1]) / size.y, float(target[2]) / size.z)))
	var holder := Node3D.new()
	holder.name = slot.capitalize().replace(" ", "")
	holder.position = at
	holder.rotation.y = turn
	holder.set_meta("height", size.y * fit)
	holder.set_meta("library_id", id)
	parent.add_child(holder)
	model.scale = Vector3.ONE * fit
	model.rotation.y = spin
	holder.add_child(model)
	# A plain box keeps the player from walking through it.
	if size.y * fit > 0.2:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size * fit
		shape.shape = box
		shape.position.y = size.y * fit * 0.5
		body.add_child(shape)
		holder.add_child(body)
	return holder

static func _load_choices() -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(CHOICES))
	if not value is Dictionary or value.get("version") != 1:
		push_error("Invalid house furnishings: " + CHOICES)
		return {}
	return value

# --- Parts --------------------------------------------------------------------------------------

static func _part(parent: Node3D, size: Vector3, at: Vector3, material: Material, collision := true) -> Node3D:
	var part := _box(size, at, material, collision)
	parent.add_child(part)
	return part

static func _box(size: Vector3, at: Vector3, material: Material, collision := true) -> Node3D:
	var part := Shapes.build({"size": [size.x, size.y, size.z], "shape": "box", "collision": collision, "cast_shadow": size.y > 0.03})
	(part.get_node("Mesh") as MeshInstance3D).material_override = material
	part.position = at
	return part

static func _cylinder(parent: Node3D, radius: float, height: float, at: Vector3, material: Material, top := -1.0) -> void:
	var mesh := MeshInstance3D.new()
	var shape := CylinderMesh.new()
	shape.bottom_radius = radius
	shape.top_radius = radius if top < 0.0 else top
	shape.height = height
	shape.radial_segments = 24
	mesh.mesh = shape
	mesh.material_override = material
	mesh.position = at
	parent.add_child(mesh)

## A framed abstract print hung on the wall behind `at`, facing +Z.
static func _art(parent: Node3D, at: Vector3, size: Vector2, f: Dictionary, seed: int) -> void:
	_part(parent, Vector3(size.x + 0.06, size.y + 0.06, 0.03), at + Vector3(0, 0, 0.015), f.black, false)
	_part(parent, Vector3(size.x, size.y, 0.01), at + Vector3(0, 0, 0.032), f.canvas, false)
	var paints: Array = [f.paint_a, f.paint_b, f.paint_c]
	for index in 2:
		var paint: Material = paints[(seed + index) % paints.size()]
		var block := Vector2(size.x * (0.45 - index * 0.12), size.y * (0.5 + index * 0.2))
		var shift := Vector3((index - 0.5) * size.x * 0.28, (0.5 - index) * size.y * 0.12, 0.038 + index * 0.002)
		_part(parent, Vector3(block.x, block.y, 0.004), at + shift, paint, false)

static func _lamp(parent: Node3D, at: Vector3, f: Dictionary) -> void:
	_cylinder(parent, 0.06, 0.25, at + Vector3(0, 0.125, 0), f.porcelain)
	_cylinder(parent, 0.15, 0.2, at + Vector3(0, 0.34, 0), f.shade, 0.11)

static func _plant(node: Node3D, at: Vector3, f: Dictionary) -> void:
	var plant := Node3D.new()
	plant.position = at
	node.add_child(plant)
	_cylinder(plant, 0.2, 0.45, Vector3(0, 0.225, 0), f.pot, 0.24)
	if Library.has("shrub_04"):
		var leaves := Library.instance("shrub_04")
		if leaves:
			leaves.scale = Vector3.ONE * 2.2
			leaves.position.y = 0.45
			plant.add_child(leaves)
			return
	var crown := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.38
	ball.height = 0.9
	crown.mesh = ball
	crown.material_override = f.leaf
	crown.position.y = 0.95
	plant.add_child(crown)
