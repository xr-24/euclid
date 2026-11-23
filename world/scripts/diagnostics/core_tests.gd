extends SceneTree
## Focused data-contract and ownership tests, without rendering or the user's normal save.
const Catalog = preload("res://scripts/zones/zone_catalog.gd")
const Packages = preload("res://scripts/zones/zone_packages.gd")
const Store = preload("res://scripts/persistence/world_state_store.gd")
const Context = preload("res://scripts/zones/zone_build_context.gd")
const Assets = preload("res://scripts/assets/asset_library.gd")
const WaterInteractions = preload("res://scripts/simulation/water_interactions.gd")
const WorldTools = preload("res://scripts/workshop/world_tools.gd")
const ScenePlacement = preload("res://scripts/workshop/scene_placement.gd")
const AuthoredProps = preload("res://scripts/zones/authored_props.gd")
const SceneCommands = preload("res://scripts/workshop/scene_commands.gd")
const MotionClip = preload("res://scripts/animation/motion_clip.gd")
const ActivityMotions = preload("res://scripts/agents/activity_motions.gd")
const BinaryAvatar = preload("res://scripts/agents/binary_avatar.gd")
const SceneAnimations = preload("res://scripts/animation/scene_animations.gd")
const ActivityView = preload("res://scripts/agents/activity_view.gd")
const SpeechPlayerScript = preload("res://scripts/agents/speech_player.gd")
const TweakLayer = preload("res://scripts/extensions/tweak_layer.gd")
const EnvironmentExport = preload("res://scripts/zones/environment_export.gd")
const Commands = preload("res://scripts/workshop/command_registry.gd")
const ToolRegistry = preload("res://scripts/workshop/tool_registry.gd")
const PrefabLibrary = preload("res://scripts/workshop/prefab_library.gd")
const BehaviorRuntime = preload("res://scripts/plugins/behavior_runtime.gd")
const ShorelineLook = preload("res://scripts/rendering/shoreline_look.gd")
const EnvironmentLibrary = preload("res://scripts/zones/environment_library.gd")
const TextEffects = preload("res://scripts/ui/code_fx.gd")
const CodeEditor = preload("res://scripts/ui/code_editor.gd")
const Highlighters = preload("res://scripts/ui/code_highlighters.gd")
const FindBar = preload("res://scripts/ui/find_bar.gd")
const QuickOpen = preload("res://scripts/ui/quick_open.gd")
const WorkbenchPanel = preload("res://scripts/ui/workbench_panel.gd")
const CodexConsole = preload("res://scripts/ui/codex_console.gd")
const DevelopmentSession = preload("res://scripts/persistence/development_session.gd")
const WorldDevelopment = preload("res://scripts/agents/world_development.gd")
const GridPaletteHost = preload("res://scripts/ui/grid_palette_host.gd")
const PropGrabber = preload("res://scripts/player/prop_grabber.gd")
const SceneScanner = preload("res://scripts/player/scene_scanner.gd")
var _failures := 0
var _checks := 0

class WristFixture extends RefCounted:
	var ran := []

	func status_line() -> String:
		return "TEST"

	func pages() -> Array:
		return [
			{"id": "one", "title": "ONE", "rows": [{"label": "A", "run": func() -> void: ran.append("a")},
				{"label": "B", "enabled": false, "why": "Not here."}]},
			{"id": "two", "title": "TWO", "rows": [{"label": "SEND", "input": true, "then": "one",
				"run": func(line: String) -> void: ran.append(line)},
				{"label": "QUIT", "confirm": "Again to quit.", "close": true, "run": func() -> void: ran.append("quit")}]},
		]

class ScannerWristFixture extends RefCounted:
	var scanner: SceneScanner

	func pages() -> Array:
		return [scanner.page()]

class PalmFixture extends RefCounted:
	func palm_position() -> Vector3:
		return Vector3(0.3, 1.9, -0.5)

class RefreshFixtureClient extends "res://scripts/agents/workbench_client.gd":
	signal finish_poll
	var revised := false

	func send(action: String, _arguments := {}) -> Dictionary:
		if action == "state":
			await finish_poll
		elif action == "revise":
			revised = true
		return {}

const HotLoad = preload("res://scripts/extensions/hot_load.gd")
const LiveExtensions = preload("res://scripts/extensions/live_extensions.gd")
const LiveKinds = preload("res://scripts/extensions/live_kinds.gd")
const TerminalView = preload("res://scripts/ui/terminal_view.gd")
const AgentsPanel = preload("res://scripts/ui/agents_panel.gd")
const WristComputer = preload("res://scripts/player/wrist_computer.gd")
const SpringFollow = preload("res://scripts/player/spring_follow.gd")
const TransformGizmo = preload("res://scripts/workshop/transform_gizmo.gd")
const Atmosphere = preload("res://scripts/rendering/atmosphere.gd")
const WorldArt = preload("res://scripts/world_art.gd")
const PieceTypes = preload("res://scripts/pieces/piece_types.gd")
const Surfaces = preload("res://scripts/pieces/finishes.gd")
const HousePiece = preload("res://scripts/pieces/house_piece.gd")
const HouseLayout = preload("res://scripts/pieces/house_layout.gd")
const BuildingOpening = preload("res://scripts/pieces/building_opening.gd")
const TerrainNode = preload("res://scripts/pieces/terrain_node.gd")
const PieceBuilder = preload("res://scripts/pieces/piece_builder.gd")
const PieceEditor = preload("res://scripts/pieces/piece_editor.gd")
const PieceDocument = preload("res://scripts/persistence/piece_document.gd")
const TerrainTools = preload("res://scripts/pieces/terrain_tools.gd")
const TerrainData = preload("res://scripts/pieces/terrain_data.gd")

class FixtureKind extends "res://scripts/extensions/live_kind.gd":
	var name := ""
	var key := ""
	var held := {}
	var reloads := 0
	var on_commit := false
	var warning := ""

	func _init(kind_name: String, candidate_key: String, reload_on_commit := false) -> void:
		name = kind_name
		key = candidate_key
		on_commit = reload_on_commit

	func id() -> String:
		return name

	func accepts(candidate: Dictionary) -> bool:
		return key.is_empty() or candidate.has(key)

	func preview(candidate: Dictionary) -> Dictionary:
		held[candidate.draft] = "active"
		return {"ok": true, "message": name}

	func status(draft: String) -> String:
		return held.get(draft, "")

	func finish(draft: String, _keep: bool) -> Dictionary:
		var was_live := held.has(draft)
		held.erase(draft)
		return {"live": was_live, "warning": warning}

	func reload_committed() -> void:
		reloads += 1

	func reloads_on_commit() -> bool:
		return on_commit

## A second, unrelated hot-swappable panel: a Label whose contract is one show_view method.
class LabelSwap extends "res://scripts/ui/panel_swap.gd":
	static var base_code: GDScript

	func _builtin() -> GDScript:
		return base_code

	func _label() -> String:
		return "test panel"

	func _base_type() -> StringName:
		return &"Label"

	func _valid_code(code: GDScript) -> bool:
		return code.has_script_method(&"show_view")

	func _initialize(widget: Control, _mount_context: Dictionary, view: Dictionary, _live: bool) -> Dictionary:
		return {"ok": widget.show_view(str(view.get("text", ""))) == true}

	func _capture_widget(widget: Control) -> Variant:
		return {"text": str(widget.get("shown")), "zone": _context.get("zone")}

class FocusFixtureClient extends "res://scripts/agents/workbench_client.gd":
	var focused := "unset"
	var answer := {}

	func send(action: String, arguments := {}) -> Dictionary:
		if action == "focus":
			focused = str(arguments.get("id", ""))
		return answer

class HotLoadRecorder extends RefCounted:
	var reports: Array = []

	func record(draft: String, version: String, report: Dictionary) -> void:
		reports.append([draft, version, report.get("status", ""), report.get("message", "")])

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("CORE_TEST_FAILED: " + label)

func _run() -> void:
	var manifest := Catalog.read("res://data/world.json")
	_check(not manifest.is_empty(), "real manifest conforms to the content contract")
	var changed: Dictionary = manifest.duplicate(true)
	changed.anchors[0].zone = "missing"
	_check(not Catalog.validate(changed).is_empty(), "reject dangling anchors")
	changed = manifest.duplicate(true)
	changed.zones.append(changed.zones[0].duplicate())
	_check(not Catalog.validate(changed).is_empty(), "reject duplicate zone identities")
	changed = manifest.duplicate(true)
	changed.anchors[0].position = ["command", 0, 0]
	_check(not Catalog.validate(changed).is_empty(), "reject nonnumeric positions")
	changed = manifest.duplicate(true)
	changed.anchors[0].kind = "shell.execute"
	_check(not Catalog.validate(changed).is_empty(), "reject executable anchor kinds")
	var path := "user://module-test-%d.json" % Time.get_ticks_usec()
	_check(Store.write(path,"villa",Vector3(4,0.1,2),0.6,0.2) == OK, "write state")
	var saved := Store.read(path,manifest.zones)
	var restored: Array = saved.get("position", [0,0,0])
	_check(saved.get("zone") == "villa" and Vector3(restored[0],restored[1],restored[2]).distance_to(Vector3(4,0.1,2)) < 0.00001, "round-trip coordinates")
	_check(Store.write(path,"beach",Vector3.ONE,0,0) == OK and Store.read(path,manifest.zones).zone == "beach", "atomically replace an existing save")
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string('{"schema_version":999,"zone":"villa"}')
	file.close()
	_check(Store.read(path,manifest.zones).is_empty(), "reject incompatible save schema")
	file = FileAccess.open(path,FileAccess.WRITE)
	file.store_string('{partial')
	file.close()
	_check(Store.read(path,manifest.zones).is_empty(), "reject interrupted JSON save")
	DirAccess.remove_absolute(path)
	var a := Context.new(manifest)
	var b := Context.new(manifest)
	var first := a.build("construct")
	var second := b.build("construct")
	_check(first.root != second.root and not first.root.is_inside_tree(), "detached per-build ownership")
	_check(first.interactables.size() == 1 and second.interactables.size() == 1, "build registries do not alias")
	first.root.free()
	_check(is_instance_valid(second.root), "disposing one build leaves the other intact")
	second.root.free()
	_check(Assets.pbr("marble_01",3.0) == Assets.pbr("marble_01",3.0), "identical material requests share a resource")
	_check(Assets.pbr("marble_01",3.0) != Assets.pbr("marble_01",1.0), "distinct texture scales remain distinct")
	var velocity := Vector3(0.8,0,-1.4)
	var sixty := WaterInteractions.wake(velocity,1.0/60.0,"pool")*60.0
	var one_twenty := WaterInteractions.wake(velocity,1.0/120.0,"pool")*120.0
	_check(sixty.distance_to(one_twenty) < 0.00001, "wake impulse per second is independent of physics tick rate")
	_check(sixty.length() < WaterInteractions.wake(velocity,1.0/60.0,"shore").length()*60.0, "pool disturbances are gentler than shore disturbances")
	_check(WaterInteractions.splash(-100.0,"pool") <= 0.025 and WaterInteractions.splash(1.0,"pool") == 0.0, "pool entry impulse is bounded and rising players do not splash")
	_check(WaterInteractions.wake(Vector3(100,0,100),1.0/60.0,"pool").length() <= 4.5*3.0/60.0+0.00001, "teleports and high velocity cannot inject unbounded wakes")
	_check(is_equal_approx(WaterInteractions.wake_height(velocity,1.0/60.0,"pool")*60.0,
		WaterInteractions.wake_height(velocity,1.0/120.0,"pool")*120.0), "bow ripple height injection is time-scaled")
	var fountain_60 := WaterInteractions.fountain(0.3,1.0/60.0,0.0)*60.0
	var fountain_120 := WaterInteractions.fountain(0.3,1.0/120.0,0.0)*120.0
	_check(fountain_60.distance_to(fountain_120) < 0.00001, "fountain forcing is a rate rather than a per-tick dose")
	var pool: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/generated/villa_pool.json"))
	var pool_bottom := FileAccess.get_file_as_bytes("res://assets/generated/villa_pool_bottom.bin").to_float32_array()
	var pool_state := FileAccess.get_file_as_bytes("res://assets/generated/villa_pool_state.bin").to_float32_array()
	var dry_margin := true
	for row in int(pool.n):
		for col in [0,1,2,int(pool.n)-3,int(pool.n)-2,int(pool.n)-1]:
			for index in [(row*int(pool.n)+col)*4,(col*int(pool.n)+row)*4]:
				dry_margin = dry_margin and pool_bottom[index] > 0.0 and is_equal_approx(pool_state[index],pool_bottom[index])
	_check(dry_margin,"pool mirror-boundary stencil lies entirely in dry padding")
	var ramp_i := int((28.0-float(pool.z0))/float(pool.dx))
	var ramp_j := int((0.0-float(pool.x0))/float(pool.dx))
	var ramp_y := pool_bottom[(ramp_j*int(pool.n)+ramp_i)*4]+float(pool.water_y)
	_check(ramp_y > -0.22 and ramp_y < -0.15,"pool bathymetry matches the sloped entry rather than a flat floor")
	_check_world_tools(path)
	_check_stretch(path + ".stretch")
	_check_scene_edits(path)
	_check_authored_dressing(path + ".dressing")
	_check_registered_props()
	await _check_grab_release()
	await _check_scanner_physics()
	_check_zone_packages(path + ".packages", manifest)
	_check_pieces(manifest)
	_check_piece_edits(manifest)
	_check_building()
	_check_pool_basin()
	_check_houses()
	_check_youtube_links()
	_check_prop_migration(path + ".piece-migration")
	_check_piece_upgrade()
	await _check_terrain()
	_check_data_entity_type()
	_check_workshop_actions(path)
	_check_prefabs(path)
	_check_live_behaviors(path)
	_check_linked_plugin(path)
	_check_shoreline_look()
	_check_text_tools()
	_check_development_session()
	await _check_development_refresh()
	await _check_workbench_drafts()
	await _check_live_extensions()
	await _check_hot_load_unload_all()
	_check_palette_reload()
	_check_panel_swap()
	_check_terminal_keys()
	_check_agents_panel()
	_check_agent_activity()
	_check_tweaks()
	_check_environment_export()
	_check_asset_refresh()
	await _check_agent_vision()
	_check_live_hud()
	_check_wrist_computer()
	_check_desktop_focus()
	_check_spring_follow()
	_check_atmosphere()
	_check(is_equal_approx(TransformGizmo._segment_distance(Vector2(5, 3), Vector2.ZERO, Vector2(10, 0)), 3.0)
		and is_equal_approx(TransformGizmo._segment_distance(Vector2(14, 0), Vector2.ZERO, Vector2(10, 0)), 4.0),
		"measure how far the pointer is from a gizmo handle on screen")
	var library := EnvironmentLibrary.new(path)
	var created := library.create("Signal Lab", manifest.zones)
	_check(created.ok and created.zone.template == "grid", "create a custom environment from the Grid template")
	_check(not library.create("signal lab", library.environments()).ok, "reject duplicate environment names")
	_check(EnvironmentLibrary.new(path).environments() == library.environments(), "reload custom environments with stable IDs")
	DirAccess.remove_absolute(path.get_base_dir().path_join(PieceDocument.filename(created.zone.id)))
	DirAccess.remove_absolute(path)
	print("CONSTRUCT_CORE_TESTS: %d checks, %d failures" % [_checks,_failures])
	if _failures == 0: print("CONSTRUCT_CORE_TESTS_OK")
	quit(0 if _failures == 0 else 1)

