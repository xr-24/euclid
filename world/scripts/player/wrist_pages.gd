extends RefCounted
## What the wrist computer shows. Each page is plain data: an id, a tab title, an optional lead
## line, rows and an optional log. A row runs its Callable on Enter, or with "input" takes one
## typed line and passes it on. Optional row fields: detail, value, tone (good, warn, accent),
## about (shown under the list while selected), enabled and why, close (lower the wrist first),
## confirm (ask for a second Enter), placeholder and then (the page to show after sending).

const Graphics = preload("res://scripts/rendering/graphics_settings.gd")
const OFFLINE := "Needs the local gateway. Start Euclid with Start Euclid.cmd."

var _world # world.gd

func _init(world) -> void:
	_world = world

func status_line() -> String:
	var clock := Time.get_time_dict_from_system()
	return "%s  ·  %02d:%02d" % [_zone_name(_world.zone_id).to_upper(), clock.hour, clock.minute]

func pages() -> Array:
	return [_areas(), _build(), _codex(), _workbench(), _system()]

func _areas() -> Dictionary:
	var rows := []
	var zones: Array = _world.manifest.zones
	for index in zones.size():
		var zone: Dictionary = zones[index]
		var id := str(zone.id)
		var here: bool = id == _world.zone_id
		var shortcut := str(index + 1) if index < 3 else ""
		rows.append({"label": str(zone.name).to_upper(), "detail": str(zone.get("subtitle", "Custom space")),
			"value": "HERE" if here else shortcut, "tone": "good" if here else "",
			"about": str(zone.get("description", "")), "enabled": not here and not _world.shifting,
			"why": "You are already here." if here else "Wait for the shift to finish.",
			"run": Callable(_world, "_shift").bind(id), "close": true})
	var lead := "SHIFTING THE WORLD AROUND YOU…" if _world.shifting else "CHOOSE A PLACE. THE WORLD SHIFTS AROUND YOU."
	return {"id": "areas", "title": "AREAS", "lead": lead, "rows": rows}

func _build() -> Dictionary:
	var tools := "GRID TOOLS" if _world._is_workshop(_world.zone_id) else "SCENE TOOLS"
	var online: bool = _world.gateway_connected
	return {"id": "build", "title": "BUILD", "lead": "AIM FIRST. THE TOOLS OPEN ON WHATEVER IS UNDER THE CROSSHAIR.", "rows": [
		{"label": "OPEN " + tools, "value": "B", "detail": "Spawn, move, script and save prefabs",
			"enabled": _world._scene_ready(), "why": "Wait for the area to finish loading.",
			"run": Callable(_world, "_request_grid_palette"), "close": true,
			"about": "Select something by aiming at it first. Undo, duplicate and delete are in the same palette."},
		{"label": "DESCRIBE IT", "detail": "Tell Codex what to build here", "input": true, "then": "codex",
			"placeholder": "A ring of lanterns around the pool", "enabled": online and not _world._dev.busy,
			"why": OFFLINE if not online else "Codex is still working on the last request.",
			"run": Callable(_world, "_submit_codex_command"),
			"about": "Codex builds with the same tools you have. Its reply appears on the CODEX page."},
	]}

func _codex() -> Dictionary:
	var dev = _world._dev
	var online: bool = _world.gateway_connected
	var lead := "UPLINK ONLINE"
	if not online:
		lead = "UPLINK OFFLINE"
	elif dev.busy:
		lead = "WORKING ON IT…"
	return {"id": "codex", "title": "CODEX", "lead": lead, "log_title": "UPLINK", "log": dev.console_lines, "rows": [
		{"label": "MESSAGE", "input": true, "placeholder": "Ask for a change, or /task for longer work",
			"enabled": online and not dev.busy, "why": OFFLINE if not online else "Codex is still working on the last request.",
			"run": Callable(_world, "_submit_codex_command"),
			"about": "World commands run right away. /task, /msg and @agent go to the task queue."},
		{"label": "OPEN UPLINK", "value": "F2", "run": Callable(dev, "open_console"), "close": true,
			"about": "The full console: history, drafts under review and the native Codex CLI."},
	]}

func _workbench() -> Dictionary:
	var dev = _world._dev
	var available: bool = not str(dev.capability).is_empty() and not str(_world.gateway_url).is_empty()
	var lead := "NO DRAFT IN PROGRESS"
	if not available:
		lead = "OFFLINE"
	elif dev.client != null and not dev.client.draft.is_empty():
		var draft: Dictionary = dev.client.draft
		var summary := str(draft.get("summary", ""))
		lead = "DRAFT %s%s" % [str(draft.get("status", "")).to_upper(), "  ·  " + summary if not summary.is_empty() else ""]
	var rows := []
	for tab in [["OPEN WORKBENCH", "", "F4", "Source, drafts, diffs and checks for Euclid itself."],
			["TERMINAL", "Terminal", "", "PowerShell in the repository root. It keeps running across restarts."],
			["AGENTS", "Agents", "", "Approve, inspect and disconnect cloud agents, and set up the relay."],
			["HISTORY", "History", "", "Recent drafts, checks and commits."]]:
		rows.append({"label": tab[0], "value": tab[2], "about": tab[3], "enabled": available, "why": OFFLINE,
			"run": Callable(dev, "open_workbench_tab").bind(tab[1]), "close": true})
	return {"id": "workbench", "title": "WORKBENCH", "lead": lead, "rows": rows}

func _system() -> Dictionary:
	var fullscreen: bool = _world.get_window().mode == Window.MODE_FULLSCREEN
	return {"id": "system", "title": "SYSTEM", "lead": "YOUR PLACE, AREA AND VIEW SAVE AUTOMATICALLY.", "rows": [
		{"label": "FULLSCREEN", "value": "ON" if fullscreen else "OFF", "tone": "good" if fullscreen else "",
			"run": _toggle_fullscreen, "about": "F11 does the same from anywhere."},
		{"label": "GRAPHICS", "value": Graphics.label().to_upper(), "tone": "accent", "run": _cycle_graphics,
			"about": "Balanced keeps every effect with lighter antialiasing and shadows. Cinematic adds 4x MSAA and a larger shadow atlas. Some villa settings follow on the next shift."},
		{"label": "SAVE AND QUIT", "tone": "warn", "confirm": "PRESS ENTER AGAIN TO SAVE AND QUIT", "run": Callable(_world, "_quit"),
			"about": "Saves where you are and closes Euclid."},
	]}

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
