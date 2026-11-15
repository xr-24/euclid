extends RefCounted
## Hot loading inside the running world, every tier: a shader swaps, a script reloads keeping
## state, a file the environment is built from rebuilds it around the player, a discard puts files
## back, and a script whose variables change (with a data file a library keeps a copy of) restarts
## the world in place, which then still holds the change. Run with `-- --hot-check`; it prints
## HOT_CHECK_OK. Changes live only in overlays in this process's user data, never on disk.

const HotLoad = preload("res://scripts/extensions/hot_load.gd")
const ActivityView = preload("res://scripts/agents/activity_view.gd")
const ActivityMotions = preload("res://scripts/agents/activity_motions.gd")
const PHASE := "hot_check_phase"
const SHADER := "res://shaders/agent_prop.gdshader"
const VIEW := "res://scripts/agents/activity_view.gd"
const ART := "res://scripts/world_art.gd"
const HOST := "res://scripts/agents/development_host.gd"
const MOTIONS := "res://data/agents/activity_motions.json"
const TweakLayer = preload("res://scripts/extensions/tweak_layer.gd")
const EnvironmentExport = preload("res://scripts/zones/environment_export.gd")
const Packages = preload("res://scripts/zones/zone_packages.gd")
const Commands = preload("res://scripts/workshop/command_registry.gd")

class Recorder extends RefCounted:
	var reports: Array = []
	func record(draft: String, _version: String, report: Dictionary) -> void:
		reports.append([draft, report.status])

static func run(world: Node3D) -> void:
	var tree := world.get_tree()
	await tree.process_frame
	var phase := int(Engine.get_meta(PHASE, 0))
	if phase == 0:
		await _first(world, tree)
	elif phase == 1:
		_after_restart(world, tree)
	else:
		_after_discard(world, tree)

static func _fail(tree: SceneTree, message: String) -> void:
	push_error("HOT_CHECK_FAILED: " + message)
	tree.quit(1)

