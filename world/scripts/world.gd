extends Node3D

const SAVE_PATH := "user://world-state.json"
const WorldArt = preload("res://scripts/world_art.gd")
const Villa = preload("res://scripts/zones/villa.gd")
const Graphics = preload("res://scripts/rendering/graphics_settings.gd")
const Grid = preload("res://scripts/zones/grid_zone.gd")
const WorldTools = preload("res://scripts/workshop/world_tools.gd")
const PrefabLibrary = preload("res://scripts/workshop/prefab_library.gd")
const GridPalette = preload("res://scripts/ui/grid_palette.gd")
const GridAgentClient = preload("res://scripts/agents/grid_agent_client.gd")
const AssetClient = preload("res://scripts/agents/asset_client.gd")
const WorldToolBridge = preload("res://scripts/agents/world_tool_bridge.gd")
const EnvironmentLibrary = preload("res://scripts/zones/environment_library.gd")
const BinaryAvatar = preload("res://scripts/agents/binary_avatar.gd")
const SceneAnimations = preload("res://scripts/animation/scene_animations.gd")
const CodexConsole = preload("res://scripts/ui/codex_console.gd")
const WorkbenchPanel = preload("res://scripts/ui/workbench_panel.gd")
const WorldDevelopment = preload("res://scripts/agents/world_development.gd")
const ShorelineLook = preload("res://scripts/rendering/shoreline_look.gd")
const GridScenery = preload("res://scripts/zones/grid_scenery.gd")
const WorkshopToolRegistry = preload("res://scripts/workshop/tool_registry.gd")
const BehaviorRuntime = preload("res://scripts/plugins/behavior_runtime.gd")
const WorldStateStore = preload("res://scripts/persistence/world_state_store.gd")
var manifest: Dictionary
var asset_client: Node
var zone_id := "construct"
var zone_root: Node3D
var player: CharacterBody3D
var camera: Camera3D
var environment: Environment
var sky_material: ProceduralSkyMaterial
var sun: DirectionalLight3D
var hud: Label
var hint: Label
var gateway_label: Label
var overlay: PanelContainer
var overlay_content: VBoxContainer
var overlay_panel_style: StyleBoxFlat
var interactables: Array[Dictionary] = []
var nearest: Dictionary = {}
var agent_labels: Dictionary = {}
var agent_states: Dictionary = {}
var request: HTTPRequest
var gateway_url := ""
var gateway_token := ""
var request_pending := false
var gateway_connected := false
var save_clock := 0.0
var pitch := 0.0
var sensitivity := 0.002
var smoke_mode := false
var shifting := false
var building := false
var zone_title_tween: Tween
const SHIFT_SECONDS := 4.5
const JUMP_SPEED := 4.8
# A zone is built off-screen into these, then committed on the main thread.
var build_root: Node3D
## Builders share build_root and friends, so only one zone may be under construction at a time,
## whether on a worker thread (shifts, warm-up) or on the main thread (start-up, menu travel).
var build_mutex := Mutex.new()
var build_interactables: Array[Dictionary] = []
var build_agent_labels: Dictionary = {}
var water := {"has": false, "level": -INF}
var underwater: ColorRect
var world_tools: RefCounted
var prefab_library: PrefabLibrary
var behavior_runtime: BehaviorRuntime
var workshops := {}
var grid_palette_requested := false
var grid_agent: HTTPRequest
var world_bridge: HTTPRequest
var environment_library: RefCounted
var companion: Node3D
var scene_animations: RefCounted
var codex_console: Control
var cli_process := -1
var console_busy := false
var voice_enabled := false
var console_lines := PackedStringArray()
var _workbench_capability := ""
var _workbench_panel: Control
var _development: WorldDevelopment
var _shoreline := ShorelineLook.new()
var _grid_scenery := GridScenery.new()
var _workshop_actions := WorkshopToolRegistry.new()
var _development_action_busy := false
var _development_status := ""

func _ready() -> void:
	manifest = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var args := OS.get_cmdline_user_args()
	if "--workbench" in args:
		_workbench_capability = OS.get_environment("EUCLID_WORKBENCH_TOKEN")
	OS.unset_environment("EUCLID_WORKBENCH_TOKEN")
	var water_check := "--water-check" in args or "--coast-check" in args
	var benchmark := "--benchmark" in args
	smoke_mode = "--smoke" in args or "--capture" in args or water_check or benchmark
	environment_library = EnvironmentLibrary.new("" if smoke_mode else "user://environments.json")
	manifest.zones.append_array(environment_library.environments())
	prefab_library = PrefabLibrary.new("" if smoke_mode else "user://grid-prefabs.json")
	Graphics.configure(get_viewport(), smoke_mode)
	_setup_input()
	_setup_lighting()
	_setup_player()
	behavior_runtime = BehaviorRuntime.new(player)
	world_tools = WorldTools.new("" if smoke_mode else "user://grid-entities.json", prefab_library, behavior_runtime)
	companion = BinaryAvatar.new()
	companion.name = "CodexAvatar"
	add_child(companion)
	scene_animations = SceneAnimations.new("" if smoke_mode else "user://companion-animation.json", companion.animation_player())
	_setup_ui()
	_setup_gateway()
	WorldArt.init(self)
	_load_zone("construct")
	if not smoke_mode:
		_restore()
		_setup_world_bridge()
		if "--workbench-preview" not in args:
			_warm_up()
	get_tree().auto_accept_quit = false
	if water_check:
		var diagnostic := "coast_check.gd" if "--coast-check" in args else "water_check.gd"
		var check: Node = load("res://scripts/diagnostics/" + diagnostic).new()
		add_child(check)
		check.start.call_deferred(self)
	elif benchmark:
		await get_tree().process_frame
		load("res://scripts/diagnostics/benchmark.gd").run(self)
	elif "--smoke" in args:
		call_deferred("_smoke_test")
	elif "--capture" in OS.get_cmdline_user_args():
		smoke_mode = true
		call_deferred("_capture_previews")
	else:
		_report_boot_ready()

func _report_boot_ready() -> void:
	var receipt := OS.get_environment("EUCLID_BOOT_READY")
	OS.unset_environment("EUCLID_BOOT_READY")
	if receipt.is_empty():
		return
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	if is_instance_valid(zone_root) and is_instance_valid(player) and camera.is_current():
		var file := FileAccess.open(receipt, FileAccess.WRITE)
		if file:
			file.store_string(str(OS.get_process_id()))
			file.close()

func _setup_input() -> void:
	var keys := {"forward": KEY_W, "back": KEY_S, "left": KEY_A, "right": KEY_D, "interact": KEY_E, "travel": KEY_TAB, "jump": KEY_SPACE, "dive": KEY_C}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var event := InputEventKey.new()
		event.physical_keycode = keys[action]
		InputMap.action_add_event(action, event)
	# 1, 2, 3 shift the world around you to the zones in manifest order.
	for i in mini(3, manifest.zones.size()):
		var action := "zone_%d" % (i + 1)
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var key := InputEventKey.new()
			key.physical_keycode = KEY_1 + i
			InputMap.action_add_event(action, key)

func _setup_lighting() -> void:
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	sky_material = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("6f9fc3")
	sky_material.sky_horizon_color = Color("e5d6b8")
	sky_material.ground_bottom_color = Color("74796a")
	sky_material.ground_horizon_color = Color("d0c4ab")
	var sky := Sky.new()
	sky.sky_material = sky_material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_color = Color("d6e3ed")
	environment.ambient_light_energy = 0.50
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	if RenderingServer.get_current_rendering_method() == "forward_plus":
		environment.ssao_enabled = true
		environment.ssao_radius = 1.4
		environment.ssao_intensity = 1.8
		environment.glow_enabled = true
		environment.glow_intensity = 0.22
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-36, -32, 0)
	sun.light_color = Color("fff0da")
	sun.light_energy = 1.1
	sun.light_angular_distance = 0.6
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 70
	add_child(sun)