func _check_live_behaviors(path: String) -> void:
	var zone := Node3D.new()
	var observer := Node3D.new()
	root.add_child(zone)
	zone.add_child(observer)
	var runtime := BehaviorRuntime.new(observer)
	_check(runtime.available().size() == runtime.registry.list().size(), "all registered plugins compile and pass their sample probes")
	var library := PrefabLibrary.new("")
	var tools := WorldTools.new(path, library, runtime)
	tools.attach(zone)
	var spawned := tools.execute("spawn", {"type": "traffic_cone", "position": [1.0, 0.0, 0.0]})
	var entity := zone.get_node("WorkshopEntities").get_child(0)
	var animation := {"name": "Draft motion", "duration": 4.0, "interpolation": "linear", "keyframes": [
		{"time": 0.0, "offset": [0.0, 0.0, 0.0], "rotation": [0.0, 0.0, 0.0], "pose": [0.0, 0.0]},
		{"time": 4.0, "offset": [0.0, 0.0, 0.0], "rotation": [0.0, 0.0, 0.0], "pose": [0.0, 0.0]},
	]}
	tools.animation_player(spawned.id).set_clip(animation)
	var behavior := {"id": "proximity_pulse", "settings": {"radius": 3.5}}
	var configured := tools.execute("set_behavior", {"id": spawned.id, "behavior": behavior})
	_check(configured.ok and entity == zone.get_node("WorkshopEntities").get_child(0) and entity.has_node("BehaviorHost"),
		"attach a registered behavior without replacing the entity")
	_check(tools.animation_player(spawned.id).clip == animation, "behavior edits preserve a running animation preview")
	_check(not tools.execute("set_behavior", {"id": spawned.id, "behavior": {"id": "proximity_pulse", "settings": {"radius": 30.0}}}).ok,
		"reject a behavior setting outside its declared range")
	var original := runtime.evaluate(behavior, 0.25, 0.0)
	var source := "extends RefCounted\nconst API_VERSION := 1\nfunc sample(_time: float, _distance: float, _settings: Dictionary) -> float:\n\treturn 0.73\n"
	var candidate := {"plugin": "proximity_pulse", "draft": "test", "source": source, "digest": source.sha256_text()}
	var host := entity.get_node_or_null("BehaviorHost")
	_check(runtime.preview(candidate).ok and is_equal_approx(runtime.evaluate(behavior, 0.25, 0.0), 0.73)
		and host == entity.get_node_or_null("BehaviorHost"), "swap GDScript while keeping the behavior host")
	_check(runtime.finish("test", false) and is_equal_approx(runtime.evaluate(behavior, 0.25, 0.0), original), "discard restores the committed evaluator")
	var incompatible := source.replace("API_VERSION := 1", "API_VERSION := 2")
	candidate.source = incompatible
	candidate.digest = incompatible.sha256_text()
	_check(not runtime.preview(candidate).ok and is_equal_approx(runtime.evaluate(behavior, 0.25, 0.0), original), "reject incompatible code without replacing the active evaluator")
	var faulty := source.replace("return 0.73", "return 4.0 if _time > 1.0 else 0.73")
	candidate.source = faulty
	candidate.digest = faulty.sha256_text()
	var original_later := runtime.evaluate(behavior, 2.0, 0.0)
	_check(runtime.preview(candidate).ok and is_equal_approx(runtime.evaluate(behavior, 2.0, 0.0), original_later)
		and runtime.preview_status("test") == "failed", "invalid output after activation rolls back the live draft")
	runtime.finish("test", false)
	candidate.source = source
	candidate.digest = source.sha256_text()
	_check(runtime.preview(candidate).ok and runtime.finish("test", true) and is_equal_approx(runtime.evaluate(behavior, 0.25, 0.0), 0.73),
		"keep the accepted evaluator after the draft closes")
	var saved := tools.execute("save_prefab", {"id": spawned.id, "name": "Signal cone"})
	var copy := tools.execute("spawn_prefab", {"prefab_id": saved.get("prefab_id", ""), "position": [2.0, 0.0, 0.0]})
	_check(copy.ok and copy.entity.behavior == behavior, "prefabs retain behavior identity and settings")
	var reopened := WorldTools.new(path, library, runtime)
	var other := Node3D.new()
	reopened.attach(other)
	_check(reopened.execute("inspect", {"id": spawned.id}).entity.behavior == behavior, "reload saved behavior settings")
	other.free()
	_check(tools.execute("set_behavior", {"id": spawned.id, "behavior": null}).ok and not entity.has_node("BehaviorHost")
		and tools.execute("undo").ok and entity.has_node("BehaviorHost"), "removing and undoing behavior reuse the entity")
	zone.free()
	DirAccess.remove_absolute(path)

func _check_linked_plugin(path: String) -> void:
	var zone := Node3D.new()
	var observer := Node3D.new()
	root.add_child(zone)
	zone.add_child(observer)
	var runtime := BehaviorRuntime.new(observer)
	var library := PrefabLibrary.new("")
	var tools := WorldTools.new(path, library, runtime)
	tools.attach(zone)
	var plate := tools.execute("spawn", {"type": "pressure_plate", "position": [0.0, 0.0, 0.0]})
	var door := tools.execute("spawn", {"type": "sliding_door", "position": [0.0, 0.0, -2.0]})
	var plate_node := zone.get_node("WorkshopEntities/Entity_" + plate.id)
	var door_node := zone.get_node("WorkshopEntities/Entity_" + door.id)
	var leaf := door_node.get_node("DoorLeaf") as AnimatableBody3D
	var collider := leaf.get_child(0) as CollisionShape3D
	var controller := door_node.get_node("DoorActuator")
	var source := "extends RefCounted\nconst API_VERSION := 1\nfunc sample(_time: float, distance: float, settings: Dictionary) -> float:\n\treturn 1.0 if distance < float(settings.radius) else 0.0\n"
	var definition := {"id": "test_plate", "name": "Test plate", "entity_type": "pressure_plate", "output": "door_open", "settings": {
		"radius": {"label": "Radius", "minimum": 0.4, "maximum": 3.0, "default": 0.65},
		"speed": {"label": "Speed", "minimum": 0.2, "maximum": 8.0, "default": 2.0}}}
	var candidate := {"plugin": "test_plate", "draft": "test-package", "source": source, "digest": source.sha256_text(), "definition": definition}
	var binding := {"id": "test_plate", "settings": {}, "target": door.id}
	_check(runtime.preview(candidate).ok and not tools.preview_behavior("test-package", plate.id,
		{"id": "test_plate", "settings": {}, "target": plate.id}).ok and tools.preview_behavior("test-package", plate.id, binding).ok,
		"a new plugin package registers only in preview and requires a compatible target")
	plate_node.get_node("BehaviorHost")._process(0.0)
	controller._physics_process(2.0)
	_check(leaf.position.y > 2.4 and collider.global_position.y > 3.4, "a linked plate moves the existing door and its collision")
	var on_disk: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	_check(on_disk.entities.all(func(item: Dictionary) -> bool: return not item.has("behavior")), "a live test link never enters the save before commit")
	runtime.finish("test-package", false)
	tools.finish_behavior_preview("test-package", false)
	controller._physics_process(2.0)
	_check(not plate_node.has_node("BehaviorHost") and is_zero_approx(leaf.position.y) and runtime.registry.definition("test_plate").is_empty(),
		"discard unregisters the plugin, removes its request, and closes the door")
	_check(runtime.preview(candidate).ok and tools.preview_behavior("test-package", plate.id, binding).ok
		and runtime.finish("test-package", true) and tools.finish_behavior_preview("test-package", true).ok, "commit keeps the registered plugin and saves its link")
	var configured := tools.execute("inspect", {"id": plate.id})
	var saved := tools.execute("save_prefab", {"id": plate.id, "name": "Reusable plate"})
	var instance := tools.execute("spawn_prefab", {"prefab_id": saved.get("prefab_id", ""), "position": [2.0, 0.0, 0.0]})
	_check(configured.entity.behavior.target == door.id and instance.entity.behavior.id == "test_plate" and not instance.entity.behavior.has("target"),
		"prefabs reuse the plugin and settings without carrying a link to another space")
	var reopened := WorldTools.new(path, library, runtime)
	var other := Node3D.new()
	reopened.attach(other)
	_check(reopened.execute("inspect", {"id": plate.id}).entity.behavior.target == door.id, "reload the committed link by stable entity ID")
	other.free()
	zone.free()
	DirAccess.remove_absolute(path)

func _check_shoreline_look() -> void:
	var profile: Variant = JSON.parse_string(FileAccess.get_file_as_string(ShorelineLook.PATH))
	_check(ShorelineLook.valid_profile(profile), "the committed shoreline appearance is valid")
	var look := ShorelineLook.new()
	var beach := Node3D.new()
	var terrain := ShaderMaterial.new()
	terrain.shader = load("res://shaders/shore_terrain.gdshader")
	var surface := ShaderMaterial.new()
	surface.shader = load("res://shaders/shore_water.gdshader")
	surface.set_shader_parameter("wave_time", 12.0)
	beach.set_meta("water", {"sims": [{"profile": "shore", "terrain": terrain, "surfaces": [surface]}]})
	look.attach(beach)
	var candidate := {"draft": "test-shoreline", "shoreline": {"schema_version": 1, "foam_strength": 0.5, "foam_softness": 1.75}}
	_check(look.preview(candidate).ok and is_equal_approx(float(terrain.get_shader_parameter("foam_strength")), 0.5)
		and is_equal_approx(float(surface.get_shader_parameter("foam_softness")), 1.75)
		and is_equal_approx(float(surface.get_shader_parameter("wave_time")), 12.0), "preview updates surf and sand and preserves the wave clock")
	var invalid := candidate.duplicate(true)
	invalid.shoreline.foam_softness = INF
	_check(not look.preview(invalid).ok and is_equal_approx(float(surface.get_shader_parameter("foam_softness")), 1.75), "reject invalid profiles without touching the active appearance")
	_check(look.finish("test-shoreline", false) and is_equal_approx(float(terrain.get_shader_parameter("foam_strength")), float(profile.foam_strength)),
		"discard restores the committed shoreline appearance")
	_check(look.preview(candidate).ok and look.finish("test-shoreline", true) and look.status("test-shoreline").is_empty()
		and is_equal_approx(float(surface.get_shader_parameter("foam_softness")), 1.75), "commit retains the visible appearance")
	var pool := Node3D.new()
	pool.set_meta("water", {"sims": [{"profile": "pool", "terrain": terrain, "surfaces": [surface]}]})
	look.attach(pool)
	_check(not look.available() and not look.preview(candidate).ok, "the shore preview cannot attach to a pool")
	pool.free()
	beach.free()

func _check_prefabs(path: String) -> void:
	var library := PrefabLibrary.new(path)
	var first := WorldTools.new("", library)
	var source := Node3D.new()
	first.attach(source)
	var clip := {"name": "Hover", "duration": 4.0, "interpolation": "smooth", "keyframes": [
		{"time": 0.0, "offset": [0.0, 0.0, 0.0], "rotation": [0.0, 0.0, 0.0], "pose": [0.0, 0.0]},
		{"time": 2.0, "offset": [0.0, 0.2, 0.0], "rotation": [0.0, 0.0, 0.0], "pose": [0.0, 0.0]},
		{"time": 4.0, "offset": [0.0, 0.0, 0.0], "rotation": [0.0, 0.0, 0.0], "pose": [0.0, 0.0]},
	]}
	var entity := first.execute("spawn", {"type": "traffic_cone", "position": [2.0, 0.0, -2.0],
		"color": "ee8822", "scale": 2.0, "animation": clip})
	var entity_id: String = entity.get("id", "")
	var saved := first.execute("save_prefab", {"id": entity_id, "name": "Hover cone"})
	var prefab_id: String = saved.get("prefab_id", "")
	_check(saved.ok and not first.execute("save_prefab", {"id": entity_id, "name": "hover cone"}).ok,
		"save a named prefab and reject duplicate names")
	first.execute("delete", {"id": entity_id})
	source.free()
	var second := WorldTools.new("", PrefabLibrary.new(path))
	var destination := Node3D.new()
	second.attach(destination)
	var catalog := second.execute("list_prefabs")
	_check(catalog.get("prefabs", []) == [{"id": prefab_id, "name": "Hover cone", "type": "traffic_cone", "animated": true}],
		"reload the shared library independently of the original entity")
	var placed := second.execute("spawn_prefab", {"prefab_id": prefab_id, "position": [4.0, 0.0, 1.0]})
	var record: Dictionary = placed.get("entity", {})
	_check(placed.ok and record.id != entity_id and record.position == [4.0, 0.0, 1.0]
		and record.color == "ee8822" and record.scale == 2.0 and record.animation == clip,
		"place a new animated instance with the original properties and new position")
	_check(second.execute("undo").ok and second.execute("list").entities.is_empty()
		and second.execute("list_prefabs") == catalog, "undo placement without changing the library")
	_check(not second.execute("spawn_prefab", {"prefab_id": "unknown", "position": [0.0, 0.0, 0.0]}).ok,
		"unknown prefab IDs do not create entities")
	destination.free()
	DirAccess.remove_absolute(path)

func _check_workshop_actions(path: String) -> void:
	var zone := Node3D.new()
	root.add_child(zone)
	var workshop := WorldTools.new(path)
	workshop.attach(zone)
	var cone := workshop.execute("spawn", {"type": "traffic_cone", "position": [5.0, 0.0, 4.0]})
	var door := workshop.execute("spawn", {"type": "sliding_door", "position": [4.0, 0.0, 3.0]})
	var actuator := zone.get_node("WorkshopEntities/Entity_%s/DoorActuator" % door.id)
	actuator.set_opening_height(1.5)
	var targets := [{"id": cone.id, "changes": {"position": [0.0, 0.0, -2.0]}, "close_door": false},
		{"id": door.id, "changes": {"yaw": 25.0}, "close_door": true}]
	var definition := {"schema_version": 1, "id": "fixture_reset", "label": "Reset demo", "description": "Reset cone and door.",
		"zone": "fixture-space", "targets": targets}
	var registry := ToolRegistry.new()
	var draft := {"draft": "fixture", "workshop_tool": definition}
	_check(registry.preview(draft, "fixture-space", workshop).ok and registry.catalog("other-space").size() == 1,
		"preview registers the action only in its bound Grid space")
	var name := "grid_action_fixture_reset"
	var action: Dictionary = registry.catalog("fixture-space").filter(func(item: Dictionary) -> bool: return item.name == name)[0]
	_check(not registry.execute("fixture-space", name, "stale", workshop).ok and actuator.opening_height() == 1.5,
		"stale action revisions cannot mutate the Grid")
	var invalid := targets.duplicate(true)
	invalid[1].id = "a".repeat(32)
	var saved := FileAccess.get_file_as_string(path)
	_check(not workshop.run_action(invalid).ok and FileAccess.get_file_as_string(path) == saved,
		"a missing target rejects the whole reset before saving")
	_check(registry.execute("fixture-space", name, action.revision, workshop).ok, "run a registered workshop action")
	actuator = zone.get_node("WorkshopEntities/Entity_%s/DoorActuator" % door.id)
	_check(actuator.opening_height() == 0.0 and workshop.execute("inspect", {"id": cone.id}).entity.position == [0.0, 0.0, -2.0],
		"reset saves the cone placement and closes the door")
	_check(registry.finish("fixture", false) and not registry.execute("fixture-space", name, action.revision, workshop).ok,
		"discard withdraws the registered action")
	_check(workshop.execute("undo").ok and FileAccess.get_file_as_string(path) == saved
		and zone.get_node("WorkshopEntities/Entity_%s/DoorActuator" % door.id).opening_height() == 1.5,
		"one undo restores both saved records and door opening")
	zone.free()
	DirAccess.remove_absolute(path)

func _check_world_tools(path: String) -> void:
	var zone := Node3D.new()
	var tools := WorldTools.new(path)
	tools.attach(zone)
	var spawn := {"type": "traffic_cone", "position": [2.0, 0.0, -2.0]}
	var created := tools.execute("spawn", spawn)
	var id: String = created.get("id", "")
	_check(created.ok and zone.get_node("WorkshopEntities").get_child_count() == 1, "spawn returns the ID of a real entity")
	var edit := {"id": id, "changes": {"color": "40bbff", "scale": 2.0}}
	_check(tools.execute("edit", edit).ok, "edit an entity through the shared tool boundary")
	var rejected := tools.execute("edit", {"id": id, "changes": {"position": [INF, 0.0, 0.0]}})
	_check(not rejected.ok, "reject nonfinite entity coordinates")
	zone.free()
	zone = Node3D.new()
	var next_session := WorldTools.new(path)
	next_session.attach(zone)
	var restored: Dictionary = next_session.execute("inspect", {"id": id}).get("entity", {})
	_check(restored.get("color") == "40bbff" and restored.get("scale") == 2.0, "persist validated edits with their entity ID")
	_check(next_session.execute("delete", {"id": id}).ok, "delete a saved entity")
	_check(next_session.execute("undo").get("entity", {}) == restored, "undo restores the exact deleted record")
	zone.free()
	zone = Node3D.new()
	var unwritable := WorldTools.new(path.path_join("entities.json"))
	unwritable.attach(zone)
	_check(not unwritable.execute("spawn", spawn).ok and unwritable.execute("list").entities.is_empty(), "failed save does not apply an edit")
	zone.free()
	DirAccess.remove_absolute(path)

