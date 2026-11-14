extends RefCounted
## Turns a house record into a plan: rooms, then the walls between them with their doors and
## windows. Pure data, so agents, tests and the house factory all see the same plan.
## Plan coordinates are [x, z] metres in the house's local space; the entrance faces -Z.

const KINDS := ["living", "kitchen", "dining", "bedroom", "bathroom", "hall", "office", "laundry", "closet", "stairs"]
## Rooms that open into each other without walls in an open layout.
const SHARED := ["living", "kitchen", "dining", "hall"]
## Rooms that need their own door.
const PRIVATE := ["bedroom", "bathroom", "office", "laundry", "closet"]
const DOOR_FROM := ["hall", "living", "dining", "kitchen", "bedroom", "office", "laundry", "closet", "bathroom", "stairs"]
## A stairwell opens without a wall onto these rooms, on every floor and in every layout.
const STAIRS_OPEN := ["hall", "living", "dining", "kitchen", "stairs"]
## Houses have at most this many floors.
const MAX_LEVELS := 2
## The width of a generated stairwell (a U-shaped stair of two flights).
const STAIRWELL := 2.4
const MIN_ROOM := 1.2
const LIMIT := 32.0
const EDGE := 0.35
const SNAP := 0.05

## The rooms of a record: its own list, or a layout generated from its program.
static func rooms(record: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var listed: Array = record.get("rooms", [])
	if listed.is_empty():
		listed = generate(int(record.get("bedrooms", 2)), int(record.get("bathrooms", 1)),
			float(record.get("floor_area", 0.0)), str(record.get("layout", "open")), int(record.get("storeys", 1)))
	for index in listed.size():
		var room: Dictionary = listed[index]
		var corners: Array = room.rect
		var x0 := _snap(minf(corners[0], corners[2]))
		var z0 := _snap(minf(corners[1], corners[3]))
		var x1 := _snap(maxf(corners[0], corners[2]))
		var z1 := _snap(maxf(corners[1], corners[3]))
		# Edges use the exact x0..z1 values; Rect2 is single precision and only for geometry.
		result.append({"index": index, "kind": str(room.kind), "name": str(room.get("name", _title(room.kind, listed, index))),
			"level": int(room.get("level", 0)), "x0": x0, "z0": z0, "x1": x1, "z1": z1, "rect": Rect2(x0, z0, x1 - x0, z1 - z0)})
	return result

## The rooms on each floor, ground floor first. Each floor's rooms are copies indexed from 0 within
## that floor (walls and furniture work floor by floor); "id" keeps the index in the whole house.
static func levels(list: Array[Dictionary]) -> Array:
	var count := 1
	for room: Dictionary in list:
		count = maxi(count, int(room.level) + 1)
	var result := []
	for level in count:
		var floor: Array[Dictionary] = []
		for room: Dictionary in list:
			if int(room.level) == level:
				var copy := room.duplicate()
				copy["id"] = room.index
				copy["index"] = floor.size()
				floor.append(copy)
		result.append(floor)
	return result

## The stairwell above or below a room on the next floor (same rectangle), or {}.
static func stairwell(level_rooms: Array, room: Dictionary) -> Dictionary:
	if room.kind != "stairs":
		return {}
	for other: Dictionary in level_rooms:
		if other.kind == "stairs" and absf(float(other.x0) - float(room.x0)) < 0.06 and absf(float(other.z0) - float(room.z0)) < 0.06 \
				and absf(float(other.x1) - float(room.x1)) < 0.06 and absf(float(other.z1) - float(room.z1)) < 0.06:
			return other
	return {}

## Whether a rectangle lies over the rooms of the floor below.
static func supported(below: Array, rect: Rect2) -> bool:
	var inset := rect.grow(-0.1)
	for i in 3:
		for j in 3:
			var point := inset.position + inset.size * Vector2(i / 2.0, j / 2.0)
			if not below.any(func(room: Dictionary) -> bool: return (room.rect as Rect2).grow(0.06).has_point(point)):
				return false
	return true

## A single-storey plan: shared rooms across the front, a hall, then bedrooms and baths at the back.
## With two storeys, the bedrooms and most baths go upstairs around a stairwell beside the hall.
static func generate(bedrooms: int, bathrooms: int, floor_area := 0.0, layout := "open", storeys := 1) -> Array:
	bedrooms = clampi(bedrooms, 0, 5)
	bathrooms = clampi(bathrooms, 1, 3)
	if storeys >= 2:
		return _two_storeys(bedrooms, bathrooms, floor_area, layout)
	var back: Array = []
	var baths := bathrooms
	for index in bedrooms:
		back.append(["bedroom", 4.2 if index == 0 else 3.4])
		if baths > 0 and (index == 0 or bedrooms - index - 1 < baths):
			back.append(["bathroom", 2.5])
			baths -= 1
	while baths > 0:
		back.append(["bathroom", 2.5])
		baths -= 1
	if bedrooms == 0:
		back.append(["laundry", 2.2])
	var width := 0.0
	for room: Array in back:
		width += float(room[1])
	var scale := 1.0
	if floor_area > 0.0:
		var natural := maxf(width, 8.6) * (5.0 + 1.3 + 3.8)
		scale = clampf(sqrt(floor_area / natural), 0.85, 1.35)
	var stretch := maxf(1.0, 8.6 / width) * scale
	width = _snap(width * stretch)
	var front_depth := _snap(5.0 * scale)
	var back_depth := _snap(3.8 * scale)
	var hall := 1.3
	var z0 := _snap(-(front_depth + hall + back_depth) * 0.5)
	var x0 := _snap(-width * 0.5)
	var plan: Array = []
	var living := _snap(width * (0.56 if layout == "open" else 0.5))
	plan.append({"kind": "living", "rect": [x0, z0, x0 + living, z0 + front_depth]})
	if layout == "open" or width - living < 5.5:
		plan.append({"kind": "kitchen", "rect": [x0 + living, z0, -x0, z0 + front_depth]})
	else:
		var middle := _snap(x0 + living + (width - living) * 0.5)
		plan.append({"kind": "dining", "rect": [x0 + living, z0, middle, z0 + front_depth]})
		plan.append({"kind": "kitchen", "rect": [middle, z0, -x0, z0 + front_depth]})
	var hall_z := z0 + front_depth
	plan.append({"kind": "hall", "rect": [x0, hall_z, -x0, hall_z + hall]})
	var at := x0
	var back_z := hall_z + hall
	for index in back.size():
		var room: Array = back[index]
		var next := -x0 if index == back.size() - 1 else _snap(at + float(room[1]) * stretch)
		plan.append({"kind": room[0], "rect": [at, back_z, next, back_z + back_depth]})
		at = next
	return plan

static func _two_storeys(bedrooms: int, bathrooms: int, floor_area: float, layout: String) -> Array:
	var down_baths := 1 if bathrooms >= 2 else 0
	var upper: Array = []
	var baths := bathrooms - down_baths
	for index in bedrooms:
		upper.append(["bedroom", 4.2 if index == 0 else 3.4])
		if baths > 0 and (index == 0 or bedrooms - index - 1 < baths):
			upper.append(["bathroom", 2.5])
			baths -= 1
	while baths > 0:
		upper.append(["bathroom", 2.5])
		baths -= 1
	if upper.size() < 2:
		upper.append(["office", 3.0])
	# Upstairs rooms fill the front row, then the back row beside the stairwell.
	var total := STAIRWELL
	for room: Array in upper:
		total += float(room[1])
	var front: Array = []
	var back: Array = []
	var used := 0.0
	# Bedrooms take the front row (over the living rooms); baths and the rest go beside the stairwell.
	for room: Array in upper:
		if room[0] == "bedroom" and (front.is_empty() or used + float(room[1]) <= total * 0.5 + 0.6):
			front.append(room)
			used += float(room[1])
		else:
			back.append(room)
	if front.is_empty():
		front.append(back.pop_front())
	if back.is_empty():
		back.append(front.pop_back())
	var front_width := 0.0
	for room: Array in front:
		front_width += float(room[1])
	var back_width := STAIRWELL
	for room: Array in back:
		back_width += float(room[1])
	var width := maxf(8.6, maxf(front_width, back_width))
	var scale := 1.0
	if floor_area > 0.0:
		scale = clampf(sqrt(floor_area / (2.0 * width * 10.1)), 0.85, 1.35)
	width = _snap(width * scale)
	var front_depth := _snap(5.0 * scale)
	var back_depth := _snap(maxf(3.8 * scale, 3.4))
	var hall := 1.3
	var z0 := _snap(-(front_depth + hall + back_depth) * 0.5)
	var x0 := _snap(-width * 0.5)
	var hall_z := z0 + front_depth
	var back_z := hall_z + hall
	var stair_x := x0 + STAIRWELL
	var plan: Array = []
	# Ground floor: living and kitchen at the front, the hall, then the stairwell, a bath and a study or laundry.
	var living := _snap(width * (0.56 if layout == "open" else 0.5))
	plan.append({"kind": "living", "rect": [x0, z0, x0 + living, hall_z]})
	if layout == "open" or width - living < 5.5:
		plan.append({"kind": "kitchen", "rect": [x0 + living, z0, -x0, hall_z]})
	else:
		var middle := _snap(x0 + living + (width - living) * 0.5)
		plan.append({"kind": "dining", "rect": [x0 + living, z0, middle, hall_z]})
		plan.append({"kind": "kitchen", "rect": [middle, z0, -x0, hall_z]})
	plan.append({"kind": "hall", "rect": [x0, hall_z, -x0, back_z]})
	plan.append({"kind": "stairs", "name": "Stairs", "rect": [x0, back_z, stair_x, back_z + back_depth]})
	var ground: Array = []
	var rest := width - STAIRWELL
	if down_baths > 0:
		ground.append(["bathroom", 2.2])
		rest -= 2.2
	if rest >= 5.4:
		ground.append(["office", rest - 2.2])
		ground.append(["laundry", 2.2])
	elif rest >= 2.4:
		ground.append(["office", rest])
	elif rest >= 1.4:
		ground.append(["laundry", rest])
	elif not ground.is_empty():
		ground[-1][1] += rest
	plan.append_array(_row(ground, stair_x, -x0, back_z, back_z + back_depth, 0))
	# Upstairs: the same outline, hall and stairwell.
	plan.append_array(_row(front, x0, -x0, z0, hall_z, 1))
	plan.append({"kind": "hall", "name": "Landing", "level": 1, "rect": [x0, hall_z, -x0, back_z]})
	plan.append({"kind": "stairs", "name": "Stairwell", "level": 1, "rect": [x0, back_z, stair_x, back_z + back_depth]})
	plan.append_array(_row(back, stair_x, -x0, back_z, back_z + back_depth, 1))
	return plan

## Rooms side by side from x = start to x = end, widths in proportion to each room's [kind, width].
static func _row(rooms: Array, start: float, end: float, z0: float, z1: float, level: int) -> Array:
	var total := 0.0
	for room: Array in rooms:
		total += float(room[1])
	var result := []
	var at := start
	for index in rooms.size():
		var room: Array = rooms[index]
		var next := end if index == rooms.size() - 1 else _snap(at + (end - start) * float(room[1]) / total)
		result.append({"kind": room[0], "level": level, "rect": [at, z0, next, z1]})
		at = next
	return result

## Problems with a record's rooms, or an empty string.
static func problem(record: Dictionary) -> String:
	var list := rooms(record)
	if list.is_empty():
		return "A house needs at least one room."
	for room: Dictionary in list:
		var rect: Rect2 = room.rect
		if rect.size.x < MIN_ROOM or rect.size.y < MIN_ROOM:
			return "%s is smaller than %.1f m across." % [room.name, MIN_ROOM]
		if absf(rect.position.x) > LIMIT or absf(rect.end.x) > LIMIT or absf(rect.position.y) > LIMIT or absf(rect.end.y) > LIMIT:
			return "%s is more than %d m from the house origin." % [room.name, int(LIMIT)]
	var floors := levels(list)
	if floors.size() > MAX_LEVELS:
		return "A house has at most %d floors (levels 0 to %d)." % [MAX_LEVELS, MAX_LEVELS - 1]
	for level in floors.size():
		var rooms: Array[Dictionary] = floors[level]
		if rooms.is_empty():
			return "Level %d has no rooms." % level
		for a in rooms.size():
			for b in range(a + 1, rooms.size()):
				var overlap: Rect2 = (rooms[a].rect as Rect2).intersection(rooms[b].rect)
				if overlap.size.x > SNAP and overlap.size.y > SNAP:
					return "%s overlaps %s." % [rooms[a].name, rooms[b].name]
		if not _connected(rooms):
			return "Every room must touch another room on its floor."
		if level == 0:
			continue
		var below: Array = floors[level - 1]
		for room: Dictionary in rooms:
			if not supported(below, room.rect):
				return "%s is not over rooms on the floor below." % room.name
		var well: Dictionary = {}
		for room: Dictionary in rooms:
			if not stairwell(below, room).is_empty():
				well = room
		if well.is_empty():
			return "Level %d needs a stairs room directly over a stairs room on the floor below." % level
		var rect: Rect2 = well.rect
		if minf(rect.size.x, rect.size.y) < 1.9 or maxf(rect.size.x, rect.size.y) < 3.0:
			return "%s is too small for a stair: it needs at least 1.9 by 3.0 m." % well.name
	return ""

## The walls of a plan. Each wall runs from "a" to "b" along one axis and lists its openings with
## an "at" position along that axis. Exterior walls carry their outward "normal".
static func walls(record: Dictionary, list: Array[Dictionary], style: Dictionary, level := 0) -> Array[Dictionary]:
	var open_plan: bool = record.get("layout", "open") == "open"
	var pieces := _edges(list, open_plan)
	_doors(record, list, pieces, style, open_plan, level)
	_windows(record, list, pieces, style)
	return _merge(pieces)

## What lines each room: its clear inner rectangle and, for each side, the inner wall face and
## the stretches free of doors and windows (for furniture) or of doors only (for baseboards).
static func room_sides(list: Array[Dictionary], walls: Array[Dictionary], outer: float, inner: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for room: Dictionary in list:
		var sides: Array[Dictionary] = []
		var clear := {"x0": float(room.x0), "z0": float(room.z0), "x1": float(room.x1), "z1": float(room.z1)}
		for side in [[0, room.z0, Vector2(0, -1), room.x0, room.x1, "z0"], [0, room.z1, Vector2(0, 1), room.x0, room.x1, "z1"],
				[1, room.x0, Vector2(-1, 0), room.z0, room.z1, "x0"], [1, room.x1, Vector2(1, 0), room.z0, room.z1, "x1"]]:
			var axis: int = side[0]
			var line: float = side[1]
			var normal: Vector2 = side[2]
			var low: float = side[3]
			var high: float = side[4]
			var solid := []
			var thickness := 0.0
			var openings := []
			for wall: Dictionary in walls:
				if int(wall.axis) != axis or absf(float(wall.line) - line) > 0.01:
					continue
				var a := maxf(low, float(wall.from))
				var b := minf(high, float(wall.to))
				if b - a < 0.05:
					continue
				solid.append([a, b])
				thickness = maxf(thickness, outer * 0.5 + 0.016 if wall.exterior else inner * 0.5)
				for opening: Dictionary in wall.openings:
					if float(opening.at) > a - 0.01 and float(opening.at) < b + 0.01:
						openings.append(opening)
			var face := line - (normal.y if axis == 0 else normal.x) * thickness
			clear[side[5]] = face
			sides.append({"axis": axis, "normal": normal, "face": face, "from": low, "to": high, "solid": solid,
				"openings": openings})
		for side: Dictionary in sides:
			# Trim each side to the clear rectangle so furniture stays out of the corners.
			var low: float = clear.x0 if side.axis == 0 else clear.z0
			var high: float = clear.x1 if side.axis == 0 else clear.z1
			var spans := []
			for span: Array in side.solid:
				var a := maxf(low, span[0])
				var b := minf(high, span[1])
				if b - a > 0.05:
					spans.append([a, b])
			var free := spans.duplicate(true)
			var skirting := spans.duplicate(true)
			for opening: Dictionary in side.openings:
				var half := float(opening.width) * 0.5
				var door: bool = opening.kind != "window"
				free = _cut(free, float(opening.at) - half - (0.3 if door else 0.08), float(opening.at) + half + (0.3 if door else 0.08))
				if door or float(opening.get("sill", 1.0)) < 0.3:
					skirting = _cut(skirting, float(opening.at) - half, float(opening.at) + half)
			side["free"] = free
			side["skirting"] = skirting
			side["low"] = low
			side["high"] = high
		result.append({"index": room.index, "kind": room.kind, "name": room.name, "clear": clear, "sides": sides})
	return result

static func bounds(list: Array[Dictionary]) -> Rect2:
	var box: Rect2 = list[0].rect
	for room: Dictionary in list:
		box = box.merge(room.rect)
	return box

static func is_rectangle(list: Array[Dictionary]) -> bool:
	var area := 0.0
	for room: Dictionary in list:
		area += (room.rect as Rect2).get_area()
	return absf(bounds(list).get_area() - area) < 0.05

## The room containing a plan point, or -1.
static func room_at(list: Array[Dictionary], point: Vector2) -> int:
	for room: Dictionary in list:
		if point.x > room.x0 and point.x < room.x1 and point.y > room.z0 and point.y < room.z1:
			return room.index
	return -1

## Split every room side at its neighbours' corners, and say what lies beyond each part.
static func _edges(list: Array[Dictionary], open_plan: bool) -> Array[Dictionary]:
	var xs := {}
	var zs := {}
	for room: Dictionary in list:
		xs[room.x0] = true
		xs[room.x1] = true
		zs[room.z0] = true
		zs[room.z1] = true
	var cuts_x := xs.keys()
	cuts_x.sort()
	var cuts_z := zs.keys()
	cuts_z.sort()
	var result: Array[Dictionary] = []
	for room: Dictionary in list:
		# Sides: front (-Z), back (+Z), left (-X), right (+X).
		for side in [[0, room.z0, Vector2(0, -1)], [0, room.z1, Vector2(0, 1)],
				[1, room.x0, Vector2(-1, 0)], [1, room.x1, Vector2(1, 0)]]:
			var axis: int = side[0]
			var line: float = side[1]
			var normal: Vector2 = side[2]
			var start: float = room.x0 if axis == 0 else room.z0
			var end: float = room.x1 if axis == 0 else room.z1
			var cuts: Array = cuts_x if axis == 0 else cuts_z
			var points: Array = [start]
			for cut: float in cuts:
				if cut > start + 0.001 and cut < end - 0.001:
					points.append(cut)
			points.append(end)
			for index in points.size() - 1:
				var p: float = points[index]
				var q: float = points[index + 1]
				var middle := (p + q) * 0.5
				var probe := (Vector2(middle, line) if axis == 0 else Vector2(line, middle)) + normal * 0.05
				var other := room_at(list, probe)
				if other != -1 and other < room.index:
					continue
				var open: bool = other != -1 and ((open_plan and room.kind in SHARED and list[other].kind in SHARED)
					or (room.kind == "stairs" and list[other].kind in STAIRS_OPEN)
					or (list[other].kind == "stairs" and room.kind in STAIRS_OPEN))
				# Corners of rooms elsewhere split this side too; rejoin pieces facing the same room.
				var last: Dictionary = result[-1] if not result.is_empty() else {}
				if not last.is_empty() and last.room == room.index and last.axis == axis and last.line == line \
						and last.other == other and absf(float(last.to) - p) < 0.001:
					last.to = q
					continue
				result.append({"axis": axis, "line": line, "from": p, "to": q, "room": room.index, "other": other,
					"normal": normal, "open": open, "openings": []})
	return result

static func _doors(record: Dictionary, list: Array[Dictionary], parts: Array[Dictionary], style: Dictionary, open_plan: bool,
		level := 0) -> void:
	var door: Dictionary = style.get("door", {})
	var width := float(door.get("width", 0.86))
	var height := float(door.get("height", 2.1))
	var centre := bounds(list).get_center()
	var reached := {}
	# Private rooms each get one door, preferring a hall, then shared rooms.
	for room: Dictionary in list:
		if not room.kind in PRIVATE:
			continue
		var best: Dictionary = {}
		var best_rank := 999
		for part: Dictionary in parts:
			if part.open or part.other == -1 or (part.room != room.index and part.other != room.index):
				continue
			var neighbour: Dictionary = list[part.other if part.room == room.index else part.room]
			var rank := DOOR_FROM.find(neighbour.kind) * 100 - int((part.to - part.from) * 10.0)
			if neighbour.kind in PRIVATE:
				rank += 1000
			if part.to - part.from >= width + EDGE * 2.0 and rank < best_rank:
				best = part
				best_rank = rank
		if best.is_empty():
			continue
		var along := _toward(best, centre)
		var at: float = best.to - EDGE - width * 0.5 if along > 0.0 else best.from + EDGE + width * 0.5
		best.openings.append({"kind": "door", "at": at, "width": width - (0.06 if room.kind == "bathroom" else 0.0),
			"height": height, "motion": "hinge", "finish": "interior"})
		reached[room.index] = true
	# Closed layouts join shared rooms with wide archways.
	if not open_plan:
		for part: Dictionary in parts:
			if part.other == -1 or part.open:
				continue
			if list[part.room].kind in SHARED and list[part.other].kind in SHARED and part.to - part.from >= 2.0:
				var span := minf(1.6, part.to - part.from - EDGE * 2.0)
				part.openings.append({"kind": "archway", "at": (part.from + part.to) * 0.5, "width": span,
					"height": height + 0.1})
	if level > 0:
		return
	# The entrance: a front wall of a shared room, nearest the middle of the house.
	var entry: Dictionary = style.get("entry_door", {"width": 1.0, "height": 2.2})
	var entrance := _best_exterior(parts, list, ["hall", "living", "dining", "kitchen"], Vector2(0, -1),
		float(entry.width) + EDGE * 2.0)
	if not entrance.is_empty():
		var along := _toward(entrance, Vector2(0, centre.y) if entrance.axis == 0 else centre)
		var room_kind: String = list[entrance.room].kind
		var at: float = clampf(centre.x, entrance.from + EDGE + float(entry.width) * 0.5,
			entrance.to - EDGE - float(entry.width) * 0.5) if room_kind == "hall" else \
			(entrance.to - EDGE * 2.0 - float(entry.width) * 0.5 if along > 0.0 else entrance.from + EDGE * 2.0 + float(entry.width) * 0.5)
		entrance.openings.append({"kind": "door", "at": at, "width": float(entry.width), "height": float(entry.height),
			"motion": "hinge", "finish": "entry", "entrance": true})
	# A glazed patio door from the living room to the side or back.
	var patio: Dictionary = style.get("patio_door", {"width": 2.4, "height": 2.3})
	for normal in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, 1)]:
		var side := _best_exterior(parts, list, ["living", "dining"], normal, float(patio.width) + EDGE * 2.0 + 0.4)
		if not side.is_empty() and side.openings.is_empty():
			side.openings.append({"kind": "door", "at": (side.from + side.to) * 0.5, "width": float(patio.width),
				"height": float(patio.height), "motion": "slide", "finish": "glazed", "patio": true})
			break