func _setup_player() -> void:
	player = CharacterBody3D.new()
	player.floor_snap_length = 0.35
	player.floor_max_angle = deg_to_rad(50)
	player.floor_constant_speed = true
	add_child(player)
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.7
	shape.shape = capsule
	shape.position.y = 0.85
	player.add_child(shape)
	camera = Camera3D.new()
	camera.position.y = 1.65
	camera.fov = 75
	player.add_child(camera)
	camera.current = true

func _setup_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var ui := Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(ui)
	hud = _ui_label(ui, Vector2(36, 30), 22)
	hud.modulate.a = 0.0
	gateway_label = _ui_label(ui, Vector2(36, 62), 13)
	gateway_label.visible = false
	hint = _ui_label(ui, Vector2(32, 850), 17)
	underwater = ColorRect.new()
	underwater.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	underwater.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var under_mat := ShaderMaterial.new()
	under_mat.shader = load("res://shaders/underwater.gdshader")
	underwater.material = under_mat
	underwater.visible = false
	ui.add_child(underwater)
	ui.move_child(underwater, 0)
	var crosshair := _ui_label(ui, Vector2.ZERO, 14)
	crosshair.text = "·"
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	overlay = PanelContainer.new()
	ui.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.offset_left = 80
	overlay.offset_top = 170
	overlay.offset_right = -80
	overlay.offset_bottom = -70
	var style := StyleBoxFlat.new()
	style.bg_color = Color("111d2c")
	style.content_margin_left = 38
	style.content_margin_top = 32
	style.content_margin_right = 38
	style.content_margin_bottom = 32
	style.corner_radius_top_left = 16
	style.corner_radius_top_right = 16
	style.corner_radius_bottom_left = 16
	style.corner_radius_bottom_right = 16
	overlay_panel_style = style
	overlay.add_theme_stylebox_override("panel", overlay_panel_style)
	overlay_content = VBoxContainer.new()
	overlay_content.add_theme_constant_override("separation", 18)
	overlay.add_child(overlay_content)
	overlay.hide()
	_show_menu()

func _ui_label(parent: Node, at: Vector2, font_size: int) -> Label:
	var label := Label.new()
	parent.add_child(label)
	label.position = at
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("f5f8ff"))
	label.add_theme_color_override("font_shadow_color", Color("142137"))
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _panel(title: String, description: String) -> void:
	overlay.add_theme_stylebox_override("panel", overlay_panel_style)
	overlay.offset_left = 520
	overlay.offset_top = 190
	overlay.offset_right = -520
	overlay.offset_bottom = -190
	for child in overlay_content.get_children():
		if child == codex_console:
			codex_console = null
		if child == _workbench_panel:
			_workbench_panel = null
		overlay_content.remove_child(child)
		child.queue_free()
	if not title.is_empty():
		var heading := Label.new()
		heading.text = title
		heading.add_theme_font_size_override("font_size", 34)
		overlay_content.add_child(heading)
	if not description.is_empty():
		var text := Label.new()
		text.text = description
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_theme_font_size_override("font_size", 18)
		text.modulate.a = 0.75
		overlay_content.add_child(text)
	overlay.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _button(title: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size.y = 46
	button.add_theme_font_size_override("font_size", 20)
	button.pressed.connect(callback)
	overlay_content.add_child(button)

func _show_menu() -> void:
	_panel("EUCLID", "")
	_button("Resume", _close_panel)
	for i in mini(3, manifest.zones.size()):
		var zone: Dictionary = manifest.zones[i]
		_button("%d    %s" % [i + 1, zone.name], _travel.bind(str(zone.id)))
	if _is_workshop(zone_id) and not shifting:
		_button("Grid tools  [B]", _request_grid_palette)
	_button("Codex  [F2]", _open_codex_console)
	if not _workbench_capability.is_empty():
		_button("Workbench  [F4]", _open_workbench)
	if manifest.zones.size() > 3:
		var spaces := OptionButton.new()
		spaces.add_item("Custom spaces")
		for zone in manifest.zones.slice(3):
			spaces.add_item(zone.name)
			spaces.set_item_metadata(spaces.item_count - 1, zone.id)
		spaces.item_selected.connect(func(index: int) -> void:
			if index > 0: _travel(spaces.get_item_metadata(index)))
		overlay_content.add_child(spaces)
	_button("Save and quit", _quit)

func _close_panel() -> void:
	overlay.hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _open_workbench() -> void:
	if _workbench_capability.is_empty() or shifting:
		return
	if is_instance_valid(_workbench_panel):
		if overlay.visible:
			_close_panel()
		else:
			overlay.show()
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	_panel("", "")
	overlay.offset_left = 68
	overlay.offset_top = 55
	overlay.offset_right = -68
	overlay.offset_bottom = -55
	var frame := CodexConsole.frame_style()
	frame.content_margin_left = 18
	frame.content_margin_right = 18
	frame.content_margin_top = 12
	frame.content_margin_bottom = 12
	overlay.add_theme_stylebox_override("panel", frame)
	_workbench_panel = WorkbenchPanel.new()
	overlay_content.add_child(_workbench_panel)
	_workbench_panel.setup(gateway_url, gateway_token, _workbench_capability, _preview_live_change,
		_finish_live_change, _live_change_status, _workbench_plugin_context)
	_workbench_panel.close_requested.connect(_close_panel)
	_workbench_panel.restart_requested.connect(_restart_workbench)

func _preview_live_change(candidate: Dictionary) -> Dictionary:
	await get_tree().process_frame
	if shifting or building:
		return {"ok": false, "message": "Wait for the environment to finish loading before starting a live preview."}
	if candidate.has("shoreline"):
		return _shoreline.preview(candidate)
	if candidate.has("grid"):
		return _grid_scenery.preview(candidate)
	if candidate.has("workshop_tool"):
		return _workshop_actions.preview(candidate, zone_id, world_tools if _is_workshop(zone_id) else null)
	var binding: Dictionary = candidate.get("binding", {})
	if not binding.is_empty() and (not _is_workshop(zone_id) or binding.get("zone") != zone_id):
		return {"ok": false, "message": "Return to the Grid space used to author this plugin."}
	var result := behavior_runtime.preview(candidate)
	if not result.ok or binding.is_empty():
		return result
	var request := {"id": candidate.plugin, "settings": {}}
	if not str(binding.get("target", "")).is_empty():
		request["target"] = binding.target
	var linked: Dictionary = world_tools.preview_behavior(candidate.draft, binding.get("source", ""), request)
	if not linked.ok:
		behavior_runtime.finish(candidate.draft, false)
		return {"ok": false, "message": linked.error}
	return {"ok": true, "message": "Plugin and test link active. Try the interaction in The Grid."}

func _live_change_status(draft_id: String) -> String:
	var action_status := _workshop_actions.status(draft_id)
	if not action_status.is_empty():
		return action_status
	var shore_status := _shoreline.status(draft_id)
	if not shore_status.is_empty():
		return shore_status
	var grid_status := _grid_scenery.status(draft_id)
	return grid_status if not grid_status.is_empty() else behavior_runtime.preview_status(draft_id)

func _finish_live_change(action: String, draft_id: String) -> Dictionary:
	if action in ["apply", "restore"]:
		_workshop_actions.reload_committed()
	if action == "restore":
		behavior_runtime.reload_committed()
		_shoreline.reload_committed()
		_grid_scenery.reload_committed()
		return {"live": false}
	var keep := action == "apply"
	if _development:
		_development.forget(draft_id)
	if _shoreline.finish(draft_id, keep) or _grid_scenery.finish(draft_id, keep) or _workshop_actions.finish(draft_id, keep):
		return {"live": true}
	var was_live := behavior_runtime.finish(draft_id, keep)
	var result: Dictionary = world_tools.finish_behavior_preview(draft_id, keep and was_live) if _is_workshop(zone_id) else {"ok": true}
	return {"live": was_live, "warning": result.get("error", "")}

func _workbench_plugin_context() -> Dictionary:
	if not _is_workshop(zone_id) or shifting:
		return {}
	var entities: Array = world_tools.execute("list_entities").get("entities", [])
	return {"zone": zone_id, "entities": entities.slice(maxi(0, entities.size() - 64))}

func _restart_workbench() -> void:
	if smoke_mode or shifting or _workbench_capability.is_empty():
		return
	if _write_state(SAVE_PATH) != OK:
		_workbench_panel.show_error("Euclid could not save your place. Restart cancelled.")
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
	OS.set_environment("EUCLID_WORKBENCH_TOKEN", _workbench_capability)
	var supervisor := OS.get_environment("EUCLID_BOOT_NODE")
	if supervisor.is_empty():
		OS.set_restart_on_exit(true, arguments)
	else:
		var command := PackedStringArray([ProjectSettings.globalize_path("res://../scripts/recovery.mjs"),
			"restart", OS.get_executable_path(), str(OS.get_process_id())])
		command.append_array(arguments)
		if OS.create_process(supervisor, command) == -1:
			OS.unset_environment("EUCLID_WORKBENCH_TOKEN")
			_workbench_panel.show_error("Euclid could not start the recovery supervisor. Restart cancelled.")
			return
	get_tree().quit()

func _request_grid_palette() -> void:
	grid_palette_requested = true

func _show_grid_palette() -> void:
	if not _is_workshop(zone_id) or shifting:
		return
	var direction := -camera.global_basis.z
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, camera.global_position + direction * 24.0)
	query.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var at := player.global_position + Vector3(direction.x, 0, direction.z).normalized() * 3.0
	var selected := ""
	if not hit.is_empty():
		var collider: Object = hit.collider
		selected = str(collider.get_meta("entity_id")) if collider.has_meta("entity_id") else ""
		if collider is Node and collider.name == "GridFloor" and hit.normal.y > 0.9:
			at = hit.position
	at = Vector3(clampf(at.x, -60.0, 60.0), 0, clampf(at.z, -60.0, 60.0))
	_panel("Grid tools", "")
	overlay.offset_left = 850
	overlay.offset_top = 110
	overlay.offset_right = -30
	overlay.offset_bottom = -100
	var palette := GridPalette.new()
	overlay_content.add_child(palette)
	palette.setup(world_tools, at, selected, _workshop_action_catalog, _run_palette_action)
	palette.agent_requested.connect(_run_grid_agent.bind(palette))
	_button("Back to The Grid  [Esc]", _close_panel)

