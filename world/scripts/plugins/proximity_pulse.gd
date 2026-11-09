extends RefCounted

const API_VERSION := 1
const PULSE_HZ := 1.0

func sample(seconds: float, distance: float, settings: Dictionary) -> float:
	var radius: float = settings.radius
	var nearby := 1.0 - smoothstep(radius * 0.70, radius, distance)
	var pulse := 0.5 - 0.5 * cos(TAU * PULSE_HZ * seconds)
	return nearby * pulse
