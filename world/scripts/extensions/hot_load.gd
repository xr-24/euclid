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
	## Catch every error, not only those from the watched scripts (the shader gate).
	var any := false
	var _errors: Array[String] = []
	var _mutex := Mutex.new()

	func _log_error(_function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, traces: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING:
			return
		var at := "%s:%d" % [file, line] if paths.has(file) or any else ""
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

## Each file shows the top of a stack of layers over its committed text: one layer per live draft.
## Discarding a draft removes only its layers; committing one folds them into the base.
static var _base := {}
## path -> Array of [draft, text], bottom first
static var _layers := {}
## draft id -> {"version", "files": {path: text}, "tier", "status", "error", "label", "owner", "at"}
static var _held := {}
## Draft ids in the order they were loaded, for the timeline.
static var _order: Array[String] = []
static var _serial := 0
static var _watch: Watch
static var _watch_draft := ""
static var _watch_until := 0
## Told about every load, failure, rollback and unload: reporter.call(draft, version, report).
## Set it to an object's method, never a lambda: statics outlive lambdas' code at exit.
static var reporter := Callable()
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
			"gdshader":
				# Compile on the renderer; any error it raises meanwhile refuses the shader.
				var catch := Watch.new()
				catch.any = true
				OS.add_logger(catch)
				var shader := RenderingServer.shader_create()
				RenderingServer.shader_set_code(shader, text)
				RenderingServer.free_rid(shader)
				OS.remove_logger(catch)
				var errors := catch.take()
				if not errors.is_empty():
					problem = "%s does not compile: %s" % [path.trim_prefix("res://"), errors[0]]
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
			# An exact rule settles the tier: for files whose readers refresh themselves.
			if rule.get("exact", false) and local.match(str(rule.get("files", ""))):
				need = str(rule.tier)
				why = ""
				break
			if local.match(str(rule.get("files", ""))) and TIERS.find(str(rule.get("tier"))) > TIERS.find(need):
				need = str(rule.tier)
				why = "%s is built when the environment loads" % path.get_file() if need == "zone" else "%s needs the world restarted" % path.get_file()
		if TIERS.find(need) > TIERS.find(tier):
			tier = need
		if not why.is_empty():
			reasons.append(why)
	return {"tier": tier, "reasons": reasons}

## Apply a draft's files. host holds callables from the world: "rebuild_zone" (awaitable),
## "soft_restart"(between: Callable) and "busy" (-> bool). A newer version of a held draft replaces
## its layers. about may carry a "label" and "owner" for the timeline. Returns {"ok", "message", "tier"}.
static func apply(draft: String, version: String, files: Dictionary, host: Dictionary, about := {}) -> Dictionary:
	var size := 0
	for path in files:
		size += str(files[path]).length()
	if size > MAX_BYTES:
		return _told(draft, version, {"ok": false, "message": "This draft is too large to hot load. Commit it and restart Euclid."})
	if host.has("busy") and host.busy.call():
		return {"ok": false, "message": "Wait for the environment to finish loading, then try again."}
	var problem := gate(files)
	if not problem.is_empty():
		return _told(draft, version, {"ok": false, "status": "refused", "message": "Not loaded: " + problem, "error": problem})
	var before := _showing(_touched(draft, files.keys()))
	for path: String in files:
		if not _base.has(path):
			_base[path] = _current(path)
	_drop_layers(draft)
	for path: String in files:
		if not _layers.has(path):
			_layers[path] = []
		_layers[path].append([draft, files[path]])
	var changed := _changes(before)
	var planned := plan(changed)
	var cost_before := await render_ms() if planned.tier != "restart" else -1.0
	var result := await _install(changed, planned.tier, host)
	if not result.ok:
		return _told(draft, version, result)
	var cost_after := -1.0
	if cost_before >= 0.0:
		# Give new shaders and rebuilt nodes a moment to compile and settle before measuring.
		for frame in 10:
			await (Engine.get_main_loop() as SceneTree).process_frame
		cost_after = await render_ms()
	_held[draft] = {"version": version, "files": files, "tier": planned.tier, "status": "active", "error": "",
		"label": str(about.get("label", "")), "owner": str(about.get("owner", "")), "at": Time.get_unix_time_from_system()}
	_order.erase(draft)
	_order.append(draft)
	_start_watch(draft, files)
	var how := {"instant": "Swapped in place.", "in_place": "Reloaded in place.",
		"zone": "Rebuilt this environment.", "restart": "Restarted the world in place."}
	var message := "Loaded %d file%s live. %s" % [files.size(), "" if files.size() == 1 else "s", how[planned.tier]]
	if not planned.reasons.is_empty():
		message += " (" + "; ".join(planned.reasons) + ")"
	var report := {"ok": true, "status": "active", "message": message, "tier": planned.tier}
	if cost_before >= 0.0 and cost_after >= 0.0:
		report["frame_ms"] = [snappedf(cost_before, 0.01), snappedf(cost_after, 0.01)]
		report.message += " Render time %.2f → %.2f ms (%+.2f)." % [cost_before, cost_after, cost_after - cost_before]
	return _told(draft, version, report)

## The main view's measured CPU and GPU render time, averaged over some frames, in milliseconds;
## -1 without a renderer, or with one that does not measure (the compatibility renderer). Unlike
## frame time it is not capped by vsync.
static func render_ms(frames := 20) -> float:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or DisplayServer.get_name() == "headless":
		return -1.0
	var view := tree.root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(view, true)
	await RenderingServer.frame_post_draw
	var total := 0.0
	for frame in frames:
		await RenderingServer.frame_post_draw
		total += RenderingServer.viewport_get_measured_render_time_cpu(view) + RenderingServer.viewport_get_measured_render_time_gpu(view)
	return total / frames if total > 0.0 else -1.0

## Keep a held draft (it was committed: its text becomes the base) or drop it (discarded).
static func finish(draft: String, keep: bool, host: Dictionary) -> bool:
	if not _held.has(draft):
		return false
	var record: Dictionary = _held[draft]
	_held.erase(draft)
	_order.erase(draft)
	if _watch_draft == draft:
		_stop_watch()
	if keep and record.status == "active":
		for path: String in record.files:
			_base[path] = record.files[path]
	var before := _showing(record.files.keys())
	_drop_layers(draft)
	var changed := _changes(before)
	if not changed.is_empty():
		await _install(changed, plan(changed).tier, host)
	return true

## Take a held draft out of the world but keep it listed, so it can be loaded again (the timeline).
static func unload(draft: String, host: Dictionary) -> Dictionary:
	var record: Dictionary = _held.get(draft, {})
	if record.is_empty() or record.status != "active":
		return {"ok": false, "message": "That change is not loaded."}
	if _watch_draft == draft:
		_stop_watch()
	var before := _showing(record.files.keys())
	_drop_layers(draft)
	var changed := _changes(before)
	if not changed.is_empty():
		await _install(changed, plan(changed).tier, host)
	record.status = "unloaded"
	return _told(draft, record.version, {"ok": true, "status": "unloaded", "message": "Unloaded %s." % _name(record)})

## Load an unloaded change from the timeline again.
static func reload(draft: String, host: Dictionary) -> Dictionary:
	var record: Dictionary = _held.get(draft, {})
	if record.is_empty() or record.status == "active":
		return {"ok": false, "message": "That change is already loaded."}
	return await apply(draft, record.version, record.files, host, {"label": record.label, "owner": record.owner})

## Live changes, newest first: {"draft", "label", "owner", "files", "tier", "status", "error", "at"}.
static func timeline() -> Array:
	var entries := []
	for index in range(_order.size() - 1, -1, -1):
		var draft := _order[index]
		var record: Dictionary = _held.get(draft, {})
		if record.is_empty():
			continue
		entries.append({"draft": draft, "label": _name(record), "owner": record.owner, "files": record.files.keys(),
			"tier": record.tier, "status": record.status, "error": record.error, "at": record.at})
	return entries

## Load files exactly as they are on disk now, after a commit or a revert: they become the base.
## Files a live draft still covers keep showing the draft. Returns the same as apply.
static func apply_disk(paths: Array, host: Dictionary) -> Dictionary:
	var local_paths: Array[String] = []
	for path: String in paths:
		if supports(path):
			local_paths.append("res://" + path.trim_prefix("world/"))
	var before := _showing(local_paths)
	for local: String in local_paths:
		var disk := ProjectSettings.globalize_path(local)
		_base[local] = FileAccess.get_file_as_string(disk) if FileAccess.file_exists(disk) else ""
	var changed := _changes(before)
	if changed.is_empty():
		return {"ok": true, "message": "", "tier": ""}
	var planned := plan(changed)
	var result := await _install(changed, planned.tier, host)
	if not result.ok:
		return result
	return {"ok": true, "message": "Loaded the committed change here.", "tier": planned.tier}

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
	var record: Dictionary = _held.get(draft, {})
	if record.is_empty():
		return ""
	var before := _showing(record.files.keys())
	_drop_layers(draft)
	var changed := _changes(before)
	if not changed.is_empty():
		await _install(changed, plan(changed).tier, host)
	record.status = "failed"
	record.error = errors[0]
	var message := "Rolled back the live change: " + errors[0]
	_told(draft, record.version, {"ok": false, "status": "rolled_back", "message": message, "error": errors[0], "errors": errors.slice(0, 8)})
	return message

static func _told(draft: String, version: String, result: Dictionary) -> Dictionary:
	if reporter.is_valid() and not draft.begins_with("disk-"):
		var report := result.duplicate()
		if not report.has("status"):
			report["status"] = "active" if result.get("ok", false) else "refused"
		reporter.call(draft, version, report)
	return result

static func _name(record: Dictionary) -> String:
	if not str(record.get("label", "")).is_empty():
		return str(record.label)
	var names: Array = record.files.keys().map(func(path: String) -> String: return path.get_file())
	return ", ".join(names.slice(0, 3)) + ("…" if names.size() > 3 else "")

## Every path a draft held before, plus the ones it brings now.
static func _touched(draft: String, paths: Array) -> Array:
	var all := paths.duplicate()
	for path in _held.get(draft, {}).get("files", {}):
		if path not in all:
			all.append(path)
	return all

static func _drop_layers(draft: String) -> void:
	for path in _layers.keys():
		_layers[path] = _layers[path].filter(func(layer: Array) -> bool: return layer[0] != draft)
		if _layers[path].is_empty():
			_layers.erase(path)

## What each path shows: its top layer, else its base, else the file as loaded.
static func _top(path: String) -> String:
	if _layers.has(path) and not _layers[path].is_empty():
		return _layers[path].back()[1]
	return _base[path] if _base.has(path) else _current(path)

static func _showing(paths: Array) -> Dictionary:
	var shown := {}
	for path: String in paths:
		shown[path] = _top(path)
	return shown

## Paths whose shown text differs from before, with the text they show now.
static func _changes(before: Dictionary) -> Dictionary:
	var changed := {}
	for path: String in before:
		var now := _top(path)
		if now != before[path]:
			changed[path] = now
	return changed

## Overlay the files, then bring the world up to date at the given tier.
static func _install(files: Dictionary, tier: String, host: Dictionary) -> Dictionary:
	if files.is_empty():
		return {"ok": true}
	if not _overlay(files):
		return {"ok": false, "message": "Could not overlay the changed files."}
	_announce(files.keys())
	if tier == "restart":
		if not host.has("soft_restart"):
			return {"ok": false, "message": "This change needs Euclid restarted."}
		host.soft_restart.call(func() -> void: _swap(files, true))
		return {"ok": true}
	_swap(files, false)
	if tier == "zone" and host.has("rebuild_zone"):
		await host.rebuild_zone.call()
	return {"ok": true}

## Scripts may keep caches built from files: any loaded script under res://scripts that declares
## static func _hot_changed(paths: PackedStringArray) hears which files changed.
static func _announce(paths: Array) -> void:
	var changed := PackedStringArray(paths)
	for script_path in _project_scripts():
		if not ResourceLoader.has_cached(script_path):
			continue
		var script: GDScript = load(script_path)
		if script.get_script_method_list().any(func(method: Dictionary) -> bool: return method.name == "_hot_changed"):
			script.call("_hot_changed", changed)

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
	for path in _project_scripts():
		# Diagnostics name files to test them; they are not the world's readers.
		if path.begins_with("res://scripts/diagnostics/"):
			continue
		var text := FileAccess.get_file_as_string(path)
		if needles.any(func(needle: String) -> bool: return text.contains(needle)):
			found.append(path)
	return found

static func _project_scripts() -> Array[String]:
	var found: Array[String] = []
	var folders: Array[String] = ["res://scripts"]
	while not folders.is_empty():
		var folder: String = folders.pop_back()
		for sub in DirAccess.get_directories_at(folder):
			folders.append(folder.path_join(sub))
		for file in DirAccess.get_files_at(folder):
			if file.get_extension() == "gd":
				found.append(folder.path_join(file))
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
