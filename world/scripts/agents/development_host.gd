extends Node
## Euclid's in-world development surface: the F4 Workbench panel, the F2 Codex console and its
## development actions, villa benchmarks, the native CLI and console voice. The world coordinator
## still owns zones, overlays, the F2 command planner and the live extension lifecycle; this host
## reaches them only through the world it was created with.
const CodexConsole = preload("res://scripts/ui/codex_console.gd")
const WorkbenchPanel = preload("res://scripts/ui/workbench_panel.gd")
const WorldDevelopment = preload("res://scripts/agents/world_development.gd")
const DevelopmentSession = preload("res://scripts/persistence/development_session.gd")
const WorkbenchDiagnostics = preload("res://scripts/ui/workbench_diagnostics.gd")
const CONSOLE_SCROLLBACK := 300

## The local Workbench capability the launcher handed over. Empty without one.
var capability := ""
var client: WorldDevelopment
var console: Control
var workbench_panel: Control
var console_lines := PackedStringArray()
var busy := false
var voice_enabled := false
var _world
var _session: DevelopmentSession
var _cli_process := -1
var _benchmark_id := ""
var _benchmark_display := {}
var _action_busy := false
var _announced := ""

func _init(world) -> void:
	_world = world
	name = "Development"

## Connects to the Workbench once the gateway is known. Without a capability there is nothing to do.
func connect_gateway(url: String, token: String) -> void:
	if capability.is_empty() or url.is_empty() or token.is_empty():
		return
	client = WorldDevelopment.new()
	add_child(client)
	client.configure(url, token, capability)
	client.changed.connect(_client_changed)
	client.diagnostics_changed.connect(_benchmark_changed)
	client.refresh()

## Forgets a panel the world's overlay is about to free.
func release(child: Node) -> void:
	if child == console:
		console = null
	if child == workbench_panel:
		workbench_panel = null

func open_workbench() -> void:
	if _world.shifting:
		return
	if capability.is_empty() or _world.gateway_url.is_empty() or _world.gateway_token.is_empty():
		_world._panel("Workbench", "Workbench needs the local gateway. Open your main Euclid session with Start Euclid.cmd.", 240)
		_world._button("Back", Callable(_world, "_close_panel"))
		return
	if is_instance_valid(workbench_panel):
		if _world.overlay.visible:
			_world._close_panel()
		else:
			_world._show_panel()
		return
	_world._panel("", "", 500.0, true)
	_world.overlay.offset_left = 68
	_world.overlay.offset_top = 55
	_world.overlay.offset_right = -68
	_world.overlay.offset_bottom = -55
	var frame := CodexConsole.frame_style()
	frame.content_margin_left = 18
	frame.content_margin_right = 18
	frame.content_margin_top = 12
	frame.content_margin_bottom = 12
	_world.overlay.add_theme_stylebox_override("panel", frame)
	workbench_panel = WorkbenchPanel.new()
	_world.overlay_content.add_child(workbench_panel)
	var saved_view := {}
	if _session:
		saved_view = {"file": _session.file, "tab": _session.tab}
		workbench_panel.view_changed.connect(_session.save_view)
	workbench_panel.setup(_world.gateway_url, _world.gateway_token, capability, Callable(_world, "_preview_live_change"),
		Callable(_world, "_finish_live_change"), Callable(_world, "_live_change_status"), Callable(_world, "_workbench_plugin_context"), saved_view, run_benchmark,
		Callable(_world._palette_host, "error_log"))
	workbench_panel.draft_reviewed.connect(Callable(_world._palette_host, "observe"))
	workbench_panel.close_requested.connect(Callable(_world, "_close_panel"))
	workbench_panel.restart_requested.connect(_restart)
	workbench_panel.commit_recorded.connect(func(revision: String) -> void:
		notice("Committed source draft %s." % revision.left(7)))