func _check_stretch(path: String) -> void:
	var zone := Node3D.new()
	var tools := WorldTools.new(path)
	tools.attach(zone)
	var id: String = tools.execute("spawn", {"type": "traffic_cone", "position": [0.0, 0.0, 0.0]}).get("id", "")
	var collider_width := func() -> float:
		var shape := tools.scene_node(id).find_children("*", "CollisionShape3D", false, false)[0] as CollisionShape3D
		var widest := 0.0
		for point in (shape.shape as ConvexPolygonShape3D).points:
			widest = maxf(widest, point.x)
		return widest
	var mesh_width := func() -> float:
		var mesh := tools.scene_node(id).find_children("*", "MeshInstance3D", false, false)[0] as MeshInstance3D
		return mesh.transform.basis.x.length() / mesh.transform.basis.y.length()
	var width: float = collider_width.call()
	var stretched := tools.execute("edit", {"id": id, "changes": {"stretch": [2.0, 1.0, 1.0]}})
	_check(stretched.ok and stretched.entity.get("stretch") == [2.0, 1.0, 1.0], "save a prop's stretch")
	_check(is_equal_approx(collider_width.call(), width * 2.0) and is_equal_approx(mesh_width.call(), 2.0),
		"stretch a prop's model and collider along its own X")
	_check(tools.execute("undo").ok and is_equal_approx(collider_width.call(), width) and is_equal_approx(mesh_width.call(), 1.0),
		"undo a stretch")
	_check(not tools.execute("edit", {"id": id, "changes": {"stretch": [9.0, 1.0, 1.0]}}).ok, "reject a stretch past five times")
	var door: String = tools.execute("spawn", {"type": "sliding_door", "position": [2.0, 0.0, 0.0]}).get("id", "")
	_check(not tools.execute("edit", {"id": door, "changes": {"stretch": [1.0, 2.0, 1.0]}}).ok, "keep doors unstretched")
	zone.free()
	DirAccess.remove_absolute(path)

func _check_scene_edits(path: String) -> void:
	var villa_root := Node3D.new()
	var beach_root := Node3D.new()
	var villa_path := path + ".villa"
	var beach_path := path + ".beach"
	var villa := WorldTools.new(villa_path, null, null, ScenePlacement.bounds_for("villa"))
	var beach := WorldTools.new(beach_path, null, null, ScenePlacement.bounds_for("beach"))
	villa.attach(villa_root)
	beach.attach(beach_root)
	var added := SceneCommands.execute(villa, {"tool": "spawn_prop", "target": "traffic_cone",
		"changes": {"position": [1.0, 0.15, -76.0], "name": "Library marker"}}, [])
	_check(added.ok and added.entity.name == "Library marker", "place named props beyond the Grid bounds")
	var id: String = added.get("id", "")
	var moved := SceneCommands.execute(villa, {"tool": "edit_entity", "target": id,
		"changes": {"position": [1.0, 0.15, -77.0], "yaw": 45.0, "collision": false}}, [])
	_check(moved.ok and moved.entity.id == id and moved.entity.yaw == 45.0 and not moved.entity.collision,
		"agent edits preserve scene prop identity and allow disabling collision")
	_check(not SceneCommands.execute(villa, {"tool": "edit_entity", "target": id,
		"changes": {"position": [121.0, 0.15, -77.0]}}, []).ok, "reject an edit outside the villa bounds")
	var duplicate := SceneCommands.execute(villa, {"tool": "duplicate_entity", "target": id}, [])
	_check(duplicate.ok and duplicate.id != id and duplicate.entity.name == "Library marker" and not duplicate.entity.collision,
		"duplicate keeps props independent and carries over the collision setting")
	var beach_prop := SceneCommands.execute(beach, {"tool": "spawn_prop", "target": "traffic_cone",
		"changes": {"position": [2.0, 0.0, -8.0], "name": "Shore marker"}}, [])
	_check(beach_prop.ok and not beach.execute("inspect", {"id": id}).ok, "prop identity is scoped to one scene")
	_check(SceneCommands.execute(villa, {"tool": "undo_scene"}, []).ok and not villa.execute("inspect", {"id": duplicate.id}).ok
		and beach.execute("inspect", {"id": beach_prop.id}).ok, "undo changes only the active scene")
	villa_root.free()
	beach_root.free()
	villa_root = Node3D.new()
	beach_root = Node3D.new()
	villa = WorldTools.new(villa_path, null, null, ScenePlacement.bounds_for("villa"))
	beach = WorldTools.new(beach_path, null, null, ScenePlacement.bounds_for("beach"))
	villa.attach(villa_root)
	beach.attach(beach_root)
	_check(villa.execute("inspect", {"id": id}).get("entity") == moved.get("entity")
		and beach.execute("inspect", {"id": beach_prop.id}).get("entity") == beach_prop.get("entity"),
		"reopen both scene saves with their exact IDs and edits")
	_check(villa.execute("undo").get("entity") == added.get("entity")
		and beach.execute("inspect", {"id": beach_prop.id}).ok, "undo a persisted edit only in its own scene")
	villa_root.free()
	beach_root.free()
	DirAccess.remove_absolute(villa_path)
	DirAccess.remove_absolute(beach_path)

func _check_authored_dressing(path: String) -> void:
	var zone := Node3D.new()
	var statue := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	statue.add_child(shape)
	var model := MeshInstance3D.new()
	model.mesh = BoxMesh.new()
	var finish := StandardMaterial3D.new()
	model.material_override = finish
	statue.add_child(model)
	zone.add_child(statue)
	var id := "a".repeat(32)
	AuthoredProps.register(zone, id, statue, "test", 0.0, {"label": "River statue", "position": [0, 0, 0]})
	var authored: Dictionary = zone.get_meta("authored_dressing")[id].record
	var legacy := {"id": "b".repeat(32), "type": "traffic_cone", "position": [0.0, 0.0, -2.0],
		"yaw": 0.0, "scale": 1.0, "color": "ff681d"}
	_check(Store.write_json(path, {"schema_version": 1, "entities": [legacy]}) == OK, "seed a legacy placed prop save")
	var tools := WorldTools.new(path)
	tools.attach(zone)
	var inspected: Dictionary = tools.execute("inspect", {"id": legacy.id}).get("entity", {})
	_check(inspected == legacy.merged({"collision": true}), "load legacy props with collision on")
	var changes := {"position": [3, 0, 0], "yaw": 90, "scale": 1.5, "name": "Moved statue"}
	_check(tools.execute("edit", {"id": id, "changes": changes}).ok and statue.position.x == 3.0
		and is_equal_approx(statue.rotation_degrees.y, 90.0) and statue.scale == Vector3.ONE * 1.5,
		"transform an authored prop and its collision together")
	_check(tools.execute("edit", {"id": id, "changes": {"color": "0088ff"}}).ok
		and model.material_override.albedo_color.is_equal_approx(Color("0088ff")) and finish.albedo_color == Color.WHITE,
		"tint an authored prop without changing its shared finish")
	_check(tools.execute("delete", {"id": id}).ok and not statue.visible and shape.disabled,
		"hide authored visuals and collision together")
	var state: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	_check(state.schema_version == 2 and state.entities == [legacy] and state.dressing[id].hidden
		and state.dressing[id].color == "0088ff" and state.undo.size() == 3 and authored.position == [0, 0, 0],
		"save overrides and history together without changing authored data")
	tools = WorldTools.new(path)
	tools.attach(zone)
	_check(tools.execute("inspect", {"id": id}).get("entity", {}).get("hidden", false) and shape.disabled,
		"reload a hidden authored prop")
	_check(tools.execute("undo").get("entity", {}).get("name") == "Moved statue" and statue.visible
		and not shape.disabled and statue.position.x == 3.0, "undo the hide after reload without discarding earlier edits")
	var restored := SceneCommands.execute(tools, {"tool": "restore_dressing", "target": id}, [])
	_check(restored.ok and not restored.entity.overridden and statue.position == Vector3.ZERO
		and statue.scale == Vector3.ONE and model.material_override == finish, "restore the authored defaults")
	_check(tools.execute("undo").ok and statue.position.x == 3.0, "undo restoring the authored defaults")
	state = JSON.parse_string(FileAccess.get_file_as_string(path))
	state.undo = [{"id": id, "previous": [], "dressing": {}}]
	_check(Store.write_json(path, state) == OK, "seed an invalid undo journal")
	tools = WorldTools.new(path)
	tools.attach(zone)
	_check(not tools.execute("list").get("can_undo", true) and tools.execute("inspect", {"id": legacy.id}).ok
		and statue.position.x == 3.0, "recover props and overrides even when history is invalid")
	_check(tools.execute("edit", {"id": id, "changes": {"collision": false}}).ok and shape.disabled,
		"disable an authored prop's original collision")
	tools = WorldTools.new(path)
	tools.attach(zone)
	var picker := statue.get_node_or_null("EntityPicker") as Area3D
	_check(not tools.execute("inspect", {"id": id}).entity.collision and shape.disabled
		and picker != null and not picker.get_child(0).disabled, "reload an authored collision edit and retain picking")
	_check(tools.execute("undo").ok and not shape.disabled and picker.get_child(0).disabled,
		"undo an authored collision edit without recreating the prop")
	zone.free()
	DirAccess.remove_absolute(path)

func _check_registered_props() -> void:
	var zone := Node3D.new()
	var rock := MeshInstance3D.new()
	rock.mesh = BoxMesh.new()
	rock.basis = Basis(Vector3.RIGHT, 0.4).scaled(Vector3.ONE * 1.25)
	zone.add_child(rock)
	var rock_basis := rock.basis
	var rock_id := AuthoredProps.stable_id("fixture", "rock")
	AuthoredProps.register(zone, rock_id, rock, "rock", 0.0)
	var picker := rock.get_child(0) as Area3D
	_check(picker != null and picker.collision_layer == AuthoredProps.PICK_LAYER
		and picker.get_meta("entity_id") == rock_id, "register visual props with an editor-only pick volume")

	var floater := RigidBody3D.new()
	var model := Node3D.new()
	model.position.y = -0.5
	var shape := CollisionShape3D.new()
	var template := BoxShape3D.new()
	shape.shape = template
	floater.add_child(model)
	floater.add_child(shape)
	floater.position = Vector3(2, 1, 0)
	zone.add_child(floater)
	var floater_id := AuthoredProps.stable_id("fixture", "floater")
	AuthoredProps.register(zone, floater_id, floater, "buoy", 0.0)
	var tools := WorldTools.new()
	tools.attach(zone)
	_check(tools.execute("edit", {"id": rock_id, "changes": {"yaw": 90.0, "scale": 2.0}}).ok
		and rock.basis.is_equal_approx(Basis(Vector3.UP, PI / 2.0) * rock_basis.scaled(Vector3.ONE * 2.0)),
		"rotate and scale a sloped prop relative to its authored basis")
	_check(tools.execute("restore_dressing", {"id": rock_id}).ok and rock.basis.is_equal_approx(rock_basis),
		"restore the exact authored basis and scale")
	_check(not tools.execute("inspect", {"id": rock_id}).entity.collision, "report a visual-only authored prop as non-solid")
	var solid := tools.execute("edit", {"id": rock_id, "changes": {"collision": true}})
	_check(solid.ok and picker.get_child(0).disabled and rock.find_children("*", "StaticBody3D", true, false).size() == 1,
		"give a visual-only authored prop a collider when enabled")
	_check(tools.execute("undo").ok and not picker.get_child(0).disabled, "restore a visual-only prop's selection area on undo")
	var unlocked := tools.commit_grab(rock_id, rock, {"locked": false})
	var released := tools.scene_node(rock_id) as RigidBody3D
	_check(unlocked.ok and released != null and not released.freeze and picker.get_child(0).disabled,
		"unlock an authored static prop with a rigid collider and disable its original picker")
	_check(tools.execute("undo").ok and released != null and released.freeze and not picker.get_child(0).disabled,
		"undo the unlock and restore the authored prop's original collision and lock")
	floater.position.x += 3.0
	var renamed := tools.execute("edit", {"id": floater_id, "changes": {"name": "Drifting buoy"}})
	_check(renamed.ok and renamed.entity.position[0] == 2.0 and renamed.entity.live_position[0] == 5.0,
		"keep the live physics pose separate from the saved release pose")
	_check(tools.execute("edit", {"id": floater_id, "changes": {"scale": 2.0}}).ok
		and floater.position.x == 5.0 and floater.scale == Vector3.ONE and model.position.y == -1.0
		and shape.shape.size == Vector3.ONE * 2.0 and template.size == Vector3.ONE,
		"resize a floating prop without scaling its rigid body or collision template")
	_check(tools.execute("delete", {"id": floater_id}).ok and floater.freeze and shape.disabled,
		"hide a floating prop and suspend its physics")
	_check(tools.execute("undo").ok and floater.visible and not floater.freeze and not shape.disabled
		and floater.position.x == 5.0 and shape.shape.size == Vector3.ONE * 2.0,
		"undo a hide without teleporting the floater or losing its size")
	_check(tools.execute("restore_dressing", {"id": floater_id}).ok and floater.position == Vector3(2, 1, 0)
		and shape.shape.size == Vector3.ONE, "restore the floater's original release pose and collision")
	zone.free()

func _check_grab_release() -> void:
	var zone := Node3D.new()
	root.add_child(zone)
	var player := CharacterBody3D.new()
	zone.add_child(player)
	var camera := Camera3D.new()
	player.add_child(camera)
	camera.position.y = 2.25
	var grabber := PropGrabber.new()
	zone.add_child(grabber)
	var hands := PalmFixture.new()
	var tools := WorldTools.new()
	tools.attach(zone)
	var result := tools.execute("spawn", {"type": "traffic_cone", "position": [0.0, 2.0, -4.0]})
	var body := tools.scene_node(result.id) as RigidBody3D
	body.gravity_scale = 0.0
	body.basis = Basis(Vector3.RIGHT, 0.16)
	await physics_frame
	await physics_frame
	_grab_button(grabber, MOUSE_BUTTON_LEFT)
	grabber.tick(0.0, player, camera, tools, hands, true)
	_check(body.freeze and not grabber._hold.is_empty(), "aimed prop freezes temporarily while grabbed")
	_grab_button(grabber, MOUSE_BUTTON_WHEEL_UP)
	_grab_button(grabber, MOUSE_BUTTON_LEFT, false)
	grabber.tick(0.0, player, camera, tools, hands, true)
	var expected := Basis(Vector3.UP, deg_to_rad(15.0)) * Basis(Vector3.RIGHT, 0.16)
	await physics_frame
	await physics_frame
	var record: Dictionary = tools.execute("inspect", {"id": result.id}).entity
	_check(not body.freeze and body.basis.is_equal_approx(expected) and is_equal_approx(record.yaw, 15.0)
		and not record.get("locked", true), "wheel and release in the same tick preserve live rotation and resume physics")
	_grab_button(grabber, MOUSE_BUTTON_LEFT)
	_grab_button(grabber, MOUSE_BUTTON_RIGHT)
	grabber.tick(0.0, player, camera, tools, hands, true)
	await physics_frame
	_check(body.freeze and tools.execute("inspect", {"id": result.id}).entity.locked,
		"right click while holding commits the lock")
	_grab_button(grabber, MOUSE_BUTTON_LEFT, false)
	grabber.tick(0.0, player, camera, tools, hands, true)
	_check(body.freeze, "the left release after locking leaves the lock in place")
	_grab_button(grabber, MOUSE_BUTTON_RIGHT)
	grabber.tick(0.0, player, camera, tools, hands, true)
	await physics_frame
	await physics_frame
	_check(not body.freeze and body.basis.is_equal_approx(expected)
		and not tools.execute("inspect", {"id": result.id}).entity.locked,
		"right click on the locked collider releases it without resetting the pose")
	_grab_button(grabber, MOUSE_BUTTON_LEFT)
	_grab_button(grabber, MOUSE_BUTTON_LEFT, false)
	grabber.tick(0.0, player, camera, tools, hands, true)
	_check(not body.freeze, "a grab with no scene edit still releases its temporary freeze")
	var release_height := body.position.y
	body.gravity_scale = 1.0
	for frame in 6:
		await physics_frame
	_check(body.position.y < release_height, "the released prop falls under gravity")
	body.free()
	var layer := Node3D.new()
	zone.add_child(layer)
	var editor := PieceEditor.new()
	editor.attach(layer, PieceDocument.new("", []), true, tools.bounds)
	tools.attach(zone, editor)
	editor.display_changed.connect(tools.refresh_piece_props.bind(zone))
	result = tools.execute("spawn", {"type": "traffic_cone", "position": [0.0, 2.0, -4.0]})
	body = tools.scene_node(result.id) as RigidBody3D
	var turned_off := tools.execute("edit", {"id": result.id, "changes": {"collision": false}})
	await physics_frame
	await physics_frame
	var center := camera.get_viewport().get_visible_rect().get_center()
	var aim := ScenePlacement.aim_at(player, camera, center, PropGrabber.REACH)
	_check(turned_off.ok and body.collision_layer == 0 and body.collision_mask == 0
		and body.freeze and aim.id == result.id, "collisionless props hold their pose and remain selectable")
	var floor := StaticBody3D.new()
	var ground := CollisionShape3D.new()
	var slab := BoxShape3D.new()
	slab.size = Vector3(10, 1, 10)
	ground.shape = slab
	ground.position = Vector3(0, 1.5, -4)
	floor.add_child(ground)
	zone.add_child(floor)
	_check(tools.commit_grab(result.id, body, {"position": [0.0, 1.9, -4.0], "locked": false}).ok,
		"place a collisionless prop partly inside the ground")
	for frame in 12:
		await physics_frame
	_check(body.position.is_equal_approx(Vector3(0, 1.9, -4)),
		"a collisionless prop placed in the ground stays at its saved position")
	floor.free()
	_check(tools.execute("undo").ok, "undo the embedded placement")
	_check(tools.execute("undo").ok and body.collision_layer != 0 and not body.freeze,
		"restore the spawned prop's collision and physics on undo")
	body.position.x = -5.0
	var authored := MeshInstance3D.new()
	authored.mesh = BoxMesh.new()
	authored.position = camera.global_position
	zone.add_child(authored)
	var authored_id := AuthoredProps.stable_id("fixture", "close prop")
	AuthoredProps.register(zone, authored_id, authored, "box", 0.0)
	var authored_tools := WorldTools.new()
	authored_tools.attach(zone)
	await physics_frame
	_grab_button(grabber, MOUSE_BUTTON_RIGHT)
	grabber.tick(0.0, player, camera, authored_tools, hands, true)
	var freed := authored_tools.scene_node(authored_id) as RigidBody3D
	_check(freed != null and not freed.freeze, "right click can unlock an authored prop from inside its pick volume")
	var fixture := MeshInstance3D.new()
	fixture.mesh = BoxMesh.new()
	fixture.position = Vector3(4, camera.position.y, -4)
	zone.add_child(fixture)
	var fixture_id := AuthoredProps.stable_id("fixture", "release prop")
	AuthoredProps.register(zone, fixture_id, fixture, "box", 0.0)
	authored_tools.attach(zone)
	await physics_frame
	await physics_frame
	camera.rotation.y = -PI / 4.0
	_grab_button(grabber, MOUSE_BUTTON_LEFT)
	grabber.tick(0.0, player, camera, authored_tools, hands, true)
	_check(grabber._hold.get("id") == fixture_id, "grab an authored prop away from the origin")
	camera.rotation.y -= 0.15
	grabber.tick(0.0, player, camera, authored_tools, hands, true)
	var drop := fixture.global_position
	_grab_button(grabber, MOUSE_BUTTON_LEFT, false)
	grabber.tick(0.0, player, camera, authored_tools, hands, true)
	var released := authored_tools.scene_node(fixture_id) as RigidBody3D
	for frame in 4:
		await physics_frame
	_check(released != null and not released.freeze and released.global_position.distance_to(drop) < 0.15
		and released.global_position.y < drop.y, "the new rigid body starts falling from the authored prop's release pose")
	zone.free()