static func _windows(record: Dictionary, list: Array[Dictionary], parts: Array[Dictionary], style: Dictionary) -> void:
	var rules: Dictionary = style.get("windows", {})
	var ceiling := float(record.get("ceiling_height", 2.7))
	for part: Dictionary in parts:
		if part.other != -1:
			continue
		var kind: String = list[part.room].kind
		if not rules.has(kind):
			continue
		var rule: Dictionary = rules[kind]
		var sill := float(rule.get("sill", 0.9))
		var height := ceiling - sill - 0.32 if str(rule.get("height")) == "full" else float(rule.get("height", 1.2))
		height = minf(height, ceiling - sill - 0.2)
		if height < 0.4:
			continue
		# Leave room beside doors already on this wall and at its ends.
		var free: Array = [[part.from + EDGE, part.to - EDGE]]
		for opening: Dictionary in part.openings:
			var half := float(opening.width) * 0.5 + 0.3
			free = _cut(free, float(opening.at) - half, float(opening.at) + half)
		var limit := int(rule.get("max", 2))
		for span: Array in free:
			var length: float = span[1] - span[0]
			var width := minf(float(rule.get("width", 1.2)), length)
			if width < maxf(0.6, float(rule.get("width", 1.2)) * 0.6) or limit <= 0:
				continue
			var count := clampi(int(length / float(rule.get("per", 3.0))), 1, limit)
			while count > 1 and length < count * (width + 0.45):
				count -= 1
			for index in count:
				var at: float = span[0] + length * (index + 0.5) / count
				part.openings.append({"kind": "window", "at": at, "width": width, "height": height, "sill": sill,
					"motion": rule.get("motion", "slide"), "finish": rule.get("finish", "glass")})
			limit -= count

