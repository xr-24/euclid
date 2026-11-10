extends Node
## Stable owner of the replaceable Grid palette and its unsaved view.

signal agent_requested(prompt: String, placement: Array, panel: Control)
signal preview_failed(message: String)

const Builtin = preload("res://scripts/ui/grid_palette.gd")
const SOURCE_PATH := "res://scripts/ui/grid_palette.gd"
const METHODS := [&"setup", &"capture_view", &"restore_view", &"finish_agent_request"]

class SetupTools extends RefCounted:
	const READS := ["list", "inspect", "list_entities", "list_behaviors", "list_prefabs", "list_scene_assets"]
	var delegate: RefCounted
	var bounds: AABB
	var action: Callable
	var ready := false
	var denied := false

	func execute(tool: String, arguments := {}) -> Dictionary:
		if ready or tool in READS:
			return delegate.execute(tool, arguments)
		denied = true
		return {"ok": false, "error": "The palette tried to edit the world during setup."}

	func run_action(entry: Dictionary) -> Dictionary:
		if ready:
			return action.call(entry)
		denied = true
		return {"ok": false, "message": "Workshop actions are unavailable during palette setup."}

class PreviewLogger extends Logger:
	var script_path: String
	var _error := ""
	var _mutex := Mutex.new()

	func _log_error(_function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, traces: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING:
			return
		var location := line if file == script_path else -1
		if location < 0:
			for trace in traces:
				for index in trace.get_frame_count():
					if trace.get_frame_file(index) == script_path:
						location = trace.get_frame_line(index)
						break
				if location >= 0:
					break
		if location >= 0:
			_mutex.lock()
			_error = "%s:%d  %s" % [SOURCE_PATH, location, rationale if not rationale.is_empty() else code]
			_mutex.unlock()

	func take_error() -> String:
		_mutex.lock()
		var message := _error
		_error = ""
		_mutex.unlock()
		return message

var panel: VBoxContainer
var _committed: GDScript = Builtin
var _draft := {}
var _saved := {}
var _context := {}
var _mounted_view := {}
var _logger: PreviewLogger
var _generation := 0

func _ready() -> void:
	set_process(false)

func _exit_tree() -> void:
	_stop_logging()

func unmount(remember: bool) -> void:
	if not is_instance_valid(panel):
		return
	_saved = _capture() if remember else {}
	panel = null
	_context = {}

func clear_view() -> void:
	_saved.clear()
	if is_instance_valid(panel):
		_dispose(panel)
	panel = null
	_context = {}

func mount(parent: Control, zone: String, at: Vector3, selected: String, tools: RefCounted,
		catalog: Callable, action: Callable) -> void:
	_context = {"parent": parent, "zone": zone, "tools": tools, "catalog": catalog, "action": action}
	var view := {"spawn_at": at, "selected": selected}
	if _saved.get("zone") == zone:
		view = _saved
	_saved = {}
	var code: GDScript = _draft.get("code", _committed)
	if not _replace(code, view):
		if code != _committed:
			var failure := _fail("The preview could not reopen with the saved palette state.")
			_restore_working(view)
			preview_failed.emit(failure.message)
		elif code != Builtin:
			_replace(Builtin, view)

func preview(candidate: Dictionary, zone: String, tools: RefCounted, catalog: Callable, action: Callable) -> Dictionary:
	var source: String = candidate.get("source", "")
	var id: String = candidate.get("draft", "")
	var version: String = candidate.get("version", "")
	if id.is_empty() or version.is_empty() or source.is_empty() or source.sha256_text() != candidate.get("digest"):
		return _error("The reviewed palette source is unavailable or mismatched.")
	if status(id) == "active" and _draft.version == version:
		return {"ok": true, "message": "The Grid palette preview is active. Press B to try it."}
	if is_instance_valid(panel) and _draft.has("code"):
		var previous := _capture()
		_stop_logging()
		_restore_working(previous)
	_stop_logging()
	_draft = {"id": id, "version": version}
	var script_path := _script_path()
	_logger = PreviewLogger.new()
	_logger.script_path = script_path
	OS.add_logger(_logger)
	var code := _compile(source, script_path)
	if code == null:
		return _fail("The script could not load as a version 1 Grid palette.")
	var view := _capture() if is_instance_valid(panel) else (_saved if _saved.get("zone") == zone else {})
	if is_instance_valid(panel):
		if not _replace(code, view):
			return _fail("The candidate could not restore the Grid palette view.")
	else:
		var probe := _build(code, self, {"tools": tools, "catalog": catalog, "action": action}, view)
		if probe == null:
			return _fail("The candidate could not build the Grid palette.")
		_dispose(probe)
	_draft.code = code
	set_process(true)
	return {"ok": true, "message": "Grid palette preview active. Press B in The Grid to try it."}

func status(id: String) -> String:
	if id.is_empty() or _draft.get("id") != id:
		return ""
	return "failed" if _draft.has("error") else ("active" if _draft.has("code") else "")

func error_log(id: String, version: String) -> String:
	return _draft.get("error", "") if _draft.get("id") == id and _draft.get("version") == version else ""

func observe(id: String, version: String) -> void:
	if not _draft.is_empty() and not version.is_empty() and (_draft.id != id or _draft.version != version):
		finish(_draft.id, false)

func finish(id: String, keep: bool) -> bool:
	var state := status(id)
	if state.is_empty():
		return false
	var active := state == "active"
	if keep and active:
		_committed = _draft.code
	elif active and is_instance_valid(panel):
		var view := _capture()
		_stop_logging()
		_restore_working(view)
	_draft.clear()
	_stop_logging()
	return active

func reload_committed() -> void:
	var source := FileAccess.get_file_as_string(SOURCE_PATH)
	if not source.is_empty() and source != _committed.source_code:
		var code := _compile(source, _script_path())
		if code != null and (not is_instance_valid(panel) or _replace(code, _capture())):
			_committed = code

func _process(_delta: float) -> void:
	var error := _logger.take_error()
	if not error.is_empty():
		var view := _capture()
		_fail(error)
		if is_instance_valid(panel):
			_restore_working(view)
		preview_failed.emit(_draft.error)

func _compile(source: String, script_path: String) -> GDScript:
	var code := GDScript.new()
	code.resource_path = script_path
	code.source_code = source
	if code.reload() != OK or not code.can_instantiate() or code.get_instance_base_type() != &"VBoxContainer":
		return null
	if code.get_script_constant_map().get("API_VERSION") != Builtin.API_VERSION or not code.has_script_signal(&"agent_requested"):
		return null
	for method in METHODS:
		if not code.has_script_method(method):
			return null
	return code

func _script_path() -> String:
	_generation += 1
	return "user://grid-palette-%d-%d.gd" % [get_instance_id(), _generation]

func _build(code: GDScript, parent: Node, context: Dictionary, view: Dictionary) -> VBoxContainer:
	var tools := SetupTools.new()
	tools.delegate = context.tools
	tools.bounds = context.tools.bounds
	tools.action = context.action
	var result: Variant = code.new()
	if not result is VBoxContainer:
		return null
	var widget: VBoxContainer = result
	widget.hide()
	parent.add_child(widget)
	if widget.get_parent() != parent:
		widget.queue_free()
		return null
	var initialized: Variant = widget.setup(tools, view.get("spawn_at", Vector3.ZERO), view.get("selected", ""),
		context.catalog, tools.run_action)
	var restored: Variant = widget.restore_view(view) if initialized == true else false
	var reported := _logger.take_error() if _logger else ""
	if initialized != true or restored != true or tools.denied or not reported.is_empty() or widget.is_queued_for_deletion():
		if not reported.is_empty():
			_draft["detail"] = reported
		elif tools.denied:
			_draft["detail"] = "The candidate attempted a world edit during setup."
		_dispose(widget)
		return null
	tools.ready = parent != self
	return widget

func _replace(code: GDScript, view: Dictionary) -> bool:
	var parent: Control = _context.parent
	var replacement := _build(code, parent, _context, view)
	if replacement == null:
		return false
	if is_instance_valid(panel):
		var index := panel.get_index()
		_dispose(panel)
		parent.move_child(replacement, index)
	panel = replacement
	_mounted_view = view.duplicate(true)
	panel.agent_requested.connect(func(prompt: String, placement: Array) -> void:
		agent_requested.emit(prompt, placement, replacement))
	panel.show()
	return true

func _capture() -> Dictionary:
	if not is_instance_valid(panel):
		return {}
	var view: Variant = panel.capture_view()
	if not view is Dictionary or not view.get("selected") is String or not view.get("spawn_at") is Vector3:
		return _mounted_view.duplicate(true)
	view["zone"] = _context.zone
	return view

func _restore_working(view: Dictionary) -> void:
	if not _replace(_committed, view) and _committed != Builtin:
		_replace(Builtin, view)

func _dispose(widget: VBoxContainer) -> void:
	if widget.get_parent() != null:
		widget.get_parent().remove_child(widget)
	widget.queue_free()

func _stop_logging() -> void:
	set_process(false)
	if _logger:
		OS.remove_logger(_logger)
		_logger = null

func _fail(message: String) -> Dictionary:
	var detail: String = _draft.get("detail", "")
	if detail.is_empty() and _logger:
		detail = _logger.take_error()
	_draft.erase("code")
	_draft["error"] = message if detail.is_empty() else message + "\n" + detail
	_stop_logging()
	return _error(_draft.error + " The working Grid palette is available.")

static func _error(message: String) -> Dictionary:
	return {"ok": false, "message": message}
