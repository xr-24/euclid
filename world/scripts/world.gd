extends Node3D

const SAVE_PATH := "user://world-state.json"
const WorldArt = preload("res://scripts/world_art.gd")
const BuildContext = preload("res://scripts/zones/zone_build_context.gd")
const Workstations = preload("res://scripts/zones/workstations.gd")
const Graphics = preload("res://scripts/rendering/graphics_settings.gd")
const RenderLayers = preload("res://scripts/rendering/render_layers.gd")
const Packages = preload("res://scripts/zones/zone_packages.gd")
const ZoneCatalog = preload("res://scripts/zones/zone_catalog.gd")
const WorldTools = preload("res://scripts/workshop/world_tools.gd")
const ScenePlacement = preload("res://scripts/workshop/scene_placement.gd")
const WorldCommands = preload("res://scripts/agents/world_commands.gd")
const DevelopmentCommands = preload("res://scripts/agents/development_commands.gd")
const Commands = preload("res://scripts/workshop/command_registry.gd")
const SceneCommands = preload("res://scripts/workshop/scene_commands.gd")
const PrefabLibrary = preload("res://scripts/workshop/prefab_library.gd")
const GridPaletteHost = preload("res://scripts/ui/grid_palette_host.gd")
const GridAgentClient = preload("res://scripts/agents/grid_agent_client.gd")
const AssetClient = preload("res://scripts/agents/asset_client.gd")
const SkyClient = preload("res://scripts/agents/sky_client.gd")
const MaterialClient = preload("res://scripts/agents/material_client.gd")
const WorldToolBridge = preload("res://scripts/agents/world_tool_bridge.gd")
const EnvironmentLibrary = preload("res://scripts/zones/environment_library.gd")
const SceneAnimations = preload("res://scripts/animation/scene_animations.gd")
const TerminalTheme = preload("res://scripts/ui/terminal_theme.gd")
const DesktopPanel = preload("res://scripts/ui/desktop_panel.gd")
const AgentPresence = preload("res://scripts/agents/agent_presence.gd")
const PlayerAvatar = preload("res://scripts/player/player_avatar.gd")
const PropGrabber = preload("res://scripts/player/prop_grabber.gd")
const TransformGizmo = preload("res://scripts/workshop/transform_gizmo.gd")
const SceneScanner = preload("res://scripts/player/scene_scanner.gd")
const RigAuthoring = preload("res://scripts/player/rig_authoring.gd")
const PlayerRigPanel = preload("res://scripts/ui/player_rig_panel.gd")
const Atmosphere = preload("res://scripts/rendering/atmosphere.gd")
const AtmospherePanel = preload("res://scripts/ui/atmosphere_panel.gd")
const PieceEditor = preload("res://scripts/pieces/piece_editor.gd")
const PieceDocument = preload("res://scripts/persistence/piece_document.gd")
const PiecePanel = preload("res://scripts/ui/piece_panel.gd")
const TerrainBrush = preload("res://scripts/player/terrain_brush.gd")
const TerrainPanel = preload("res://scripts/ui/terrain_panel.gd")
const TerrainTools = preload("res://scripts/pieces/terrain_tools.gd")
const PlayerMotor = preload("res://scripts/player/player_motor.gd")
const WristComputer = preload("res://scripts/player/wrist_computer.gd")
const WristPages = preload("res://scripts/player/wrist_pages.gd")
const ShorelineLook = preload("res://scripts/rendering/shoreline_look.gd")
const GridScenery = preload("res://scripts/zones/grid_scenery.gd")
const WorkshopToolRegistry = preload("res://scripts/workshop/tool_registry.gd")
const BehaviorRuntime = preload("res://scripts/plugins/behavior_runtime.gd")
const WorldStateStore = preload("res://scripts/persistence/world_state_store.gd")
const DevelopmentHost = preload("res://scripts/agents/development_host.gd")
const LiveExtensions = preload("res://scripts/extensions/live_extensions.gd")
const LiveKinds = preload("res://scripts/extensions/live_kinds.gd")
var manifest: Dictionary
var asset_client: Node
var material_client: MaterialClient
var sky_client: SkyClient
var zone_id := "construct"
var zone_root: Node3D
var player: CharacterBody3D
var camera: Camera3D
var player_avatar: PlayerAvatar
var grabber: PropGrabber
## Drag handles on the selected prop while the build palette is open.
var gizmo: TransformGizmo
var scanner: SceneScanner
var player_rig: RigAuthoring
## Sun, sky, stars, fog and light edits per environment, shared by agents and the panel.
var atmosphere: Atmosphere
var pieces := PieceEditor.new()
var piece_panel: Control
var terrain_brush: TerrainBrush
var _player_motor := PlayerMotor.new()
## Euclid's menu: areas, build tools, Codex, Workbench and settings on the left wrist (Tab).
var wrist: WristComputer
var environment: Environment
var sky_material: ProceduralSkyMaterial
var sun: DirectionalLight3D
var hud: Label
var hint: Label
var gateway_label: Label
var overlay: DesktopPanel
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
var scene_tools := {}
var grid_palette_requested := false
var _palette_host := GridPaletteHost.new()
var grid_agent: HTTPRequest
var world_bridge: HTTPRequest
var environment_library: RefCounted
var agent_presence := AgentPresence.new()
var scene_animations: RefCounted
var _shoreline := ShorelineLook.new()
var _grid_scenery := GridScenery.new()
var _workshop_actions := WorkshopToolRegistry.new()
var _live := LiveExtensions.new()
var _dev: DevelopmentHost = DevelopmentHost.new(self)
var _world_commands := WorldCommands.new(self)
var _development_commands := DevelopmentCommands.new(self)

