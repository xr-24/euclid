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
const TaskClient = preload("res://scripts/agents/task_client.gd")
const ApplicationWindow = preload("res://scripts/ui/application_window.gd")
const Presence = preload("res://scripts/agents/agent_presence.gd")
const ChatHistory = preload("res://scripts/agents/chat_history.gd")
const SpeechPlayer = preload("res://scripts/agents/speech_player.gd")
const CONSOLE_SCROLLBACK := 300

## The local Workbench capability the launcher handed over. Empty without one.
var capability := ""
var client: WorldDevelopment
var _tasks: TaskClient
var console: Control
var workbench_panel: Control
var console_lines := PackedStringArray()
var busy := false
var _voice := SpeechPlayer.new()
var _world
var _session: DevelopmentSession
var _cli_process := -1
var _benchmark_id := ""
var _benchmark_display := {}
var _action_busy := false
var _announced := ""
var chat_peer := ""
var _chat_tabs: Array[String] = []
var _chat_agents := {}
var _conversations := {}
var _chat_requests := {}
var _chat_errors := {}
var _polling_chat := false
var _next_chat_poll := 0
var _chat_dirty := false
var _directory_due := 0

func _init(world) -> void:
	_world = world
	name = "Development"
	add_child(_voice)
	_voice.changed.connect(_refresh_voice)
	_voice.voice_selected.connect(func(id: String) -> void:
		if _session:
			_session.save_voice(id))

## Connects to the Workbench once the gateway is known. Without a capability there is nothing to do.
func connect_gateway(url: String, token: String) -> void:
	if capability.is_empty() or url.is_empty() or token.is_empty():
		return
	_voice.configure(url, token, capability)
	client = WorldDevelopment.new()
	add_child(client)
	client.configure(url, token, capability)
	client.changed.connect(_client_changed)
	client.diagnostics_changed.connect(_benchmark_changed)
	client.refresh()
	_tasks = TaskClient.new()
	add_child(_tasks)
	_tasks.configure(url, token, capability)
	_tasks.notice.connect(notice)
	_tasks.addressed.connect(func(peer: String) -> void:
		if _chat_agents.has(peer):
			_world._activate_agent(peer)
			if chat_peer.is_empty():
				select_chat(peer)
			elif peer not in _chat_tabs:
				_chat_tabs.append(peer)
				if _session:
					_session.save_chat_tabs(_chat_tabs, chat_peer)
				if is_instance_valid(console):
					_show_chat_tabs()
		_poll_chat())
	var task_poll := Timer.new()
	task_poll.wait_time = 1
	add_child(task_poll)
	task_poll.timeout.connect(func() -> void:
		if is_instance_valid(console) and _world.overlay.visible:
			var working := _chat_requests.has(chat_peer) or bool(_conversations.get(chat_peer, {}).get("working", false))
			if working or Time.get_ticks_msec() >= _next_chat_poll:
				_next_chat_poll = Time.get_ticks_msec() + 3000
				_poll_chat()
		elif _world.wrist.is_open and Time.get_ticks_msec() >= _next_chat_poll:
			_next_chat_poll = Time.get_ticks_msec() + 3000
			_poll_chat())
	task_poll.start()

func is_task_command(prompt: String) -> bool:
	return prompt.begins_with("@") or prompt.get_slice(" ", 0) in ["/task", "/msg", "/inbox", "/cancel", "/journal", "/share-view"]

func task_command(prompt: String) -> void:
	if _tasks == null:
		notice("Tasks need the local Euclid launcher.")
		return
	if prompt.get_slice(" ", 0) == "/share-view":
		_share_view(prompt.get_slice(" ", 1).to_lower())
		return
	var session: String = _world.world_bridge.session if is_instance_valid(_world.world_bridge) else ""
	_tasks.submit(prompt, session)

func _share_view(agent: String) -> void:
	var valid := RegEx.create_from_string("^[a-z0-9_-]{1,32}$")
	if not valid.search(agent):
		notice("Use /share-view <agent>.")
		return
	if not _world._scene_ready() or DisplayServer.get_name() == "headless":
		notice("Wait for the rendered world before sharing a view.")
		return
	_world._close_panel()
	var hidden: Array[Node] = []
	for surface in get_tree().get_nodes_in_group("private_world_surfaces"):
		if surface.visible:
			surface.hide()
			hidden.append(surface)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	for surface in hidden:
		if is_instance_valid(surface):
			surface.show()
	if image == null or image.is_empty():
		notice("Could not capture the current world.")
		return
	var ratio := minf(1.0, 640.0 / float(image.get_width()))
	image.resize(maxi(1, roundi(image.get_width() * ratio)), maxi(1, roundi(image.get_height() * ratio)), Image.INTERPOLATE_BILINEAR)
	_tasks.share_view(agent, _world.zone_id, image.save_jpg_to_buffer(0.82))

