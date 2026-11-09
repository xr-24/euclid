extends RefCounted
## A reviewed revision replaces an evaluator as a unit. Entity hosts keep their own state.

const Registry = preload("res://scripts/plugins/behavior_registry.gd")
const API_VERSION := 1
const SOURCE_LIMIT := 65536

var registry := Registry.new()
var observer: Node3D
var _active := {}
var _draft := {}

func _init(player: Node3D) -> void:
	observer = player
	reload_committed()

func reload_committed() -> void:
	for plugin in registry.list():
		var path := registry.script_path(plugin.id)
		var source := FileAccess.get_file_as_string(path)
		var compiled := _compile(plugin.id, source)
		if compiled.ok:
			_active[plugin.id] = compiled.code

func available(entity_type := "") -> Array[Dictionary]:
	return registry.list(entity_type).filter(func(item: Dictionary) -> bool: return _active.has(item.id))

func preview(candidate: Dictionary) -> Dictionary:
	var id: String = candidate.get("plugin", "")
	var draft_id: String = candidate.get("draft", "")
	var source: String = candidate.get("source", "")
	if draft_id.is_empty() or not _active.has(id) or source.sha256_text() != candidate.get("digest"):
		return _error("The reviewed behavior revision is unavailable or mismatched.")
	if not _draft.is_empty() and _draft.id != draft_id:
		return _error("Finish the current live preview before replacing it.")
	var compiled := _compile(id, source)
	if not compiled.ok:
		return compiled
	_draft = {"id": draft_id, "plugin": id, "code": compiled.code, "failed": false}
	return {"ok": true, "message": "Live preview active. Approach an entity with this behavior to try it."}

func finish(draft_id: String, keep: bool) -> bool:
	if _draft.is_empty() or _draft.id != draft_id:
		return false
	var active: bool = not _draft.failed
	if keep and active:
		_active[_draft.plugin] = _draft.code
	_draft = {}
	return active

func preview_status(draft_id: String) -> String:
	if _draft.is_empty() or _draft.id != draft_id:
		return ""
	return "failed" if _draft.failed else "active"

func evaluate(behavior: Dictionary, seconds: float, distance: float) -> float:
	var id: String = behavior.id
	var previewing: bool = _draft.get("plugin") == id and not _draft.failed
	var code: RefCounted = _draft.code if previewing else _active.get(id)
	if code == null:
		return 0.0
	var value: Variant = code.call("sample", seconds, distance, behavior.settings)
	if not _valid_output(value) and previewing:
		# A candidate can pass the probe and still fail for a particular entity.
		_draft.failed = true
		value = _active[id].call("sample", seconds, distance, behavior.settings)
	return float(value) if _valid_output(value) else 0.0

func _compile(id: String, source: String) -> Dictionary:
	if source.is_empty() or source.to_utf8_buffer().size() > SOURCE_LIMIT:
		return _error("Behavior source is missing or exceeds 64 KiB.")
	var code := GDScript.new()
	code.source_code = source
	if code.reload() != OK or not code.can_instantiate() or code.get_instance_base_type() != &"RefCounted" \
			or code.get_script_constant_map().get("API_VERSION") != API_VERSION or not code.has_script_method(&"sample"):
		return _error("The script could not load as a version 1 behavior.")
	var sample_method := {}
	for method in code.get_script_method_list():
		if method.name == &"sample":
			sample_method = method
			break
	# Probe the evaluator before it can replace the active implementation.
	if sample_method.is_empty() or sample_method.args.size() != 3:
		return _error("A behavior must provide sample(seconds, distance, settings).")
	var instance: RefCounted = code.new()
	if instance == null:
		return _error("The behavior could not be instantiated.")
	for plugin in registry.list():
		if plugin.id == id:
			var config := registry.configure(plugin.entity_type, {"id": id, "settings": {}})
			config.settings.make_read_only()
			for distance in [0.0, 2.0, 12.0]:
				if not _valid_output(instance.call("sample", 0.25, distance, config.settings)):
					return _error("Behavior sample must return a finite value from zero to one.")
			return {"ok": true, "code": instance}
	return _error("This behavior is not registered.")

static func _valid_output(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and float(value) >= 0.0 and float(value) <= 1.0

static func _error(message: String) -> Dictionary:
	return {"ok": false, "message": message}
