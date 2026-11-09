extends RefCounted
## Small, time-scaled disturbances. A reflecting pool and an open coast have different budgets.
const PROFILES := {
	"pool": {"wake_gain":3.0, "wake_radius":0.30, "splash_gain":0.006, "splash_limit":0.025},
	"shore": {"wake_gain":4.0, "wake_radius":0.38, "splash_gain":0.012, "splash_limit":0.08},
}

static func wake(velocity: Vector3, delta: float, profile: String) -> Vector2:
	var settings: Dictionary = PROFILES.get(profile,PROFILES.shore)
	var horizontal := Vector2(velocity.z,velocity.x).limit_length(4.5)
	return horizontal * settings.wake_gain * clampf(delta,0.0,0.05)

static func splash(vertical_speed: float, profile: String) -> float:
	var settings: Dictionary = PROFILES.get(profile,PROFILES.shore)
	return minf(maxf(-vertical_speed,0.0)*settings.splash_gain,settings.splash_limit)

static func wake_height(velocity: Vector3, delta: float, profile: String) -> float:
	# A small volume-neutral bow ripple remains visible even when horizontal flow is subtle.
	if profile != "pool": return 0.0
	return minf(Vector2(velocity.x,velocity.z).length()/2.0,1.0)*0.12*clampf(delta,0.0,0.05)

static func fountain(time: float, delta: float, phase: float) -> Vector2:
	# A recirculating jet adds momentum only. A height kernel clipped by the end wall
	# would lose part of its negative lobe and gradually raise the pool's water level.
	var pulse := 0.7 + 0.3 * sin(time*TAU*1.15+phase)
	return Vector2(0.0,0.18*pulse)*clampf(delta,0.0,0.05)
