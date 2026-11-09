extends RefCounted
## Workshop-local output requests keyed by target and source entity IDs.

var _requests := {}

func drive(source: String, target: String, amount: float, speed: float) -> void:
	if amount <= 0.0:
		release(source, target)
		return
	if not _requests.has(target):
		_requests[target] = {}
	_requests[target][source] = Vector2(amount, speed)

func release(source: String, target: String) -> void:
	if _requests.has(target):
		_requests[target].erase(source)
		if _requests[target].is_empty():
			_requests.erase(target)

func request(target: String) -> Vector2:
	var strongest := Vector2.ZERO
	for value: Vector2 in _requests.get(target, {}).values():
		if value.x > strongest.x:
			strongest = value
	return strongest
