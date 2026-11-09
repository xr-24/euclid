extends RefCounted
## Movement only: no zone loading, UI, HTTP or persistence dependencies.
const JUMP_SPEED := 4.8

func step(player: CharacterBody3D, delta: float, direction: Vector3, water: Dictionary, controls: bool) -> void:
	var depth: float = water.level - player.position.y if water.has else -1.0
	var swimming := depth > 1.3
	var speed := 4.5
	if depth > 0.25:
		speed *= lerpf(1.0, 0.55, clampf((depth - 0.25) / 1.0, 0.0, 1.0)) # wading drags
	if swimming:
		speed = 2.6
	player.velocity.x = direction.x * speed
	player.velocity.z = direction.z * speed
	if swimming:
		# Buoyancy holds the eyes just above the surface; Space climbs, C dives.
		var target: float = water.level - 1.42
		if controls and Input.is_action_pressed("jump"):
			target += 0.9
		if controls and Input.is_action_pressed("dive"):
			target = player.position.y - 2.5
		player.velocity.y = lerpf(player.velocity.y, clampf((target - player.position.y) * 2.5, -2.5, 3.0), 1.0 - exp(-5.0 * delta))
	else:
		player.velocity.y -= 16 * delta * (0.7 if depth > 0.0 else 1.0)
		if controls and Input.is_action_just_pressed("jump") and player.is_on_floor():
			player.velocity.y = JUMP_SPEED
	player.move_and_slide()