func _check_scanner_physics() -> void:
	var zone := Node3D.new()
	root.add_child(zone)
	var player := CharacterBody3D.new()
	zone.add_child(player)
	var camera := Camera3D.new()
	player.add_child(camera)
	camera.position.y = 2.5
	var model := StaticBody3D.new()
	model.position = Vector3(0.0, 2.5, -5.0)
	zone.add_child(model)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	model.add_child(mesh)
	var collider := CollisionShape3D.new()
	collider.shape = BoxShape3D.new()
	model.add_child(collider)
	var id := AuthoredProps.stable_id("fixture", "scanner")
	AuthoredProps.register(zone, id, model, "box", 0.0)

	var tools := WorldTools.new()
	tools.attach(zone)
	var scanner := SceneScanner.new()
	zone.add_child(scanner)
	var wrist := WristComputer.new()
	zone.add_child(wrist)
	var fixture := ScannerWristFixture.new()
	fixture.scanner = scanner
	wrist.configure(fixture)
	scanner.setup("", wrist)
	scanner.attach(zone, "fixture", tools)
	wrist.raise_wrist("scan")
	await physics_frame
	await physics_frame
	var center := camera.get_viewport().get_visible_rect().get_center()
	scanner.tick(0.15, player, camera, center)
	wrist.refresh()
	var rows: Array = wrist.current().rows
	var labels := rows.map(func(row: Dictionary) -> String: return row.label)
	var physics := labels.find("Physics")
	var collision := labels.find("Collision")
	_check(physics >= 0 and collision >= 0, "the Scan screen offers separate Physics and Collision controls")
	if physics < 0 or collision < 0:
		zone.free()
		return
	_check(rows[physics].value == "Off" and rows[collision].value == "On", "scan displays an authored solid prop as fixed")
	var confirm := InputEventMouseButton.new()
	confirm.button_index = MOUSE_BUTTON_LEFT
	confirm.pressed = true
	wrist.move(collision)
	wrist.handle(confirm)
	wrist.refresh()
	await physics_frame
	await physics_frame
	scanner.tick(0.15, player, camera, center)
	wrist.refresh()
	_check(collider.disabled and wrist.current().rows[collision].value == "Off", "M1 disables collision and the scanner keeps its target")
	wrist.move(physics - collision)
	wrist.handle(confirm)
	wrist.refresh()
	var body := tools.scene_node(id) as RigidBody3D
	var at := Vector3(0.0, 2.5, -5.0)
	for frame in 4:
		await physics_frame
	var record: Dictionary = tools.execute("inspect", {"id": id}).entity
	_check(body != null and body.freeze and body.global_position.is_equal_approx(at) and not record.collision
		and not record.locked and wrist.current().rows[physics].value == "Paused",
		"the Physics toggle stores the setting while collisionless motion is paused")
	wrist.handle(confirm)
	wrist.refresh()
	var paused := body.position
	for frame in 4:
		await physics_frame
	_check(body.freeze and body.position.is_equal_approx(paused) and wrist.current().rows[physics].value == "Off",
		"turning Physics off holds the live pose")
	wrist.move(collision - physics)
	wrist.handle(confirm)
	wrist.refresh()
	_check(body.freeze and wrist.current().rows[collision].value == "On", "turning collision on keeps the frozen prop in place")
	_check(tools.execute("undo").ok and body.freeze and not tools.execute("inspect", {"id": id}).entity.collision,
		"undo can restore collision separately from physics")
	_check(tools.set_prop_physics(id, true).ok and body.freeze, "a collisionless prop can be armed for physics")
	_check(tools.execute("edit", {"id": id, "changes": {"collision": true}}).ok and not body.freeze,
		"restoring collision resumes the saved physics state")
	zone.free()

func _grab_button(grabber: PropGrabber, button: MouseButton, pressed := true) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	grabber.handle(event)

func _check_zone_packages(path: String, manifest: Dictionary) -> void:
	for id in Packages.ids():
		_check(Packages.valid(Packages.definition(id)), "validate the installed " + id + " package")
	var invalid := Packages.definition("villa").duplicate(true)
	invalid.builder = "res://scripts/../untrusted.gd"
	_check(not Packages.valid(invalid), "reject a builder outside the reviewed zone source directory")
	invalid = Packages.definition("villa").duplicate(true)
	invalid.benchmark_views = ["missing"]
	_check(not Packages.valid(invalid), "reject a missing named benchmark view")
	var library := EnvironmentLibrary.new(path)
	var created := library.create("Garden annex", manifest.zones, "villa")
	_check(created.ok and created.zone.package == "villa" and created.zone.id != "villa",
		"create a distinct environment using a villa package")
	Packages.register_zone(created.zone)
	_check(Packages.bounds(created.zone.id) == Packages.bounds("villa")
		and Packages.spawn(created.zone.id) == Packages.spawn("villa")
		and not Packages.definition(created.zone.id).capabilities.workshop,
		"inherit the package's bounds, spawn, and capabilities without a zone-name branch")
	_check(EnvironmentLibrary.new(path).environments() == library.environments(),
		"restore an environment's template reference after restart")
	_check(not library.create("Missing template", manifest.zones, "missing").ok,
		"reject a template outside the installed environment catalog")
	DirAccess.remove_absolute(path.get_base_dir().path_join(PieceDocument.filename(created.zone.id)))
	DirAccess.remove_absolute(path)

func _check_pieces(manifest: Dictionary) -> void:
	var ground := {"id": "ground", "type": "shape", "shape": "plane", "size": [40.0, 0.1, 40.0],
		"material": {"texture": "dry_ground_01", "texture_size": 3.0}}
	var lamp := {"id": "lamp", "type": "light", "kind": "spot", "position": [0.0, 4.0, 0.0], "rotation": [-90.0, 0.0, 0.0]}
	var crate := {"id": "crate", "type": "shape", "shape": "box", "size": [1.0, 1.0, 1.0], "material": {"color": "8a6a4a"}}
	var stack := {"id": "stack", "type": "group", "position": [3.0, 0.0, 0.0], "rotation": [0.0, 90.0, 0.0], "children": [crate]}
	var pieces := [ground, lamp, stack]
	_check(PieceTypes.valid_tree(pieces), "accept a document of registered pieces")
	var broken := [{"id": "x", "type": "shape", "shape": "box"}, {"id": "x", "type": "unknown"},
		{"id": "x", "type": "light", "kind": "spot", "energy": 1000.0}, {"id": "x", "type": "group", "script": "res://evil.gd"},
		{"id": "Bad Id", "type": "group"}, {"id": "x", "type": "shape", "shape": "box", "size": [1, 1, 1], "material": {"shine": 1}}]
	for record: Dictionary in broken:
		_check(not PieceTypes.valid_tree([record]), "reject an invalid piece " + JSON.stringify(record))
	_check(not PieceTypes.valid_tree([crate, crate.duplicate()]), "reject duplicate piece ids")
	var root := Node3D.new()
	_check(PieceBuilder.build(root, pieces), "build a document of pieces")
	var group: Node3D = root.get_node_or_null("Piece_stack")
	var box: Node = group.get_node_or_null("Piece_crate") if group != null else null
	_check(box is StaticBody3D and (box as Node3D).position == Vector3.ZERO and group.position == Vector3(3, 0, 0),
		"nest child pieces under their group")
	_check(root.get_node_or_null("Piece_lamp") is SpotLight3D, "make lights from light pieces")
	_check(root.get_node("Piece_ground").get_meta("piece_type") == "shape", "tag built nodes with their piece type")
	root.free()
	var context := Context.new(manifest)
	var built := context.build("open_ground")
	_check((built.root as Node3D).get_node_or_null(PieceBuilder.LAYER + "/Piece_ground") is StaticBody3D,
		"build the Open Ground package from pieces alone")
	(built.root as Node3D).free()

func _check_prop_migration(path: String) -> void:
	var old_path := path + ".old"
	var zone := Node3D.new()
	var legacy := WorldTools.new(old_path)
	legacy.attach(zone)
	var placed := legacy.execute("spawn", {"type": "traffic_cone", "position": [1, 0, 2]})
	_check(placed.ok, "legacy prop fixture saves")
	var id: String = placed.id
	var before := FileAccess.get_file_as_string(old_path)
	var document := PieceDocument.new(path, [])
	legacy.migrate_saved_props(document)
	_check(document.pieces.size() == 1 and document.pieces[0].id == id and document.history.size() == 1,
		"migrate legacy prop IDs and undo into the piece document")
	_check(FileAccess.get_file_as_string(old_path) == before, "preserve the old prop save during migration")
	var reopened := PieceDocument.new(path, [])
	var retry := WorldTools.new(old_path)
	retry.migrate_saved_props(reopened)
	_check(reopened.pieces.size() == 1, "retrying prop migration does not duplicate props")
	_check(reopened.save([], []), "save a removal of a migrated prop")
	var removed := PieceDocument.new(path, [])
	WorldTools.new(old_path).migrate_saved_props(removed)
	_check(removed.pieces.is_empty(), "deleted migrated props stay deleted after restart")
	zone.free()
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(old_path)

func _check_piece_edits(manifest: Dictionary) -> void:
	var directory := "user://piece-test-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(directory)
	var path := directory.path_join(PieceDocument.filename("open_ground"))
	var defaults: Array = Packages.definition("open_ground").pieces
	var layer := Node3D.new()
	root.add_child(layer)
	var document := PieceDocument.new(path, defaults)
	PieceBuilder.build(layer, document.pieces)
	var editor := PieceEditor.new()
	editor.attach(layer, document, true, Packages.bounds("open_ground"))
	var ground := editor.node_for("ground")
	var added := editor.execute({"tool": "add_piece", "target": "group", "piece_values": {"name": "Landing",
		"position": [3.0, 1.0, 0.0]}})
	_check(added.ok and ground == editor.node_for("ground"), "add a piece without rebuilding existing scenery")
	var child := editor.execute({"tool": "add_piece", "target": "shape", "parent": added.id,
		"piece_values": {"material": {"color": "e88033", "roughness": 0.5}}})
	var shape := editor.node_for(child.id)
	_check(child.ok and shape.get_parent() == editor.node_for(added.id) and shape.position == Vector3.ZERO,
		"add a child relative to its selected parent and apply registered defaults")
	_check(not editor.execute({"tool": "edit_piece", "target": child.id, "piece_values": {"energy": 4}}).ok
		and not editor.execute({"tool": "edit_piece", "target": child.id, "piece_values": {"position": [900, 0, 0]}}).ok,
		"reject a field belonging to another type and positions outside the active environment")
	_check(editor.execute({"tool": "edit_piece", "target": child.id,
		"piece_values": {"position": [0, 1, 0], "rotation": [0, 30, 0]}}).ok and shape == editor.node_for(child.id)
		and shape.global_position == Vector3(3, 2, 0), "apply a transform to the live node in its parent's frame")
	_check(editor.execute({"tool": "edit_piece", "target": child.id,
		"piece_values": {"material": {"metallic": 0.8}}}).ok and ground == editor.node_for("ground")
		and editor.record(child.id).material == {"color": "e88033", "roughness": 0.5, "metallic": 0.8},
		"merge material fields without touching other pieces")
	_check(editor.execute({"tool": "remove_piece", "target": added.id}).ok and editor.node_for(child.id) == null,
		"remove a piece subtree")
	var reloaded := PieceDocument.new(path, [])
	editor.attach(layer, reloaded, true, Packages.bounds("open_ground"))
	_check(reloaded.pieces.size() == 1 and editor.execute({"tool": "undo_piece"}).ok
		and editor.node_for(child.id).global_position == Vector3(3, 2, 0),
		"undo the removal after loading the piece document and its journal")
	var library_path := directory.path_join("environments.json")
	var library := EnvironmentLibrary.new(library_path)
	var created := library.create("Piece editor copy", manifest.zones, "open_ground")
	var copy_path := directory.path_join(PieceDocument.filename(created.zone.id))
	var copy := PieceDocument.new(copy_path, [])
	_check(created.ok and copy.pieces == reloaded.pieces and copy.history.is_empty(),
		"save a custom environment's independent copy of the template's current pieces")
	_check(defaults.size() == 1 and defaults[0].id == "ground", "leave installed package defaults immutable")
	var blocked := PieceDocument.new(directory.path_join("missing/document.json"), defaults)
	editor.attach(layer, blocked, true, Packages.bounds("open_ground"))
	_check(not editor.execute({"tool": "add_piece", "target": "light", "piece_values": {"position": [0, 4, 0]}}).ok
		and blocked.pieces == defaults and blocked.history.is_empty(),
		"an unsuccessful save leaves the document and undo journal unchanged")
	layer.free()
	for file in [path, library_path, copy_path]:
		DirAccess.remove_absolute(file)
	DirAccess.remove_absolute(directory)

