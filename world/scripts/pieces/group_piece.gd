extends RefCounted
## A group holds child pieces so they move, turn and hide together.

static func build(_record: Dictionary) -> Node3D:
	return Node3D.new()