func _run_grid_agent(prompt: String, placement: Array, palette: Control) -> void:
	var requested_zone := zone_root
	var response: Dictionary = await grid_agent.plan(prompt)
	if not is_instance_valid(palette) or not palette.is_visible_in_tree() or requested_zone != zone_root or shifting:
		return
	if response.has("error"):
		palette.finish_agent_request(response)
		return
	var plan: Dictionary = response.plan
	if plan.get("action") != "spawn_cone":
		palette.finish_agent_request({"error": "Codex can create one traffic cone. Try asking for a color or size."})
		return
	var result: Dictionary = world_tools.execute("spawn", {
		"type": "traffic_cone", "position": placement, "color": plan.get("color"), "scale": plan.get("scale"),
	})
	palette.finish_agent_request(result)

func _open_codex_console() -> void:
	if is_instance_valid(codex_console):
		if codex_console.is_visible_in_tree():
			_close_panel()
		else:
			overlay.show()
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			codex_console.focus_entry()
		return
	_panel("", "")
	overlay.add_theme_stylebox_override("panel", CodexConsole.frame_style())
	codex_console = CodexConsole.new()
	codex_console.size_flags_vertical = Control.SIZE_EXPAND_FILL
	overlay_content.add_child(codex_console)
	codex_console.submitted.connect(_submit_codex_command)
	codex_console.cli_requested.connect(_open_native_cli)
	codex_console.minimize_requested.connect(_close_panel)
	codex_console.layout_requested.connect(_layout_codex_console)
	codex_console.voice_requested.connect(_set_voice)
	codex_console.development_requested.connect(_codex_development_action)
	_layout_codex_console(false)
	codex_console.setup(console_lines, console_busy, voice_enabled)
	_refresh_development_actions()
	if _development:
		_development.refresh()

func _refresh_development_actions() -> void:
	if is_instance_valid(codex_console) and _development:
		var draft := _development.draft
		var available := false
		match draft.get("subject", ""):
			"shoreline": available = _shoreline.available()
			"grid": available = _grid_scenery.available()
			"behavior", "workshop_tool": available = _grid_scenery.available() and zone_id == draft.get("preview_zone")
		if draft.get("agent_source", false):
			available = true
		codex_console.update_development(draft, available and not shifting and not _development_action_busy,
			_live_change_status(draft.get("id", "")) == "active")

func _development_changed() -> void:
	var draft := _development.draft
	var status: String = draft.get("status", "")
	var stamp := "%s/%s" % [draft.get("id", ""), status]
	if stamp != _development_status:
		_development_status = stamp
		match status:
			"staged":
				if draft.get("agent_source", false):
					_console_notice(draft.summary if not draft.summary.is_empty() else "Codex prepared the source draft.")
					_console_notice("Review the diff, then run checks to prepare a playable build.")
			"passed": _console_notice("Draft checks passed. Preview the change or review the diff.")
			"failed":
				if draft.get("has_patch", false):
					_console_notice("The draft failed checks. Open the draft to inspect the results.")
				else:
					_console_notice("Source authoring failed. " + draft.error)
	_refresh_development_actions()

func _codex_development_action(action: String) -> void:
	if not _development or _development.draft.is_empty() or _development_action_busy or shifting:
		return
	if action == "review":
		_open_workbench()
		if is_instance_valid(_workbench_panel):
			_workbench_panel.show_review(not _development.draft.get("has_patch", false))
		return
	var id: String = _development.draft.id
	if action == "live" and _development.draft.get("agent_source", false):
		action = "play" if _development.draft.status == "passed" else "check"
	_development_action_busy = true
	_refresh_development_actions()
	var result := await _development.command(action)
	if result.has("error"):
		_console_notice(result.error)
	elif action == "live":
		var activated := await _preview_live_change(result.live)
		_console_notice(activated.message)
	elif action == "play":
		_console_notice("Opened the checked build in a separate Euclid window.")
	elif action == "check":
		_console_notice("Running checks in the isolated preview project.")
	elif action == "discard":
		var finished := _finish_live_change("discard", id)
		_console_notice("Discarded the draft and restored the previous version." if finished.live else "Discarded the draft.")
	_development_action_busy = false
	_refresh_development_actions()

func _layout_codex_console(expanded: bool) -> void:
	overlay.offset_left = 46 if expanded else 835
	overlay.offset_top = 45 if expanded else 96
	overlay.offset_right = -46 if expanded else -46
	overlay.offset_bottom = -45 if expanded else -108

func _console_notice(line: String) -> void:
	console_lines.append(line)
	if console_lines.size() > 22:
		console_lines.remove_at(0)
	if is_instance_valid(codex_console):
		codex_console.update_display(console_lines, console_busy)