func _check_building() -> void:
	var layer := Node3D.new()
	root.add_child(layer)
	var editor := PieceEditor.new()
	var area := AABB(Vector3(-10, -10, -10), Vector3(20, 20, 20))
	editor.attach(layer, PieceDocument.new("", []), true, area)
	var built := editor.execute({"tool": "add_piece", "target": "building", "piece_values": {"position": [0, 0, 0]}})
	_check(built.ok, "place a building from the registered plan")
	if built.ok:
		var shell := editor.node_for(built.id)
		var opened := editor.execute({"tool": "edit_piece", "target": built.id,
			"piece_values": {"openings": {"front": {"open": true}}}})
		var plan := editor.record(built.id)
		_check(opened.ok and editor.node_for(built.id) == shell and plan.openings.front.kind == "door"
			and plan.openings.right.motion == "slide", "edit one opening without replacing other fields or rebuilding the shell")
		var invalid := editor.execute({"tool": "edit_piece", "target": built.id,
			"piece_values": {"openings": {"right": {"width": 2.4}}}})
		_check(not invalid.ok and editor.record(built.id) == plan, "reject a sliding window with insufficient travel")
		_check(editor.execute({"tool": "undo_piece"}).ok and not editor.record(built.id).openings.front.get("open", false),
			"undo the building edit")
	var rooms := editor.execute({"tool": "add_piece", "target": "building", "piece_values": {"position": [0, 0, 0],
		"footprint": [10, 10], "partitions": [
			{"start": [-5, 0], "end": [5, 0], "openings": [
				{"kind": "door", "offset": -2.5}, {"kind": "door", "offset": 2.5}]},
			{"start": [0, 0], "end": [0, 5]}],
		"wall_openings": {"front": [{"kind": "window", "offset": -2.5}, {"kind": "window", "offset": 2.5}],
			"left": [{"kind": "archway", "width": 2.0}]}}})
	var house := editor.node_for(rooms.get("id", ""))
	_check(rooms.ok and house and house.has_node("Partition1/Opening2/Leaf") and house.has_node("Partition2")
		and house.has_node("Front/Opening2/Leaf"), "build two rooms, a shared living area and multiple openings on one wall")
	var blocked := editor.execute({"tool": "edit_piece", "target": rooms.get("id", ""), "piece_values": {
		"wall_openings": {"front": [{"kind": "door", "offset": 0.0}, {"kind": "window", "offset": 0.4}]}}})
	_check(not blocked.ok, "reject overlapping wall openings")

	layer.free()

func _check_houses() -> void:
	var record := {"id": "home", "type": "house", "style": "modern", "bedrooms": 2, "bathrooms": 1}
	_check(PieceTypes.valid(record), "accept a house described only by its programme")
	var rooms := HouseLayout.rooms(record)
	var kinds := rooms.map(func(room: Dictionary) -> String: return room.kind)
	_check(kinds.count("bedroom") == 2 and kinds.count("bathroom") == 1 and kinds.has("living") and kinds.has("kitchen"),
		"plan two bedrooms, a bath, a living room and a kitchen")
	var walls := HouseLayout.walls(record, rooms, HousePiece.style_for(record))
	var entrances := 0
	var doors := 0
	var windows := 0
	for wall: Dictionary in walls:
		for opening: Dictionary in wall.openings:
			entrances += 1 if opening.get("entrance", false) else 0
			doors += 1 if opening.kind == "door" else 0
			windows += 1 if opening.kind == "window" else 0
	_check(entrances == 1 and doors >= 4 and windows >= 5, "give the house one entrance, a door to each private room and windows")
	for room: Dictionary in rooms:
		if room.kind in ["bedroom", "bathroom"]:
			var reached := walls.any(func(wall: Dictionary) -> bool:
				return not wall.exterior and wall.openings.any(func(opening: Dictionary) -> bool:
					var at := float(opening.at)
					var r: Rect2 = room.rect
					return int(wall.axis) == 0 and absf(float(wall.line) - r.position.y) < 0.02 and at > r.position.x and at < r.end.x))
			_check(reached, "reach %s through a door from the hall" % room.name)
	var overlap := {"id": "bad", "type": "house", "rooms": [{"kind": "living", "rect": [0, 0, 5, 5]}, {"kind": "bedroom", "rect": [4, 0, 8, 4]}]}
	_check(not PieceTypes.valid(overlap), "reject overlapping rooms")
	var apart := {"id": "bad", "type": "house", "rooms": [{"kind": "living", "rect": [0, 0, 5, 5]}, {"kind": "bedroom", "rect": [9, 0, 12, 4]}]}
	_check(not PieceTypes.valid(apart), "reject rooms that do not touch")
	var shaped := {"id": "ell", "type": "house", "style": "farmhouse", "rooms": [{"kind": "living", "rect": [-4, -3, 2, 2]},
		{"kind": "kitchen", "rect": [2, -3, 6, 2]}, {"kind": "bedroom", "rect": [-4, 2, 0, 6]}, {"kind": "bathroom", "rect": [0, 2, 2.5, 6]}]}
	_check(PieceTypes.valid(shaped) and not HouseLayout.is_rectangle(HouseLayout.rooms(shaped)), "accept an L-shaped plan")
	var home := HousePiece.build(record)
	var openings := home.find_children("*", "", true, false).filter(func(node: Node) -> bool: return node is BuildingOpening)
	var labels := openings.map(func(opening: Node) -> String: return opening.interaction_label())
	_check(home.has_node("Walls") and home.has_node("Roof") and home.has_node("Ceilings") and home.has_node("Furniture"),
		"build walls, roof, ceilings and furniture")
	_check(labels.has("Open door") and labels.has("Open window") and labels.has(""), "make doors and casements open and picture windows fixed")
	_check(home.find_children("*", "SpotLight3D", true, false).size() >= rooms.size(), "light every room")
	home.free()
	var gable := HousePiece.build(shaped)
	_check(gable.get_node("Roof").get_child_count() > 0, "fall back to a flat roof over an L-shaped plan")
	gable.free()
	_check(HousePiece.terrain_cut(record).is_empty(), "leave the ground alone without a pool")
	var pooled := record.duplicate()
	pooled["pool"] = true
	var cut := HousePiece.terrain_cut(pooled)
	var footprint := HouseLayout.bounds(rooms)
	_check(not cut.is_empty() and not footprint.has_point(cut.center), "dig the pool outside the house")
	var pool_home := HousePiece.build(pooled)
	_check(pool_home.find_children("*", "", true, false).any(func(node: Node) -> bool: return node.has_meta("water_piece")),
		"fill the house's pool with registered water")
	pool_home.free()
	_check_house_finishes(record)
	_check_house_storeys()

func _check_house_finishes(record: Dictionary) -> void:
	var named := []
	for style: Dictionary in HousePiece.styles().values():
		for rule: Dictionary in style.get("walls", []):
			named.append(str(rule.get("finish", "paint_white")))
		named.append(str(style.get("backsplash", "tile_white")))
	_check(not named.is_empty() and named.all(func(id: String) -> bool: return Surfaces.has(id)),
		"name only wall finishes that exist in the house styles")
	var dressed := record.duplicate(true)
	dressed.merge({"walls": [{"finish": "paint_sage"}, {"room": "bathroom", "finish": "tile_marble", "height": 1.2},
		{"room": "bedroom", "side": "feature", "finish": "wood_panels"}], "backsplash": "brick_whitewashed",
		"materials": {"exterior": "cladding_panels"}, "furnishings": {"fridge": "none", "bathtub": "bathtub_clawfoot"}}, true)
	_check(PieceTypes.valid(dressed), "accept wall rules, a splashback, finish names and furnishing picks on a house")
	var bad := record.duplicate(true)
	bad["walls"] = [{"room": "bathroom", "side": "ceiling", "finish": "tile_white"}]
	_check(not PieceTypes.valid(bad), "reject a wall rule for a side that is not a wall")
	var style := HousePiece.style_for(dressed)
	var rules := HousePiece.wall_rules(dressed, style)
	_check(str(style.materials.exterior.get("texture", "")) == "exterior_wall_cladding_03"
		and rules.size() == style.get("walls", []).size() + 3 and rules.back().finish == "wood_panels",
		"resolve a finish name for the exterior and put the record's wall rules after the style's")
	var plain := record.duplicate(true)
	plain["furnish"] = false
	plain["walls"] = [{"finish": "paint_white"}]
	plain["style"] = "modern"
	var tiled := plain.duplicate(true)
	tiled["walls"] = [{"finish": "paint_white"}, {"room": "bathroom", "finish": "tile_white"}, {"room": "living", "side": "feature", "finish": "brick_red"}]
	var plain_home := HousePiece.build(plain)
	var tiled_home := HousePiece.build(tiled)
	_check(_vertices(tiled_home.get_node("Walls")) > _vertices(plain_home.get_node("Walls")) + 100,
		"cover the bathroom and the living room's feature wall in their own finishes")
	plain_home.free()
	tiled_home.free()

func _check_house_storeys() -> void:
	var record := {"id": "tall", "type": "house", "style": "farmhouse", "storeys": 2, "bedrooms": 3, "bathrooms": 2}
	_check(PieceTypes.valid(record), "accept a two-storey house described by its programme")
	var rooms := HouseLayout.rooms(record)
	var floors := HouseLayout.levels(rooms)
	var upstairs: Array = floors[1] if floors.size() > 1 else []
	_check(floors.size() == 2 and upstairs.filter(func(room: Dictionary) -> bool: return room.kind == "bedroom").size() == 3
		and upstairs.any(func(room: Dictionary) -> bool: return not HouseLayout.stairwell(floors[0], room).is_empty()),
		"put the bedrooms upstairs around a stairwell over the ground floor's")
	var home := HousePiece.build(record)
	_check(home.has_node("Walls/Level1") and home.find_children("Stair", "", true, false).size() == 1
		and home.find_children("Guard", "", true, false).size() >= 1, "build both storeys, a stair and a guarded landing")
	_check(HousePiece.plan(record).storeys == 2 and HousePiece.level_height(record, 1) > HousePiece.level_height(record, 0) + 2.5,
		"report two storeys a full storey apart")
	home.free()
	var floating := {"id": "bad", "type": "house", "rooms": [{"kind": "living", "rect": [0, 0, 6, 5]}, {"kind": "stairs", "rect": [6, 0, 8.4, 3.6]},
		{"kind": "stairs", "level": 1, "rect": [6, 0, 8.4, 3.6]}, {"kind": "bedroom", "level": 1, "rect": [8.4, 0, 12, 3.6]}]}
	_check(not PieceTypes.valid(floating), "reject an upstairs room with nothing under it")
	var stairless := {"id": "bad", "type": "house", "rooms": [{"kind": "living", "rect": [0, 0, 6, 5]},
		{"kind": "bedroom", "level": 1, "rect": [0, 0, 6, 5]}]}
	_check(not PieceTypes.valid(stairless), "reject an upstairs without a stair up to it")
	var dressed := {"id": "dressed", "type": "house", "floors": [{"room": "bedroom", "finish": "carpet_sisal"}],
		"pool": true, "pool_finish": {"basin": "pool_mosaic_aqua", "waterline": "pool_tile_talavera"}}
	_check(PieceTypes.valid(dressed), "accept floor rules and pool finishes")
	var bedroom := {"kind": "bedroom", "name": "Bedroom 1"}
	_check(HousePiece.floor_finish(dressed, HousePiece.style_for(dressed), bedroom).get("texture") == "hessian_230"
		and HousePiece.pool_finishes(dressed).waterline.get("texture") == "pool_tile_talavera",
		"resolve a room's floor and the pool's tiles from named finishes")
	var tinted := Surfaces.spec({"finish": "tile_white", "color": "dfe8ee"})
	_check(tinted.get("texture") == "long_white_tiles" and tinted.get("color") == "dfe8ee",
		"start any piece material from a named finish and override its tint")

func _vertices(node: Node) -> int:
	var count := 0
	for found: Node in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := (found as MeshInstance3D).mesh
		if mesh:
			count += mesh.get_faces().size()
	return count

func _check_pool_basin() -> void:
	var zone := Node3D.new()
	root.add_child(zone)
	var layer := Node3D.new()
	zone.add_child(layer)
	var editor := PieceEditor.new()
	var document := PieceDocument.new("", [])
	editor.attach(layer, document, true, AABB(Vector3(-40, -24, -40), Vector3(80, 48, 80)))
	var ground := editor.execute({"tool": "add_piece", "target": "terrain", "piece_values": {
		"position": [0, 0, 0], "terrain_size": [32, 32]}})
	var terrain := editor.node_for(ground.get("id", "")) as TerrainNode
	_check(ground.ok and terrain, "place ground for an excavated basin")
	if terrain:
		var pool := editor.execute({"tool": "add_piece", "target": "pool_basin", "parent": ground.id,
			"piece_values": {"position": [0, 0, 0], "rotation": [0, 25, 0]}})
		_check(pool.ok and terrain.surface_height(Vector2.ZERO) < -1.45 and terrain.data.height_at(128, 128) == 0.0
			and zone.get_meta("water_surfaces").size() == 1, "add excavation, basin and water in one undoable piece")
		_check(editor.execute({"tool": "undo_piece"}).ok and terrain.surface_height(Vector2.ZERO) == 0.0
			and zone.get_meta("water_surfaces").is_empty(), "restore the original terrain when the pool is undone")
		var invalid := editor.execute({"tool": "add_piece", "target": "pool_basin", "parent": ground.id,
			"piece_values": {"position": [15, 0, 0]}})
		_check(not invalid.ok, "reject a pool that extends beyond its parent terrain")
	var raised := editor.execute({"tool": "add_piece", "target": "pool_basin", "piece_values": {"position": [0, 0, 0]}})
	_check(raised.ok and zone.get_meta("water_surfaces")[0].surface.position.y > 1.0, "place a raised pool without terrain")
	zone.free()

func _check_youtube_links() -> void:
	const Links = preload("res://scripts/assets/youtube_link.gd")
	_check(Links.parse("https://youtu.be/M7lc1UVf-VE?si=token").get("video") == "M7lc1UVf-VE"
		and Links.parse("https://www.youtube.com/playlist?list=PLBCF2DAC6FFB574DE").get("playlist") == "PLBCF2DAC6FFB574DE"
		and Links.parse("https://www.youtube.com/watch?v=M7lc1UVf-VE&list=PL123&index=2").get("index") == 2,
		"accept YouTube videos, playlist links and indexed watch links")
	_check(Links.parse("https://youtube.com.example.com/watch?v=M7lc1UVf-VE").is_empty()
		and Links.parse("https://www.youtube.com/watch?v=invalid").is_empty(), "reject look-alike hosts and malformed video IDs")

func _check_piece_upgrade() -> void:
	var path := "user://piece-upgrade-%d.json" % Time.get_ticks_usec()
	var package := Packages.definition("construct")
	var defaults: Array = package.pieces
	var revision: int = int(package.piece_revision)
	var local := {"id": "saved-lamp", "type": "light", "kind": "omni", "position": [4, 2, 3]}
	_check(Store.write_json(path, {"schema_version": 1, "pieces": [local], "undo": [{"pieces": []}]}) == OK,
		"seed a piece save from before the Grid's conversion")
	var doc := PieceDocument.new(path, defaults, revision)
	var saved_lamp := doc.pieces.any(func(record: Dictionary) -> bool:
		return record.id == local.id and record.kind == local.kind and Packages.vector(record.position) == Vector3(4, 2, 3))
	_check(doc.error.is_empty() and doc.pieces.size() == defaults.size() + 1 and saved_lamp
		and doc.history.size() == 1 and doc.history[0].pieces == defaults,
		"add the structural defaults to old saves and to each undo snapshot")
	var edited := doc.pieces.filter(func(record: Dictionary) -> bool: return record.id != "backdrop")
	_check(doc.save(edited, doc.history), "save an intentional removal after the Grid upgrade")
	var reopened := PieceDocument.new(path, defaults, revision)
	_check(reopened.pieces == edited and not reopened.pieces.any(func(record: Dictionary) -> bool: return record.id == "backdrop"),
		"respect a deliberate removal on later loads")
	DirAccess.remove_absolute(path)

