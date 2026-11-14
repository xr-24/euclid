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
const RuntimeSkies = preload("res://scripts/assets/runtime_skies.gd")
const HDRI_DIR := "res://assets/thirdparty/polyhaven/hdri/"
## Field -> schema type in data/commands/schema.json.
const FIELDS := {"sun_azimuth": "sun_azimuth", "sun_elevation": "sun_elevation", "sun_color": "color",
	"time_mode": "time_mode", "time_of_day": "time_of_day", "day_length": "day_length",
	"cloud_cover": "weather_amount", "rain": "weather_amount", "sun_energy": "sun_energy", "sky": "sky_choice", "sky_energy": "sky_energy", "stars": "star_brightness",
	"exposure": "exposure", "eye_adaptation": "eye_adaptation", "bounce_light": "bounce_light", "contrast": "contrast",
	"ambient": "ambient_energy", "fog_density": "fog_density", "fog_color": "color",
	"fog_direction": "fog_direction", "haze": "haze_density", "haze_color": "color", "shadow_distance": "shadow_distance"}
## Defaults for zones that do not set these (world_art.gd uses the same).
const DEFAULT_ADAPTATION := 0.8
const DEFAULT_CONTRAST := 1.08
signal changed

static var _skies: Array = []
static var _photo_suns: Variant = null
var _path: String
var _saved := {}
var _draft := {}
var _draft_zone := ""
var _refresh: Callable
var _clocks := {}
var _draft_clock := {}
var _active_zone := ""
var _active_clock := {}

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

## The clock advances only while the environment is active. Saves capture the chosen hour.
func advance(zone: String, delta: float) -> bool:
	if zone != _active_zone:
		_active_zone = zone
		_active_clock = _clock_settings(zone)
	var settings := _active_clock
	if settings.mode != "cycle":
		return false
	var clocks := _draft_clock if previewing(zone) else _clocks
	var clock: Vector2 = clocks.get(zone, Vector2(settings.hour, 0.0))
	clock += Vector2(delta * 24.0 / (60.0 * settings.length), delta)
	clock.x = fposmod(clock.x, 24.0)
	var update := clock.y >= 0.25
	if update:
		clock.y = fmod(clock.y, 0.25)
	clocks[zone] = clock
	return update

func lighting_values(zone: String) -> Dictionary:
	var edits := values_for(zone).duplicate()
	var settings := _clock_settings(zone)
	edits["time_mode"] = settings.mode
	edits["time_of_day"] = _current_hour(zone, settings)
	return edits

func current_hour(zone: String) -> float:
	return _current_hour(zone, _clock_settings(zone))

func rain_amount(zone: String) -> float:
	return float(values_for(zone).get("rain", Packages.definition(zone).environment.get("rain", 0.0)))

func _clock_settings(zone: String) -> Dictionary:
	var profile: Dictionary = Packages.definition(zone).environment
	var edits := values_for(zone)
	return {"mode": edits.get("time_mode", profile.get("time_mode", "manual")),
		"hour": float(edits.get("time_of_day", profile.get("time_of_day", 12.0))),
		"length": float(edits.get("day_length", profile.get("day_length", 15.0)))}

func _current_hour(zone: String, settings: Dictionary) -> float:
	var clocks := _draft_clock if previewing(zone) else _clocks
	return (clocks.get(zone, Vector2(settings.hour, 0.0)) as Vector2).x if settings.mode == "cycle" else settings.hour

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
	values["time_of_day"] = _current_hour(zone, _clock_settings(zone))
	var sun := "Sun %d° round, %d° up" % [roundi(values.sun_azimuth), roundi(values.sun_elevation)]
	if values.time_mode != "manual":
		var minutes := posmod(roundi(values.time_of_day * 60.0), 1440)
		sun = "%02d:%02d (%s)" % [floori(minutes / 60.0), minutes % 60, values.time_mode]
	var message := "%s, sky %s, cloud cover %d%%, rain %d%%, fog %.4f, stars %.2f%s." % [
		sun, values.sky, roundi(values.cloud_cover * 100.0), roundi(values.rain * 100.0),
		values.fog_density, values.stars, " (previewing; save or discard)" if previewing(zone) else ""]
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
	if not changes.has("time_of_day") and changes.get("time_mode") == "fixed" and _clock_settings(zone).mode == "cycle":
		next["time_of_day"] = current_hour(zone)
	if _draft_zone != zone:
		_draft_clock.clear()
		if _clocks.has(zone):
			_draft_clock[zone] = _clocks[zone]
	if changes.has("time_of_day") or changes.get("reset", false) or changes.has("time_mode"):
		_draft_clock.erase(zone)
	_draft = next
	_draft_zone = zone
	_active_zone = ""
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
			if _clock_settings(_draft_zone).mode == "cycle":
				next[_draft_zone]["time_of_day"] = _current_hour(_draft_zone, _clock_settings(_draft_zone))
		if not _path.is_empty() and Store.write_json(_path, {"version": 1, "environments": next}) != OK:
			return _error("Could not save the atmosphere. The preview is still showing.")
		_saved = next
		_clocks.erase(_draft_zone)
		if _draft_clock.has(_draft_zone):
			_clocks[_draft_zone] = _draft_clock[_draft_zone]
	_draft_clock.clear()
	_draft = {}
	_draft_zone = ""
	_active_zone = ""
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
		"time_mode": profile.get("time_mode", "manual"), "time_of_day": float(profile.get("time_of_day", 12.0)),
		"day_length": float(profile.get("day_length", 15.0)), "cloud_cover": float(profile.get("cloud_cover", 0.0)),
		"rain": float(profile.get("rain", 0.0)), "sky": hdri if not hdri.is_empty() else "gradient", "sky_energy": float(profile.get("sky_energy", 1.0)),
		"stars": float(profile.get("stars", 0.0)), "exposure": float(profile.get("exposure", 1.0)),
		"eye_adaptation": float(profile.get("eye_adaptation", DEFAULT_ADAPTATION)),
		"bounce_light": float(profile.get("bounce_light", 1.0)), "contrast": float(profile.get("contrast", DEFAULT_CONTRAST)),
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
	return _skies + RuntimeSkies.installed()

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