func _open_native_cli() -> void:
	if OS.get_name() != "Windows" or not is_instance_valid(world_bridge):
		_console_notice("Open the Windows Euclid launcher with its gateway to start the native CLI.")
		return
	if gateway_url.is_empty() or gateway_token.is_empty():
		_console_notice("The native CLI needs Euclid’s local gateway.")
		return
	if cli_process > 0 and OS.is_process_running(cli_process):
		_console_notice("The Codex terminal is open. Use Alt+Tab to return to it.")
		return
	var script_path := ProjectSettings.globalize_path("res://../scripts/codex-terminal.ps1")
	cli_process = OS.create_process("powershell.exe", ["-NoProfile", "-ExecutionPolicy", "Bypass",
		"-File", script_path, "-WorldSession", world_bridge.session], true)
	if cli_process <= 0:
		_console_notice("The native terminal could not be opened.")

func _set_voice(enabled: bool) -> void:
	voice_enabled = enabled
	if not DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		if enabled: _console_notice("System voices are unavailable on this device.")
	elif enabled:
		if DisplayServer.tts_get_voices_for_language("en").is_empty():
			_console_notice("Install an English system voice to enable speech.")
	else:
		DisplayServer.tts_stop()

func _world_context() -> Dictionary:
	var environments := []
	for zone in manifest.zones:
		environments.append({"id": zone.id, "name": zone.name, "description": zone.get("description", zone.get("subtitle", ""))})
	return {"current": zone_id, "environments": environments, "workshop_tools": _workshop_action_catalog()}

func _workshop_action_catalog() -> Array[Dictionary]:
	return _workshop_actions.catalog(zone_id) if not shifting and _is_workshop(zone_id) else []

func _run_palette_action(entry: Dictionary) -> Dictionary:
	return _run_registered_action({"target": entry.name, "revision": entry.revision, "zone": zone_id})

func _run_registered_action(plan: Dictionary) -> Dictionary:
	if shifting or plan.get("zone") != zone_id or not _is_workshop(zone_id):
		return {"ok": false, "message": "Return to the Grid space where this action was listed."}
	return _workshop_actions.execute(zone_id, plan.target, plan.get("revision", ""), world_tools)

func _setup_world_bridge() -> void:
	world_bridge = WorldToolBridge.new()
	add_child(world_bridge)
	world_bridge.configure(gateway_url, gateway_token, _world_context, _call_world_tool)

func _submit_codex_command(prompt: String) -> void:
	if console_busy:
		return
	console_busy = true
	_console_notice("> " + prompt)
	var context := _world_context()
	context["shoreline_preview"] = zone_id == "beach"
	context["grid_development"] = _development != null and _grid_scenery.available() and not shifting
	context["source_development"] = _development != null
	var requested_zone := zone_root.get_instance_id() if is_instance_valid(zone_root) else 0
	if _is_workshop(zone_id) and not shifting:
		var entities: Array = world_tools.execute("list_entities").get("entities", [])
		context["entities"] = entities.slice(maxi(0, entities.size() - 64))
		context["prefabs"] = world_tools.execute("list_prefabs").get("prefabs", [])
		context["behaviors"] = world_tools.execute("list_behaviors").get("behaviors", [])
	if scene_animations:
		context["animation"] = scene_animations.context(world_tools if _is_workshop(zone_id) else null)
	var response: Dictionary = await grid_agent.plan(prompt, context)
	console_busy = false
	if response.has("error"):
		_console_notice(str(response.error))
		return
	console_busy = true
	if response.plan.tool in ["draft_shoreline", "draft_grid", "draft_behavior", "draft_workshop_tool", "draft_source"]:
		await _request_development_draft(response.plan.tool, prompt, requested_zone)
	elif response.plan.tool == "run_workshop_tool":
		for entry in context.workshop_tools:
			if entry.name == response.plan.target:
				response.plan["zone"] = context.current
				response.plan["revision"] = entry.revision
				break
		await _call_world_tool(response.plan)
	else:
		await _call_world_tool(response.plan)
	console_busy = false
	if is_instance_valid(codex_console):
		codex_console.update_display(console_lines, false)

func _request_development_draft(tool: String, prompt: String, requested_zone: int) -> void:
	if not _development:
		_console_notice("Open Start Euclid Workbench.cmd to develop and preview changes from F2.")
		return
	var available := _shoreline.available() if tool == "draft_shoreline" else _grid_scenery.available()
	if tool != "draft_source" and (not is_instance_valid(zone_root) or requested_zone != zone_root.get_instance_id() or shifting or not available):
		_console_notice("Enter the beach with simulated surf to draft a shoreline change." if tool == "draft_shoreline"
			else "Enter a Grid space to draft this change.")
		return
	var context := {}
	if tool == "draft_behavior":
		context = _workbench_plugin_context()
	elif tool == "draft_workshop_tool":
		var entities: Array = world_tools.execute("list").get("entities", [])
		context = {"zone": zone_id, "entities": []}
		for entity in entities.slice(maxi(0, entities.size() - 64)):
			context.entities.append({"id": entity.id, "type": entity.type, "position": entity.position,
				"yaw": entity.yaw, "scale": entity.scale, "color": entity.color})
	var result := await _development.request(tool, prompt, context)
	if result.has("error"):
		_console_notice(result.error)
	elif tool == "draft_source":
		if result.draft.status == "authoring":
			_console_notice("Codex is working in a separate source workspace. Open Workbench to see progress.")
	else:
		var summary: String = result.draft.get("summary", "")
		if not summary.is_empty():
			_console_notice(summary)
		if result.draft.status == "checking":
			_console_notice("Review the diff while the checks run.")

func _call_world_tool(plan: Dictionary) -> Dictionary:
	var result := await _execute_world_tool(plan)
	_console_notice(str(result.message))
	if voice_enabled and result.ok and DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		var voices := DisplayServer.tts_get_voices_for_language("en")
		if not voices.is_empty():
			DisplayServer.tts_speak(str(result.message).xml_escape(), voices[0], 65, 1.0, 1.0, 0, true)
	return result

func _execute_world_tool(plan: Dictionary) -> Dictionary:
	var target: String = str(plan.get("target", ""))
	match plan.get("tool", ""):
		"run_workshop_tool":
			return _run_registered_action(plan)
		"list_workshop_tools":
			var catalog := _workshop_action_catalog()
			var labels := PackedStringArray()
			for entry in catalog:
				labels.append(entry.label)
			return {"ok": true, "message": ", ".join(labels) if not labels.is_empty() else "Enter a Grid space to find workshop actions.", "tools": catalog}
		"list_entities", "list_prefabs", "save_prefab", "spawn_prefab", "list_behaviors", "set_behavior":
			return _execute_workshop_tool(plan)
		"inspect_animation", "preview_animation", "save_animation", "discard_animation":
			if shifting or not scene_animations:
				return {"ok": false, "message": "Wait for the current environment to finish loading."}
			return scene_animations.execute(plan, world_tools if _is_workshop(zone_id) else null)
		"list_assets":
			var listed: Dictionary = await asset_client.list_assets()
			listed["message"] = JSON.stringify(listed.get("assets", [])) if listed.get("ok", false) else listed.get("message", "Asset listing failed.")
			return listed
		"spawn_asset":
			if not _is_workshop(zone_id) or shifting:
				return {"ok": false, "message": "Enter The Grid or a custom Grid space to spawn editable models."}
			var requested_zone := zone_root
			# Capture placement before a download so camera movement cannot change it.
			var position: Array = plan.get("position", _workshop_spawn_position())
			_console_notice("Finding and preparing the model…")
			var imported: Dictionary = await asset_client.ensure_asset(target, _world_context(), plan.get("preserve_rig", false))
			if not imported.get("ok", false):
				return {"ok": false, "message": imported.get("message", "The model could not be imported.")}
			if not is_instance_valid(requested_zone) or zone_root != requested_zone or shifting:
				return {"ok": false, "message": "The model is cached. Spawn it again in your current environment."}
			var result: Dictionary = world_tools.execute("spawn", {"type": "imported_model", "asset_id": imported.asset.asset_id,
				"position": position, "scale": plan.get("scale", 1.0), "color": "ffffff"})
			result["message"] = "Spawned %s. %s — %s. %s" % [imported.asset.title, imported.asset.author,
				imported.asset.license_label, imported.asset.get("credit", "")] if result.ok else result.error
			return result
		"list_environments":
			var context := _world_context()
			var labels := PackedStringArray()
			for zone in context.environments:
				labels.append(zone.name)
			return {"ok": true, "message": "Available environments: " + ", ".join(labels) + ".", "context": context}
		"travel":
			if shifting:
				return {"ok": false, "message": "A world shift is in progress."}
			var zone := _zone(target)
			if zone.id != target:
				return {"ok": false, "message": "That environment is no longer in the catalog."}
			await _shift(target)
			return {"ok": zone_id == target, "message": "You’re in %s." % zone.name, "environment": zone_id}
		"create_environment":
			if shifting or building:
				return {"ok": false, "message": "Wait for the current environment to finish loading."}
			var created: Dictionary = environment_library.create(target, manifest.zones)
			if created.ok:
				manifest.zones.append(created.zone)
			return created
		"follow", "stay":
			var mode: String = plan.tool
			companion.set_mode(mode, zone_id, player)
			return {"ok": true, "message": "I’ll follow you." if mode == "follow" else "I’ll stay here.", "mode": mode}
	return {"ok": false, "message": "Try listing environments, traveling, creating a Grid space, following, or staying."}

