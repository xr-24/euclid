extends Node3D
## A solid door or pane with one hinge or slide track.

var _leaf: AnimatableBody3D
var _motion: String
var _opened: bool
var _width: float
var _depth: float
var _progress := 0.0
var _kind: String
var _slide_side := 1.0

func configure(kind: String, motion: String, width: float, height: float, depth: float, opened: bool, slide_side := 1.0) -> void:
	_kind = kind
	_motion = motion
	_width = width
	_depth = depth
	_slide_side = slide_side
	_opened = opened
	_progress = 1.0 if opened else 0.0
	_leaf = AnimatableBody3D.new()
	_leaf.name = "Leaf"
	_leaf.sync_to_physics = false
	_leaf.set_meta("piece_interaction", self)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, height, 0.045)
	collider.shape = shape
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = shape.size
	mesh.mesh = box
	mesh.position = Vector3(width * 0.5, height * 0.5, 0)
	collider.position = mesh.position
	var finish := StandardMaterial3D.new()
	finish.albedo_color = Color("664737")
	finish.roughness = 0.53
	if kind == "window":
		finish.albedo_color = Color(0.4, 0.67, 0.75, 0.26)
		finish.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		finish.roughness = 0.17
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.material_override = finish
	_leaf.add_child(mesh)
	_leaf.add_child(collider)
	add_child(_leaf)
	# The frame can still be aimed at after the leaf has opened.
	var handle := StaticBody3D.new()
	handle.set_meta("piece_interaction", self)
	var handle_collider := CollisionShape3D.new()
	var jamb := BoxShape3D.new()
	jamb.size = Vector3(0.07, height, depth + 0.1)
	handle_collider.shape = jamb
	handle_collider.position = Vector3(-0.025, height * 0.5, 0)
	handle.add_child(handle_collider)
	add_child(handle)
	_pose()
	set_physics_process(false)

func interaction_label() -> String:
	return ("Close " if _opened else "Open ") + _kind

func interact() -> void:
	set_open(not _opened)

func set_open(opened: bool) -> void:
	if opened == _opened:
		return
	_opened = opened
	set_physics_process(true)

func _physics_process(delta: float) -> void:
	var target := 1.0 if _opened else 0.0
	_progress = move_toward(_progress, target, delta * 2.35)
	_pose()
	if is_equal_approx(_progress, target):
		set_physics_process(false)

func _pose() -> void:
	if _motion == "slide":
		_leaf.position = Vector3((_width + 0.06) * _progress * _slide_side, 0, -(_depth * 0.5 + 0.04) * smoothstep(0.0, 0.17, _progress))
	else:
		_leaf.rotation.y = _progress * PI * 0.53
