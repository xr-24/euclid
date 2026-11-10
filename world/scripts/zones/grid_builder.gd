extends RefCounted
## Adapts the Grid renderer to the common environment-builder contract.

const Grid = preload("res://scripts/zones/grid_zone.gd")

static func build(context: RefCounted) -> bool:
	return Grid.build(context.build_root, context.appearance)