static func _first(world: Node3D, tree: SceneTree) -> void:
	var host: Dictionary = world._hot_host()
	var zone := OS.get_environment("HOT_CHECK_ZONE")
	if not zone.is_empty():
		world._load_zone(zone)
		await tree.process_frame
	# Instant: shader code swaps on the loaded shader.
	var shader: Shader = load(SHADER)
	var code := shader.code + "\n// hot check\n"
	var swapped: Dictionary = await HotLoad.apply("shader", "1", {SHADER: code}, host)
	if not swapped.ok or swapped.tier != "instant" or shader.code != code:
		return _fail(tree, "shader swap: %s" % swapped)
	# In place: a script reloads; its loaded copy changes, nothing else does.
	var zone_before: Node = world.zone_root
	var view_text := FileAccess.get_file_as_string(VIEW).replace("\treturn 2.0\n", "\treturn 2.5\n")
	var reloaded: Dictionary = await HotLoad.apply("view", "1", {VIEW: view_text}, host)
	if not reloaded.ok or reloaded.tier != "in_place" or ActivityView.duration({"kind": "unknown"}) != 2.5 or world.zone_root != zone_before:
		return _fail(tree, "in-place reload: %s" % reloaded)
	if FileAccess.get_file_as_string(VIEW) != view_text or FileAccess.get_file_as_string(ProjectSettings.globalize_path(VIEW)) == view_text:
		return _fail(tree, "the overlay should serve the change and leave the file on disk alone")
	# Zone: the environment rebuilds and the player stays put.
	world.player.global_position += Vector3(1.5, 0.0, -2.0)
	var stood: Vector3 = world.player.global_position
	var started := Time.get_ticks_msec()
	var rebuilt: Dictionary = await HotLoad.apply("art", "1", {ART: FileAccess.get_file_as_string(ART) + "\n# hot check\n"}, host)
	if not rebuilt.ok or rebuilt.tier != "zone" or world.zone_root == zone_before or not is_instance_valid(world.zone_root) \
			or world.player.global_position.distance_to(stood) > 0.01:
		return _fail(tree, "zone rebuild: %s" % rebuilt)
	print("HOT_CHECK: rebuilt %s in %d ms" % [world.zone_id, Time.get_ticks_msec() - started])
	# A discard puts the file back as it was.
	await HotLoad.finish("view", false, host)
	if ActivityView.duration({"kind": "unknown"}) != 2.0 or HotLoad.status("view") != "":
		return _fail(tree, "discard did not restore the script")
	# Two live drafts on one file: discarding the lower one keeps the upper one's text.
	var recorder := Recorder.new()
	var told := HotLoad.reporter
	HotLoad.reporter = Callable(recorder, "record")
	var base := FileAccess.get_file_as_string(VIEW)
	await HotLoad.apply("lower", "1", {VIEW: base.replace("\treturn 2.0\n", "\treturn 3.0\n")}, host, {"label": "Lower"})
	await HotLoad.apply("upper", "1", {VIEW: base.replace("\treturn 2.0\n", "\treturn 4.0\n")}, host, {"label": "Upper"})
	await HotLoad.finish("lower", false, host)
	if ActivityView.duration({"kind": "unknown"}) != 4.0:
		return _fail(tree, "discarding the lower draft undid the upper one")
	# The timeline unloads a change and loads it again.
	var off: Dictionary = await HotLoad.unload("upper", host)
	if not off.ok or ActivityView.duration({"kind": "unknown"}) != 2.0 or HotLoad.timeline()[0].status != "unloaded":
		return _fail(tree, "unload from the timeline: %s" % off)
	var on: Dictionary = await HotLoad.reload("upper", host)
	if not on.ok or ActivityView.duration({"kind": "unknown"}) != 4.0 or HotLoad.timeline()[0].label != "Upper":
		return _fail(tree, "reload from the timeline: %s" % on)
	await HotLoad.finish("upper", false, host)
	if ActivityView.duration({"kind": "unknown"}) != 2.0:
		return _fail(tree, "discarding the last draft did not restore the file")
	if recorder.reports != [["lower", "active"], ["upper", "active"], ["upper", "unloaded"], ["upper", "active"]]:
		return _fail(tree, "load reports: %s" % [recorder.reports])
	HotLoad.reporter = told
	# Live tweaks reach real nodes, and a hot-loaded tweaks file applies at once, in place.
	var target := str(world.get_path_to(world.player))
	var angle: float = world.player.floor_max_angle
	if not TweakLayer.set_value(target, "floor_max_angle", 0.5).ok or not is_equal_approx(world.player.floor_max_angle, 0.5):
		return _fail(tree, "tweak a real node")
	TweakLayer.discard()
	var tweaks := JSON.stringify({"schema_version": 1, "tweaks": [{"node": target, "property": "floor_max_angle", "value": 0.6}]})
	var zone_now: Node = world.zone_root
	var kept: Dictionary = await HotLoad.apply("tweaks", "1", {"res://data/tweaks.json": tweaks}, host)
	if not kept.ok or kept.tier != "in_place" or not is_equal_approx(world.player.floor_max_angle, 0.6) or world.zone_root != zone_now:
		return _fail(tree, "hot-load kept tweaks: %s" % kept)
	await HotLoad.finish("tweaks", false, host)
	world.player.floor_max_angle = angle
	# Undo by agent: everything one agent has live unloads; others' changes stay.
	var scout_text := FileAccess.get_file_as_string(VIEW).replace("\treturn 2.0\n", "\treturn 5.0\n")
	await HotLoad.apply("scout-draft", "1", {VIEW: scout_text}, host, {"owner": "scout"})
	var undone: Dictionary = await world._undo_agent("scout")
	if undone.get("unloaded") != 1 or ActivityView.duration({"kind": "unknown"}) != 2.0:
		return _fail(tree, "undo an agent's live changes: %s" % undone)
	await HotLoad.finish("scout-draft", false, host)
	# Point and ask: looking down at the floor names its piece and node for agents.
	var ScenePlacement = load("res://scripts/workshop/scene_placement.gd")
	var tilt: float = world.camera.rotation.x
	world.camera.rotation.x = -1.2
	var aim: Dictionary = ScenePlacement.aim_at(world.player, world.camera, world.get_viewport().get_visible_rect().size * 0.5, 60.0)
	world.pointed = world.describe_point(aim)
	world.camera.rotation.x = tilt
	if str(world.pointed.get("piece", "")).is_empty() or not world.has_node(NodePath(str(world.pointed.get("node", "")))) \
			or not world.pointing_note().contains(str(world.pointed.piece)):
		return _fail(tree, "point at the floor: %s" % world.pointed)
	# Saving an environment with no edits reproduces its package exactly; edits change only their lines.
	var package_path := "res://data/zones/%s/zone.json" % world.zone_id
	var package := FileAccess.get_file_as_string(package_path)
	var same: Dictionary = EnvironmentExport.package_text(package, world.pieces.saved_pieces(), {})
	if same.get("text") != package or same.pieces != 0:
		return _fail(tree, "an unedited environment did not export unchanged: %s" % [same.get("error", "%d pieces differ" % same.get("pieces", -1))])
	# A changed command set reloads the registry; a changed package is read again and rebuilds.
	var commands_path := "res://data/commands/world.json"
	var described := FileAccess.get_file_as_string(commands_path).replace("List environment names and IDs and the current environment.", "List every environment.")
	var reloaded_commands: Dictionary = await HotLoad.apply("commands", "1", {commands_path: described}, host)
	if not reloaded_commands.ok or Commands.command("list_environments").description != "List every environment.":
		return _fail(tree, "hot-load a command set: %s" % reloaded_commands)
	await HotLoad.finish("commands", false, host)
	var spawn_yaw := float(Packages.definition(world.zone_id).spawn.yaw)
	var turned := package.replace('"yaw": %s' % EnvironmentExport.compact(spawn_yaw), '"yaw": 1.25')
	var rebuilt_package: Dictionary = await HotLoad.apply("package", "1", {package_path: turned}, host)
	if not rebuilt_package.ok or rebuilt_package.tier != "zone" or not is_equal_approx(float(Packages.definition(world.zone_id).spawn.yaw), 1.25):
		return _fail(tree, "hot-load an environment package: %s" % rebuilt_package)
	await HotLoad.finish("package", false, host)
	if not is_equal_approx(float(Packages.definition(world.zone_id).spawn.yaw), spawn_yaw):
		return _fail(tree, "discarding the package draft did not restore it")
	# The quick gate refuses data that does not parse, before anything changes.
	var refused: Dictionary = await HotLoad.apply("bad", "1", {MOTIONS: "{ not json"}, host)
	if refused.ok or not str(refused.message).begins_with("Not loaded:"):
		return _fail(tree, "the gate let broken JSON through: %s" % refused)
	# Restart: a new variable on a node script, and data a static library keeps a copy of.
	var planned := HotLoad.plan({HOST: FileAccess.get_file_as_string(HOST) + "\nvar hot_probe := 7\n",
		MOTIONS: FileAccess.get_file_as_string(MOTIONS).replace('"reply": "say"', '"reply": "say", "hot": "read"')})
	if planned.tier != "restart" or planned.reasons.size() != 2:
		return _fail(tree, "plan for a restart: %s" % planned)
	Engine.set_meta(PHASE, 1)
	Engine.set_meta("hot_check_world", world.get_instance_id())
	Engine.set_meta("hot_check_started", Time.get_ticks_msec())
	var restarted: Dictionary = await HotLoad.apply("host", "1", {HOST: FileAccess.get_file_as_string(HOST) + "\nvar hot_probe := 7\n",
		MOTIONS: FileAccess.get_file_as_string(MOTIONS).replace('"reply": "say"', '"reply": "say", "hot": "read"')}, host)
	if not restarted.ok or restarted.tier != "restart":
		return _fail(tree, "soft restart: %s" % restarted)
	print("HOT_CHECK: restarting the world in place")