## Join wall parts that continue each other along a line, so long walls are single pieces.
static func _merge(parts: Array[Dictionary]) -> Array[Dictionary]:
	var groups := {}
	for part: Dictionary in parts:
		if part.open:
			continue
		var exterior: bool = part.other == -1
		var key := "%d/%.2f/%s/%s" % [part.axis, part.line, exterior, str(part.normal) if exterior else ""]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(part)
	var result: Array[Dictionary] = []
	for key: String in groups:
		var group: Array = groups[key]
		group.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.from < y.from)
		var current: Dictionary = {}
		for part: Dictionary in group:
			if not current.is_empty() and absf(float(current.to) - float(part.from)) < 0.001:
				current.to = part.to
				current.openings.append_array(part.openings)
				current.rooms.append(part.room)
				continue
			if not current.is_empty():
				result.append(current)
			current = {"axis": part.axis, "line": part.line, "from": part.from, "to": part.to,
				"exterior": part.other == -1, "normal": part.normal, "openings": part.openings.duplicate(),
				"rooms": [part.room]}
		if not current.is_empty():
			result.append(current)
	return result

static func _best_exterior(parts: Array[Dictionary], list: Array[Dictionary], kinds: Array, normal: Vector2, minimum: float) -> Dictionary:
	var best: Dictionary = {}
	var best_rank := 999.0
	for part: Dictionary in parts:
		if part.other != -1 or part.normal != normal or part.to - part.from < minimum:
			continue
		var rank: int = kinds.find(list[part.room].kind)
		if rank == -1:
			continue
		var score: float = rank * 100.0 - (part.to - part.from)
		if score < best_rank:
			best = part
			best_rank = score
	return best