func _ready() -> void:
	add_child(_dev)
	manifest = ZoneCatalog.read("res://data/world.json")
	var args := OS.get_cmdline_user_args()
	var water_check := "--water-check" in args or "--coast-check" in args
	var benchmark := "--benchmark" in args
	smoke_mode = "--smoke" in args or "--capture" in args or water_check or benchmark
	if not smoke_mode and "--workbench-preview" not in args:
		_dev.capability = OS.get_environment("EUCLID_WORKBENCH_TOKEN")
		if not _dev.capability.is_empty():
			_dev.resume("user://development-session.json")
	OS.unset_environment("EUCLID_WORKBENCH_TOKEN")
	environment_library = EnvironmentLibrary.new("" if smoke_mode else "user://environments.json")
	manifest.zones.append_array(environment_library.environments())
	for zone in manifest.zones:
		Packages.register_zone(zone)
	prefab_library = PrefabLibrary.new("" if smoke_mode else "user://grid-prefabs.json")
	Graphics.configure(get_viewport(), smoke_mode)
	_setup_input()
	_setup_lighting()
	_setup_player()
	behavior_runtime = BehaviorRuntime.new(player)
	world_tools = WorldTools.new("" if smoke_mode else "user://grid-entities.json", prefab_library, behavior_runtime)
	_register_live_extensions()
	add_child(agent_presence)
	scene_animations = SceneAnimations.new("" if smoke_mode else "user://companion-animation.json", null)
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
	if "--draft-view" in args:
		call_deferred("_run_diagnostic", "draft_views.gd")
	elif water_check:
		var diagnostic := "coast_check.gd" if "--coast-check" in args else "water_check.gd"
		var check: Node = load("res://scripts/diagnostics/" + diagnostic).new()
		add_child(check)
		check.start.call_deferred(self)
	elif benchmark:
		await get_tree().process_frame
		load("res://scripts/diagnostics/benchmark.gd").run(self)
	elif "--smoke" in args:
		call_deferred("_run_diagnostic", "world_smoke.gd")
	elif "--capture" in OS.get_cmdline_user_args():
		smoke_mode = true
		call_deferred("_run_diagnostic", "world_capture.gd")
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
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
	var keys := {"forward": KEY_W, "back": KEY_S, "left": KEY_A, "right": KEY_D, "interact": KEY_E, "jump": KEY_SPACE, "dive": KEY_C}
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
	# Mirrors light themselves with an unshadowed copy (see rendering/render_layers.gd).
	sun.layers = RenderLayers.SUN
	sun.add_to_group("scene_sun")
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
	camera.cull_mask = RenderLayers.MAIN_VIEW
	player.add_child(camera)
	camera.current = true
	player_avatar = PlayerAvatar.new()
	player_avatar.mount(player, camera)
	player_rig = RigAuthoring.new(player_avatar, "" if smoke_mode else "user://player-rig.json")
	atmosphere = Atmosphere.new("" if smoke_mode else "user://atmosphere.json", _refresh_atmosphere)
	wrist = WristComputer.new()
	scanner = SceneScanner.new()
	add_child(scanner)
	scanner.setup("" if smoke_mode else "user://water-edits.json", wrist)
	pieces.display_changed.connect(_refresh_piece_services)
	grabber = PropGrabber.new()
	add_child(grabber)
	terrain_brush = TerrainBrush.new()
	add_child(terrain_brush)
	gizmo = TransformGizmo.new()
	gizmo.world = self
	add_child(gizmo)
	gizmo.picked.connect(_select_in_palette)
	gizmo.edited.connect(_select_in_palette)
	wrist.mount(self, camera, player_avatar.hands, WristPages.new(self))

