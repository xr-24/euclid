extends RefCounted
## Euclid's live extension kinds behind the one lifecycle in live_extensions.gd. Each adapter wraps
## the service that already owns that kind. The world passes a context of callables:
##   zone() -> String, workshop() -> the Grid workshop tools in a Grid space or null,
##   catalog and run_action for the Grid palette, hot for hot loading.
## world/data/extension_kinds.json lists the same live kinds in the same order for the gateway.

## Registers every live kind in table order. services holds palette, shoreline, grid, workshop_actions
## and behaviors; the world context also carries "hot", what hot loading may do to the world. Each
## kind accepts only its own candidate; the hot kind takes every other change to the project.
static func register_all(live: RefCounted, services: Dictionary, world: Dictionary) -> void:
	live.register(Palette.new(services.get("palette"), world))
	live.register(Appearance.new("shoreline", services.get("shoreline")))
	live.register(Appearance.new("grid", services.get("grid")))
	live.register(WorkshopAction.new(services.get("workshop_actions"), world))
	live.register(Behavior.new(services.get("behaviors"), world))
	# Environment packages and command sets hot load too; they keep their own kinds in the table.
	for kind in ["environment", "command", "hot"]:
		live.register(Hot.new(world.get("hot", {}), kind))

## The replaceable Grid palette. It previews only inside a Grid space.
class Palette extends "res://scripts/extensions/live_kind.gd":
	var _host
	var _world: Dictionary

	func _init(host, world: Dictionary) -> void:
		_host = host
		_world = world

	func id() -> String:
		return "grid_palette"

	func accepts(candidate: Dictionary) -> bool:
		return candidate.has("grid_palette")

	func preview(candidate: Dictionary) -> Dictionary:
		var tools: Variant = _world.workshop.call()
		if tools == null:
			return {"ok": false, "message": "Enter The Grid to preview its palette."}
		var palette: Dictionary = candidate.grid_palette.merged({"draft": candidate.draft, "version": candidate.version})
		return _host.preview(palette, _world.zone.call(), tools, _world.catalog, _world.run_action)

	func status(draft: String) -> String:
		return _host.status(draft)

	func finish(draft: String, keep: bool) -> Dictionary:
		return {"live": _host.finish(draft, keep)}

	func reload_committed() -> void:
		_host.reload_committed()

## A data-only appearance profile, such as the shoreline look or the Grid scenery.
class Appearance extends "res://scripts/extensions/live_kind.gd":
	var _key: String
	var _look

	func _init(key: String, look) -> void:
		_key = key
		_look = look

	func id() -> String:
		return _key

	func accepts(candidate: Dictionary) -> bool:
		return candidate.has(_key)

	func preview(candidate: Dictionary) -> Dictionary:
		return _look.preview(candidate)

	func status(draft: String) -> String:
		return _look.status(draft)

	func finish(draft: String, keep: bool) -> Dictionary:
		return {"live": _look.finish(draft, keep)}

	func reload_committed() -> void:
		_look.reload_committed()

## A data-only workshop action. Committed actions reload at once so the palette and F2 list them.
class WorkshopAction extends "res://scripts/extensions/live_kind.gd":
	var _registry
	var _world: Dictionary

	func _init(registry, world: Dictionary) -> void:
		_registry = registry
		_world = world

	func id() -> String:
		return "workshop_tool"

	func accepts(candidate: Dictionary) -> bool:
		return candidate.has("workshop_tool")

	func preview(candidate: Dictionary) -> Dictionary:
		return _registry.preview(candidate, _world.zone.call(), _world.workshop.call())

	func status(draft: String) -> String:
		return _registry.status(draft)

	func finish(draft: String, keep: bool) -> Dictionary:
		return {"live": _registry.finish(draft, keep)}

	func reload_committed() -> void:
		_registry.reload_committed()

	func reloads_on_commit() -> bool:
		return true

## A behavior plugin, optionally with a test link to entities in the Grid space it was authored in.
class Behavior extends "res://scripts/extensions/live_kind.gd":
	var _runtime
	var _world: Dictionary

	func _init(runtime, world: Dictionary) -> void:
		_runtime = runtime
		_world = world

	func id() -> String:
		return "behavior"

	func accepts(candidate: Dictionary) -> bool:
		return candidate.has("plugin")

	func preview(candidate: Dictionary) -> Dictionary:
		var binding: Dictionary = candidate.get("binding", {})
		var tools: Variant = _world.workshop.call()
		if not binding.is_empty() and (tools == null or binding.get("zone") != _world.zone.call()):
			return {"ok": false, "message": "Return to the Grid space used to author this plugin."}
		var result: Dictionary = _runtime.preview(candidate)
		if not result.ok or binding.is_empty():
			return result
		var request := {"id": candidate.plugin, "settings": {}}
		if not str(binding.get("target", "")).is_empty():
			request["target"] = binding.target
		var linked: Dictionary = tools.preview_behavior(candidate.draft, binding.get("source", ""), request)
		if not linked.ok:
			_runtime.finish(candidate.draft, false)
			return {"ok": false, "message": linked.error}
		return {"ok": true, "message": "Plugin and test link active. Try the interaction in The Grid."}

	func status(draft: String) -> String:
		return _runtime.preview_status(draft)

	func finish(draft: String, keep: bool) -> Dictionary:
		var was_live: bool = _runtime.finish(draft, keep)
		var tools: Variant = _world.workshop.call()
		var released: Dictionary = tools.finish_behavior_preview(draft, keep and was_live) if tools != null else {"ok": true}
		return {"live": was_live, "warning": released.get("error", "")}

	func reload_committed() -> void:
		_runtime.reload_committed()

## Any other change to the project's text files: scripts, shaders, data and scenes, hot loaded at
## the least disruptive tier (extensions/hot_load.gd). The candidate's "hot" maps project paths to
## their reviewed text.
class Hot extends "res://scripts/extensions/live_kind.gd":
	const HotLoad = preload("res://scripts/extensions/hot_load.gd")
	var _host: Dictionary
	var _id: String

	func _init(host: Dictionary, kind := "hot") -> void:
		_host = host
		_id = kind

	func id() -> String:
		return _id

	func accepts(candidate: Dictionary) -> bool:
		return candidate.get("hot") is Dictionary

	func preview(candidate: Dictionary) -> Dictionary:
		var files := {}
		for path: String in candidate.hot:
			if not HotLoad.supports(path) or not candidate.hot[path] is String:
				return {"ok": false, "message": "%s cannot be hot loaded. Commit it and restart Euclid." % path}
			files["res://" + path.trim_prefix("world/")] = candidate.hot[path]
		return await HotLoad.apply(str(candidate.draft), str(candidate.get("version", "")), files, _host,
			{"label": str(candidate.get("summary", "")), "owner": str(candidate.get("owner", ""))})

	func status(draft: String) -> String:
		return HotLoad.status(draft)

	## Dropping a draft puts its files back; that may rebuild the environment, so it runs on.
	func finish(draft: String, keep: bool) -> Dictionary:
		if HotLoad.status(draft).is_empty():
			return {"live": false}
		var host := _host
		(func() -> void: await HotLoad.finish(draft, keep, host)).call()
		return {"live": true}