func _restart() -> void:
	if _world.smoke_mode or _world.shifting or capability.is_empty():
		return
	if _world._save_for_restart() != OK:
		workbench_panel.show_error("Euclid could not save your place. Restart cancelled.")
		return
	var arguments := OS.get_cmdline_args()
	if DisplayServer.get_name() == "headless":
		arguments.append("--headless")
	else:
		var window := get_window()
		if window.mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]:
			arguments.append("--fullscreen")
		elif window.mode == Window.MODE_MAXIMIZED:
			arguments.append("--maximized")
		else:
			arguments.append_array(PackedStringArray(["--windowed", "--resolution", "%dx%d" % [window.size.x, window.size.y]]))
		arguments.append_array(PackedStringArray(["--rendering-method", RenderingServer.get_current_rendering_method()]))
	arguments.append_array(PackedStringArray(["--path", ProjectSettings.globalize_path("res://"), "--"]))
	arguments.append_array(OS.get_cmdline_user_args())
	OS.set_environment("EUCLID_WORKBENCH_TOKEN", capability)
	var supervisor := OS.get_environment("EUCLID_BOOT_NODE")
	if supervisor.is_empty():
		OS.set_restart_on_exit(true, arguments)
	else:
		var command := PackedStringArray([ProjectSettings.globalize_path("res://../scripts/recovery.mjs"),
			"restart", OS.get_executable_path(), str(OS.get_process_id())])
		command.append_array(arguments)
		if OS.create_process(supervisor, command) == -1:
			OS.unset_environment("EUCLID_WORKBENCH_TOKEN")
			workbench_panel.show_error("Euclid could not start the recovery supervisor. Restart cancelled.")
			return
	get_tree().quit()

func open_console() -> void:
	if is_instance_valid(console):
		if console.is_visible_in_tree():
			_world._close_panel()
		else:
			_world._show_panel()
			console.focus_entry()
		return
	_world._panel("", "", 500.0, true)
	_world.overlay.add_theme_stylebox_override("panel", CodexConsole.frame_style())
	console = CodexConsole.new()
	console.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_world.overlay_content.add_child(console)
	console.submitted.connect(Callable(_world, "_submit_codex_command"))
	console.cli_requested.connect(_open_native_cli)
	console.minimize_requested.connect(Callable(_world, "_close_panel"))
	console.layout_requested.connect(_layout_console)
	console.voice_requested.connect(_set_voice)
	console.development_requested.connect(_console_action)
	_layout_console(false)
	console.setup(console_lines, busy, voice_enabled)
	refresh_actions()
	if client:
		client.refresh()

func refresh_actions() -> void:
	if is_instance_valid(console) and client:
		var draft := client.draft
		var available := false
		match draft.get("subject", ""):
			"shoreline": available = _world._shoreline.available()
			"grid": available = _world._grid_scenery.available()
			"grid_palette": available = draft.get("status") != "passed" or _world._is_workshop(_world.zone_id)
			"behavior", "workshop_tool": available = _world._grid_scenery.available() and _world.zone_id == draft.get("preview_zone")
		if draft.get("agent_source", false) and draft.get("subject") != "grid_palette":
			available = true
		console.update_development(draft, available and not _world.shifting and not _action_busy,
			_world._live_change_status(draft.get("id", "")) == "active")

func _client_changed() -> void:
	var reviewed := client.benchmark_target
	_world._palette_host.observe(reviewed.get("id", ""), reviewed.get("version", ""))
	var draft := client.draft
	var status: String = draft.get("status", "")
	var revision_notice: String = draft.get("revision_notice", "")
	var stamp := "%s/%s/%s/%s" % [draft.get("id", ""), draft.get("version", ""), status, revision_notice]
	if stamp != _announced:
		_announced = stamp
		if not revision_notice.is_empty():
			notice(revision_notice)
		elif status == "revising":
			notice("Codex is revising a copy of the active draft. Open Workbench to see progress.")
		else:
			_announce(draft, status)
	refresh_actions()

func _announce(draft: Dictionary, status: String) -> void:
	match status:
		"staged":
			if draft.get("agent_source", false):
				notice(draft.summary if not draft.summary.is_empty() else "Codex prepared the source draft.")
				notice("Review the diff, then run checks to prepare a playable build.")
		"passed": notice("Draft checks passed. Preview the change or review the diff.")
		"failed":
			if draft.get("has_patch", false):
				var guidance := "Open Workbench to inspect the results."
				if draft.get("can_revise", false):
					guidance = "Ask Codex to fix the failing check, or open Workbench to inspect it."
				notice("The draft failed checks. " + guidance)
			else:
				notice("Source authoring failed. " + draft.error)