func _check_terrain() -> void:
	var package := Packages.definition("open_ground")
	var path := "user://terrain-test-%d.json" % Time.get_ticks_usec()
	var old: Dictionary = package.piece_replacements[0]
	_check(Store.write_json(path, {"schema_version": 1, "pieces": [old], "undo": [{"pieces": [old]}]}) == OK,
		"seed an existing flat-ground save")
	var doc := PieceDocument.new(path, package.pieces, 1, package.piece_replacements)
	_check(doc.pieces[0].type == "terrain" and doc.history[0].pieces[0].type == "terrain",
		"upgrade untouched starter ground and its history to terrain")
	var layer := Node3D.new()
	root.add_child(layer)
	_check(PieceBuilder.build(layer, doc.pieces), "build a terrain piece in the scene")
	var editor := PieceEditor.new()
	editor.attach(layer, doc, true, Packages.piece_bounds("open_ground"))
	var raised := TerrainTools.execute(editor, {"tool": "terrain_brush", "target": "ground",
		"brush": "raise", "radius": 10.0, "strength": 2.0, "points": [[0, 0, 0]]})
	var sample := {"tool": "inspect_terrain", "target": "ground", "points": [[0, 0, 0]]}
	_check(raised.ok and TerrainTools.execute(editor, sample).heights == [2.0], "raise a terrain sample through the shared command")
	await physics_frame
	await physics_frame
	var ray := PhysicsRayQueryParameters3D.create(Vector3(0.05, 6, 0.05), Vector3(0.05, -3, 0.05))
	var hit := layer.get_world_3d().direct_space_state.intersect_ray(ray)
	_check(not hit.is_empty() and hit.collider == editor.node_for("ground") and hit.position.y > 1.9,
		"collision follows the sculpted height")
	var painted := TerrainTools.execute(editor, {"tool": "terrain_brush", "target": "ground",
		"brush": "paint", "paint": "rock", "radius": 10.0, "strength": 1.0, "points": [[0, 0, 0]]})
	var saved := PieceDocument.new(path, package.pieces, 1)
	var samples := TerrainData.new()
	_check(painted.ok and samples.decode(saved.pieces[0].terrain_surface)
		and samples.weights(TerrainData.COUNT / 2).b == 1.0 and TerrainTools.execute(editor, sample).heights == [2.0],
		"paint and height survive saving independently")
	editor.attach(layer, saved, true, Packages.piece_bounds("open_ground"))
	_check(editor.execute({"tool": "undo_piece"}).ok and editor.execute({"tool": "undo_piece"}).ok
		and TerrainTools.execute(editor, sample).heights == [0.0],
		"undo paint and sculpt as separate strokes after reload")
	_check(not TerrainTools.execute(editor, {"tool": "terrain_brush", "target": "ground",
		"brush": "raise", "points": [[350, 0, 0]]}).ok, "reject strokes beyond the terrain footprint")
	var lowered := TerrainTools.execute(editor, {"tool": "terrain_brush", "target": "ground",
		"brush": "lower", "strength": 2.0, "points": [[0, 0, 0]]})
	var player := CharacterBody3D.new()
	layer.add_child(player)
	player.position = Vector3(0.0, -1.95, 0.0)
	_check(lowered.ok and TerrainTools.undo(editor, player).ok and player.position.y >= 0.0,
		"undoing a depression keeps a player standing inside it above the restored ground")
	var brush := TerrainData.new()
	var area := Vector2(600, 600)
	brush.dab(Vector2.ZERO, area, "raise", 8.0, 4.0, 0, 0.0)
	brush.dab(Vector2.ZERO, area, "smooth", 8.0, 1.0, 0, 0.0)
	_check(brush.surface_at(Vector2.ZERO, area) < 4.0 and brush.surface_at(Vector2.ZERO, area) > 0.0,
		"smooth lowers a local peak towards its neighbours")
	brush.dab(Vector2.ZERO, area, "flatten", 8.0, 1.0, 0, 1.5)
	_check(is_equal_approx(brush.surface_at(Vector2.ZERO, area), 1.5), "flatten matches the stroke's sampled level")
	var center := TerrainData.CELLS / 2 * TerrainData.SIDE + TerrainData.CELLS / 2
	brush.dab(Vector2.ZERO, area, "paint", 8.0, 1.0, 2, 0.0)
	var legacy := TerrainData.new()
	_check(legacy.decode(brush.encode()) and legacy.weight(center, 2) == 255,
		"older built-in material weights still decode")
	brush.dab(Vector2.ZERO, area, "paint", 8.0, 0.5, 3, 0.0)
	var expanded := TerrainData.new()
	_check(expanded.decode(brush.encode(), brush.encode_imported(), 1) and expanded.weight(center, 2) >= 127
		and expanded.weight(center, 3) >= 127 and is_equal_approx(expanded.surface_at(Vector2.ZERO, area), 1.5),
		"an imported layer blends with saved paint and preserves height")
	layer.free()
	DirAccess.remove_absolute(path)

func _check_data_entity_type() -> void:
	var commands = preload("res://scripts/workshop/command_registry.gd")
	var types := commands.entity_types()
	types["fixture_box"] = {"factory": "box", "label": "Fixture box", "color": "24c4bc",
		"size": [2.0, 0.4, 0.8], "built_in": true}
	var zone := Node3D.new()
	var tools := WorldTools.new()
	tools.attach(zone)
	var spawned := SceneCommands.execute(tools, {"tool": "spawn_prop", "target": "fixture_box"}, [0.0, 0.0, 0.0])
	_check(spawned.ok and spawned.entity.color == "24c4bc" and "fixture_box" in commands.built_in_props(),
		"declare a built-in entity type through schema data")
	var entity: Node3D = tools._nodes[spawned.id]
	var collision := entity.get_child(0) as CollisionShape3D
	_check(collision != null and collision.shape.size == Vector3(2.0, 0.4, 0.8),
		"build the schema's primitive dimensions and collider through the normal spawn command")
	zone.set_meta("scene_edit", false)
	_check(not tools.execute("delete", {"id": spawned.id}).ok and tools.execute("inspect", {"id": spawned.id}).ok,
		"enforce package edit capabilities at the shared command boundary")
	zone.free()
	types.erase("fixture_box")

func _check_text_tools() -> void:
	var typed := TextEffects.change_between(PackedStringArray(["var a = 1"]), PackedStringArray(["var ab = 1"]))
	_check(typed.get("line") == 0 and typed.get("column") == 5 and typed.get("added") == "b" and typed.get("removed") == "",
		"text effects locate a typed character")
	var removed := TextEffects.change_between(PackedStringArray(["one", "two", "three"]), PackedStringArray(["one", "three"]))
	_check(removed.get("line") == 0 and removed.get("column") == 3 and removed.get("removed") == "\ntwo" and removed.get("added") == "",
		"text effects keep a removed line below its anchor")
	var pasted := TextEffects.change_between(PackedStringArray(["a"]), PackedStringArray(["a", "b", "c"]))
	_check(pasted.get("line") == 0 and pasted.get("column") == 1 and pasted.get("added") == "\nb\nc", "text effects follow a multi-line paste")
	_check(TextEffects.change_between(PackedStringArray(["same"]), PackedStringArray(["same"])).is_empty(), "unchanged text has no effects")
	var apart := TextEffects.changes_between(PackedStringArray(["a", "keep 1", "keep 2", "keep 3", "b"]),
		PackedStringArray(["ax", "keep 1", "keep 2", "keep 3", "by"]))
	_check(apart.size() == 2 and apart[0].line == 0 and apart[0].added == "x" and apart[1].line == 4 and apart[1].added == "y",
		"separate edits animate separately and leave the lines between them alone")
	var dropped := TextEffects.changes_between(PackedStringArray(["a", "gone", "keep", "b", "also gone", "c"]),
		PackedStringArray(["a", "keep", "b", "c"]))
	_check(dropped.size() == 2 and dropped[0].removed == "\ngone" and dropped[1].removed == "\nalso gone" and dropped[1].old_line == 3,
		"removed lines keep their original positions")
	_check(TextEffects.visual_column("\tx", 1, 4) == 4 and TextEffects.visual_column("abcd\te", 5, 4) == 8,
		"tab stops expand to monospace cells")
	var lines := PackedStringArray(["\tfunc a():", "\t\tpass", ""])
	var commented := CodeEditor.toggle_comment_lines(lines, "#")
	_check(commented[0] == "\t# func a():" and commented[1] == "\t# \tpass" and commented[2] == "", "comment at the shallowest indent")
	_check(CodeEditor.toggle_comment_lines(commented, "#") == lines, "uncomment restores the original lines")
	_check(Highlighters.language_for("world/shaders/ui_glow.gdshader") == "shader" and Highlighters.language_for("a.json") == "json",
		"choose highlighting from the file extension")
	var colors := Highlighters.for_language("gdscript") as CodeHighlighter
	_check(colors != null and colors.get_keyword_color("func") == Highlighters.KEYWORD and colors.has_keyword_color("Node3D"),
		"GDScript highlighting knows keywords and engine types")
	_check(FindBar.count_matches("Aa aa AA", "aa", false) == 3 and FindBar.count_matches("Aa aa AA", "aa", true) == 1,
		"find counts case-insensitive and exact matches")
	var path := "world/scripts/ui/workbench_panel.gd"
	_check(QuickOpen.score("wbpanel", path) > 0 and QuickOpen.score("zzz", path) < 0, "quick open matches path subsequences")
	_check(QuickOpen.score("tools", "world/scripts/workshop/world_tools.gd") > QuickOpen.score("tools", "world/tools/scripts/zone.gd"),
		"quick open prefers matches in the file name")
	var found := WorkbenchPanel.error_locations("SCRIPT ERROR: Parse Error\n   at: GDScript::reload (res://scripts/ui/code_fx.gd:42)")
	_check(found.size() == 1 and found[0].path == "world/scripts/ui/code_fx.gd" and found[0].line == 41, "check logs link back to source lines")
	var editor := CodeEditor.new()
	root.add_child(editor)
	editor.use_language_of("probe.gd")
	editor.load_text("func a():\n\tpass")
	editor.toggle_comment()
	_check(editor.get_line(0) == "# func a():" and "pass" in editor.document_words(), "editor comments the caret line and indexes words")
	editor.undo()
	_check(editor.get_line(0) == "func a():", "comment toggles are undoable")
	editor.free()
	var console := CodexConsole.new()
	root.add_child(console)
	console.setup(PackedStringArray(["> hello", "world"]), false, false)
	console.update_display(PackedStringArray(["> hello", "world", "more output"]), false)
	_check(console._history.visible_characters >= 0, "new console output types in")
	var voices := [{"id": "voice_a", "name": "Voice A"}, {"id": "voice_b", "name": "Voice B"}]
	console.update_voice(true, voices, "voice_b", "", false, false)
	_check(console._voice_row.visible and console._voice_picker.selected == 2 and not console._voice_preview.disabled,
		"the voice picker selects the saved voice by ID")
	console.update_voice(true, [], "", "Authorize in the browser", true, false)
	_check(console._voice_picker.disabled and console._voice_retry.text == "Connect" and console._voice_status_row.visible,
		"the voice picker guides disconnected players to browser approval")
	var agents := {"local-codex": "Codex", "local-claude": "Claude", "muse": "Cloud · muse"}
	var recipients: Array[String] = ["local-codex", "local-claude", "muse"]
	var tabs: Array[String] = []
	console.set_conversations(agents, recipients, tabs, "")
	var menu := console._new_chat.get_popup()
	_check(console._tabs.tab_count == 0 and menu.item_count == 3 and menu.get_item_metadata(2) == "muse",
		"the directory is available for new conversations without pre-opening tabs")
	tabs.append("local-codex")
	console.set_conversations(agents, recipients, tabs, "local-codex")
	_check(console._tabs.tab_count == 1 and menu.item_count == 2 and menu.get_item_metadata(0) == "local-claude",
		"the new chat menu excludes open conversations")
	console._entry.text = "Unsent Codex request"
	tabs.append("local-claude")
	console.set_conversations(agents, recipients, tabs, "local-claude")
	_check(console._entry.text.is_empty() and console._tabs.current_tab == 1 and not console._cli.visible,
		"switch to Claude without carrying the Codex composer or CLI shortcut")
	console.set_conversations(agents, recipients, tabs, "local-codex")
	_check(console._entry.text == "Unsent Codex request", "restore the selected conversation's unsent text")
	console.free()

func _check_development_session() -> void:
	var path := "user://development-test-%d.json" % Time.get_ticks_usec()
	var session := DevelopmentSession.new(path)
	var lines := PackedStringArray(["> Fix the failing check", "The draft failed checks."])
	var prompts := PackedStringArray(["Fix the failing check"])
	session.save_console(lines, prompts)
	session.save_view("world/scripts/world.gd", "Checks")
	session.save_chat_tabs(["local-codex", "local-claude", "muse"], "muse")
	session.save_voice("fixture_voice")
	var reopened := DevelopmentSession.new(path)
	_check(reopened.lines == lines and reopened.prompts == prompts, "reopen console scrollback and prompt recall")
	_check(reopened.file == "world/scripts/world.gd" and reopened.tab == "Checks", "reopen selected Workbench file and tab")
	_check(reopened.voice_id == "fixture_voice", "remember the selected ElevenLabs voice")
	_check(reopened.chat_tabs == ["local-codex", "local-claude", "muse"] and reopened.chat_peer == "muse",
		"reopen the same Agent Chat conversations and selection")
	Store.write_json(path, {"schema_version": 1, "chat_tabs": ["local-codex", "local-claude"], "chat_peer": "local-claude"})
	var legacy := DevelopmentSession.new(path)
	_check(legacy.chat_tabs.is_empty() and legacy.legacy_chat_tabs.size() == 2 and legacy.legacy_chat_peer == "local-claude",
		"legacy tabs wait for inbox history before appearing")
	legacy.save_chat_tabs(["muse"], "muse")
	_check(DevelopmentSession.new(path).legacy_chat_tabs == legacy.legacy_chat_tabs, "keep migration candidates while offline")
	legacy.save_chat_tabs(["muse"], "muse", true)
	_check(DevelopmentSession.new(path).legacy_chat_tabs.is_empty(), "remove legacy candidates after migration")
	Store.write_json(path, {"schema_version": 3, "lines": Array(lines)})
	_check(DevelopmentSession.new(path).lines.is_empty(), "ignore unsupported development session saves")
	DirAccess.remove_absolute(path)

func _check_development_refresh() -> void:
	var development := WorldDevelopment.new()
	var client := RefreshFixtureClient.new()
	development.add_child(client)
	development._client = client
	development.refresh()
	client.finish_poll.emit.call_deferred()
	var result := await development.revise("Fix the failing check", {"id": "fixture", "version": "reviewed"})
	_check(client.revised and not result.has("error"), "an F2 revision waits for the draft refresh")
	await process_frame
	development.free()

func _check_live_extensions() -> void:
	var live := LiveExtensions.new()
	var palette := FixtureKind.new("grid_palette", "grid_palette")
	var tools := FixtureKind.new("workshop_tool", "workshop_tool", true)
	var behavior := FixtureKind.new("behavior", "")
	behavior.warning = "Released the test link."
	for kind in [palette, tools, behavior]:
		live.register(kind)
	_check(live.kind_ids() == PackedStringArray(["grid_palette", "workshop_tool", "behavior"]), "list live extension kinds in order")
	var routed: Array[String] = []
	for candidate in [{"draft": "p", "grid_palette": {}}, {"draft": "t", "workshop_tool": {}}, {"draft": "b", "plugin": "pulse"}]:
		routed.append(str((await live.preview(candidate)).message))
	_check(routed == ["grid_palette", "workshop_tool", "behavior"], "route each live draft to the first kind that accepts it")
	_check(live.status("t") == "active" and live.status("b") == "active" and live.status("missing").is_empty(),
		"report a live draft's status from the kind that holds it")
	var kept: Dictionary = live.finish("t", true)
	_check(kept.live and kept.warning.is_empty() and tools.held.is_empty() and live.status("t").is_empty(),
		"finish a live draft in the kind that holds it")
	var released: Dictionary = live.finish("b", false)
	_check(released.live and released.warning == "Released the test link.", "pass the catch-all kind's warning through")
	_check(not live.finish("never", false).live, "finish a draft no kind holds")
	live.reload_committed(true)
	_check(tools.reloads == 1 and palette.reloads == 0 and behavior.reloads == 0, "reload only commit-time kinds after a commit")
	live.reload_committed()
	_check(tools.reloads == 2 and palette.reloads == 1 and behavior.reloads == 1, "reload every kind after a revert")
	_check(not (await LiveExtensions.new().preview({"draft": "x"})).ok, "refuse a draft no kind accepts")
	# The world's live kinds and the gateway's shared kind table name the same kinds in the same order.
	var table: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/extension_kinds.json"))
	var listed := PackedStringArray()
	if table is Dictionary:
		for kind in table.get("kinds", []):
			if kind is Dictionary and kind.get("live", false):
				listed.append(str(kind.get("id", "")))
	var world_kinds := LiveExtensions.new()
	LiveKinds.register_all(world_kinds, {}, {})
	_check(not listed.is_empty() and world_kinds.kind_ids() == listed, "register the live kinds the shared extension table lists")