func _setup_ui() -> void:
	add_child(_palette_host)
	_palette_host.agent_requested.connect(_run_grid_agent)
	_palette_host.preview_failed.connect(_console_notice)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var ui := Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.theme = TerminalTheme.make_theme()
	canvas.add_child(ui)
	hud = _ui_label(ui, Vector2(36, 30), 22)
	hud.modulate.a = 0.0
	gateway_label = _ui_label(ui, Vector2(36, 62), 13)
	gateway_label.visible = false
	hint = _ui_label(ui, Vector2.ZERO, 17)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hint.offset_left = 32
	hint.offset_top = -52
	hint.add_theme_color_override("font_outline_color", TerminalTheme.BACKGROUND)
	hint.add_theme_constant_override("outline_size", 6)
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
	overlay = DesktopPanel.new()
	ui.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.offset_left = 80
	overlay.offset_top = 170
	overlay.offset_right = -80
	overlay.offset_bottom = -70
	var style := TerminalTheme.frame_style()
	style.content_margin_left = 24
	style.content_margin_top = 20
	style.content_margin_right = 24
	style.content_margin_bottom = 20
	overlay_panel_style = style
	overlay.add_theme_stylebox_override("panel", overlay_panel_style)
	overlay_content = overlay.content
	overlay.hide()

func _ui_label(parent: Node, at: Vector2, font_size: int) -> Label:
	var label := Label.new()
	parent.add_child(label)
	label.position = at
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", TerminalTheme.BRIGHT)
	label.add_theme_color_override("font_shadow_color", TerminalTheme.BACKGROUND)
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _panel(title: String, description: String, height := 500.0, remember_palette := false) -> void:
	if terrain_brush.active():
		terrain_brush.cancel()
	overlay.add_theme_stylebox_override("panel", overlay_panel_style)
	var viewport_size := get_viewport().get_visible_rect().size
	var side_margin := maxf((viewport_size.x - 680.0) * 0.5, 24.0)
	overlay.offset_left = side_margin
	overlay.offset_right = -side_margin
	overlay.offset_top = maxf((viewport_size.y - height) * 0.5, 24.0)
	overlay.offset_bottom = -overlay.offset_top
	_palette_host.unmount(remember_palette)
	for child in overlay_content.get_children():
		_dev.release(child)
		overlay_content.remove_child(child)
		child.queue_free()
	if not title.is_empty():
		var heading := Label.new()
		heading.text = title
		heading.add_theme_font_size_override("font_size", 25)
		heading.add_theme_color_override("font_color", TerminalTheme.BRIGHT)
		overlay_content.add_child(heading)
	if not description.is_empty():
		var text := Label.new()
		text.text = description
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_theme_font_size_override("font_size", 18)
		text.add_theme_color_override("font_color", TerminalTheme.INK)
		overlay_content.add_child(text)
	_show_panel()

