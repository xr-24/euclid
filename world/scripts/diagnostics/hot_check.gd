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