func _execute_workshop_tool(plan: Dictionary) -> Dictionary:
	if not _is_workshop(zone_id) or shifting:
		return {"ok": false, "message": "Enter The Grid or a custom Grid space to edit workshop entities."}
	var target: String = plan.get("target", "")
	var behavior: Variant = plan.get("behavior")
	if behavior is Dictionary:
		var target_entity: String = behavior.get("target_entity", "")
		var settings := {}
		for setting in behavior.settings:
			settings[setting.key] = setting.value
		behavior = {"id": behavior.id, "settings": settings}
		if not target_entity.is_empty():
			behavior["target"] = target_entity
	var result: Dictionary = world_tools.execute(plan.tool, {"id": target, "prefab_id": target,
		"name": plan.get("name"), "position": _workshop_spawn_position(), "behavior": behavior})
	if not result.ok:
		result["message"] = result.error
		return result
	match plan.tool:
		"save_prefab":
			result["message"] = "Saved %s to the prefab library." % result.name
		"spawn_prefab":
			result["message"] = "Placed the prefab. You can edit it or undo the placement."
		"set_behavior":
			result["message"] = "Removed the entity’s behavior." if behavior == null else \
				("Updated the live test link." if result.get("preview", false) else "Saved the entity’s behavior.")
		"list_entities", "list_prefabs", "list_behaviors":
			var names := PackedStringArray()
			for item in result.get("prefabs", result.get("entities", result.get("behaviors", []))):
				names.append(item.name)
			result["message"] = "Nothing here yet." if names.is_empty() else ", ".join(names)
	return result

func _workshop_spawn_position() -> Array:
	var forward := -camera.global_basis.z
	var point := player.global_position + Vector3(forward.x, 0, forward.z).normalized() * 3.0
	return [clampf(point.x, -60, 60), 0.0, clampf(point.z, -60, 60)]

func _travel(destination: String) -> void:
	_close_panel()
	_shift(destination)

