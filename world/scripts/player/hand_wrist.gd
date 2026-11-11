extends SkeletonModifier3D
## Runs after the arm IK so wrist orientation remains independent of the elbow pole.

var wrists: Array[int] = []
var orientations: Array[Basis] = []
var finger_axes: Array[Vector3] = []
var bend_limit := deg_to_rad(50.0)

func _process_modification_with_delta(_delta: float) -> void:
	var rig := get_skeleton()
	for index in wrists.size():
		var bone := wrists[index]
		var parent := rig.get_bone_global_pose(rig.get_bone_parent(bone))
		var forearm := (rig.get_bone_global_pose(bone).origin - parent.origin).normalized()
		var desired := orientations[index]
		var fingers := (desired * finger_axes[index]).normalized()
		var bend := forearm.angle_to(fingers)
		if bend > bend_limit:
			var correction := Quaternion(fingers, forearm)
			desired = Basis(Quaternion.IDENTITY.slerp(correction, 1.0 - bend_limit / bend)) * desired
		rig.set_bone_pose_rotation(bone, (parent.basis.orthonormalized().inverse() * desired).get_rotation_quaternion())