func open_application(app_id: String, station: Node3D) -> void:
	var app := ApplicationWindow.new()
	_world.overlay_content.add_child(app)
	app.setup(app_id, Callable(_world, "_close_panel"),
		{"url": _world.gateway_url, "token": _world.gateway_token, "capability": capability}, station)

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

## Opens Workbench from the wrist computer, optionally on one of its tabs (by title).
func open_workbench_tab(tab := "") -> void:
	if not (is_instance_valid(workbench_panel) and _world.overlay.visible):
		open_workbench()
	if not tab.is_empty() and is_instance_valid(workbench_panel):
		workbench_panel.show_tab(tab)

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

func open_console(peer := "") -> void:
	if not peer.is_empty():
		select_chat(peer)
	if is_instance_valid(console):
		if console.is_visible_in_tree():
			if peer.is_empty():
				_world._close_panel()
		else:
			_world._show_panel()
			console.focus_entry()
			_poll_chat()
		return
	_world._panel("", "", 500.0, true)
	_world.overlay.add_theme_stylebox_override("panel", CodexConsole.frame_style())
	console = CodexConsole.new()
	console.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_world.overlay_content.add_child(console)
	console.submitted.connect(send_chat)
	console.peer_selected.connect(select_chat)
	console.cli_requested.connect(_open_native_cli)
	console.minimize_requested.connect(Callable(_world, "_close_panel"))
	console.layout_requested.connect(_layout_console)
	console.voice_requested.connect(_voice.toggle)
	console.voice_selected.connect(_voice.select)
	console.voice_preview_requested.connect(_voice.preview)
	console.voice_retry_requested.connect(_voice.retry)
	console.development_requested.connect(_console_action)
	_layout_console(false)
	console.setup(console_lines, busy, _voice.enabled)
	_refresh_voice()
	_show_chat_tabs()
	refresh_chat()
	_poll_chat()
	refresh_actions()
	if client:
		client.refresh()

func select_chat(peer: String) -> void:
	if not _chat_agents.has(peer) and peer not in _chat_tabs:
		return
	if peer not in _chat_tabs:
		_chat_tabs.append(peer)
	chat_peer = peer
	if _session:
		_session.save_chat_tabs(_chat_tabs, peer)
	if is_instance_valid(console):
		_show_chat_tabs()
		if _world.overlay.keyboard_active:
			console.focus_entry()
	refresh_chat()
	_poll_chat()

func _show_chat_tabs() -> void:
	var labels := {}
	var recipients: Array[String] = []
	for peer in _chat_agents:
		labels[peer] = _chat_agents[peer].label
		recipients.append(peer)
	for peer in _chat_tabs:
		if not labels.has(peer):
			labels[peer] = Presence.label(peer)
	console.set_conversations(labels, recipients, _chat_tabs, chat_peer)

func can_message() -> bool:
	return _tasks != null and _chat_agents.has(chat_peer)

func chat_log(peer: String, limit := 0) -> PackedStringArray:
	var transcript: PackedStringArray = _conversations.get(peer, {}).get("lines", PackedStringArray())
	var lines := PackedStringArray()
	if peer == Presence.CODEX:
		lines = console_lines.duplicate() if limit == 0 else console_lines.slice(-limit)
	lines.append_array(transcript if limit == 0 else transcript.slice(-limit))
	var error: String = _chat_errors.get(peer, "")
	if not error.is_empty():
		lines.append(error)
	return lines if limit == 0 else lines.slice(-limit)

func refresh_chat() -> void:
	if not is_instance_valid(console):
		return
	var recent := CodexConsole.prompts.duplicate() if chat_peer == Presence.CODEX else PackedStringArray()
	recent.append_array(_conversations.get(chat_peer, {}).get("prompts", PackedStringArray()))
	console.display_conversation(chat_log(chat_peer), recent, _chat_requests.has(chat_peer), can_message())
	refresh_actions()

func quick_command(prompt: String) -> void:
	if CodexConsole.prompts.is_empty() or CodexConsole.prompts[-1] != prompt:
		CodexConsole.prompts.append(prompt)
		if CodexConsole.prompts.size() > CodexConsole.HISTORY_LIMIT:
			CodexConsole.prompts.remove_at(0)
	_world._submit_codex_command(prompt)

