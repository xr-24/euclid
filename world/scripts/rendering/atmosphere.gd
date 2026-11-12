extends RefCounted
## Per-environment atmosphere edits: sun, sky, stars, fog, haze and light. The package's
## environment block is the default; edits are saved per environment ID in their own file, so
## package updates still flow through and an edit can be reset. One draft at a time is shared by
## the Atmosphere panel and the registered world tools: preview, then save or discard.
##
## Field names are the ones agents and the panel use. world_art.gd merges values_for() into the
## package values when it builds a zone's lighting.

const Commands = preload("res://scripts/workshop/command_registry.gd")
const Packages = preload("res://scripts/zones/zone_packages.gd")
const Store = preload("res://scripts/persistence/world_state_store.gd")
const HDRI_DIR := "res://assets/thirdparty/polyhaven/hdri/"
## Field -> schema type in data/commands/schema.json.
const FIELDS := {"sun_azimuth": "sun_azimuth", "sun_elevation": "sun_elevation", "sun_color": "color",
	"sun_energy": "sun_energy", "sky": "sky_choice", "sky_energy": "sky_energy", "stars": "star_brightness",
	"exposure": "exposure", "ambient": "ambient_energy", "fog_density": "fog_density", "fog_color": "color",
	"fog_direction": "fog_direction", "haze": "haze_density", "haze_color": "color", "shadow_distance": "shadow_distance"}
signal changed

static var _skies: Array = []
static var _photo_suns: Variant = null
var _path: String
var _saved := {}
var _draft := {}
var _draft_zone := ""
var _refresh: Callable

## refresh re-applies the current environment's lighting; it is called after every change.
func _init(path: String, refresh: Callable) -> void:
	_path = path
	_refresh = refresh
	var file: FileAccess = null if path.is_empty() else FileAccess.open(path, FileAccess.READ)
	if file and file.get_length() <= 262144:
		var data: Variant = JSON.parse_string(file.get_as_text())
		if data is Dictionary and data.get("version") == 1 and data.get("environments") is Dictionary:
			for zone in data.environments:
				if zone is String and valid(data.environments[zone]):
					_saved[zone] = data.environments[zone]

## The edits in force for an environment: the draft while previewing there, else what is saved.
func values_for(zone: String) -> Dictionary:
	if zone == _draft_zone and not _draft_zone.is_empty():
		return _draft
	return _saved.get(zone, {})

func previewing(zone: String) -> bool:
	return zone == _draft_zone and not _draft_zone.is_empty()

## Everything an agent or the panel needs: every field's current value, which are edited, the
## skies installed and whether a draft is open.
func inspect(zone: String) -> Dictionary:
	var edits := values_for(zone)
	var values := defaults(zone)
	values.merge(edits, true)
	var message := "Sun %d° round, %d° up, sky %s, fog %.4f, stars %.2f%s." % [roundi(values.sun_azimuth),
		roundi(values.sun_elevation), values.sky, values.fog_density, values.stars,
		" (previewing; save or discard)" if previewing(zone) else ""]
	return {"ok": true, "message": message, "environment": zone, "values": values, "edited": edits.keys(),
		"skies": skies(), "preview": previewing(zone)}

func planning_context(zone: String) -> Dictionary:
	var summary := inspect(zone)
	return {"values": summary.values, "edited": summary.edited, "skies": summary.skies, "preview": summary.preview}

## Change some fields (null leaves one alone); reset clears this environment's edits first.
func preview(zone: String, changes: Dictionary) -> Dictionary:
	var next := {} if changes.get("reset", false) else values_for(zone).duplicate(true)
	for key in changes:
		if key == "reset" or changes[key] == null:
			continue
		if not FIELDS.has(key):
			return _error("Unknown atmosphere setting: %s." % key)
		next[key] = changes[key]
	if not valid(next):
		return _error("That atmosphere setting is out of range, or the sky is not installed.")
	_draft = next
	_draft_zone = zone
	_refresh.call()
	changed.emit()
	return {"ok": true, "message": "Previewing the atmosphere. Save or discard it when finished."}

func finish(keep: bool) -> Dictionary:
	if _draft_zone.is_empty():
		return _error("There is no atmosphere draft.")
	if keep:
		var next := _saved.duplicate(true)
		if _draft.is_empty():
			next.erase(_draft_zone)
		else:
			next[_draft_zone] = _draft.duplicate(true)
		if not _path.is_empty() and Store.write_json(_path, {"version": 1, "environments": next}) != OK:
			return _error("Could not save the atmosphere. The preview is still showing.")
		_saved = next
	_draft = {}
	_draft_zone = ""
	_refresh.call()
	changed.emit()
	return {"ok": true, "message": "Saved the atmosphere." if keep else "Restored the saved atmosphere."}

## The package's own values, in field names.
static func defaults(zone: String) -> Dictionary:
	var profile: Dictionary = Packages.definition(zone).get("environment", {})
	var hdri := str(profile.get("hdri", ""))
	var elevation := float(profile.get("sun_elevation", 40.0))
	if not hdri.is_empty():
		elevation = float(photo_sun(hdri).get("elevation_deg", elevation))
	return {"sun_azimuth": float(profile.get("sun_azimuth", 0.0)), "sun_elevation": elevation,
		"sun_color": str(profile.get("sun_color", "ffffff")), "sun_energy": float(profile.get("sun_energy", 1.0)),
		"sky": hdri if not hdri.is_empty() else "gradient", "sky_energy": float(profile.get("sky_energy", 1.0)),
		"stars": float(profile.get("stars", 0.0)), "exposure": float(profile.get("exposure", 1.0)),
		"ambient": float(profile.get("ambient", 1.0)), "fog_density": float(profile.get("fog_density", 0.0)),
		"fog_color": str(profile.get("fog_albedo", "ffffff")), "fog_direction": float(profile.get("fog_anisotropy", 0.0)),
		"haze": float(profile.get("haze", 0.0)), "haze_color": str(profile.get("haze_color", "ffffff")),
		"shadow_distance": float(profile.get("shadow_distance", 60.0))}

## Installed skies: HDRI panoramas, plus a painted gradient.
static func skies() -> Array:
	if _skies.is_empty():
		_skies = ["gradient"]
		for file: String in DirAccess.get_files_at(HDRI_DIR):
			var sky := file.trim_suffix(".import")
			if sky.get_extension() in ["hdr", "exr"] and sky not in _skies:
				_skies.append(sky)
	return _skies.duplicate()

## Where the photographed sun sits in an HDRI (azimuth offset u, elevation), from sun.json.
static func photo_sun(hdri: String) -> Dictionary:
	if _photo_suns == null:
		var path := HDRI_DIR + "sun.json"
		_photo_suns = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else {}
	return _photo_suns.get(hdri, {}) if _photo_suns is Dictionary else {}

static func valid(edits: Variant) -> bool:
	if not edits is Dictionary:
		return false
	for key in edits:
		if not FIELDS.has(key) or not Commands.valid_field(FIELDS[key], edits[key]):
			return false
	return not edits.has("sky") or edits.sky in skies()

static func _error(message: String) -> Dictionary:
	return {"ok": false, "message": message, "error": message}
