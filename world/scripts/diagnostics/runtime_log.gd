extends Logger
## Thread-safe bounded ring buffer capturing Godot runtime logs, warnings, and errors.

const MAX_ENTRIES := 200

static var _entries: Array[Dictionary] = []
static var _mutex := Mutex.new()
static var _logger: Logger
static var _installed := false

static func install() -> void:
	_mutex.lock()
	if _installed:
		_mutex.unlock()
		return
	_installed = true
	var instance: Logger = new()
	_logger = instance
	_mutex.unlock()
	OS.add_logger(instance)

static func record(level: String, message: String, file := "", line := 0) -> void:
	_mutex.lock()
	_entries.append({
		"at_ms": Time.get_ticks_msec(),
		"level": level,
		"file": file.trim_prefix("res://"),
		"line": line,
		"message": message.left(500),
	})
	while _entries.size() > MAX_ENTRIES:
		_entries.pop_front()
	_mutex.unlock()

static func tail(limit := 50, level := "all") -> Array[Dictionary]:
	var count := clampi(limit, 1, MAX_ENTRIES)
	var filter_level := level in ["error", "warning", "info"]
	_mutex.lock()
	var filtered: Array[Dictionary] = []
	for entry in _entries:
		if not filter_level or entry.get("level", "") == level:
			filtered.append(entry.duplicate())
	_mutex.unlock()
	if filtered.size() <= count:
		return filtered
	var result: Array[Dictionary] = []
	for index in range(filtered.size() - count, filtered.size()):
		result.append(filtered[index])
	return result

static func clear() -> void:
	_mutex.lock()
	_entries.clear()
	_mutex.unlock()

func _log_error(function: String, file: String, line: int, code: String, rationale: String,
		_editor_notify: bool, error_type: int, _traces: Array[ScriptBacktrace]) -> void:
	var level := "warning" if error_type == Logger.ERROR_TYPE_WARNING else "error"
	var msg := rationale if not rationale.is_empty() else code
	if msg.is_empty():
		msg = function
	record(level, msg, file, line)

func _log_message(message: String, error: bool) -> void:
	var text := message.strip_edges()
	if text.is_empty():
		return
	record("error" if error else "info", text)