func _check_hot_load_unload_all() -> void:
	var empty_result: Dictionary = await HotLoad.unload_all()
	_check(empty_result.get("ok", false) and empty_result.get("unloaded", -1) == 0,
		"HotLoad.unload_all returns unloaded == 0 when empty")
	var fixture_path := "res://data/hot_unload_all_fixture.json"
	var prior_reporter := HotLoad.reporter
	var recorder := HotLoadRecorder.new()
	HotLoad.reporter = Callable(recorder, "record")
	HotLoad._base[fixture_path] = "{}"
	HotLoad._layers[fixture_path] = [["draft-a", "{\"a\":1}"], ["draft-b", "{\"b\":2}"]]
	HotLoad._held["draft-a"] = {"version": "v1", "files": {fixture_path: "{\"a\":1}"},
		"tier": "in_place", "status": "active", "error": "", "label": "A", "owner": "codex", "at": 1.0}
	HotLoad._held["draft-b"] = {"version": "v2", "files": {fixture_path: "{\"b\":2}"},
		"tier": "in_place", "status": "active", "error": "", "label": "B", "owner": "claude", "at": 2.0}
	HotLoad._order = ["draft-a", "draft-b"]
	var result: Dictionary = await HotLoad.unload_all()
	HotLoad._base.erase(fixture_path)
	HotLoad.reporter = prior_reporter
	_check(result.get("ok", false) and result.get("unloaded", 0) == 2 and result.get("tier", "") == "in_place",
		"HotLoad.unload_all reports unloaded count and tier")
	_check(HotLoad._layers.is_empty() and HotLoad._held.is_empty() and HotLoad._order.is_empty() and HotLoad.timeline().is_empty(),
		"HotLoad.unload_all clears layers, held drafts, and timeline order")
	_check(recorder.reports == [
		["draft-b", "v2", "unloaded", "Unloaded by emergency rollback."],
		["draft-a", "v1", "unloaded", "Unloaded by emergency rollback."]],
		"HotLoad.unload_all reports each unloaded draft newest-first")
	var after_empty: Dictionary = await HotLoad.unload_all()
	_check(after_empty.get("ok", false) and after_empty.get("unloaded", -1) == 0,
		"HotLoad.unload_all is idempotent once cleared")

func _check_workbench_drafts() -> void:
	_check(WorkbenchPanel.draft_label({"owner": "grok", "files": ["a", "b"], "status": "passed", "behind_main": true})
		== "grok · 2 files · passed · behind main", "label an agent's draft in the Workbench picker")
	_check(WorkbenchPanel.draft_label({"owner": "", "files": ["a"], "status": "staged"}) == "Your draft · 1 file · staged",
		"label the person's own draft in the Workbench picker")
	var history := WorkbenchPanel.history_text([
		{"at": "2026-11-10T19:02:03.000Z", "event": "committed", "owner": "grok", "draft": "1234567890ab", "commit": "abcdef0123",
			"message": "Fix speed", "files": ["world/scripts/a.gd", "world/scripts/b.gd"]},
		{"at": "2026-11-10T18:00:00.000Z", "event": "checked", "status": "failed", "scope": "gateway", "error": "Boom\nmore"}])
	var rows := history.split("\n")
	_check(rows.size() == 2 and rows[0].begins_with("11-10 19:02  committed ")
		and rows[0].ends_with("grok  12345678  abcdef0  Fix speed  world/scripts/a.gd +1"), "summarize a commit in the Workbench history")
	_check(rows.size() == 2 and rows[1].contains("  you  failed (gateway)  — Boom") and not rows[1].contains("more"),
		"summarize a failed check in the Workbench history")
	_check(WorkbenchPanel.history_text([]) == "No Workbench history yet.", "explain an empty Workbench history")

	var panel := WorkbenchPanel.new()
	root.add_child(panel)
	panel.setup("http://127.0.0.1:9", "test", "test", func(_c: Dictionary) -> Dictionary: return {},
		func(_a: String, _b: String) -> Dictionary: return {"live": false}, func(_id: String) -> String: return "",
		func() -> Dictionary: return {})
	var client := FocusFixtureClient.new()
	panel.add_child(client)
	panel._client.queue_free()
	panel._client = client
	panel._busy = false
	var agent := {"id": "a", "owner": "grok", "files": ["world/scripts/a.gd"], "status": "passed", "version": "v", "behind_main": true}
	var in_view: Dictionary = agent.merged({"name": "world/scripts/a.gd", "diff": "", "log": "", "activation": "restart"})
	panel._show_state({"focus": "a", "drafts": [agent], "draft": in_view})
	_check(panel._drafts.visible and panel._drafts.item_count == 2 and panel._drafts.selected == 1,
		"list open drafts and select the one in view")
	_check(panel._buttons.rebase.visible and panel._status.text.contains("Rebase"), "offer a rebase when the main branch moved")
	_check(panel._chip.text == "draft · grok · passed", "name the agent that holds the draft in view")
	client.answer = {"focus": "", "drafts": [agent]}
	await panel._on_draft_selected(0)
	_check(client.focused == "" and panel._state.get("draft") == null and panel._drafts.selected == 0
		and not panel._buttons.rebase.visible, "step back to the person's own files beside an agent's draft")
	_check(panel._status.text.contains("1 open draft"), "point to the open draft from the person's files")
	var mine := {"id": "g", "owner": "", "files": ["gateway/server.mjs"], "status": "staged", "version": "w"}
	panel._show_state({"focus": "g", "drafts": [mine, agent], "draft": mine.merged({"name": "gateway/server.mjs", "diff": "", "log": "",
		"activation": "gateway_restart"})})
	_check(panel._drafts.item_count == 2 and panel._drafts.selected == 0 and panel._status.text.contains("Gateway reload"),
		"show the person's gateway draft with its gateway reload")
	panel.free()

static func _press(code: Key, unicode := 0, ctrl := false, alt := false, shift := false) -> InputEventKey:
	var key := InputEventKey.new()
	key.keycode = code
	key.unicode = unicode
	key.ctrl_pressed = ctrl
	key.alt_pressed = alt
	key.shift_pressed = shift
	key.pressed = true
	return key

func _check_atmosphere() -> void:
	var refreshed := [0]
	var atmosphere := Atmosphere.new("", func() -> void: refreshed[0] += 1)
	var start: Dictionary = atmosphere.inspect("villa").values
	_check(atmosphere.values_for("villa").is_empty() and start.sky != "" and start.has("sun_elevation"), "start from the package's atmosphere")
	var previewed := atmosphere.preview("villa", {"sun_elevation": -10.0, "stars": 1.0, "fog_color": "203040", "sun_azimuth": null})
	_check(previewed.ok and atmosphere.previewing("villa") and refreshed[0] == 1
		and atmosphere.values_for("villa") == {"sun_elevation": -10.0, "stars": 1.0, "fog_color": "203040"}, "preview only the atmosphere fields given")
	_check(not atmosphere.preview("villa", {"fog_density": 0.5}).ok and not atmosphere.preview("villa", {"sky": "missing.hdr"}).ok
		and not atmosphere.preview("villa", {"weather": 1.0}).ok, "reject out-of-range values, missing skies and unknown settings")
	_check(atmosphere.finish(true).ok and not atmosphere.previewing("villa") and atmosphere.values_for("villa").has("stars"), "save the atmosphere")
	atmosphere.preview("villa", {"reset": true})
	_check(atmosphere.values_for("villa").is_empty() and atmosphere.finish(false).ok and atmosphere.values_for("villa").has("stars"),
		"discard a reset and keep the saved atmosphere")
	var day: Dictionary = WorldArt.zone_state("construct")
	var night: Dictionary = WorldArt.zone_state("construct", {"sun_elevation": -10.0, "stars": 1.0})
	_check(night.sun_energy < 0.01 and (night.to_sun as Vector3).y < 0.0 and night.sky_energy < day.sky_energy * 0.2 and night.stars == 1.0,
		"a sun below the horizon stops lighting and the sky darkens")

	var zone := "open_ground"
	_check(atmosphere.preview(zone, {"time_mode": "cycle", "time_of_day": 23.9, "day_length": 1.0}).ok
		and atmosphere.advance(zone, 0.5) and is_equal_approx(atmosphere.current_hour(zone), 0.1)
		and atmosphere.finish(true).ok, "cycle through midnight and save the current hour")
	_check(atmosphere.preview(zone, {"time_mode": "fixed", "time_of_day": 8.0, "rain": 0.6}).ok
		and is_equal_approx(atmosphere.current_hour(zone), 8.0) and is_equal_approx(atmosphere.rain_amount(zone), 0.6)
		and atmosphere.finish(false).ok and is_equal_approx(atmosphere.current_hour(zone), 0.1)
		and is_zero_approx(atmosphere.rain_amount(zone)), "discard weather and restore the running clock")
	var noon := WorldArt.zone_state(zone, {"time_mode": "fixed", "time_of_day": 12.0})
	var dusk := WorldArt.zone_state(zone, {"time_mode": "fixed", "time_of_day": 18.0, "cloud_cover": 0.7})
	_check(noon.to_sun.y > 0.8 and absf(dusk.to_sun.y) < 0.001 and dusk.cloud_cover == 0.7,
		"drive the rendered sun and clouds from the atmosphere settings")

func _check_spring_follow() -> void:
	var bouncy := SpringFollow.new(3.0, 0.5, 0.0)
	var firm := SpringFollow.new(3.0, 1.0, 0.0)
	var peak := 0.0
	var firm_peak := 0.0
	for frame in 180:
		peak = maxf(peak, bouncy.step(1.0 / 60.0, Vector3.ONE).x)
		firm_peak = maxf(firm_peak, firm.step(1.0 / 60.0, Vector3.ONE).x)
	_check(absf(bouncy.value.x - 1.0) < 0.01 and absf(firm.value.x - 1.0) < 0.01, "arm springs settle on their target")
	_check(peak > 1.05 and firm_peak <= 1.001, "light damping overshoots and full damping does not")
	var hitch := SpringFollow.new(3.0, 0.74, 0.9)
	hitch.step(0.5, Vector3(0, 1, 0))
	_check(hitch.value.is_finite() and hitch.value.length() < 3.0, "a long frame does not throw an arm across the view")

func _check_wrist_computer() -> void:
	var fixture := WristFixture.new()
	var wrist := WristComputer.new()
	wrist.configure(fixture)
	_check(not wrist.handle(_press(KEY_E, 101)) and not wrist.is_open, "leave E to the world while the wrist is down")
	_check(wrist.handle(_press(KEY_TAB)) and wrist.is_open, "raise the wrist with Tab")
	wrist.handle(_press(KEY_ENTER))
	_check(fixture.ran == ["a"], "run the selected row on Enter")
	wrist.handle(_press(KEY_DOWN))
	wrist.handle(_press(KEY_ENTER))
	_check(wrist.cursor() == 1 and fixture.ran.size() == 1 and wrist.notice().get("text") == "Not here.", "explain a row that is not available")
	wrist.handle(_press(KEY_DOWN))
	_check(wrist.cursor() == 1, "keep the selection on the list")
	wrist.handle(_press(KEY_E, 101))
	_check(wrist.current().id == "two" and wrist.cursor() == 0, "turn pages with E, each keeping its own selection")
	wrist.handle(_press(KEY_ENTER))
	_check(wrist.typing and wrist.blocks_movement() and wrist.handle(_press(KEY_W, 119)), "take the keyboard for a typed line")
	wrist.handle(_press(KEY_BACKSPACE))
	for character in "hi":
		wrist.handle(_press(KEY_A, character.unicode_at(0)))
	wrist.handle(_press(KEY_ENTER))
	_check(fixture.ran == ["a", "hi"] and not wrist.typing and wrist.current().id == "one",
		"send one typed line, then show the page the row names")
	wrist.handle(_press(KEY_Q, 113))
	wrist.handle(_press(KEY_DOWN))
	wrist.handle(_press(KEY_ENTER))
	_check(fixture.ran.size() == 2 and wrist.is_open, "ask again before a row that needs confirming")
	wrist.handle(_press(KEY_ENTER))
	_check(fixture.ran[-1] == "quit" and not wrist.is_open, "run a confirmed row and lower the wrist")
	_check(wrist.handle(_press(KEY_ESCAPE)) and wrist.is_open, "raise the wrist with Escape")
	wrist.handle(_press(KEY_ESCAPE))
	_check(not wrist.is_open, "lower it again with Escape")
	var confirm := InputEventMouseButton.new()
	confirm.button_index = MOUSE_BUTTON_LEFT
	confirm.pressed = true
	var back := InputEventMouseButton.new()
	back.button_index = MOUSE_BUTTON_RIGHT
	back.pressed = true
	wrist.raise_wrist("two")
	wrist.move(-1)
	_check(wrist.handle(confirm) and wrist.typing, "M1 starts editing the selected wrist row")
	_check(wrist.handle(back) and not wrist.typing and wrist.is_open, "M2 backs out of a wrist edit")
	_check(wrist.handle(back) and not wrist.is_open, "M2 lowers the wrist from a top-level page")
	wrist.free()

func _check_desktop_focus() -> void:
	const Chrome = preload("res://scripts/ui/desktop_panel.gd")
	var panel := Chrome.new()
	root.add_child(panel)
	panel.position = Vector2(80, 60)
	panel.size = Vector2(440, 280)
	var entry := LineEdit.new()
	panel.content.add_child(entry)
	panel.set_keyboard_active(true)
	entry.grab_focus()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(20, 20)
	panel._input(click)
	_check(panel.visible and not panel.keyboard_active and not entry.has_focus(),
		"clicking the world leaves a desktop panel visible and frees the movement keys")
	click.position = Vector2(280, 200)
	panel._input(click)
	_check(panel.keyboard_active and entry.has_focus(), "clicking the desktop panel restores its previous keyboard focus")
	panel.free()

func _check_agents_panel() -> void:
	var connected := {"state": "connected", "url": "https://relay.test", "agent_url": "https://relay.test/mcp"}
	_check(AgentsPanel.relay_summary(connected) == "Connected to https://relay.test. Cloud agents use https://relay.test/mcp",
		"summarize a connected relay")
	_check(AgentsPanel.relay_summary({}).begins_with("Not connected.") and AgentsPanel.relay_summary({"state": "refused", "error": "Wrong key."}) == "Wrong key.",
		"explain an unset or refused relay")
	var cloud := {"name": "cloud", "remote": true, "checks": false, "last_seen": {"at": "2026-11-11T06:30:00.000Z", "via": "relay"}}
	_check(AgentsPanel.agent_line(cloud) == "cloud  ·  cloud  ·  last seen 11-11 06:30 via relay", "describe a cloud agent and when it was last seen")
	_check(AgentsPanel.agent_line({"name": "codex", "remote": false}) == "codex  ·  local  ·  not seen yet", "describe a local agent")
	var activity := AgentsPanel.activity_text([{"at": "2026-11-11T06:30:00.000Z", "agent": "cloud", "tool": "submit_draft", "status": 200, "via": "relay"},
		{"at": "2026-11-11T06:29:00.000Z", "agent": "", "status": 401, "via": "tunnel"}])
	_check(activity == "11-11 06:30  cloud  submit_draft  200  relay\n11-11 06:29  unknown agent  -  401  tunnel", "list recent outside calls")
	_check(AgentsPanel.activity_text([]) == "No outside calls yet.", "explain an empty activity list")
	var panel := AgentsPanel.new()
	root.add_child(panel)
	panel.setup("http://127.0.0.1:9", "test", "test")
	panel.show_state({"relay": connected, "agents": [cloud, {"name": "codex", "remote": false}]}, [])
	_check(panel._agents.get_child_count() == 2 and panel._relay_url.text == "https://relay.test" and panel._relay_status.text.begins_with("Connected"),
		"show the relay and one row per agent")
	panel.free()

func _check_terminal_keys() -> void:
	_check(TerminalView.key_sequence(_press(KEY_A, 97)) == "a" and TerminalView.key_sequence(_press(KEY_ENTER)) == "\r",
		"send typed text and Enter to the terminal")
	_check(TerminalView.key_sequence(_press(KEY_C, 99, true)) == "\u0003" and TerminalView.key_sequence(_press(KEY_BACKSPACE)) == "\u007f",
		"send Ctrl+C as an interrupt and Backspace as DEL")
	_check(TerminalView.key_sequence(_press(KEY_UP)) == "\u001b[A" and TerminalView.key_sequence(_press(KEY_UP), true) == "\u001bOA",
		"send arrow keys in normal and application cursor mode")
	_check(TerminalView.key_sequence(_press(KEY_X, 120, false, true)) == "\u001bx" and TerminalView.key_sequence(_press(KEY_TAB, 0, false, false, true)) == "\u001b[Z",
		"prefix Alt with Escape and send Shift+Tab as a back tab")
	_check(TerminalView.key_sequence(_press(KEY_F5)) == "\u001b[15~" and TerminalView.key_sequence(_press(KEY_SHIFT)).is_empty(),
		"send function keys and ignore bare modifiers")