func _material(color: Color, emissive := false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.75
	if emissive:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 0.6
	return mat

func _box(at: Vector3, size: Vector3, color: Color, collision := true) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _material(color)
	mesh.position = at
	build_root.add_child(mesh)
	if collision:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = size
		shape.shape = box_shape
		body.add_child(shape)
		mesh.add_child(body)
	return mesh

func _label3d(text: String, at: Vector3, color := Color.WHITE, size := 45) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.position = at
	label.font_size = size
	label.modulate = color
	label.outline_size = 3
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	build_root.add_child(label)
	return label

## Instant zone change (restoring a save, tests, captures). Travel uses _shift instead.
func _load_zone(destination: String) -> void:
	var built := _build_zone(destination, _grid_scenery.profile())
	if zone_root:
		zone_root.free()
	_commit_zone(built)
	WorldArt.apply_environment(self, destination)
	var spawn: Dictionary = WorldArt.spawn(destination)
	player.position = spawn.position
	player.velocity = Vector3.ZERO
	player.rotation.y = spawn.yaw
	pitch = 0
	camera.rotation.x = 0
	if is_instance_valid(companion):
		companion.arrive(zone_id, player)
	_update_agent_labels()
	_announce_zone()

## Build a zone into a detached root. Safe to run on a worker thread: nothing here touches the
## scene tree, and the result is only handed to the world by _commit_zone on the main thread.
func _build_zone(destination: String, grid_appearance: Dictionary) -> Dictionary:
	build_mutex.lock()
	var built := _build_zone_locked(destination, grid_appearance)
	build_mutex.unlock()
	return built

func _build_zone_locked(destination: String, grid_appearance: Dictionary) -> Dictionary:
	build_root = Node3D.new()
	build_root.name = "Zone_" + destination
	build_interactables = []
	build_agent_labels = {}
	var zone := _zone(destination)
	var is_grid: bool = destination == "construct" or zone.get("template") == "grid"
	var art := (is_grid and Grid.build(build_root, grid_appearance)) \
		or (destination == "villa" and Villa.build(self)) or (destination == "beach" and WorldArt.shore(self))
	if not art:
		var floor_y := -0.26 if destination == "villa" else -0.2
		_box(Vector3(0,floor_y,0), Vector3(24,0.4,24), Color("69675c") if destination == "villa" else Color(zone.color))
		# Low boundary walls preserve the horizon while keeping the player on the floor.
		for x in [-12,12]:
			_box(Vector3(x,0.55,0), Vector3(0.25,1.1,24), Color(zone.color).darkened(0.09)).visible = destination != "beach"
		for z in [-12,12]:
			_box(Vector3(0,0.55,z), Vector3(24,1.1,0.25), Color(zone.color).darkened(0.09)).visible = destination != "beach"
		if destination == "villa":
			for x in [-8,8]:
				for z in [-7,-2,3,8]:
					_column(Vector3(x,0,z))
		else:
			var sea := _box(Vector3(0,-0.12,-85), Vector3(300,0.1,150), Color("3b9cae"), false)
			var sea_material := ShaderMaterial.new()
			sea_material.shader = load("res://shaders/water.gdshader")
			sea_material.set_shader_parameter("water_color", Color("238b9a"))
			sea.material_override = sea_material
			for x in [-8,8]:
				_box(Vector3(x,1.6,-6), Vector3(0.3,3.2,0.3), Color("81654a"))
				for angle in [0,60,120]:
					var leaf := _box(Vector3(x,3.2,-6), Vector3(4.5,0.12,0.8), Color("538b69"), false)
					leaf.rotation_degrees.y = angle
	for anchor in manifest.anchors:
		if anchor.zone == destination:
			_add_anchor(anchor)
	# Every surface gets the construct effect built in now, so nothing is swapped later.
	WorldArt.make_constructible(build_root)
	return {"id": destination, "root": build_root, "interactables": build_interactables, "agent_labels": build_agent_labels}

## Build on a worker thread so the world keeps running.
func _build_zone_async(destination: String) -> Dictionary:
	while building:
		await get_tree().process_frame
	building = true
	var result := {}
	var appearance := _grid_scenery.profile()
	var task := WorkerThreadPool.add_task(func() -> void: result.merge(_build_zone(destination, appearance)), true, "Build " + destination)
	while not WorkerThreadPool.is_task_completed(task):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	building = false
	return result

func _commit_zone(built: Dictionary, side := 0.0) -> void:
	if scene_animations:
		scene_animations.leave_workshop()
	zone_id = built.id
	zone_root = built.root
	_grid_scenery.attach(zone_root)
	if world_tools != null:
		var linked_preview: String = world_tools.behavior_preview_id()
		if not linked_preview.is_empty():
			behavior_runtime.finish(linked_preview, false)
			world_tools.finish_behavior_preview(linked_preview, false)
		world_tools.attach(null)
		if not workshops.has("construct"):
			workshops["construct"] = world_tools
		if _is_workshop(zone_id):
			if not workshops.has(zone_id):
				var path := "" if smoke_mode else "user://grid-entities-%s.json" % zone_id
				workshops[zone_id] = WorldTools.new(path, prefab_library, behavior_runtime)
			world_tools = workshops[zone_id]
			world_tools.attach(zone_root)
	if side != 0.0:
		WorldArt.set_side(zone_root, side)
	add_child(zone_root)
	_shoreline.attach(zone_root)
	_refresh_development_actions()
	interactables = built.interactables
	agent_labels = built.agent_labels
	nearest = {}

## Build the other zones once in the background after startup, so their models, textures and
## shaders are already loaded the first time you shift to them.
func _warm_up() -> void:
	for zone in manifest.zones.slice(0, 3):
		if zone.id != zone_id:
			var built := await _build_zone_async(str(zone.id))
			built.root.free()

func _zone(id: String) -> Dictionary:
	for item in manifest.zones:
		if item.id == id:
			return item
	return manifest.zones[0]

func _is_workshop(id: String) -> bool:
	return id == "construct" or _zone(id).get("template") == "grid"

## Rewrite the world around the player: the new zone is built in place, then a sphere grows from
## the player's eyes. Behind its front the old zone unravels into blue lattice and pouring digits
## while the new one assembles out of them; sky, sun and atmosphere blend across. The player keeps
## walking throughout and stays where they are.
func _shift(destination: String, seconds := SHIFT_SECONDS) -> void:
	if shifting or destination == zone_id:
		return
	shifting = true
	var built := await _build_zone_async(destination)
	var from_state := WorldArt.zone_state(zone_id)
	var to_state := WorldArt.zone_state(destination)
	var old_root := zone_root
	for body in old_root.find_children("*", "CollisionObject3D", true, false):
		body.process_mode = Node.PROCESS_MODE_DISABLED
	WorldArt.set_side(old_root, -1.0)
	var us := Time.get_ticks_usec()
	_commit_zone(built, 1.0)
	_shift_log("commit", us)
	await _land_in(destination)
	if is_instance_valid(companion):
		companion.arrive(zone_id, player)
	var old_lights := old_root.find_children("*", "Light3D", true, false)
	var new_lights := zone_root.find_children("*", "Light3D", true, false)
	for light in old_lights + new_lights:
		light.set_meta("energy", light.light_energy)
	RenderingServer.global_shader_parameter_set("construct_origin", camera.global_position)
	# Wall-clock timing: frame deltas are capped when a frame runs long, which would otherwise
	# stretch the effect.
	var start := Time.get_ticks_usec()
	var t := 0.0
	var old_dropped := false
	var frame_us := Time.get_ticks_usec()
	while t < 1.0:
		await get_tree().process_frame
		if smoke_mode and Time.get_ticks_usec() - frame_us > 40000:
			print("CONSTRUCT_SHIFT_STEP long frame %.1f ms at t=%.2f" % [(Time.get_ticks_usec() - frame_us) / 1000.0, t])
		frame_us = Time.get_ticks_usec()
		t = clampf((Time.get_ticks_usec() - start) / 1000000.0 / seconds, 0.0, 1.0)
		# Slow and close at first, then racing out to the horizon.
		RenderingServer.global_shader_parameter_set("construct_radius", 30.0 * pow(t, 1.6) + 600.0 * pow(t, 4.0))
		RenderingServer.global_shader_parameter_set("construct_progress", t)
		WorldArt.apply_state(self, from_state, to_state, smoothstep(0.1, 0.8, t))
		for light in new_lights:
			light.light_energy = light.get_meta("energy") * smoothstep(0.15, 0.5, t)
		if is_instance_valid(old_root):
			for light in old_lights:
				light.light_energy = light.get_meta("energy") * (1.0 - smoothstep(0.0, 0.35, t))
			# By now what is left of the old zone is hundreds of metres out: drop it and let
			# global illumination re-learn the new zone while the effect still covers the change.
			if t >= 0.78 and not old_dropped:
				old_dropped = true
				us = Time.get_ticks_usec()
				old_root.queue_free()
				WorldArt.rebuild_gi(self, destination)
				_shift_log("drop old zone (queued)", us)
	if is_instance_valid(old_root) and not old_dropped:
		old_root.queue_free()
	WorldArt.set_side(zone_root, 0.0)
	for light in new_lights:
		light.light_energy = light.get_meta("energy")
	RenderingServer.global_shader_parameter_set("construct_radius", 0.0)
	RenderingServer.global_shader_parameter_set("construct_progress", 0.0)
	WorldArt.apply_environment(self, destination)
	_update_agent_labels()
	_announce_zone()
	shifting = false
	_refresh_development_actions()
	_save()

## Timing of the heavier steps of a shift, printed only by the automated preview capture.
func _shift_log(step: String, since_usec: int) -> void:
	if smoke_mode:
		print("CONSTRUCT_SHIFT_STEP %s %.1f ms" % [step, (Time.get_ticks_usec() - since_usec) / 1000.0])

## Shifting keeps you where you stand when the destination has ground there. If that spot would
## leave you inside a hill, under a roof, in mid-air or out in deep water, you arrive at the
## destination's usual starting point instead.
func _land_in(destination: String) -> void:
	await get_tree().physics_frame
	var p := player.global_position
	var query := PhysicsRayQueryParameters3D.create(p + Vector3(0, 2.4, 0), p + Vector3(0, -6, 0))
	query.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	var sea: float = -INF
	if zone_root.has_meta("water"):
		sea = (zone_root.get_meta("water") as Dictionary).get("sea_level", -INF)
	if not hit.is_empty() and hit.position.y > sea - 1.0:
		player.global_position.y = maxf(p.y, hit.position.y + 0.05)
		return
	var spawn: Dictionary = WorldArt.spawn(destination)
	player.position = spawn.position
	player.velocity = Vector3.ZERO
	player.rotation.y = spawn.yaw

## The zone's name, shown briefly after arriving.
func _announce_zone() -> void:
	hud.text = str(_zone(zone_id).name)
	if zone_title_tween:
		zone_title_tween.kill()
	hud.modulate.a = 0.0
	zone_title_tween = create_tween()
	zone_title_tween.tween_property(hud, "modulate:a", 0.9, 0.6)
	zone_title_tween.tween_interval(2.2)
	zone_title_tween.tween_property(hud, "modulate:a", 0.0, 1.4)

func _column(at: Vector3) -> void:
	var asset_path := "res://assets/generated/villa_column.glb"
	if ResourceLoader.exists(asset_path):
		var asset := load(asset_path) as PackedScene
		var instance := asset.instantiate() as Node3D
		build_root.add_child(instance)
		instance.position = at
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var collision := BoxShape3D.new()
		collision.size = Vector3(0.9,4.4,0.9)
		shape.shape = collision
		shape.position.y = 2.2
		body.add_child(shape)
		instance.add_child(body)
	else:
		_box(at + Vector3(0,2.2,0), Vector3(0.65,4.4,0.65), Color("f1dfbb"))
		_box(at + Vector3(0,0.15,0), Vector3(1.1,0.3,1.1), Color("e3c99b"))

func _add_anchor(anchor: Dictionary) -> void:
	var at := Vector3(anchor.position[0],anchor.position[1],anchor.position[2])
	var item := anchor.duplicate()
	item.position = at
	build_interactables.append(item)
	if anchor.kind == "application":
		if anchor.zone == "construct":
			Grid.workstation(build_root, at)
		elif not WorldArt.workstation(self, at, str(anchor.zone)):
			_box(at + Vector3(0,0.84,0), Vector3(1.9,0.09,0.85), Color("493b30"))
			for x in [-0.82,0.82]:
				_box(at + Vector3(x,0.41,0), Vector3(0.06,0.82,0.65), Color("252d34"))
			_box(at + Vector3(0,1.27,-0.12), Vector3(1.4,0.77,0.07), Color("192a33"), false)
			var screen := _box(at + Vector3(0,1.27,-0.075), Vector3(1.29,0.65,0.012), Color("3c7b82"), false)
			screen.material_override = _material(Color("36737a"), true)
			_box(at + Vector3(0,0.902,0.2), Vector3(0.58,0.018,0.2), Color("768088"), false)
	else:
		var avatar := BinaryAvatar.projection(Color("8aaeff"))
		avatar.position = at + Vector3(0, 1.2, 0)
		build_root.add_child(avatar)
		build_agent_labels[anchor.agent_id] = _label3d(anchor.label, at + Vector3(0,2.2,0), Color("d8e7ff"), 30)
		build_agent_labels[anchor.agent_id].set_meta("name", anchor.label)

func _physics_process(delta: float) -> void:
	if not player:
		return
	var direction := Vector3.ZERO
	var controls := not overlay.visible and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not smoke_mode
	if controls:
		var axes := Input.get_vector("left", "right", "forward", "back")
		direction = player.basis * Vector3(axes.x,0,axes.y)
	# Water: the zone reports the surface height under the player (simulated where it can be),
	# and the player's movement pushes wakes back into the simulation.
	water = WorldArt.water_tick(self, delta)
	var depth: float = water.level - player.position.y if water.has else -1.0
	var swimming := depth > 1.3
	var speed := 4.5
	if depth > 0.25:
		speed *= lerpf(1.0, 0.55, clampf((depth - 0.25) / 1.0, 0.0, 1.0)) # wading drags
	if swimming:
		speed = 2.6
	player.velocity.x = direction.x * speed
	player.velocity.z = direction.z * speed
	if swimming:
		# Buoyancy holds the eyes just above the surface; Space climbs, C dives.
		var target: float = water.level - 1.42
		if controls and Input.is_action_pressed("jump"):
			target += 0.9
		if controls and Input.is_action_pressed("dive"):
			target = player.position.y - 2.5
		player.velocity.y = lerpf(player.velocity.y, clampf((target - player.position.y) * 2.5, -2.5, 3.0), 1.0 - exp(-5.0 * delta))
	else:
		player.velocity.y -= 16 * delta * (0.7 if depth > 0.0 else 1.0)
		if controls and Input.is_action_just_pressed("jump") and player.is_on_floor():
			player.velocity.y = JUMP_SPEED
	player.move_and_slide()
	if is_instance_valid(companion):
		companion.tick(player, delta)
	if player.position.y < -100:
		var spawn: Dictionary = WorldArt.spawn(zone_id)
		player.position = spawn.position
		player.velocity = Vector3.ZERO
	underwater.visible = water.has and camera.global_position.y < water.level - 0.05
	nearest = {}
	var best := 3.0
	for item in interactables:
		var distance: float = player.position.distance_to(item.position)
		var eye_target: Vector3 = item.position + Vector3(0,1.5,0) - camera.global_position
		if distance < best and -camera.global_basis.z.dot(eye_target.normalized()) > 0.55:
			best = distance
			nearest = item
	hint.text = "E    " + str(nearest.label) if not overlay.visible and not nearest.is_empty() else ""
	if grid_palette_requested:
		grid_palette_requested = false
		_show_grid_palette()
	save_clock += delta
	if save_clock > 4:
		save_clock = 0
		_save()

func _unhandled_input(event: InputEvent) -> void:
	if smoke_mode: # automated smoke and capture runs must not react to stray input
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F2:
		_open_codex_console()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F4:
		_open_workbench()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		var window := get_window()
		window.mode = Window.MODE_WINDOWED if window.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_B:
		if _is_workshop(zone_id) and not overlay.visible and not shifting:
			_request_grid_palette()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if overlay.visible:
			_close_panel()
		else:
			_show_menu()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("travel"):
		_show_menu()
	elif not overlay.visible and _zone_key(event) >= 0:
		_shift(str(manifest.zones[_zone_key(event)].id))
	elif event.is_action_pressed("interact") and not overlay.visible and not nearest.is_empty():
		if nearest.kind == "application":
			if zone_id == "construct" and nearest.app_id == "terminal":
				_open_codex_console()
			else:
				_open_app(nearest.app_id)
		else:
			var status: Dictionary = agent_states.get(nearest.agent_id, {})
			_panel(nearest.label, str(status.get("summary", "No report yet.")))
			_button("Back", _close_panel)
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not overlay.visible:
		player.rotate_y(-event.relative.x * sensitivity)
		pitch = clampf(pitch - event.relative.y * sensitivity, -1.35, 1.35)
		camera.rotation.x = pitch
	elif event is InputEventMouseButton and event.pressed and not overlay.visible:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _zone_key(event: InputEvent) -> int:
	for i in mini(3, manifest.zones.size()):
		if event.is_action_pressed("zone_%d" % (i + 1)):
			return i
	return -1

func _open_app(app_id: String) -> void:
	_panel("Terminal" if app_id == "terminal" else "Media", "Not connected yet.")
	overlay.offset_left = 0
	overlay.offset_top = 0
	overlay.offset_right = 0
	overlay.offset_bottom = 0
	_button("Back", _close_panel)

func _save() -> void:
	if smoke_mode:
		return
	_write_state(SAVE_PATH)

func _write_state(save_path: String) -> Error:
	return WorldStateStore.write(save_path, zone_id, player.position, player.rotation.y, pitch)

func _restore() -> void:
	_read_state(SAVE_PATH)

func _read_state(save_path: String) -> void:
	if not FileAccess.file_exists(save_path):
		return
	var state = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if not state is Dictionary or state.get("schema_version") != 1:
		return
	var valid_zone := false
	for zone in manifest.zones:
		if zone.id == state.get("zone"):
			valid_zone = true
	if not valid_zone:
		return
	_load_zone(state.zone)
	var at = state.get("position", [])
	if at is Array and at.size() == 3:
		player.position = Vector3(clampf(float(at[0]),-150,150),clampf(float(at[1]),-20,60),clampf(float(at[2]),-150,150))
	player.rotation.y = float(state.get("yaw",0))
	pitch = clampf(float(state.get("pitch",0)),-1.35,1.35)
	camera.rotation.x = pitch

func _setup_gateway() -> void:
	asset_client = AssetClient.new()
	add_child(asset_client)
	gateway_url = OS.get_environment("CONSTRUCT_GATEWAY_URL")
	gateway_token = OS.get_environment("CONSTRUCT_GATEWAY_TOKEN")
	asset_client.configure(gateway_url, gateway_token)
	grid_agent = GridAgentClient.new()
	add_child(grid_agent)
	grid_agent.configure(gateway_url, gateway_token)
	if not _workbench_capability.is_empty() and not gateway_url.is_empty() and not gateway_token.is_empty():
		_development = WorldDevelopment.new()
		add_child(_development)
		_development.configure(gateway_url, gateway_token, _workbench_capability)
		_development.changed.connect(_development_changed)
	request = HTTPRequest.new()
	request.timeout = 3
	add_child(request)
	request.request_completed.connect(_gateway_result)
	var timer := Timer.new()
	timer.wait_time = 2
	timer.timeout.connect(_poll_gateway)
	add_child(timer)
	timer.start()
	_poll_gateway()

func _poll_gateway() -> void:
	if request_pending:
		return
	if gateway_url.is_empty() or gateway_token.is_empty():
		gateway_label.text = "Gateway offline  /  World exploration available"
		return
	request_pending = true
	var result := request.request(gateway_url + "/v1/world", ["Authorization: Bearer " + gateway_token])
	if result != OK:
		request_pending = false
		_gateway_offline()

func _gateway_offline() -> void:
	gateway_connected = false
	gateway_label.text = "Gateway offline  /  World exploration available"
	_update_agent_labels()

func _gateway_result(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	request_pending = false
	if code != 200:
		_gateway_offline()
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary or not data.get("agents") is Array:
		_gateway_offline()
		return
	gateway_connected = true
	gateway_label.text = "Gateway connected  /  Local event bridge"
	agent_states.clear()
	for agent in data.agents:
		agent_states[agent.agent_id] = agent
	_update_agent_labels()

func _update_agent_labels() -> void:
	for id in agent_labels:
		var state: Dictionary = agent_states.get(id, {})
		var online: bool = gateway_connected and state.get("connected", false)
		agent_labels[id].text = str(agent_labels[id].get_meta("name", "Agent")) + ("  ·  " + str(state.get("status", "online")) if online else "  ·  offline")

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT and not smoke_mode:
		if is_instance_valid(overlay) and not overlay.visible:
			_show_menu()

func _quit() -> void:
	_save()
	get_tree().quit()

func _smoke_test() -> void:
	for zone in manifest.zones:
		_load_zone(zone.id)
		if zone.id == "construct":
			assert(zone_root.get_node_or_null("GridFloor") is StaticBody3D)
		else:
			assert(zone_root.get_child_count() > 5)
		assert(not interactables.is_empty())
		await get_tree().process_frame
	_open_app("terminal")
	assert(overlay.visible)
	_close_panel()
	assert(not overlay.visible)
	_load_zone("villa")
	player.position = Vector3(4,0.1,2) # on the walk beside the reflecting pool
	player.rotation.y = 0.6
	_write_state("user://smoke-state.json")
	_load_zone("construct")
	_read_state("user://smoke-state.json")
	assert(zone_id == "villa")
	assert(player.position.distance_to(Vector3(4,0.1,2)) < 0.01)
	assert(absf(player.rotation.y - 0.6) < 0.01)
	DirAccess.remove_absolute("user://smoke-state.json")
	for frame in range(15):
		await get_tree().physics_frame
	assert(player.position.y > -0.1)
	# Shift in place: the new zone replaces the old one around the player, who stays put.
	var before := player.position
	var old_root := zone_root
	await _shift("beach", 0.5)
	await get_tree().process_frame # the old zone is queued for deletion
	assert(zone_id == "beach" and not is_instance_valid(old_root) and zone_root.get_child_count() > 5)
	assert(not interactables.is_empty() and not shifting)
	assert(Vector2(player.position.x, player.position.z).distance_to(Vector2(before.x, before.z)) < 0.5)
	if not gateway_url.is_empty():
		if request_pending:
			await request.request_completed
		assert(gateway_connected, "Configured gateway must return a valid authenticated snapshot")
		print("CONSTRUCT_GATEWAY_OK: authenticated snapshot received in Godot")
	print("CONSTRUCT_SMOKE_OK: three zones, anchors, collision, application return, saved location round trip, in-place shift")
	get_tree().quit()

func _capture_previews() -> void:
	var output := OS.get_environment("CONSTRUCT_CAPTURE_DIR")
	if output.is_empty():
		get_tree().quit(1)
		return
	# Extra viewpoints per zone: [suffix, eye position, point to look at].
	var views := {
		"villa": [["_pool", Vector3(3.4,0.1,-15), Vector3(0,0.6,22)], ["_house", Vector3(9,0.1,-12), Vector3(-2,4.5,-36)],
			["_view", Vector3(6,0.1,46.6), Vector3(0,-60,140)], ["_cliff", Vector3(12,-78.2,112), Vector3(0,-12,40)],
			["_coastline", Vector3(-75,0.5,50), Vector3(80,-55,150)], ["_hedge", Vector3(4.2,0.1,-12), Vector3(5.6,0.35,-8)],
			["_inner", Vector3(6,0.2,-46.6), Vector3(0,1.6,-64)], ["_atrium", Vector3(-17,0.2,-44.8), Vector3(-23,1.8,-56)],
			["_library", Vector3(-10,0.2,-72), Vector3(10,2,-79)], ["_gallery", Vector3(-28,0.2,-38.4), Vector3(-6,2,-38.4)],
			["_east_garden", Vector3(34.5,0.05,-42), Vector3(44,1,-58)], ["_herb", Vector3(24,-0.85,-30), Vector3(50,-3,30)],
			["_theatre", Vector3(-34.8,-1.0,-50), Vector3(-55,0,-58)], ["_apollo", Vector3(-12.5,0.1,-15), Vector3(-18.5,1.8,-17)]],
		"beach": [["_shore", Vector3(-7,0,-10.5), Vector3(10,0.6,-26)], ["_surf", Vector3(2,0,-11.5), Vector3(0,-0.5,-17.5)], ["_back", Vector3(4,0,-11), Vector3(-6,1.2,8)], ["_wade", Vector3(1,-0.5,-17), Vector3(-4,-0.2,-40)]],
	}
	for zone in manifest.zones:
		_load_zone(zone.id)
		_close_panel()
		# Let global illumination, volumetric fog and temporal effects converge; on the shore, give
		# the simulated surf time to roll in from the wavemaker.
		for frame in range(90):
			await get_tree().process_frame
		if zone.id == "beach":
			await get_tree().create_timer(14.0).timeout
		print("CONSTRUCT_FPS %s %d" % [zone.id, Engine.get_frames_per_second()])
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(output.path_join(str(zone.id) + ".png"))
		for view in views.get(zone.id, []):
			player.position = view[1]
			camera.global_position = player.position + Vector3(0,1.65,0)
			var target: Vector3 = view[2]
			var flat := Vector3(target.x - player.position.x, 0, target.z - player.position.z)
			player.rotation.y = atan2(-flat.x, -flat.z)
			camera.rotation.x = atan2(target.y - 1.65, flat.length())
			for frame in range(60):
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(output.path_join(str(zone.id) + view[0] + ".png"))
	# The shift itself, mid-flight: villa to shore and back to the hub.
	for leg in [["villa", "beach", "shift_villa_beach"], ["beach", "construct", "shift_beach_hub"]]:
		_load_zone(leg[0])
		for frame in range(60):
			await get_tree().process_frame
		var start := Time.get_ticks_msec()
		var worst := 0
		var tick := Time.get_ticks_usec()
		_shift(leg[1])
		for moment in [0.6, 1.3, 2.4, 3.6, 4.4]:
			while (Time.get_ticks_msec() - start) / 1000.0 < moment:
				await get_tree().process_frame
				var now := Time.get_ticks_usec()
				worst = maxi(worst, now - tick)
				tick = now
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(output.path_join("%s_%d.png" % [leg[2], int(moment * 10)]))
			await get_tree().process_frame
			tick = Time.get_ticks_usec() # screenshot frames are left out of the timing
		var longest := 0
		var last := Time.get_ticks_usec()
		while shifting:
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			longest = maxi(longest, now - last)
			last = now
		print("CONSTRUCT_SHIFT %s longest frame %.1f ms" % [leg[2], maxi(worst, longest) / 1000.0])
	_show_menu()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output.path_join("menu.png"))
	print("CONSTRUCT_CAPTURE_OK")
	get_tree().quit()
