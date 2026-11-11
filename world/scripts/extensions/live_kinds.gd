extends RefCounted
## Euclid's live extension kinds behind the one lifecycle in live_extensions.gd. Each adapter wraps
## the service that already owns that kind. The world passes a context of callables:
##   zone() -> String, workshop() -> the Grid workshop tools in a Grid space or null,
##   catalog and run_action for the Grid palette.

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
## It accepts every remaining candidate, so register it last.
class Behavior extends "res://scripts/extensions/live_kind.gd":
	var _runtime
	var _world: Dictionary

	func _init(runtime, world: Dictionary) -> void:
		_runtime = runtime
		_world = world

	func id() -> String:
		return "behavior"

	func accepts(_candidate: Dictionary) -> bool:
		return true

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