func send_chat(prompt: String) -> void:
	var peer := chat_peer
	if is_task_command(prompt):
		task_command(prompt)
		return
	if not can_message() or _chat_requests.has(peer):
		return
	if prompt.length() > 4000:
		_chat_errors[peer] = "Enter up to 4000 characters."
		refresh_chat()
		return
	_chat_errors.erase(peer)
	_chat_requests[peer] = true
	refresh_chat()
	var session: String = _world.world_bridge.session if is_instance_valid(_world.world_bridge) else ""
	var local: bool = _chat_agents[peer].kind == "worker"
	var result := await _tasks.send_chat(peer, prompt, session, local)
	_chat_requests.erase(peer)
	if result.has("error"):
		_chat_errors[peer] = str(result.error)
	else:
		_world._activate_agent(peer)
		_poll_chat()
	refresh_chat()

func _poll_chat() -> void:
	if _tasks == null:
		return
	if _polling_chat:
		_chat_dirty = true
		return
	_polling_chat = true
	var changed := false
	if Time.get_ticks_msec() >= _directory_due:
		_directory_due = Time.get_ticks_msec() + 12000
		var directory := await _tasks.directory()
		if not directory.has("error"):
			var agents := {}
			for agent: Dictionary in directory.get("chat_agents", []):
				agents[agent.name] = agent
			if agents != _chat_agents:
				_chat_agents = agents
				changed = true
				if is_instance_valid(console):
					_show_chat_tabs()
	if _session and not _session.legacy_chat_tabs.is_empty():
		if await _restore_legacy_chats():
			changed = true
	var peers: Array[String] = _chat_tabs.duplicate()
	for start in range(0, peers.size(), 12):
		var result := await _tasks.conversations(peers.slice(start, start + 12))
		for peer in result.get("conversations", {}):
			var history := ChatHistory.read(result.conversations[peer])
			if history != _conversations.get(peer):
				var previous: Dictionary = _conversations.get(peer, {})
				if peer == chat_peer and not previous.is_empty() and not history.reply.is_empty() and history.reply != previous.reply:
					speak(history.reply.text)
				_conversations[peer] = history
				changed = true
	if changed:
		refresh_chat()
	_polling_chat = false
	if _chat_dirty:
		_chat_dirty = false
		_poll_chat.call_deferred()

func _restore_legacy_chats() -> bool:
	var legacy := _session.legacy_chat_tabs
	var used: Array[String] = []
	for start in range(0, legacy.size(), 12):
		var result := await _tasks.conversations(legacy.slice(start, start + 12))
		if not result.has("conversations"):
			return false
		for peer in result.conversations:
			var history := ChatHistory.read(result.conversations[peer])
			if not history.lines.is_empty():
				used.append(peer)
	for peer in used:
		if peer not in _chat_tabs:
			_chat_tabs.append(peer)
	if chat_peer.is_empty() and not _chat_tabs.is_empty():
		chat_peer = _session.legacy_chat_peer if _session.legacy_chat_peer in _chat_tabs else _chat_tabs[0]
	_session.save_chat_tabs(_chat_tabs, chat_peer, true)
	if is_instance_valid(console):
		_show_chat_tabs()
	return true

func refresh_actions() -> void:
	if is_instance_valid(console) and client:
		if not chat_peer.is_empty() and chat_peer != Presence.CODEX:
			console.update_development({}, false, false)
			return
		var draft := client.draft
		var available := false
		match draft.get("subject", ""):
			"shoreline": available = _world._shoreline.available()
			"grid": available = _world._grid_scenery.available()
			"grid_palette": available = draft.get("status") != "passed" or _world._is_workshop(_world.zone_id)
			"behavior", "workshop_tool": available = _world._is_workshop(_world.zone_id) and _world.zone_id == draft.get("preview_zone")
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
		refresh_chat()

func resume(path: String) -> void:
	_session = DevelopmentSession.new(path)
	_voice.selected = _session.voice_id
	console_lines = _session.lines
	CodexConsole.prompts = _session.prompts
	_chat_tabs = _session.chat_tabs.duplicate()
	chat_peer = _session.chat_peer

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
	else:
		_world._activate_agent(Presence.CODEX)

func speak(text: String) -> void:
	_voice.speak(text)

func _refresh_voice() -> void:
	if is_instance_valid(console):
		console.update_voice(_voice.enabled, _voice.voices, _voice.selected, _voice.status, _voice.can_connect, _voice.loading)
