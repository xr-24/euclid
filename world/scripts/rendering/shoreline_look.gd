extends RefCounted
## Owns the live appearance revision for one attached coastline.

const PATH := "res://data/shoreline_appearance.json"
const DEFAULT := {"schema_version": 1, "foam_strength": 1.0, "foam_softness": 1.0}

var _committed := DEFAULT.duplicate()
var _draft := {}
var _surfaces: Array[ShaderMaterial] = []
var _terrain: ShaderMaterial

func _init() -> void:
	reload_committed()

func reload_committed() -> void:
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if valid_profile(saved):
		_committed = saved
	_apply()

func attach(root: Node3D) -> void:
	_surfaces.clear()
	_terrain = null
	for body in root.get_meta("water", {}).get("sims", []):
		if body.get("profile") == "shore" and body.get("terrain") is ShaderMaterial:
			_terrain = body.terrain
			_surfaces.assign(body.get("surfaces", []))
			break
	_apply()

func available() -> bool:
	return _terrain != null and not _surfaces.is_empty()

func preview(candidate: Dictionary) -> Dictionary:
	var id: String = candidate.get("draft", "")
	var profile: Variant = candidate.get("shoreline")
	if not available():
		return {"ok": false, "message": "Enter the beach with simulated surf to preview shoreline changes."}
	if id.is_empty() or not valid_profile(profile):
		return {"ok": false, "message": "The shoreline draft has invalid appearance settings."}
	if not _draft.is_empty() and _draft.id != id:
		return {"ok": false, "message": "Finish the current shoreline preview first."}
	_draft = {"id": id, "profile": profile.duplicate()}
	_apply()
	return {"ok": true, "message": "Shoreline preview active. Close the panel to look around."}

func status(id: String) -> String:
	return "active" if _draft.get("id") == id and available() else ""

func finish(id: String, keep: bool) -> bool:
	if _draft.get("id") != id:
		return false
	if keep:
		_committed = _draft.profile
	_draft = {}
	_apply()
	return true

func _apply() -> void:
	if not available():
		return
	var profile: Dictionary = _draft.get("profile", _committed)
	_terrain.set_shader_parameter("foam_strength", profile.foam_strength)
	_terrain.set_shader_parameter("foam_softness", profile.foam_softness)
	for material in _surfaces:
		material.set_shader_parameter("foam_strength", profile.foam_strength)
		material.set_shader_parameter("foam_softness", profile.foam_softness)

static func valid_profile(value: Variant) -> bool:
	return value is Dictionary and value.size() == 3 and value.get("schema_version") == 1 \
		and _number(value.get("foam_strength"), 0.0, 1.0) and _number(value.get("foam_softness"), 0.5, 2.0)

static func _number(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= minimum and value <= maximum
