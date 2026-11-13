extends RefCounted
## Projects piece water into the solver and scanner, and keeps older authored prop IDs addressable.

const Props = preload("res://scripts/zones/authored_props.gd")
const WaterEdits = preload("res://scripts/workshop/water_edits.gd")

static func refresh(layer: Node3D) -> void:
	var zone := layer.get_parent() as Node3D
	if zone == null:
		return
	var water := {"sims": [], "floaters": [], "sources": [], "time": zone.get_meta("water", {}).get("time", 0.0)}
	var surfaces := []
	var previous_water: Dictionary = zone.get_meta("editable_water", {})
	var before: Dictionary = zone.get_meta("authored_dressing", {})
	var authored := {}
	for id in before:
		var node: Variant = before[id].node
		if is_instance_valid(node) and not layer.is_ancestor_of(node):
			authored[id] = before[id]
	zone.set_meta("authored_dressing", authored)
	zone.set_meta("editable_water", {})
	_collect(layer, zone, Transform3D.IDENTITY, water, surfaces, before, previous_water)
	zone.set_meta("water", water)
	zone.set_meta("water_surfaces", surfaces)

static func _collect(parent: Node3D, zone: Node3D, transform: Transform3D, water: Dictionary, surfaces: Array, before: Dictionary, previous_water: Dictionary) -> void:
	for child in parent.get_children():
		var node := child as Node3D
		if node == null or not node.has_meta("piece_id"):
			continue
		if node.has_meta("legacy_prop"):
			var options: Dictionary = node.get_meta("legacy_prop")
			var id: String = node.get_meta("piece_id")
			var entries: Dictionary = zone.get_meta("authored_dressing")
			var previous: Dictionary = before.get(id, {})
			if is_instance_valid(previous.get("node")) and previous.node == node and node.get_meta("piece_placement_changed", false):
				previous = previous.duplicate()
				previous["record"] = previous.record.merged({"position": [node.position.x, node.position.y, node.position.z],
					"yaw": node.rotation_degrees.y, "name": options.label}, true)
				previous["basis"] = node.basis
				node.remove_meta("piece_placement_changed")
				entries[id] = previous
			elif is_instance_valid(previous.get("node")) and previous.node == node:
				entries[id] = previous
			else:
				Props.register(zone, id, node, options.asset, node.rotation_degrees.y, options)
		if not node.visible:
			continue
		var local := transform * node.transform
		if node.has_meta("water_simulation"):
			water.sims.append(node.get_meta("water_simulation"))
		if node.has_meta("water_sea"):
			water["sea_level"] = node.get_meta("water_sea")
		if node.has_meta("water_source"):
			water.sources.append(local * node.get_meta("water_source"))
		if node.has_meta("water_floater"):
			water.floaters.append(node)
		if node.has_meta("editable_water"):
			(zone.get_meta("editable_water") as Dictionary).merge(node.get_meta("editable_water"), true)
		if node.has_meta("water_piece"):
			var surface: Dictionary = node.get_meta("water_piece")
			surfaces.append(surface)
			var mesh: MeshInstance3D = surface.surface
			if is_instance_valid(previous_water.get(surface.id, {}).get("surface_node")) and previous_water[surface.id].surface_node == mesh:
				zone.get_meta("editable_water")[surface.id] = previous_water[surface.id]
			else:
				WaterEdits.register_surface(zone, surface.id, surface.label, mesh, surface.size, surface.kind == "round")
		_collect(node, zone, local, water, surfaces, before, previous_water)
