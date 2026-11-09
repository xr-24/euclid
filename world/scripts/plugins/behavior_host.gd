extends Node
## One per configured entity. Owns the clock and a private material override.

const Runtime = preload("res://scripts/plugins/behavior_runtime.gd")
const DoorLinks = preload("res://scripts/plugins/door_links.gd")
var runtime: Runtime
var behavior: Dictionary
var links: DoorLinks
var entity_id: String
var output: String
var _seconds := 0.0
var _surface: MeshInstance3D
var _original: ShaderMaterial
var _material: ShaderMaterial
var _base := 0.0
var _value := 0.0

func _ready() -> void:
	_surface = get_parent().get_node_or_null("SignalSurface") as MeshInstance3D
	_original = _surface.material_override as ShaderMaterial if _surface else null
	if not _original or not is_instance_valid(runtime.observer):
		set_process(false)
		return
	_material = _original.duplicate() as ShaderMaterial
	_base = float(_material.get_shader_parameter("emission_energy"))
	_surface.material_override = _material

func _process(delta: float) -> void:
	if not is_instance_valid(runtime.observer):
		return
	_seconds += delta
	var distance := _surface.global_position.distance_to(runtime.observer.global_position)
	var value := runtime.evaluate(behavior, _seconds, distance)
	if not is_equal_approx(value, _value):
		_value = value
		_material.set_shader_parameter("emission_energy", _base + 1.65 * value)
		if output == "door_open" and behavior.has("target"):
			links.drive(entity_id, behavior.target, value, clampf(float(behavior.settings.get("speed", 2.0)), 0.2, 8.0))

func _exit_tree() -> void:
	if links and behavior.has("target"):
		links.release(entity_id, behavior.target)
	if is_instance_valid(_surface) and _material and _surface.material_override == _material:
		_surface.material_override = _original