func _console_action(action: String) -> void:
	if not client or client.draft.is_empty() or _action_busy or _world.shifting:
		return
	if action == "review":
		open_workbench()
		if is_instance_valid(workbench_panel):
			workbench_panel.show_review(client.draft.status in ["failed", "authoring", "revising"])
		return
	var id: String = client.draft.id
	var revising: bool = client.draft.status == "revising"
	if action == "live" and client.draft.get("agent_source", false):
		if client.draft.status != "passed":
			action = "check"
		elif client.draft.get("subject") != "grid_palette":
			action = "play"
	_action_busy = true
	refresh_actions()
	var result := await client.command(action)
	if result.has("error"):
		notice(result.error)
	elif action == "live":
		var activated: Dictionary = await _world._preview_live_change(result.live)
		notice(activated.message)
	elif action == "play":
		notice("Opened the checked build in a separate Euclid window.")
	elif action == "check":
		notice("Running checks in the isolated preview project.")
	elif action == "discard" and not revising:
		var finished: Dictionary = _world._finish_live_change("discard", id)
		notice("Discarded the draft and restored the previous version." if finished.live else "Discarded the draft.")
	_action_busy = false
	refresh_actions()

func _layout_console(expanded: bool) -> void:
	_world.overlay.offset_left = 46 if expanded else 835
	_world.overlay.offset_top = 45 if expanded else 96
	_world.overlay.offset_right = -46 if expanded else -46
	_world.overlay.offset_bottom = -45 if expanded else -108

func notice(line: String) -> void:
	console_lines.append(line)
	if console_lines.size() > CONSOLE_SCROLLBACK:
		console_lines.remove_at(0)
	if _session:
		_session.save_console(console_lines, CodexConsole.prompts)
	if is_instance_valid(console):
		console.update_display(console_lines, busy)

func resume(path: String) -> void:
	_session = DevelopmentSession.new(path)
	console_lines = _session.lines
	CodexConsole.prompts = _session.prompts

func run_benchmark(action: String, arguments: Dictionary) -> Dictionary:
	if not client or _world.shifting:
		return {"error": "Wait for the current environment to finish loading."}
	var result := await client.benchmark(action, arguments)
	if action != "benchmark" or result.has("error"):
		return result
	var job: Variant = result.get("diagnostic_job")
	if job is Dictionary:
		_benchmark_id = job.id
		notice("Running the villa benchmark. Euclid will return when the measurements finish.")
		if DisplayServer.get_name() != "headless":
			_benchmark_display = {"mode": get_window().mode, "fps": Engine.max_fps,
				"rendering": RenderingServer.render_loop_enabled}
			get_window().mode = Window.MODE_MINIMIZED
			RenderingServer.render_loop_enabled = false
			Engine.max_fps = 15
	return result

func _benchmark_changed() -> void:
	if _benchmark_id.is_empty() or not client.diagnostic_job.is_empty():
		return
	var report := client.diagnostic
	var message := client.diagnostic_notice
	if report.get("id") == _benchmark_id:
		message = WorkbenchDiagnostics.summary(report)
	_benchmark_id = ""
	if not _benchmark_display.is_empty():
		Engine.max_fps = _benchmark_display.fps
		RenderingServer.render_loop_enabled = _benchmark_display.rendering
		get_window().mode = _benchmark_display.mode
		_benchmark_display.clear()
	if not message.is_empty():
		notice(message)

func _open_native_cli() -> void:
	if OS.get_name() != "Windows" or not is_instance_valid(_world.world_bridge):
		notice("Open the Windows Euclid launcher with its gateway to start the native CLI.")
		return
	if _world.gateway_url.is_empty() or _world.gateway_token.is_empty():
		notice("The native CLI needs Euclid’s local gateway.")
		return
	if _cli_process > 0 and OS.is_process_running(_cli_process):
		notice("The Codex terminal is open. Use Alt+Tab to return to it.")
		return
	var script_path := ProjectSettings.globalize_path("res://../scripts/codex-terminal.ps1")
	_cli_process = OS.create_process("powershell.exe", ["-NoProfile", "-ExecutionPolicy", "Bypass",
		"-File", script_path, "-WorldSession", _world.world_bridge.session], true)
	if _cli_process <= 0:
		notice("The native terminal could not be opened.")

func _set_voice(enabled: bool) -> void:
	voice_enabled = enabled
	if not DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		if enabled: notice("System voices are unavailable on this device.")
	elif enabled:
		if DisplayServer.tts_get_voices_for_language("en").is_empty():
			notice("Install an English system voice to enable speech.")
	else:
		DisplayServer.tts_stop()
