extends RefCounted
## What the wrist computer shows. Each page is plain data: an id, a tab title, rows and an
## optional log. A row runs its Callable on Enter, or with "input" takes one typed line and passes
## it on. Optional row fields: value and tone (good, warn, accent) on the right, enabled and why,
## close (lower the wrist first), confirm (ask for a second Enter) and then (the page to show
## after sending). Keep it terse: labels and states only, no descriptions.

const Graphics = preload("res://scripts/rendering/graphics_settings.gd")
const Presence = preload("res://scripts/agents/agent_presence.gd")
const HotLoad = preload("res://scripts/extensions/hot_load.gd")

var _world # world.gd

func _init(world) -> void:
	_world = world

func status_line() -> String:
	var clock := Time.get_time_dict_from_system()
	return "%s  ·  %02d:%02d" % [_zone_name(_world.zone_id).to_upper(), clock.hour, clock.minute]

func pages() -> Array:
	return [_areas(), _build(), _world.scanner.page(), _agents(), _workbench(), _live(), _system()]

## Changes loaded live, newest first. Selecting one unloads it, or loads it again.
func _live() -> Dictionary:
	var rows := []
	var states := {"active": "LIVE", "unloaded": "OFF", "failed": "ROLLED BACK"}
	for entry: Dictionary in HotLoad.timeline().slice(0, 12):
		var label: String = str(entry.label).to_upper()
		rows.append({"label": label.left(30) + ("…" if label.length() > 30 else ""), "value": states.get(entry.status, str(entry.status).to_upper()),
			"tone": "good" if entry.status == "active" else ("warn" if entry.status == "failed" else ""),
			"run": Callable(_world, "_toggle_live_change").bind(entry.draft)})
	if rows.is_empty():
		rows.append({"label": "NOTHING LOADED LIVE", "value": "", "enabled": false, "why": "", "run": func() -> void: pass})
	return {"id": "live", "title": "LIVE", "rows": rows}

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
		{"label": "PIECES", "enabled": _world._scene_ready(), "why": "LOADING",
			"run": Callable(_world, "_open_pieces"), "close": true},
		{"label": "TERRAIN", "enabled": _world.terrain_available(), "why": "ADD A TERRAIN PIECE",
			"run": Callable(_world, "_open_terrain"), "close": true},
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
	var status := _codex_state()
	return {"id": "agents", "title": "AGENTS", "log": dev.chat_log(Presence.CODEX, 12), "rows": [
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
		{"label": "AGENT ACTIVITY", "value": Graphics.agent_activity.to_upper(), "tone": "accent" if Graphics.agent_activity != "off" else "",
			"run": _cycle_agent_activity},
		{"label": "SHOW CODE", "value": "ON" if Graphics.show_code else "OFF", "tone": "good" if Graphics.show_code else "",
			"run": func() -> void: Graphics.set_agent_activity(Graphics.agent_activity, not Graphics.show_code)},
		{"label": "LIVE AGENT EDITS", "value": {"local": "LOCAL AGENTS", "all": "ALL AGENTS", "off": "OFF"}[Graphics.live_edits],
			"tone": "accent" if Graphics.live_edits != "off" else "",
			"run": func() -> void: Graphics.set_live_edits(Graphics.LIVE_EDITS[(Graphics.LIVE_EDITS.find(Graphics.live_edits) + 1) % Graphics.LIVE_EDITS.size()])},
		{"label": "AGENT VISION", "value": {"all": "VIEW + CAMERAS", "cameras": "CAMERAS ONLY", "off": "OFF"}[Graphics.agent_vision],
			"tone": "accent" if Graphics.agent_vision != "off" else "",
			"run": func() -> void: Graphics.set_agent_vision(Graphics.AGENT_VISION[(Graphics.AGENT_VISION.find(Graphics.agent_vision) + 1) % Graphics.AGENT_VISION.size()])},
		{"label": "AUTO-COMMIT", "value": "OFF" if Graphics.auto_commit == 0 else "AFTER %d MIN" % Graphics.auto_commit,
			"tone": "warn" if Graphics.auto_commit > 0 else "",
			"run": func() -> void: Graphics.set_auto_commit(Graphics.AUTO_COMMIT[(Graphics.AUTO_COMMIT.find(Graphics.auto_commit) + 1) % Graphics.AUTO_COMMIT.size()])},
		{"label": "SPEAK REPLIES", "value": "ALWAYS" if Graphics.speak_replies else "IN CHAT", "tone": "good" if Graphics.speak_replies else "",
			"run": func() -> void: Graphics.set_speak_replies(not Graphics.speak_replies)},
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

## Full panels, header icons only, or nothing above the agents.
func _cycle_agent_activity() -> void:
	var modes := Graphics.AGENT_ACTIVITY
	Graphics.set_agent_activity(modes[(modes.find(Graphics.agent_activity) + 1) % modes.size()], Graphics.show_code)

func _zone_name(id: String) -> String:
	for zone in _world.manifest.zones:
		if str(zone.id) == id:
			return str(zone.name)
	return id