func _show_panel() -> void:
	hint.text = ""
	if is_instance_valid(wrist):
		wrist.lower_wrist()
	overlay.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _button(title: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size.y = 36
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.pressed.connect(callback)
	overlay_content.add_child(button)

func _close_panel() -> void:
	if terrain_brush.active():
		terrain_brush.cancel()
	overlay.hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

## Re-lights the current environment after an atmosphere edit. A shift in progress applies the
## edit itself when it finishes.
func _refresh_atmosphere() -> void:
	if shifting or not is_instance_valid(zone_root):
		return
	var state := WorldArt.zone_state(zone_id, atmosphere.values_for(zone_id))
	WorldArt.apply_state(self, state, state, 1.0)

func _open_atmosphere() -> void:
	if shifting:
		return
	_panel("", "")
	var viewport_size := get_viewport().get_visible_rect().size
	# A column on the right, so the sky and the scene stay in view while it changes.
	overlay.offset_left = maxf(viewport_size.x - 560.0, viewport_size.x * 0.5 + 60.0)
	overlay.offset_top = 28
	overlay.offset_right = -28
	overlay.offset_bottom = -28
	var editor := AtmospherePanel.new()
	editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	overlay_content.add_child(editor)
	editor.setup(atmosphere, zone_id, _close_panel, sky_client)

func _open_pieces() -> void:
	if not _scene_ready():
		return
	var screen := get_viewport().get_visible_rect().size
	var aimed := ScenePlacement.aim_at(player, camera, screen * 0.5, 60.0)
	var placement := _scene_spawn_position()
	_panel("", "")
	overlay.offset_left = maxf(screen.x - 560.0, screen.x * 0.5 + 60.0)
	overlay.offset_top = 28
	overlay.offset_right = -28
	overlay.offset_bottom = -28
	piece_panel = PiecePanel.new()
	piece_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	overlay_content.add_child(piece_panel)
	piece_panel.setup(pieces, placement, aimed.piece, _close_panel)
	_button(gizmo.mode_label(), gizmo.toggle_mode)
	gizmo.mode_button = overlay_content.get_child(overlay_content.get_child_count() - 1) as Button

func terrain_available() -> bool:
	return _scene_ready() and TerrainTools.available(pieces)

func _open_terrain() -> void:
	if not terrain_available():
		return
	var screen := get_viewport().get_visible_rect().size
	_panel("", "")
	overlay.offset_left = maxf(screen.x - 470.0, screen.x * 0.55)
	overlay.offset_top = 28
	overlay.offset_right = -28
	overlay.offset_bottom = minf(380, screen.y - 28) - screen.y
	var editor := TerrainPanel.new()
	overlay_content.add_child(editor)
	editor.setup(pieces, _close_panel, TerrainTools.undo.bind(pieces, player), material_client)
	terrain_brush.attach(pieces, editor, player, camera, _look)

func _open_player_rig() -> void:
	if shifting:
		return
	_panel("", "")
	var viewport_size := get_viewport().get_visible_rect().size
	overlay.offset_top = 28
	overlay.offset_bottom = 414 - viewport_size.y
	var editor := PlayerRigPanel.new()
	overlay_content.add_child(editor)
	editor.setup(player_rig, _close_panel)

## Every kind of live extension shares one lifecycle. See scripts/extensions/.
func _register_live_extensions() -> void:
	var context := {}
	context["zone"] = func() -> String: return zone_id
	context["workshop"] = func() -> Variant: return world_tools if _is_workshop(zone_id) else null
	context["catalog"] = _workshop_action_catalog
	context["run_action"] = _run_palette_action
	LiveKinds.register_all(_live, {"palette": _palette_host, "shoreline": _shoreline, "grid": _grid_scenery,
		"workshop_actions": _workshop_actions, "behaviors": behavior_runtime}, context)

func _preview_live_change(candidate: Dictionary) -> Dictionary:
	await get_tree().process_frame
	if shifting or building:
		return {"ok": false, "message": "Wait for the environment to finish loading before starting a live preview."}
	return _live.preview(candidate)

func _live_change_status(draft_id: String) -> String:
	return _live.status(draft_id)

func _finish_live_change(action: String, draft_id: String) -> Dictionary:
	if action == "stop_palette":
		return {"live": _palette_host.finish(draft_id, false)}
	if action == "restore":
		_live.reload_committed()
		return {"live": false}
	if action == "apply":
		_live.reload_committed(true)
	if _dev.client:
		_dev.client.forget(draft_id)
	return _live.finish(draft_id, action == "apply")

func _save_for_restart() -> Error:
	return _write_state(SAVE_PATH)

## Messages for the F2 console. Commands and services report here.
func _console_notice(line: String) -> void:
	_dev.notice(line)

func _workbench_plugin_context() -> Dictionary:
	if not _is_workshop(zone_id) or shifting:
		return {}
	var entities: Array = world_tools.execute("list_entities").get("entities", [])
	entities = entities.filter(func(item: Dictionary) -> bool: return not item.get("authored", false))
	return {"zone": zone_id, "entities": entities.slice(maxi(0, entities.size() - 64))}

func _request_grid_palette() -> void:
	grid_palette_requested = true

func _show_grid_palette() -> void:
	if not _scene_ready():
		return
	var grid := _is_workshop(zone_id)
	var placement := ScenePlacement.pick(player, camera, world_tools.bounds, grid, true)
	_panel("Grid tools" if grid else "Scene tools", "")
	var viewport_size := get_viewport().get_visible_rect().size
	# A column on the right, clear of the middle of the view, so the selected prop and its
	# handles stay in sight.
	overlay.offset_left = maxf(viewport_size.x - 640.0, viewport_size.x * 0.5 + 60.0)
	overlay.offset_top = minf(110.0, viewport_size.y * 0.1)
	overlay.offset_right = -30
	overlay.offset_bottom = -overlay.offset_top
	_palette_host.mount(overlay_content, zone_id, placement.point, placement.selected, world_tools, _workshop_action_catalog, _run_palette_action)
	_button("Pieces", _open_pieces)
	if terrain_available():
		_button("Terrain", _open_terrain)
	_button(gizmo.mode_label(), gizmo.toggle_mode)
	gizmo.mode_button = overlay_content.get_child(overlay_content.get_child_count() - 1) as Button
	_button("Back  [Esc]", _close_panel)

func _select_in_palette(id: String) -> void:
	if is_instance_valid(piece_panel) and piece_panel.is_visible_in_tree():
		piece_panel.select_piece(id)
		return
	var panel := _palette_host.panel
	if is_instance_valid(panel) and panel.has_method("select_entity"):
		panel.select_entity(id)

func _look(relative: Vector2) -> void:
	player.rotate_y(-relative.x * sensitivity)
	pitch = clampf(pitch - relative.y * sensitivity, -1.35, 1.35)
	camera.rotation.x = pitch

func _run_grid_agent(prompt: String, placement: Array, palette: Control) -> void:
	if gateway_connected:
		_activate_agent(AgentPresence.CODEX)
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

func _world_context() -> Dictionary:
	var environments := []
	for zone in manifest.zones:
		environments.append({"id": zone.id, "name": zone.name, "description": zone.get("description", zone.get("subtitle", ""))})
	return {"current": zone_id, "environments": environments, "workshop_tools": _workshop_action_catalog(),
		"piece_edit": pieces.can_edit() and not shifting,
		"terrain_edit": terrain_available(),
		"behaviors": behavior_runtime.available() if behavior_runtime and not shifting else [],
		"command_registry": Commands.snapshot()}

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
	if _dev.is_task_command(prompt):
		_dev.task_command(prompt)
		return
	if _dev.busy:
		return
	if prompt.length() > 240:
		_console_notice("World commands take up to 240 characters. Use /task for longer requests.")
		return
	_dev.busy = true
	_activate_agent(AgentPresence.CODEX)
	_console_notice("> " + prompt)
	var context := _world_context()
	context["shoreline_preview"] = _dev.client != null and _shoreline.available() and not shifting
	context["grid_development"] = _dev.client != null and _grid_scenery.available() and not shifting
	context["source_development"] = _dev.client != null
	var reviewed: Dictionary = _dev.client.draft.duplicate() if _dev.client else {}
	var benchmark_target: Dictionary = _dev.client.benchmark_target.duplicate() if _dev.client else {}
	context["source_revision"] = reviewed.get("can_revise", false) and reviewed.get("status") in ["staged", "failed", "passed"]
	var requested_zone := zone_root.get_instance_id() if is_instance_valid(zone_root) else 0
	if _scene_ready():
		var entities: Array = world_tools.execute("list_entities").get("entities", [])
		context["entities"] = SceneCommands.planning_entities(entities, prompt, player.global_position)
		context["prefabs"] = world_tools.execute("list_prefabs").get("prefabs", [])
		context["behaviors"] = world_tools.execute("list_behaviors").get("behaviors", [])
		context["scene_assets"] = world_tools.execute("list_scene_assets").get("assets", [])
	if scene_animations:
		context["animation"] = scene_animations.context(world_tools if _scene_ready() else null)
	context["player_rig"] = player_rig.planning_context()
	context["atmosphere"] = atmosphere.planning_context(zone_id)
	if _scene_ready():
		var piece_list := pieces.execute({"tool": "list_pieces"})
		context["pieces"] = piece_list.get("pieces", []).slice(0, 64)
	var response: Dictionary = await grid_agent.plan(prompt, context)
	_dev.busy = false
	if response.has("error"):
		_console_notice(str(response.error))
		return
	var plan: Dictionary = response.plan
	var definition := Commands.command(plan.get("tool"))
	if definition.is_empty() or not definition.surfaces.has("f2") or not Commands.valid_plan(definition, plan):
		_console_notice("Codex returned an invalid world command.")
		return
	if definition.get("scope") == "scene":
		if not _scene_ready() or requested_zone != zone_root.get_instance_id():
			_console_notice("The environment changed while Codex was planning. Ask again in the current scene.")
			return
		plan["zone"] = context.current
	if definition.has("catalog"):
		for entry in context.get(definition.catalog, []):
			if entry.name == plan.target:
				plan["revision"] = entry.revision
				break
	_dev.busy = true
	if definition.service == "development":
		if context.get(definition.availability, false) and _dev.client:
			await _development_commands.execute(definition, {"prompt": prompt, "reviewed": reviewed, "benchmark": benchmark_target})
		else:
			_console_notice("That Workbench command is unavailable in the current session.")
	else:
		await _call_world_tool(plan)
	_dev.busy = false
	_dev.refresh_chat()

func _activate_agent(id: String) -> Node3D:
	var avatar := agent_presence.activate(id, zone_id, player, not _is_workshop(zone_id))
	if id == AgentPresence.CODEX:
		scene_animations.attach_companion(avatar.animation_player())
	return avatar

func _call_world_tool(plan: Dictionary) -> Dictionary:
	var peer: String = plan.get("agent_peer", AgentPresence.CODEX)
	var command := plan.duplicate()
	command.erase("agent_peer")
	var result := await _execute_world_tool(command, peer)
	if peer == AgentPresence.CODEX and not plan.has("agent_peer"):
		_console_notice(str(result.message))
		if result.ok:
			_dev.speak(str(result.message))
	return result

func _execute_world_tool(plan: Dictionary, peer := AgentPresence.CODEX) -> Dictionary:
	var definition := Commands.command(plan.get("tool"))
	if definition.is_empty() or definition.get("internal", false) or not Commands.valid_plan(definition, plan):
		return {"ok": false, "message": "Invalid world command arguments."}
	plan = Commands.canonical_plan(plan)
	if definition.get("scope") == "scene" and not _scene_ready(plan.get("zone", "")):
		return {"ok": false, "message": "Return to the requested environment and wait for it to finish loading."}
	match definition.service:
		"scene":
			var placement := []
			if definition.get("placement", false) and not SceneCommands.options(plan).has("position"):
				placement = _scene_spawn_position()
			var result := SceneCommands.execute(world_tools, plan, placement)
			result["zone"] = zone_id
			return result
		"animation":
			if shifting or not scene_animations:
				return {"ok": false, "message": "Wait for the current environment to finish loading."}
			return scene_animations.execute(plan, world_tools)
		"world":
			if definition.handler == "_companion_mode":
				plan["agent_peer"] = peer
			return await _world_commands.execute(definition, plan)
	return {"ok": false, "message": "That command is unavailable in this world session."}

func _scene_ready(requested := "") -> bool:
	return is_instance_valid(zone_root) and world_tools != null and not shifting \
		and (requested.is_empty() or requested == zone_id)

func _scene_spawn_position() -> Array:
	var grid := _is_workshop(zone_id)
	var placement := ScenePlacement.pick(player, camera, world_tools.bounds, grid, not grid)
	return ScenePlacement.coordinates(placement.point)

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
	WorldArt.apply_environment(self, destination, atmosphere.values_for(destination))
	var spawn: Dictionary = WorldArt.spawn(destination)
	player.position = TerrainTools.above_surface(pieces, spawn.position)
	player.velocity = Vector3.ZERO
	player.rotation.y = spawn.yaw
	pitch = 0
	camera.rotation.x = 0
	agent_presence.arrive(zone_id, player, not _is_workshop(zone_id))
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
	var context := BuildContext.new(manifest)
	context.begin(destination)
	build_root = context.build_root
	build_interactables = context.build_interactables
	build_agent_labels = context.build_agent_labels
	if not context.build_art():
		context.build_fallback(destination)
	context.build_pieces(PieceDocument.path_for(destination, smoke_mode), grid_appearance)
	for anchor in manifest.anchors:
		if anchor.zone == destination:
			_add_anchor(anchor)
	# Every surface gets the construct effect built in now, so nothing is swapped later.
	WorldArt.make_constructible(build_root)
	return {"id": destination, "root": build_root, "interactables": build_interactables, "agent_labels": build_agent_labels,
		"piece_layer": context.piece_layer, "piece_document": context.piece_document, "displayed_pieces": context.displayed_pieces}

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
	grabber.cancel()
	if scene_animations:
		scene_animations.leave_workshop()
	if zone_id != built.id:
		_palette_host.clear_view()
	zone_id = built.id
	zone_root = built.root
	if world_tools != null:
		var linked_preview: String = world_tools.behavior_preview_id()
		if not linked_preview.is_empty():
			behavior_runtime.finish(linked_preview, false)
			world_tools.finish_behavior_preview(linked_preview, false)
		world_tools.attach(null)
		if not scene_tools.has("construct"):
			scene_tools["construct"] = world_tools
		if not scene_tools.has(zone_id):
			var prefix := "grid" if _is_workshop(zone_id) else "scene"
			var path := "" if smoke_mode else "user://%s-entities-%s.json" % [prefix, zone_id]
			scene_tools[zone_id] = WorldTools.new(path, prefab_library, behavior_runtime, ScenePlacement.bounds_for(zone_id))
		world_tools = scene_tools[zone_id]
		var prior: Array = built.piece_document.pieces
		world_tools.migrate_saved_props(built.piece_document)
		if prior != built.piece_document.pieces:
			BuildContext.refresh_pieces(built)
	pieces.attach(built.piece_layer, built.piece_document, zone_root.get_meta("scene_edit", false),
		Packages.piece_bounds(zone_id), built.displayed_pieces)
	_grid_scenery.attach(pieces, Packages.definition(zone_id).get("piece_appearance", {}))
	if world_tools != null:
		world_tools.attach(zone_root, pieces)
		if not world_tools.authored_geometry_changed.is_connected(_refresh_authored_lighting):
			world_tools.authored_geometry_changed.connect(_refresh_authored_lighting)
	if side != 0.0:
		WorldArt.set_side(zone_root, side)
	add_child(zone_root)
	scanner.attach(zone_root, zone_id, world_tools)
	_shoreline.attach(zone_root)
	_dev.refresh_actions()
	interactables = built.interactables
	agent_labels = built.agent_labels
	nearest = {}

func _refresh_piece_services() -> void:
	if is_instance_valid(zone_root) and zone_root.is_inside_tree():
		scanner.refresh_water(zone_root, zone_id)
		_shoreline.attach(zone_root)
		world_tools.refresh_piece_props(zone_root)

func _refresh_authored_lighting() -> void:
	if environment:
		WorldArt.rebuild_gi(self, zone_id)

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
	return Packages.definition(id).capabilities.get("workshop", false)

## Rewrite the world around the player: the new zone is built in place, then a sphere grows from
## the player's eyes. Behind its front the old zone unravels into blue lattice and pouring digits
## while the new one assembles out of them; sky, sun and atmosphere blend across. The player keeps
## walking throughout and stays where they are.
func _shift(destination: String, seconds := SHIFT_SECONDS) -> void:
	if shifting or destination == zone_id:
		return
	if terrain_brush.active() or (is_instance_valid(piece_panel) and piece_panel.is_visible_in_tree()):
		_close_panel()
	shifting = true
	var built := await _build_zone_async(destination)
	var from_state := WorldArt.zone_state(zone_id, atmosphere.values_for(zone_id))
	var to_state := WorldArt.zone_state(destination, atmosphere.values_for(destination))
	var old_root := zone_root
	for body in old_root.find_children("*", "CollisionObject3D", true, false):
		body.process_mode = Node.PROCESS_MODE_DISABLED
	WorldArt.set_side(old_root, -1.0)
	var us := Time.get_ticks_usec()
	_commit_zone(built, 1.0)
	_shift_log("commit", us)
	await _land_in(destination)
	agent_presence.arrive(zone_id, player, not _is_workshop(zone_id))
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
	WorldArt.apply_environment(self, destination, atmosphere.values_for(destination))
	_update_agent_labels()
	_announce_zone()
	shifting = false
	_dev.refresh_actions()
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
	player.position = TerrainTools.above_surface(pieces, spawn.position)
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

func _add_anchor(anchor: Dictionary) -> void:
	var at := Vector3(anchor.position[0],anchor.position[1],anchor.position[2])
	var item := anchor.duplicate()
	item.position = at
	build_interactables.append(item)
	if anchor.kind == "application":
		item["prop"] = Workstations.build(build_root, at, anchor)
	else:
		build_agent_labels[anchor.agent_id] = _label3d(anchor.label, at + Vector3(0,2.2,0), Color("d8e7ff"), 30)
		build_agent_labels[anchor.agent_id].set_meta("name", anchor.label)

func _physics_process(delta: float) -> void:
	if not player:
		return
	var direction := Vector3.ZERO
	var controls := (not overlay.visible or terrain_brush.looking()) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not smoke_mode \
		and not wrist.blocks_movement()
	if controls:
		var axes := Input.get_vector("left", "right", "forward", "back")
		direction = player.basis * Vector3(axes.x,0,axes.y)
	# Water: the zone reports the surface height under the player (simulated where it can be),
	# and the player's movement pushes wakes back into the simulation.
	water = WorldArt.water_tick(self, delta)
	var depth: float = water.level - player.position.y if water.has else -1.0
	var swimming := depth > 1.3
	_player_motor.step(player, delta, direction, water, controls)
	var scene_controls := controls and not overlay.visible and not wrist.is_open and _scene_ready()
	var gesture := grabber.tick(delta, player, camera, world_tools, player_avatar.hands, scene_controls)
	player_avatar.tick(player, delta, swimming, gesture)
	if wrist.is_open and wrist.current().get("id") == "scan" and _scene_ready():
		scanner.tick(delta, player, camera, wrist.scanner_pixel())
	else:
		scanner.clear()
	agent_presence.tick(player, delta)
	if player.position.y < -100:
		var spawn: Dictionary = WorldArt.spawn(zone_id)
		player.position = TerrainTools.above_surface(pieces, spawn.position)
		player.velocity = Vector3.ZERO
	underwater.visible = water.has and camera.global_position.y < water.level - 0.05
	_update_interaction_hint()
	if grid_palette_requested:
		grid_palette_requested = false
		_show_grid_palette()
	save_clock += delta
	if save_clock > 4:
		save_clock = 0
		_save()

func _update_interaction_hint() -> void:
	nearest = {}
	if overlay.visible or shifting or wrist.is_open:
		hint.text = ""
		return
	var grab_hint := grabber.hint()
	if not grab_hint.is_empty():
		hint.text = grab_hint
		return
	var agent := agent_presence.aimed(camera, player)
	if not agent.is_empty():
		nearest = {"kind": "companion", "agent_id": agent}
		hint.text = "E: Command agent"
		return
	var best := 3.0
	for item in interactables:
		var prop := item.get("prop") as Node3D
		if prop and not prop.is_visible_in_tree():
			continue
		var at: Vector3 = prop.global_position if prop else item.position
		var distance := player.global_position.distance_to(at)
		var eye_target := at + Vector3(0, 1.5, 0) - camera.global_position
		if distance < best and -camera.global_basis.z.dot(eye_target.normalized()) > 0.55:
			best = distance
			nearest = item
	hint.text = "E: " + str(nearest.label) if not nearest.is_empty() else wrist.idle_hint()

func _input(event: InputEvent) -> void:
	if smoke_mode or not is_instance_valid(overlay) or not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_F2: _dev.open_console()
		KEY_F4: _dev.open_workbench()
		_: return
	get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if smoke_mode: # automated smoke and capture runs must not react to stray input
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		var window := get_window()
		window.mode = Window.MODE_WINDOWED if window.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN
		get_viewport().set_input_as_handled()
		return
	if not overlay.visible and wrist.handle(event):
		get_viewport().set_input_as_handled()
		return
	if overlay.visible and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_close_panel()
		get_viewport().set_input_as_handled()
		return
	if not overlay.visible and not wrist.is_open and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and _scene_ready() and grabber.handle(event):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_B:
		if not overlay.visible and _scene_ready():
			_request_grid_palette()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if overlay.visible:
			_close_panel()
		get_viewport().set_input_as_handled()
	elif not overlay.visible and _zone_key(event) >= 0:
		_shift(str(manifest.zones[_zone_key(event)].id))
	elif event.is_action_pressed("interact") and not overlay.visible and not nearest.is_empty():
		player_avatar.interact()
		if nearest.kind == "companion":
			_dev.open_console(nearest.agent_id)
		elif nearest.kind == "application":
			_open_app(nearest.app_id, nearest.get("prop"))
		else:
			var status: Dictionary = agent_states.get(nearest.agent_id, {})
			_panel(nearest.label, str(status.get("summary", "No report yet.")))
			_button("Back", _close_panel)
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not overlay.visible:
		_look(event.relative)
	elif event is InputEventMouseButton and event.pressed and not overlay.visible:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _zone_key(event: InputEvent) -> int:
	for i in mini(3, manifest.zones.size()):
		if event.is_action_pressed("zone_%d" % (i + 1)):
			return i
	return -1

func _open_app(app_id: String, station: Node3D = null) -> void:
	_panel("", "")
	overlay.offset_left = 24
	overlay.offset_top = 24
	overlay.offset_right = -24
	overlay.offset_bottom = -24
	_dev.open_application(app_id, station)

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
		var restored := Vector3(clampf(float(at[0]),-150,150),clampf(float(at[1]),-20,60),clampf(float(at[2]),-150,150))
		player.position = TerrainTools.above_surface(pieces, restored)
	player.rotation.y = float(state.get("yaw",0))
	pitch = clampf(float(state.get("pitch",0)),-1.35,1.35)
	camera.rotation.x = pitch

func _setup_gateway() -> void:
	asset_client = AssetClient.new()
	add_child(asset_client)
	gateway_url = OS.get_environment("CONSTRUCT_GATEWAY_URL")
	gateway_token = OS.get_environment("CONSTRUCT_GATEWAY_TOKEN")
	asset_client.configure(gateway_url, gateway_token)
	material_client = MaterialClient.new()
	add_child(material_client)
	material_client.configure(asset_client)
	sky_client = SkyClient.new()
	add_child(sky_client)
	sky_client.configure(asset_client)
	grid_agent = GridAgentClient.new()
	add_child(grid_agent)
	grid_agent.configure(gateway_url, gateway_token)
	_dev.connect_gateway(gateway_url, gateway_token)
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
		# Let go of the mouse; a click back in picks it up again.
		if is_instance_valid(terrain_brush) and terrain_brush.active():
			terrain_brush.cancel()
		if is_instance_valid(wrist):
			wrist.typing = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _quit() -> void:
	_save()
	get_tree().quit()

func _run_diagnostic(script: String) -> void:
	load("res://scripts/diagnostics/" + script).run(self)
