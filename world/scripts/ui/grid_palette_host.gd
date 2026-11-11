extends "res://scripts/ui/panel_swap.gd"
## Stable owner of the replaceable Grid palette and its unsaved view. The swap itself is the shared
## panel lifecycle in panel_swap.gd; this file is the palette's contract.

signal agent_requested(prompt: String, placement: Array, panel: Control)

const Builtin = preload("res://scripts/ui/grid_palette.gd")
const Commands = preload("res://scripts/workshop/command_registry.gd")
const SOURCE_PATH := "res://scripts/ui/grid_palette.gd"
const METHODS := [&"setup", &"capture_view", &"restore_view", &"finish_agent_request"]

## The palette may read the world while it sets up, but not edit it or run workshop actions.
class SetupTools extends RefCounted:
	var delegate: RefCounted
	var bounds: AABB
	var action: Callable
	var ready := false
	var denied := false

	func execute(tool: String, arguments := {}) -> Dictionary:
		var definition := Commands.local(tool)
		if ready or (definition.get("effect") == "read" and definition.surfaces.has("palette")):
			return delegate.execute(tool, arguments)
		denied = true
		return {"ok": false, "error": "The palette tried to edit the world during setup."}

	func run_action(entry: Dictionary) -> Dictionary:
		if ready:
			return action.call(entry)
		denied = true
		return {"ok": false, "message": "Workshop actions are unavailable during palette setup."}

func mount(parent: Control, zone: String, at: Vector3, selected: String, tools: RefCounted,
		catalog: Callable, action: Callable) -> void:
	_mount({"parent": parent, "zone": zone, "tools": tools, "catalog": catalog, "action": action},
		{"spawn_at": at, "selected": selected})

func preview(candidate: Dictionary, zone: String, tools: RefCounted, catalog: Callable, action: Callable) -> Dictionary:
	return _preview(candidate, {"zone": zone, "tools": tools, "catalog": catalog, "action": action})

func _builtin() -> GDScript:
	return Builtin

func _source_path() -> String:
	return SOURCE_PATH

func _label() -> String:
	return "Grid palette"

func _noun() -> String:
	return "palette"

func _contract_name() -> String:
	return "version %d Grid palette" % Builtin.API_VERSION

func _active_hint() -> String:
	return "Press B in The Grid to try it."

func _short_hint() -> String:
	return "Press B to try it."

func _base_type() -> StringName:
	return &"VBoxContainer"

func _valid_code(code: GDScript) -> bool:
	if code.get_script_constant_map().get("API_VERSION") != Builtin.API_VERSION or not code.has_script_signal(&"agent_requested"):
		return false
	for method in METHODS:
		if not code.has_script_method(method):
			return false
	return true

func _initialize(widget: Control, context: Dictionary, view: Dictionary, live: bool) -> Dictionary:
	var tools := SetupTools.new()
	tools.delegate = context.tools
	tools.bounds = context.tools.bounds
	tools.action = context.action
	var initialized: Variant = widget.setup(tools, view.get("spawn_at", Vector3.ZERO), view.get("selected", ""),
		context.catalog, tools.run_action)
	var restored: Variant = widget.restore_view(view) if initialized == true else false
	if tools.denied:
		return {"ok": false, "detail": "The candidate attempted a world edit during setup."}
	if initialized != true or restored != true:
		return {"ok": false}
	tools.ready = live
	return {"ok": true}

func _capture_widget(widget: Control) -> Variant:
	var view: Variant = widget.capture_view()
	if not view is Dictionary or not view.get("selected") is String or not view.get("spawn_at") is Vector3:
		return null
	view["zone"] = _context.zone
	return view

func _connect_widget(widget: Control) -> void:
	widget.agent_requested.connect(func(prompt: String, placement: Array) -> void:
		agent_requested.emit(prompt, placement, widget))
