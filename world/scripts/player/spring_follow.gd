extends RefCounted
## Second-order dynamics (after t3ssel8r's "Giving Personality to Procedural Animations"): a value
## that follows a moving target like a damped spring, so motion eases in, overshoots a little and
## settles instead of snapping or sliding at a constant rate.
##   frequency  how quickly it responds, in Hz
##   damping    1 settles without overshoot; below 1 overshoots and wobbles
##   response   0 starts slowly; 1 moves with the target at once; above 1 overshoots at the start;
##              below 0 pulls back first (anticipation)

var value := Vector3.ZERO
var _speed := Vector3.ZERO
var _previous := Vector3.ZERO
var _k1 := 0.0
var _k2 := 0.0
var _k3 := 0.0

func _init(frequency: float, damping: float, response: float, start := Vector3.ZERO) -> void:
	_k1 = damping / (PI * frequency)
	_k2 = 1.0 / pow(TAU * frequency, 2.0)
	_k3 = response * damping / (TAU * frequency)
	reset(start)

func reset(at: Vector3) -> void:
	value = at
	_previous = at
	_speed = Vector3.ZERO

func step(delta: float, target: Vector3) -> Vector3:
	if delta <= 0.0:
		return value
	var target_speed := (target - _previous) / delta
	_previous = target
	# Keeps the integration stable when a frame is long relative to the spring.
	var k2 := maxf(_k2, maxf(delta * delta * 0.5 + delta * _k1 * 0.5, delta * _k1))
	value += _speed * delta
	_speed += delta * (target + _k3 * target_speed - value - _k1 * _speed) / k2
	return value
