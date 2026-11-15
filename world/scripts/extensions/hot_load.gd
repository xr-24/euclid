extends RefCounted
## Hot loading: changed project files reach the running world without a restart, whatever they
## are. A draft's files are overlaid on res:// as a resource pack, so every later read sees them
## while the checkout stays untouched. Then each file gets the least disruptive tier that covers it
## (data/hot_reload.json explains the tiers and holds the rules agents can extend):
##   instant   shader code swaps on the loaded shader; every material using it updates
##   in_place  the file is overlaid; scripts reload keeping their state; resources reload in place
##   zone      the current environment rebuilds around the player
##   restart   an in-process soft restart of the world: for scripts whose variables changed, and
##             for data a loaded script keeps its own copy of, which it re-reads when it restarts
## Errors raised from changed scripts in the first seconds roll the change back. State is static so
## a held preview survives a soft restart.

const RULES := "res://data/hot_reload.json"
const TIERS := ["instant", "in_place", "zone", "restart"]
const TEXT := ["gd", "gdshader", "gdshaderinc", "json", "tscn", "tres", "cfg", "txt", "md", "csv"]
const MAX_BYTES := 4 * 1024 * 1024
## Seconds after a change during which errors from its scripts roll it back.
const WATCH := 6.0

## Errors raised from the changed scripts, for the rollback watch and the probe compile.
class Watch extends Logger:
	var paths := {}
	var _errors: Array[String] = []
	var _mutex := Mutex.new()

	func _log_error(_function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, traces: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING:
			return
		var at := "%s:%d" % [file, line] if paths.has(file) else ""
		if at.is_empty():
			for trace in traces:
				for index in trace.get_frame_count():
					if paths.has(trace.get_frame_file(index)):
						at = "%s:%d" % [trace.get_frame_file(index), trace.get_frame_line(index)]
						break
				if not at.is_empty():
					break
		if not at.is_empty():
			_mutex.lock()
			_errors.append("%s  %s" % [at.trim_prefix("res://"), rationale if not rationale.is_empty() else code])
			_mutex.unlock()

	func take() -> Array[String]:
		_mutex.lock()
		var errors := _errors.duplicate()
		_errors.clear()
		_mutex.unlock()
		return errors

## draft id -> {"version", "files": {res path: text}, "originals": {res path: text}, "tier", "status", "error"}
static var _held := {}
static var _serial := 0
static var _watch: Watch
static var _watch_draft := ""
static var _watch_until := 0

## Whether a project path (world/...) can be hot loaded: a text file the project reads, other than
## the engine settings, which only a full restart applies.
static func supports(path: String) -> bool:
	var local := path.trim_prefix("world/")
	return path.begins_with("world/") and local != "project.godot" and local.get_extension() in TEXT \
		and not local.begins_with(".godot/") and not local.contains("..")

static func status(draft: String) -> String:
	return str(_held.get(draft, {}).get("status", ""))

static func held(draft: String) -> Dictionary:
	return _held.get(draft, {})

## Check the files without applying them: scripts compile, JSON parses. Returns "" or the error.
static func gate(files: Dictionary) -> String:
	var watch := Watch.new()
	OS.add_logger(watch)
	var problem := ""
	for path: String in files:
		var text: String = files[path]
		match path.get_extension():
			"gd":
				var probe := GDScript.new()
				probe.source_code = _probe_source(text)
				for key in files:
					watch.paths[key] = true
				if probe.reload() != OK:
					var errors := watch.take()
					problem = "%s does not compile%s" % [path.trim_prefix("res://"), (": " + errors[0]) if not errors.is_empty() else "."]
			"json":
				var json := JSON.new()
				if json.parse(text) != OK:
					problem = "%s:%d  %s" % [path.trim_prefix("res://"), json.get_error_line(), json.get_error_message()]
		if not problem.is_empty():
			break
	OS.remove_logger(watch)
	return problem

## The tier a set of changed files needs, and why.
static func plan(files: Dictionary) -> Dictionary:
	var tier := "instant"
	var reasons: Array[String] = []
	var rules: Array = _rules()
	for path: String in files:
		var need := "in_place"
		var why := ""
		var extension := path.get_extension()
		if extension in ["gdshader", "gdshaderinc"]:
			need = "instant"
		elif extension == "gd" and ResourceLoader.has_cached(path):
			var change := _layout_change(load(path), files[path])
			if not change.is_empty():
				need = "restart"
				why = "%s %s" % [path.get_file(), change]
		elif extension not in ["gd", "tscn", "tres"]:
			var readers := _scripts_reading([path]).filter(func(script: String) -> bool: return ResourceLoader.has_cached(script))
			if not readers.is_empty():
				need = "restart"
				why = "%s keeps its own copy of %s" % [str(readers[0]).get_file(), path.get_file()]
		var local := path.trim_prefix("res://")
		for rule: Dictionary in rules:
			if local.match(str(rule.get("files", ""))) and TIERS.find(str(rule.get("tier"))) > TIERS.find(need):
				need = str(rule.tier)
				why = "%s is built when the environment loads" % path.get_file() if need == "zone" else "%s needs the world restarted" % path.get_file()
		if TIERS.find(need) > TIERS.find(tier):
			tier = need
		if not why.is_empty():
			reasons.append(why)
	return {"tier": tier, "reasons": reasons}

## Apply a draft's files. host holds callables from the world: "rebuild_zone" (awaitable),
## "soft_restart"(between: Callable) and "busy" (-> bool). Returns {"ok", "message", "tier"}.
static func apply(draft: String, version: String, files: Dictionary, host: Dictionary) -> Dictionary:
	var size := 0
	for path in files:
		size += str(files[path]).length()
	if size > MAX_BYTES:
		return {"ok": false, "message": "This draft is too large to hot load. Commit it and restart Euclid."}
	if host.has("busy") and host.busy.call():
		return {"ok": false, "message": "Wait for the environment to finish loading, then try again."}
	var problem := gate(files)
	if not problem.is_empty():
		return {"ok": false, "message": "Not loaded: " + problem}
	var previous: Dictionary = _held.get(draft, {})
	var originals: Dictionary = previous.get("originals", {}).duplicate()
	for path in files:
		if not originals.has(path):
			originals[path] = _current(path)
	var planned := plan(files)
	var result := await _install(files, planned.tier, host)
	if not result.ok:
		return result
	_held[draft] = {"version": version, "files": files, "originals": originals, "tier": planned.tier, "status": "active", "error": ""}
	_start_watch(draft, files)
	var how := {"instant": "Swapped in place.", "in_place": "Reloaded in place.",
		"zone": "Rebuilt this environment.", "restart": "Restarted the world in place."}
	var message := "Loaded %d file%s live. %s" % [files.size(), "" if files.size() == 1 else "s", how[planned.tier]]
	if not planned.reasons.is_empty():
		message += " (" + "; ".join(planned.reasons) + ")"
	return {"ok": true, "message": message, "tier": planned.tier}

## Keep a held draft (it was committed) or put the files back as they were (it was discarded).
static func finish(draft: String, keep: bool, host: Dictionary) -> bool:
	if not _held.has(draft):
		return false
	var record: Dictionary = _held[draft]
	_held.erase(draft)
	if _watch_draft == draft:
		_stop_watch()
	if not keep:
		var originals: Dictionary = record.originals
		await _install(originals, plan(originals).tier, host)
	return true

## Load files exactly as they are on disk now, after a commit or a revert of drafts that were not
## held live. Only files whose loaded version differs are applied. Returns the same as apply.
static func apply_disk(paths: Array, host: Dictionary) -> Dictionary:
	var files := {}
	for path: String in paths:
		if not supports(path):
			continue
		var local := "res://" + path.trim_prefix("world/")
		var disk := ProjectSettings.globalize_path(local)
		var text := FileAccess.get_file_as_string(disk) if FileAccess.file_exists(disk) else ""
		if text != _current(local):
			files[local] = text
	if files.is_empty():
		return {"ok": true, "message": "", "tier": ""}
	_serial += 1
	return await apply("disk-%d" % _serial, "", files, host)

## Turn the watch over: report and roll back a held draft whose scripts raised errors.
static func poll(host: Dictionary) -> String:
	if _watch == null:
		return ""
	var errors := _watch.take()
	var draft := _watch_draft
	if errors.is_empty():
		if Time.get_ticks_msec() > _watch_until:
			_stop_watch()
		return ""
	_stop_watch()
	if not _held.has(draft):
		return ""
	var record: Dictionary = _held[draft]
	await _install(record.originals, plan(record.originals).tier, host)
	record.status = "failed"
	record.error = errors[0]
	return "Rolled back the live change: " + errors[0]

## Overlay the files, then bring the world up to date at the given tier.
static func _install(files: Dictionary, tier: String, host: Dictionary) -> Dictionary:
	if not _overlay(files):
		return {"ok": false, "message": "Could not overlay the changed files."}
	if tier == "restart":
		if not host.has("soft_restart"):
			return {"ok": false, "message": "This change needs Euclid restarted."}
		host.soft_restart.call(func() -> void: _swap(files, true))
		return {"ok": true}
	_swap(files, false)
	if tier == "zone" and host.has("rebuild_zone"):
		await host.rebuild_zone.call()
	return {"ok": true}

## Write the files into a new pack and mount it over res://. Later packs win.
static func _overlay(files: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute("user://hot")
	_serial += 1
	var pack := "user://hot/overlay-%d-%d.zip" % [OS.get_process_id(), _serial]
	var zip := ZIPPacker.new()
	if zip.open(pack) != OK:
		return false
	for path: String in files:
		zip.start_file(path.trim_prefix("res://"))
		zip.write_file(str(files[path]).to_utf8_buffer())
		zip.close_file()
	zip.close()
	return ProjectSettings.load_resource_pack(pack, true)

## Update what is already loaded. after_free is true during a soft restart, when the old world is
## gone: scripts then reload completely, re-running static initialisers, and scripts that keep a
## copy of a changed file re-read it.
static func _swap(files: Dictionary, after_free: bool) -> void:
	var reloaded := {}
	for path: String in files:
		if not ResourceLoader.has_cached(path):
			continue
		var text: String = files[path]
		match path.get_extension():
			"gdshader", "gdshaderinc":
				var shader: Resource = load(path)
				shader.set("code", text)
			"gd":
				var script: GDScript = load(path)
				script.source_code = text
				_reload(script, after_free)
				reloaded[path] = true
			_:
				ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
	if after_free:
		var data := files.keys().filter(func(path: String) -> bool: return path.get_extension() not in ["gd", "gdshader", "gdshaderinc", "tscn", "tres"])
		for script_path in _scripts_reading(data) if not data.is_empty() else []:
			if not reloaded.has(script_path) and ResourceLoader.has_cached(script_path):
				_reload(load(script_path), true)
	_notify(reloaded.keys())

## Reload a script keeping its instances and static state, or, during a soft restart, completely.
## Objects that outlive the old world keep the script in use; it then reloads keeping state.
static func _reload(script: GDScript, complete: bool) -> void:
	if complete and script.reload(false) == OK:
		return
	script.reload(true)

## Nodes running a reloaded script may restart their work in _hot_reload(), for example a polling
## loop whose pending await the reload ended.
static func _notify(paths: Array) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or paths.is_empty():
		return
	var wanted := {}
	for path in paths:
		wanted[path] = true
	var stack: Array[Node] = [tree.root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var own := node.get_script() as Script
		if own != null and wanted.has(own.resource_path) and node.has_method("_hot_reload"):
			node.call_deferred("_hot_reload")
		stack.append_array(node.get_children(true))

## Project scripts that name one of these files by its full path. Files found by building a path,
## such as an environment's pieces, are covered by the rules instead.
static func _scripts_reading(paths: Array) -> Array[String]:
	var needles: Array[String] = []
	for path: String in paths:
		needles.append(path.trim_prefix("res://"))
	var found: Array[String] = []
	var folders: Array[String] = ["res://scripts"]
	while not folders.is_empty():
		var folder: String = folders.pop_back()
		for sub in DirAccess.get_directories_at(folder):
			folders.append(folder.path_join(sub))
		for file in DirAccess.get_files_at(folder):
			if file.get_extension() != "gd":
				continue
			var path := folder.path_join(file)
			var text := FileAccess.get_file_as_string(path)
			if needles.any(func(needle: String) -> bool: return text.contains(needle)):
				found.append(path)
	return found

## What changed in a loaded script that objects already running cannot take: "" if nothing.
static func _layout_change(script: GDScript, text: String) -> String:
	var probe := GDScript.new()
	probe.source_code = _probe_source(text)
	if probe.reload() != OK:
		return ""
	if probe.get_instance_base_type() != script.get_instance_base_type() or probe.get_base_script() != script.get_base_script():
		return "changed what it extends"
	if _members(probe) != _members(script):
		return "changed its variables"
	return ""

static func _members(script: Script) -> Array:
	var names := []
	for property in script.get_script_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			names.append("%s:%d" % [property.name, property.type])
	return names

## A probe compiles without its class_name, which would clash with the loaded script's.
static func _probe_source(text: String) -> String:
	var lines := text.split("\n")
	for index in lines.size():
		if lines[index].begins_with("class_name "):
			lines[index] = ""
	return "\n".join(lines)

## The file as the running world sees it now: overlays included.
static func _current(path: String) -> String:
	if ResourceLoader.has_cached(path) and path.get_extension() == "gd":
		return (load(path) as GDScript).source_code
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""

static func _rules() -> Array:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(RULES)) if FileAccess.file_exists(RULES) else null
	return value.get("rules", []) if value is Dictionary and value.get("schema_version") == 1 else []

static func _start_watch(draft: String, files: Dictionary) -> void:
	_stop_watch()
	_watch = Watch.new()
	for path: String in files:
		if path.get_extension() == "gd":
			_watch.paths[path] = true
	if _watch.paths.is_empty():
		_watch = null
		return
	OS.add_logger(_watch)
	_watch_draft = draft
	_watch_until = Time.get_ticks_msec() + int(WATCH * 1000.0)

static func _stop_watch() -> void:
	if _watch != null:
		OS.remove_logger(_watch)
	_watch = null
	_watch_draft = ""
