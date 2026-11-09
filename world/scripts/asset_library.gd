extends RefCounted
## The catalog of placeable models: every scanned statue, tree, rock and prop the world can use,
## by id, with its category, real-world size and licence. Built from the asset sources by
## scripts/assets/build_catalog.py into res://assets/library/catalog.json (see
## world/assets/library/README.md). Zones and dressing files refer to models only by id, so a
## model can be swapped or removed without touching the code that places it.
##
## Model conventions: metres, the base at y = 0, the footprint centred on the origin and the
## front facing +Z.

const CATALOG := "res://assets/library/catalog.json"

static var _assets := {}
static var _scenes := {}

## Read the catalog. Called once on the main thread at startup; safe to call again.
static func load_catalog() -> void:
	if not FileAccess.file_exists(CATALOG):
		push_warning("AssetLibrary: no catalog at %s; run scripts/assets/build_catalog.py" % CATALOG)
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
	if data is Dictionary and data.get("assets") is Dictionary:
		_assets = data.assets

static func has(id: String) -> bool:
	return _assets.has(id) and ResourceLoader.exists(str(_assets[id].scene))

## Catalog entry: title, category, tags, scene, size_m {width, depth, height}, triangles, licence, source.
static func info(id: String) -> Dictionary:
	return _assets.get(id, {})

## Ids in the catalog, optionally only one category and/or those carrying a tag.
static func ids(category := "", tag := "") -> PackedStringArray:
	var out := PackedStringArray()
	for id in _assets:
		var a: Dictionary = _assets[id]
		if (category.is_empty() or a.category == category) and (tag.is_empty() or tag in a.get("tags", [])):
			out.append(id)
	out.sort()
	return out

## Licence folders in use (cc0, cc-by, cc-by-nc, ...), for credits screens and audits.
static func licences() -> PackedStringArray:
	var out := PackedStringArray()
	for id in _assets:
		if not str(_assets[id].licence) in out:
			out.append(str(_assets[id].licence))
	return out

## A new instance of the model, or null when it is not in the catalog or its file is missing.
static func instance(id: String) -> Node3D:
	if not has(id):
		return null
	var path := str(_assets[id].scene)
	if not _scenes.has(path):
		_scenes[path] = load(path)
	var scene := _scenes[path] as PackedScene
	return scene.instantiate() as Node3D if scene else null

## Size in metres (x = width, y = height, z = depth) at scale 1.
static func size(id: String) -> Vector3:
	var s: Dictionary = info(id).get("size_m", {})
	return Vector3(s.get("width", 0.0), s.get("height", 0.0), s.get("depth", 0.0))