static func _after_restart(world: Node3D, tree: SceneTree) -> void:
	if world.get_instance_id() == int(Engine.get_meta("hot_check_world")):
		return _fail(tree, "the world was not replaced")
	if world._dev.get("hot_probe") != 7 or ActivityMotions.resolve("hot") != "read" or HotLoad.status("host") != "active":
		return _fail(tree, "the restarted world lost the change: probe %s, motion %s" % [world._dev.get("hot_probe"), ActivityMotions.resolve("hot")])
	if world._live_change_status("host", "1") != "active" or world._live_change_status("host", "2") != "":
		return _fail(tree, "live status should follow the draft version")
	print("HOT_CHECK: restarted in %d ms" % (Time.get_ticks_msec() - int(Engine.get_meta("hot_check_started"))))
	Engine.set_meta(PHASE, 2)
	(func() -> void: await HotLoad.finish("host", false, world._hot_host())).call()

static func _after_discard(world: Node3D, tree: SceneTree) -> void:
	if world._dev.get("hot_probe") != null or ActivityMotions.resolve("hot") != "hot":
		return _fail(tree, "discarding did not restore the restarted change")
	print("HOT_CHECK_OK: shader swap, in-place reload, zone rebuild, discard, gate, soft restart and restore")
	tree.quit(0)