## +1 when the centre of the house lies toward the part's "to" end, otherwise -1.
static func _toward(part: Dictionary, centre: Vector2) -> float:
	var middle := (float(part.from) + float(part.to)) * 0.5
	var target := centre.x if part.axis == 0 else centre.y
	return 1.0 if target > middle else -1.0

static func _cut(spans: Array, low: float, high: float) -> Array:
	var result := []
	for span: Array in spans:
		if high <= span[0] or low >= span[1]:
			result.append(span)
			continue
		if low > span[0]:
			result.append([span[0], low])
		if high < span[1]:
			result.append([high, span[1]])
	return result

static func _connected(list: Array[Dictionary]) -> bool:
	var seen := {0: true}
	var queue := [0]
	while not queue.is_empty():
		var current: int = queue.pop_back()
		for room: Dictionary in list:
			if seen.has(room.index):
				continue
			var a: Rect2 = list[current].rect
			var b: Rect2 = room.rect
			var touch := a.grow(SNAP).intersection(b.grow(SNAP))
			if touch.size.x > SNAP * 2.0 + 0.3 or touch.size.y > SNAP * 2.0 + 0.3:
				seen[room.index] = true
				queue.append(room.index)
	return seen.size() == list.size()

static func _title(kind: Variant, listed: Array, index: int) -> String:
	var same := 0
	var total := 0
	for i in listed.size():
		if listed[i].kind == kind and not listed[i].has("name"):
			total += 1
			if i <= index:
				same += 1
	var label := str(kind).capitalize()
	return label if total == 1 else "%s %d" % [label, same]

## Whole centimetres, so equal coordinates computed different ways compare equal.
static func _snap(value: float) -> float:
	return roundf(value * 100.0) / 100.0
