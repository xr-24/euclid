extends Node
## The wrist scanner reads the framed target and delegates edits to its owning service.

const Placement = preload("res://scripts/workshop/scene_placement.gd")
const Types = preload("res://scripts/workshop/entity_types.gd")
const Commands = preload("res://scripts/workshop/command_registry.gd")
const WaterEdits = preload("res://scripts/workshop/water_edits.gd")
const Preview = preload("res://scripts/ui/scanner_preview.gd")

var _water: WaterEdits
var _preview: Preview
var _tools
var _wrist
var _selection := ""
var _water_id := ""
var _selected_node: Node3D
var _rows: Array = []
var _label := ""
var _wait := 0.0
var _editable := true

func setup(path: String, wrist) -> void:
	_water = WaterEdits.new(path)
	_wrist = wrist
	_preview = Preview.new()
	add_child(_preview)

func attach(root: Node3D, zone: String, tools) -> void:
	_tools = tools
	_editable = root.get_meta("scene_edit", true)
	_water.attach(root, zone)
	clear()

func refresh_water(root: Node3D, zone: String) -> void:
	_water.attach(root, zone)
	if not _water_id.is_empty():
		clear()

func clear() -> void:
	if not _selection.is_empty() or not _water_id.is_empty():
		_preview.show_prop(null)
	_selection = ""
	_water_id = ""
	_selected_node = null
	_rows = []
	_label = ""
	_wait = 0.0

func tick(delta: float, player: CharacterBody3D, camera: Camera3D, pixel: Vector2) -> void:
	if _wrist.typing:
		return
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = 0.13
	var aim := Placement.aim_at(player, camera, pixel, 32.0)
	var water := _water.pick(aim)
	var id: String = "" if not water.is_empty() else aim.id
	var node: Node3D = _tools.scene_node(id) if not id.is_empty() else null
	if id == _selection and water == _water_id and node == _selected_node:
		return
	_selection = id
	_water_id = water
	_selected_node = node
	_wrist.reset_cursor("scan")
	_refresh()

func page() -> Dictionary:
	var result := {"id": "scan", "title": "SCAN", "rows": _rows, "scan_label": _label}
	if not _label.is_empty():
		result["preview"] = _preview.get_texture()
	return result

func _refresh() -> void:
	_rows = []
	_label = ""
	if not _water_id.is_empty():
		var body := _water.inspect(_water_id)
		if body.is_empty():
			return
		_label = body.label
		for key in body.rules:
			var value: Variant = body.values[key]
			_rows.append(_input_row(body.rules[key][0], value, _edit_water.bind(_water_id, key)))
		_rows.append({"label": "Reset water", "confirm": "M1 again to reset", "run": _edit_water.bind("", _water_id, ""),
			"enabled": _editable, "why": "Scene edits disabled"})
		var tint: String = body.values.get("scatter_color", body.values.get("shallow_color", "4f9c98"))
		_preview.show_water(Color.html(tint), float(body.values.get("base_roughness", body.values.get("roughness_value", 0.045))))
		return
	var result: Dictionary = _tools.execute("inspect", {"id": _selection})
	if not result.ok or not is_instance_valid(_selected_node):
		_preview.show_prop(null)
		return
	var record: Dictionary = result.entity
	_label = Types.label(record)
	_rows.append(_input_row("Name", record.get("name", ""), _edit_prop.bind(_selection, "name")))
	_rows.append(_input_row("Position XYZ", Placement.coordinates(_selected_node.position), _edit_prop.bind(_selection, "position")))
	_rows.append(_input_row("Rotation °", record.yaw, _edit_prop.bind(_selection, "yaw")))
	_rows.append(_input_row("Scale", record.scale, _edit_prop.bind(_selection, "scale")))
	if "color" in Commands.prop_fields(record.get("authored", false)):
		_rows.append(_input_row("Color", record.color, _edit_prop.bind(_selection, "color")))
	var can_simulate: bool = _tools.can_toggle_lock(_selection)
	var physics: bool = can_simulate and not record.get("locked", false)
	_rows.append(_toggle_row("Physics", physics, _toggle_physics.bind(_selection), can_simulate))
	_rows.append(_toggle_row(Commands.field("collision").title, record.collision, _toggle_collision.bind(_selection)))
	_preview.show_prop(_selected_node)

func _toggle_row(label: String, active: bool, action: Callable, supported := true) -> Dictionary:
	return {"label": label, "value": "On" if active else "Off", "run": action, "enabled": _editable and supported,
		"why": "This prop has no free-body physics" if not supported else "Scene edits disabled"}

func _input_row(label: String, value: Variant, action: Callable) -> Dictionary:
	var text := str(value)
	if value is float:
		text = "%.3f" % value
	if value is Array:
		text = " ".join(value.map(func(part: Variant) -> String: return "%.2f" % float(part)))
	return {"label": label, "value": text, "input": true, "entry": text, "run": action, "enabled": _editable, "why": "Scene edits disabled"}

func _edit_water(text: String, id: String, key: String) -> void:
	var error := _water.edit(id, key, text)
	_wrist.say("Water updated" if error.is_empty() else error, not error.is_empty())
	_refresh()

func _edit_prop(text: String, id: String, key: String) -> void:
	var value: Variant = text
	match key:
		"position":
			value = Array(text.replace(",", " ").split(" ", false)).map(func(part: String) -> Variant:
				return part.to_float() if part.is_valid_float() else null)
		"yaw", "scale":
			value = text.to_float() if text.is_valid_float() else null
		"color":
			value = text.trim_prefix("#")
	var changes := {key: value}
	var body := _tools.scene_node(id) as RigidBody3D
	if key in ["yaw", "scale", "color"] and body and not body.freeze and Placement.contains(_tools.bounds, body.position):
		changes["position"] = Placement.coordinates(body.position)
	var result: Dictionary = _tools.execute("edit", {"id": id, "changes": changes})
	_report(id, result)

func _toggle_collision(id: String) -> void:
	var inspected: Dictionary = _tools.execute("inspect", {"id": id})
	if inspected.ok:
		_report(id, _tools.execute("edit", {"id": id, "changes": {"collision": not inspected.entity.collision}}))

func _toggle_physics(id: String) -> void:
	var inspected: Dictionary = _tools.execute("inspect", {"id": id})
	if inspected.ok:
		_report(id, _tools.set_prop_physics(id, inspected.entity.get("locked", false)))

func _report(id: String, result: Dictionary) -> void:
	_wrist.say("Prop updated" if result.ok else result.error, not result.ok)
	_selected_node = _tools.scene_node(id)
	_refresh()
