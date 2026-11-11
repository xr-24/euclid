extends Node
## Hot-swaps one UI panel from reviewed source while the world keeps running. The host compiles a
## checked candidate, builds it in place of the working panel with the same view, watches the engine
## log for errors raised from that script, and falls back to the committed panel, then the built-in
## one. Commit keeps the candidate; discard restores the working panel.
##
## A subclass describes one panel's contract by overriding the hooks below: its built-in script and
## source path, the checks a candidate script must pass, how a new instance is set up with the
## mount context and view, how its view is captured, and which signals the host relays.

signal preview_failed(message: String)

class PreviewLogger extends Logger:
	var script_path: String
	var source_path: String
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
			_error = "%s:%d  %s" % [source_path, location, rationale if not rationale.is_empty() else code]
			_mutex.unlock()

	func take_error() -> String:
		_mutex.lock()
		var message := _error
		_error = ""
		_mutex.unlock()
		return message

var panel: Control
var _committed: GDScript
var _draft := {}
var _saved := {}
var _context := {}
var _mounted_view := {}
var _logger: PreviewLogger
var _generation := 0

# --- The panel's contract. Subclasses override these. ---

## The script the panel falls back to when nothing better loads.
func _builtin() -> GDScript:
	return null

## Where the committed source lives, as res://.
func _source_path() -> String:
	return ""

## The panel's name in messages, such as "Grid palette", and a short noun, such as "palette".
func _label() -> String:
	return "panel"

func _noun() -> String:
	return "panel"

## What a candidate must be, for messages: "version 1 Grid palette".
func _contract_name() -> String:
	return _label()

## Shown after a preview starts, such as "Press B in The Grid to try it."
func _active_hint() -> String:
	return ""

## The engine class every candidate must extend.
func _base_type() -> StringName:
	return &"Control"

## Further checks on a compiled candidate: API version, methods and signals.
func _valid_code(_code: GDScript) -> bool:
	return true

## Sets up a new instance with the mount context and restores the view. live is false for a probe
## built away from the screen. Returns {"ok": bool, "detail": String}.
func _initialize(_widget: Control, _mount_context: Dictionary, _view: Dictionary, _live: bool) -> Dictionary:
	return {"ok": true}

## The instance's view as a Dictionary, or null when it cannot report one.
func _capture_widget(_widget: Control) -> Variant:
	return {}

## Connects the instance's signals once it is the mounted panel.
func _connect_widget(_widget: Control) -> void:
	pass

# --- The shared lifecycle. ---

func _init() -> void:
	_committed = _builtin()

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

## Mounts the panel in context.parent. A view saved in the same zone takes precedence over view.
func _mount(context: Dictionary, view: Dictionary) -> void:
	_context = context
	if not _saved.is_empty() and _saved.get("zone") == context.get("zone"):
		view = _saved
	_saved = {}
	var code: GDScript = _draft.get("code", _committed)
	if not _replace(code, view):
		if code != _committed:
			var failure := _fail("The preview could not reopen with the saved %s state." % _noun())
			_restore_working(view)
			preview_failed.emit(failure.message)
		elif code != _builtin():
			_replace(_builtin(), view)

## Previews a reviewed candidate {draft, version, source, digest}. probe_context sets up a probe when
## no panel is mounted, so a broken candidate fails before anyone opens it.
func _preview(candidate: Dictionary, probe_context: Dictionary) -> Dictionary:
	var source: String = candidate.get("source", "")
	var id: String = candidate.get("draft", "")
	var version: String = candidate.get("version", "")
	if id.is_empty() or version.is_empty() or source.is_empty() or source.sha256_text() != candidate.get("digest"):
		return _error("The reviewed %s source is unavailable or mismatched." % _noun())
	if status(id) == "active" and _draft.version == version:
		return {"ok": true, "message": ("The %s preview is active. %s" % [_label(), _short_hint()]).strip_edges()}
	if is_instance_valid(panel) and _draft.has("code"):
		var previous := _capture()
		_stop_logging()
		_restore_working(previous)
	_stop_logging()
	_draft = {"id": id, "version": version}
	var script_path := _script_path()
	_logger = PreviewLogger.new()
	_logger.script_path = script_path
	_logger.source_path = _source_path()
	OS.add_logger(_logger)
	var code := _compile(source, script_path)
	if code == null:
		return _fail("The script could not load as a %s." % _contract_name())
	var view := _capture() if is_instance_valid(panel) else (_saved if _saved.get("zone") == probe_context.get("zone") else {})
	if is_instance_valid(panel):
		if not _replace(code, view):
			return _fail("The candidate could not restore the %s view." % _label())
	else:
		var probe := _build(code, self, probe_context, view)
		if probe == null:
			return _fail("The candidate could not build the %s." % _label())
		_dispose(probe)
	_draft.code = code
	set_process(true)
	return {"ok": true, "message": ("%s preview active. %s" % [_label(), _active_hint()]).strip_edges()}

## A shorter hint for an already active preview. Subclasses may override.
func _short_hint() -> String:
	return _active_hint()

func status(id: String) -> String:
	if id.is_empty() or _draft.get("id") != id:
		return ""
	return "failed" if _draft.has("error") else ("active" if _draft.has("code") else "")

func error_log(id: String, version: String) -> String:
	return _draft.get("error", "") if _draft.get("id") == id and _draft.get("version") == version else ""

## A preview belongs to one reviewed version. When another version comes into review, it stops.
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
	var source := FileAccess.get_file_as_string(_source_path())
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
	if code.reload() != OK or not code.can_instantiate() or code.get_instance_base_type() != _base_type():
		return null
	return code if _valid_code(code) else null

func _script_path() -> String:
	_generation += 1
	return "user://%s-%d-%d.gd" % [_noun().replace(" ", "-"), get_instance_id(), _generation]

func _build(code: GDScript, parent: Node, context: Dictionary, view: Dictionary) -> Control:
	var result: Variant = code.new()
	if not result is Control:
		return null
	var widget: Control = result
	widget.hide()
	parent.add_child(widget)
	if widget.get_parent() != parent:
		widget.queue_free()
		return null
	var outcome: Dictionary = _initialize(widget, context, view, parent != self)
	var reported := _logger.take_error() if _logger else ""
	if not outcome.get("ok", false) or not reported.is_empty() or widget.is_queued_for_deletion():
		var detail: String = reported if not reported.is_empty() else str(outcome.get("detail", ""))
		if not detail.is_empty():
			_draft["detail"] = detail
		_dispose(widget)
		return null
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
	_connect_widget(replacement)
	panel.show()
	return true

func _capture() -> Dictionary:
	if not is_instance_valid(panel):
		return {}
	var view: Variant = _capture_widget(panel)
	if not view is Dictionary:
		return _mounted_view.duplicate(true)
	return view

func _restore_working(view: Dictionary) -> void:
	if not _replace(_committed, view) and _committed != _builtin():
		_replace(_builtin(), view)

func _dispose(widget: Control) -> void:
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
	return _error(_draft.error + " The working %s is available." % _label())

static func _error(message: String) -> Dictionary:
	return {"ok": false, "message": message}
