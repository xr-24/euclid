extends RefCounted
## Joint curl in degrees, from knuckle to fingertip. The wrist and elbow are solved separately.

enum Pose { REST, POINT, GRAB, PINCH, OPEN_PALM }

const FINGERS := ["thumb", "index", "middle", "ring", "pinky"]
const CURL := {
	Pose.REST: [[10, 16, 8], [19, 25, 12], [13, 21, 10], [19, 27, 14], [25, 33, 16]],
	Pose.POINT: [[11, 14, 8], [1, 5, 2], [34, 53, 23], [41, 57, 26], [47, 59, 30]],
	Pose.GRAB: [[10, 18, 9], [31, 42, 20], [35, 48, 23], [40, 52, 25], [46, 55, 29]],
	Pose.PINCH: [[9.5, 16.3, 7.6], [36, 48, 24], [8, 12, 6], [13, 18, 10], [18, 23, 13]],
	Pose.OPEN_PALM: [[3, 6, 3], [3, 6, 3], [4, 7, 4], [6, 9, 4], [9, 11, 6]],
}
const SPREAD := {
	Pose.REST: [0, 5, 1, -4, -9],
	Pose.POINT: [0, 3, 0, -2, -4],
	Pose.GRAB: [0, 3, 0, -3, -5],
	Pose.PINCH: [0, 0, -4, -10, -15],
	Pose.OPEN_PALM: [0, 6, 1, -4, -9],
}
const THUMB_OPPOSITION := {
	Pose.REST: 12.0,
	Pose.POINT: 13.0,
	Pose.GRAB: 24.0,
	Pose.PINCH: 13.8,
	Pose.OPEN_PALM: -6.0,
}

## Wrist placement for a distant target, relative to the shoulder and aim.
const REACH := {
	Pose.POINT: Vector3(0.025, -0.043, -0.41),
	Pose.GRAB: Vector3(0.045, -0.042, -0.38),
	Pose.PINCH: Vector3(0.045, -0.009, -0.37),
	Pose.OPEN_PALM: Vector3(0.035, -0.025, -0.42),
}
