extends Node

const DoorLinks = preload("res://scripts/plugins/door_links.gd")
var links: DoorLinks
var entity_id: String
var travel: float
var _leaf: AnimatableBody3D
var _height := 0.0
var _speed := 2.0

func _ready() -> void:
	_leaf = get_parent().get_node("DoorLeaf") as AnimatableBody3D

func _physics_process(delta: float) -> void:
	var requested := links.request(entity_id)
	if requested.y > 0.0:
		_speed = requested.y
	_height = move_toward(_height, travel * requested.x, _speed * delta)
	if not is_equal_approx(_leaf.position.y, _height):
		_leaf.position.y = _height
