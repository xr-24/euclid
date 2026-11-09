extends SceneTree
## Focused data-contract and ownership tests, without rendering or the user's normal save.
const Catalog = preload("res://scripts/zones/zone_catalog.gd")
const Store = preload("res://scripts/persistence/world_state_store.gd")
const Context = preload("res://scripts/zones/zone_build_context.gd")
const Assets = preload("res://scripts/assets/asset_library.gd")
const WaterInteractions = preload("res://scripts/simulation/water_interactions.gd")
const WorldTools = preload("res://scripts/workshop/world_tools.gd")
const PrefabLibrary = preload("res://scripts/workshop/prefab_library.gd")
const EnvironmentLibrary = preload("res://scripts/zones/environment_library.gd")
var _failures := 0
var _checks := 0

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
	_check_prefabs(path)
	var library := EnvironmentLibrary.new(path)
	var created := library.create("Signal Lab", manifest.zones)
	_check(created.ok and created.zone.template == "grid", "create a custom environment from the Grid template")
	_check(not library.create("signal lab", library.environments()).ok, "reject duplicate environment names")
	_check(EnvironmentLibrary.new(path).environments() == library.environments(), "reload custom environments with stable IDs")
	DirAccess.remove_absolute(path)
	print("CONSTRUCT_CORE_TESTS: %d checks, %d failures" % [_checks,_failures])
	if _failures == 0: print("CONSTRUCT_CORE_TESTS_OK")
	quit(0 if _failures == 0 else 1)

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