func _check_panel_swap() -> void:
	var label_source := func(transform: String) -> String:
		return "extends Label\nvar shown := \"\"\nfunc show_view(value: String) -> bool:\n\tshown = value\n\ttext = %s\n\treturn true\n" % transform
	var builtin := GDScript.new()
	builtin.source_code = label_source.call("value")
	builtin.reload()
	LabelSwap.base_code = builtin
	var host := LabelSwap.new()
	var parent := VBoxContainer.new()
	root.add_child(host)
	root.add_child(parent)
	host._mount({"parent": parent, "zone": "lab"}, {"text": "hello"})
	_check(host.panel is Label and host.panel.text == "hello", "mount a hot-swappable panel with its view")
	var louder: String = label_source.call("value.to_upper()")
	var started: Dictionary = host._preview({"draft": "d", "version": "1", "source": louder, "digest": louder.sha256_text()}, {"zone": "lab"})
	_check(started.ok and host.panel.text == "HELLO" and host.status("d") == "active", "swap a checked panel candidate in with the same view")
	var broken := "extends Label\n"
	var refused: Dictionary = host._preview({"draft": "d", "version": "2", "source": broken, "digest": broken.sha256_text()}, {"zone": "lab"})
	_check(not refused.ok and refused.message.contains("working test panel") and host.panel.get_script() == builtin
		and host.panel.text == "hello" and host.status("d") == "failed", "fall back to the working panel when a candidate breaks its contract")
	host._preview({"draft": "d", "version": "3", "source": louder, "digest": louder.sha256_text()}, {"zone": "lab"})
	_check(host.finish("d", true) and host.panel.text == "HELLO" and host.status("d").is_empty(), "keep a committed panel candidate")
	host.clear_view()
	host._mount({"parent": parent, "zone": "lab"}, {"text": "again"})
	_check(host.panel.text == "AGAIN", "mount the committed candidate afterwards")
	host.free()
	parent.free()

func _check_palette_reload() -> void:
	var zone := Node3D.new()
	var overlay := VBoxContainer.new()
	var host := GridPaletteHost.new()
	root.add_child(zone)
	root.add_child(overlay)
	root.add_child(host)
	var tools := WorldTools.new("")
	tools.attach(zone)
	var cone := tools.execute("spawn", {"type": "traffic_cone", "position": [2, 0, -2], "yaw": 30.0})
	var other := tools.execute("spawn", {"type": "traffic_cone", "position": [4, 0, -2]})
	var catalog := func() -> Array: return []
	var action := func(_entry: Dictionary) -> Dictionary: return {}
	host.mount(overlay, "construct", Vector3(3, 0, -2), cone.id, tools, catalog, action)
	host.panel._fields.Yaw.value = 50.0
	host.panel._fields.X.get_line_edit().text = "3.25"
	host.panel._prefab_name.text = "Unsaved name"
	var old := host.panel
	host.unmount(true)
	overlay.remove_child(old)
	old.queue_free()
	var source := FileAccess.get_file_as_string(GridPaletteHost.SOURCE_PATH).replace("\r\n", "\n")
	var changed := source.replace("Spawn orange cone", "Preview cone")
	var candidate := {"draft": "fixture", "version": "first", "source": changed, "digest": changed.sha256_text()}
	_check(host.preview(candidate, "construct", tools, catalog, action).ok, "load a checked palette without replacing the world")
	host.mount(overlay, "construct", Vector3.ZERO, other.id, tools, catalog, action)
	var view: Dictionary = host.panel.capture_view()
	_check(view.selected == cone.id and view.spawn_at == Vector3(3, 0, -2), "keep the selection and placement through palette reload")
	_check(view.fields.Yaw.value == 50.0 and view.fields.X.text == "3.25" and view.prefab_name == "Unsaved name",
		"keep unsaved palette values and text through reload")
	host.observe("fixture", "next")
	_check(host.status("fixture").is_empty() and host.panel.get_script() == GridPaletteHost.Builtin and host.panel._fields.Yaw.value == 50.0,
		"restore the working panel when the reviewed draft version changes")
	_check(host.preview(candidate, "construct", tools, catalog, action).ok and host.finish("fixture", false)
		and host.panel.get_script() == GridPaletteHost.Builtin, "stop a palette preview and restore the working panel")
	var rejected := source.replace("\t_refresh_prefabs()\n\treturn true",
		"\t_tools.execute(\"delete\", {\"id\": _selected})\n\t_refresh_prefabs()\n\treturn true")
	var bad := {"draft": "fixture", "version": "bad", "source": rejected, "digest": rejected.sha256_text()}
	var previous := host.panel
	_check(not host.preview(bad, "construct", tools, catalog, action).ok and host.panel == previous,
		"keep the working palette when candidate setup fails")
	_check(host.error_log("fixture", "bad").contains("world edit during setup") and tools.execute("inspect", {"id": cone.id}).ok,
		"record the rejected setup and preserve the selected entity")
	host.free()
	overlay.free()
	zone.free()

func _check_agent_activity() -> void:
	ActivityMotions.use_overrides("")
	var kinds := ActivityMotions.kinds()
	_check(["read", "edit", "run", "search", "think", "tool", "say"].all(func(kind: String) -> bool:
		return kind in kinds and MotionClip.valid(ActivityMotions.clip(kind)) and not ActivityMotions.clip(kind).joint_tracks.is_empty()),
		"every agent activity has a valid looping joint motion")
	_check(ActivityMotions.resolve("write") == "edit" and ActivityMotions.prop("delete") == "keyboard"
		and not ActivityMotions.prop_spec("read").is_empty(), "file writes act out typing and reading conjures its prop")
	_check(ActivityView.duration({"kind": "edit", "added": 4, "removed": 2, "hunks": []}) > ActivityView.duration({"kind": "tool"}) * 0.5,
		"activity events have a play length")
	var body: MeshInstance3D = BinaryAvatar.projection()
	root.add_child(body)
	body.set_activity("read")
	_check(body.activity == "read" and body.prop() != null and body.prop().key == "book", "reading plays its motion and conjures a book")
	body.set_activity("write")
	var keyboard: Node3D = body.prop()
	_check(body.activity == "edit" and keyboard != null and keyboard.key == "keyboard", "editing swaps the book for a keyboard")
	body.set_activity("think")
	_check(body.activity == "think" and body.prop() == null and keyboard.leaving, "an activity without a prop dissolves the last one")
	body.set_activity("")
	_check(body.activity == "", "agents return to hovering")
	var animations := SceneAnimations.new("", body)
	var listed: Dictionary = animations.execute({"tool": "inspect_animation"}, null)
	_check(listed.ok and listed.targets.any(func(target: Dictionary) -> bool: return target.id == "activity:read"),
		"agents can find the activity motions among animation targets")
	var original := ActivityMotions.clip("read")
	var revised := original.duplicate(true)
	revised.name = "Agent read, slower"
	revised.duration = 9.0
	revised.keyframes.back().time = 9.0
	for track: Dictionary in revised.joint_tracks:
		track.keyframes.back().time = 9.0
	var shown: Dictionary = animations.execute({"tool": "preview_animation", "target": "activity:read", "clip": revised}, null)
	_check(shown.ok and ActivityMotions.clip("read").duration == 9.0 and body.activity == "read",
		"previewing an activity motion plays it on the companion")
	_check(animations.execute({"tool": "discard_animation", "target": "activity:read"}, null).ok
		and ActivityMotions.clip("read") == original and body.activity == "", "discarding restores the shipped activity motion")
	var bare := revised.duplicate(true)
	bare.erase("joint_tracks")
	_check(not animations.execute({"tool": "preview_animation", "target": "activity:read", "clip": bare}, null).ok,
		"activity motions need joint tracks")
	_check(not animations.execute({"tool": "preview_animation", "target": "activity:dance", "clip": revised}, null).ok,
		"reject unknown activity targets")
	_check(animations.execute({"tool": "preview_animation", "target": "activity:read", "clip": revised}, null).ok
		and animations.execute({"tool": "save_animation", "target": "activity:read"}, null).ok
		and ActivityMotions.clip("read").duration == 9.0, "save a revised activity motion")
	ActivityMotions.set_override("read", {})
	body.free()
	_check(ActivityMotions.resolve("reply") == "say"
		and ActivityView.duration({"kind": "reply", "text": "x".repeat(600)}) > ActivityView.duration({"kind": "reply", "text": "Done."}),
		"chat replies act out speaking and play for as long as they take to say")
	var voice_path := "user://core_voice_session.json"
	var voice_session := DevelopmentSession.new(voice_path)
	voice_session.save_voice_enabled(true)
	_check(DevelopmentSession.new(voice_path).voice_enabled, "voice stays on across launches")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(voice_path))
	var speech := SpeechPlayerScript.new()
	root.add_child(speech)
	speech.say("Not spoken while voice is off.")
	_check(speech._pending.is_empty() and not is_instance_valid(speech._speech), "replies stay silent while voice is off")
	speech.free()

func _check_tweaks() -> void:
	var world := Node3D.new()
	var lamp := OmniLight3D.new()
	lamp.name = "Lamp"
	var box := MeshInstance3D.new()
	box.name = "Box"
	var material := StandardMaterial3D.new()
	box.material_override = material
	world.add_child(lamp)
	world.add_child(box)
	TweakLayer.attach(world)
	var looked := TweakLayer.inspect("")
	_check(looked.ok and looked.children.size() == 2 and looked.children[0].name == "Lamp", "inspect the world's children")
	var lamp_values: Dictionary = TweakLayer.inspect("Lamp").get("values", {})
	_check(lamp_values.has("light_energy") and lamp_values.has("light_color"), "inspect a node's editable values")
	_check(TweakLayer.inspect("Box").values.has("material_override:albedo_color"), "inspect into a node's material")
	_check(TweakLayer.set_value("Lamp", "light_energy", 3).ok and is_equal_approx(lamp.light_energy, 3.0), "tweak a number")
	_check(TweakLayer.set_value("Lamp", "light_color", "#ff8800").ok and lamp.light_color.is_equal_approx(Color("ff8800")), "tweak a color from text")
	_check(TweakLayer.set_value("Box", "material_override:albedo_color", [0, 1, 0]).ok and material.albedo_color.is_equal_approx(Color(0, 1, 0)),
		"tweak a property inside a material")
	_check(TweakLayer.set_value("Box", "position", [1, 2, 3]).ok and box.position == Vector3(1, 2, 3), "tweak a vector")
	_check(not TweakLayer.set_value("Lamp", "light_energy", "bright").ok and not TweakLayer.set_value("Ghost", "visible", true).ok
		and not TweakLayer.set_value("Lamp", "no_such_thing", 1).ok, "refuse values of the wrong type and unknown nodes or properties")
	var kept: Variant = JSON.parse_string(TweakLayer.kept_text())
	_check(kept is Dictionary and kept.tweaks.size() == 4 and kept.tweaks.any(func(tweak: Dictionary) -> bool:
		return tweak.node == "Lamp" and tweak.property == "light_energy" and is_equal_approx(float(tweak.value), 3.0)), "keep tweaks as data")
	_check(TweakLayer.discard().ok and is_equal_approx(lamp.light_energy, 1.0) and material.albedo_color.is_equal_approx(Color.WHITE)
		and box.position == Vector3.ZERO, "discard puts tweaked values back")
	var plan := {"tool": "tweak_property", "target": "Zone_villa/Pieces/Piece_3", "property": "material_override:albedo_color", "value": [1, 0.5, 0]}
	_check(Commands.valid_plan(Commands.command("tweak_property"), plan)
		and not Commands.valid_plan(Commands.command("tweak_property"), plan.merged({"property": "Bad Name"}, true)), "the tweak command's arguments are validated")
	TweakLayer.attach(null)
	world.free()

func _check_environment_export() -> void:
	var original := FileAccess.get_file_as_string("res://data/zones/construct/zone.json")
	var package: Dictionary = JSON.parse_string(original)
	var pieces: Array = package.pieces
	var same := EnvironmentExport.package_text(original, pieces, {})
	_check(same.get("text") == original and same.get("pieces") == 0 and same.get("atmosphere") == 0, "an unedited environment exports unchanged")
	var edited: Array = pieces.duplicate(true)
	var moved: Dictionary = edited[0]
	moved["name"] = "Moved in the world"
	var removed: Dictionary = edited.pop_back()
	var added: Dictionary = pieces[0].duplicate(true)
	added["id"] = "f".repeat(32)
	edited.append(added)
	var saved := EnvironmentExport.package_text(original, edited, {"sun_energy": 3.5})
	var text := str(saved.get("text", ""))
	var result: Variant = JSON.parse_string(text) if not text.is_empty() else null
	var ids: Array = result.pieces.map(func(piece: Dictionary) -> String: return piece.id) if result is Dictionary else []
	var untouched := JSON.parse_string(original).pieces[1] as Dictionary
	var untouched_span := original.substr(original.find('"id": "%s"' % untouched.id) - 6, 40)
	_check(saved.get("pieces") == 3 and saved.get("atmosphere") == 1 and ids == [pieces[0].id, pieces[1].id, "f".repeat(32)]
		and result.pieces[0].name == "Moved in the world" and int(result.piece_revision) == int(package.get("piece_revision", 0)) + 1
		and is_equal_approx(float(result.environment.sun_energy), 3.5) and text.contains(untouched_span),
		"an edited environment changes only its edited pieces and settings, in the package's own style")
	_check(EnvironmentExport.package_text("not json", pieces, {}).has("error"), "refuse a package that cannot be read")

func _check_asset_refresh() -> void:
	var before := Assets.pbr("marble_01", 3.0)
	_check(Assets.pbr("marble_01", 3.0) == before, "materials are cached")
	Assets.forget("marble_01")
	_check(Assets.pbr("marble_01", 3.0) != before, "forgetting a texture set rebuilds its materials on next use")
	var runtime = preload("res://scripts/assets/runtime_assets.gd")
	runtime._scenes["fixture-model"] = PackedScene.new()
	runtime.forget("fixture-model")
	_check(not runtime._scenes.has("fixture-model"), "forgetting a model drops its cached scene")
	_check(Commands.command("refresh_asset").fields.has("asset_id") and Commands.command("save_environment").effect == "draft",
		"refresh_asset and save_environment are registered commands")

func _check_agent_vision() -> void:
	var Vision = preload("res://scripts/agents/agent_vision.gd")
	var Graphics = preload("res://scripts/rendering/graphics_settings.gd")
	var vision = Vision.new(Node3D.new())
	root.add_child(vision)
	var mode: String = Graphics.agent_vision
	Graphics.agent_vision = "off"
	_check(not (await vision.capture("point", "", Vector3.ZERO, [0, 0, -1])).ok and not vision.place("a", Vector3.ZERO, [0, 0, -1], 60.0).ok,
		"agent vision off refuses looks and cameras")
	Graphics.agent_vision = "cameras"
	_check(str((await vision.capture("player")).message).contains("placed cameras only"), "cameras-only vision refuses the player's view")
	_check(vision.place("door", Vector3(0, 2, 5), [0, 1, 0], 60.0).ok and vision.cameras.has("door"), "place a named camera")
	_check(not vision.place("door", Vector3.ZERO, "No/Such/Node", 60.0).ok, "refuse aiming at a node that does not exist")
	Graphics.agent_vision = mode
	_check(Commands.valid_plan(Commands.command("capture_view"), {"tool": "capture_view", "from": "point", "position": [1, 2, 3], "target": [0, 0, 0]})
		and not Commands.valid_plan(Commands.command("capture_view"), {"tool": "capture_view", "from": "behind"}), "the view command's arguments are validated")
	vision._world.free()
	vision.free()

func _check_live_hud() -> void:
	var hud: Control = preload("res://scripts/ui/live_hud.gd").new()
	root.add_child(hud)
	var answers: Array[String] = []
	hud.ask("load:a", "scout wants to load a change live", func() -> void: answers.append("loaded"), func() -> void: answers.append("declined"))
	hud.ask("commit:a", "Commit it?", func() -> void: answers.append("committed"))
	hud.ask("load:a", "scout wants to load a newer version", func() -> void: answers.append("loaded newer"))
	_check(hud.pending() == 2 and hud._question.text.begins_with("Commit it?"), "asking again replaces a question and keeps the queue in order")
	hud.workbench_status = func() -> PackedStringArray: return PackedStringArray(["CHECKING · scout"])
	hud.refresh_strip()
	_check(hud._strip.text.contains("CHECKING · scout") and hud._strip.text.contains("2 WAITING"), "the strip shows checks and waiting approvals")
	_check(hud.answer(true) and hud.answer(true) and not hud.answer(true) and answers == ["committed", "loaded newer"], "Y answers the question on show")
	hud.ask("load:b", "b", func() -> void: pass)
	hud.ask("load:c", "c", func() -> void: pass)
	hud.withdraw_prefix("load:", "load:c")
	_check(hud.pending() == 1 and hud.asking("load:c"), "withdraw stale questions about older drafts")
	hud.free()
