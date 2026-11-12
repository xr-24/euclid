extends RefCounted
## What the wrist computer shows. Each page is plain data: an id, a tab title, rows and an
## optional log. A row runs its Callable on Enter, or with "input" takes one typed line and passes
## it on. Optional row fields: value and tone (good, warn, accent) on the right, enabled and why,
## close (lower the wrist first), confirm (ask for a second Enter) and then (the page to show
## after sending). Keep it terse: labels and states only, no descriptions.

const Graphics = preload("res://scripts/rendering/graphics_settings.gd")

var _world # world.gd

func _init(world) -> void:
	_world = world

func status_line() -> String:
	var clock := Time.get_time_dict_from_system()
	return "%s  ·  %02d:%02d" % [_zone_name(_world.zone_id).to_upper(), clock.hour, clock.minute]

func pages() -> Array:
	return [_areas(), _build(), _world.scanner.page(), _agents(), _workbench(), _system()]

func _areas() -> Dictionary:
	var rows := []
	var zones: Array = _world.manifest.zones
	for index in zones.size():
		var zone: Dictionary = zones[index]
		var id := str(zone.id)
		var here: bool = id == _world.zone_id
		rows.append({"label": str(zone.name).to_upper(), "value": "HERE" if here else (str(index + 1) if index < 3 else ""),
			"tone": "good" if here else "", "enabled": not here and not _world.shifting, "why": "HERE" if here else "SHIFTING",
			"run": Callable(_world, "_shift").bind(id), "close": true})
	return {"id": "areas", "title": "AREAS", "rows": rows}

func _build() -> Dictionary:
	var codex := _codex_state()
	return {"id": "build", "title": "BUILD", "rows": [
		{"label": "GRID TOOLS" if _world._is_workshop(_world.zone_id) else "SCENE TOOLS", "value": "B",
			"enabled": _world._scene_ready(), "why": "LOADING", "run": Callable(_world, "_request_grid_palette"), "close": true},
		{"label": "ATMOSPHERE", "value": "EDITED" if not _world.atmosphere.values_for(_world.zone_id).is_empty() else "",
			"tone": "accent", "enabled": not _world.shifting, "why": "SHIFTING",
			"run": Callable(_world, "_open_atmosphere"), "close": true},
		{"label": "PLAYER RIG", "enabled": not _world.shifting, "why": "SHIFTING",
			"run": Callable(_world, "_open_player_rig"), "close": true},
		{"label": "SCAN OBJECT", "enabled": _world._scene_ready(), "why": "LOADING",
			"run": Callable(_world.wrist, "raise_wrist").bind("scan")},
		{"label": "DESCRIBE", "input": true, "then": "agents", "value": codex, "tone": "warn" if not codex.is_empty() else "",
			"enabled": codex.is_empty(), "why": codex, "run": Callable(_world, "_submit_codex_command")},
	]}

func _agents() -> Dictionary:
	var dev = _world._dev
	var status: String = _codex_state() if dev.chat_peer == "local-codex" else ("" if dev.can_message() else "OFFLINE")
	return {"id": "agents", "title": "AGENTS", "log": dev.chat_log(dev.chat_peer, 12), "rows": [
		{"label": "AGENT", "value": dev.chat_label(), "run": Callable(dev, "cycle_agent")},
		{"label": "QUICK COMMAND", "input": true, "value": status, "tone": "warn" if not status.is_empty() else "",
			"enabled": status.is_empty(), "why": status, "run": Callable(dev, "quick_command")},
		{"label": "MESSAGE", "value": "F2", "run": Callable(dev, "open_console"), "close": true},
	]}

func _workbench() -> Dictionary:
	var dev = _world._dev
	var available: bool = not str(dev.capability).is_empty() and not str(_world.gateway_url).is_empty()
	var draft := ""
	if available and dev.client != null:
		draft = str(dev.client.draft.get("status", "")).to_upper()
	var rows := []
	for tab in [["SOURCE", "Source"], ["TERMINAL", "Terminal"], ["AGENTS", "Agents"], ["HISTORY", "History"]]:
		var value := "OFFLINE" if not available else ""
		if available and tab[1] == "Source":
			value = draft if not draft.is_empty() else "F4"
		rows.append({"label": tab[0], "value": value, "tone": "accent" if tab[1] == "Source" and not draft.is_empty() else "",
			"enabled": available, "why": "OFFLINE", "run": Callable(dev, "open_workbench_tab").bind(tab[1]), "close": true})
	return {"id": "workbench", "title": "WORKBENCH", "rows": rows}

func _system() -> Dictionary:
	var fullscreen: bool = _world.get_window().mode == Window.MODE_FULLSCREEN
	return {"id": "system", "title": "SYSTEM", "rows": [
		{"label": "FULLSCREEN", "value": "ON" if fullscreen else "OFF", "tone": "good" if fullscreen else "", "run": _toggle_fullscreen},
		{"label": "GRAPHICS", "value": Graphics.label().to_upper(), "tone": "accent", "run": _cycle_graphics},
		{"label": "QUIT", "confirm": "ENTER AGAIN TO QUIT", "run": Callable(_world, "_quit")},
	]}

## Empty when Codex can take a message, otherwise why not, short enough to sit beside a row.
func _codex_state() -> String:
	if not _world.gateway_connected:
		return "OFFLINE"
	return "BUSY" if _world._dev.busy else ""

func _toggle_fullscreen() -> void:
	var window: Window = _world.get_window()
	window.mode = Window.MODE_WINDOWED if window.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN

func _cycle_graphics() -> void:
	Graphics.select("cinematic" if Graphics.current == "balanced" else "balanced", _world.get_viewport())
	Graphics.apply_zone(_world, _world.zone_id)

func _zone_name(id: String) -> String:
	for zone in _world.manifest.zones:
		if str(zone.id) == id:
			return str(zone.name)
	return id
