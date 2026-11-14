extends SceneTree
## Turns data/agents/activity_poses.json (limb directions and turns in the body's frame) into
## joint clips in data/agents/activity_motions.json for the agent projection rig.
## godot --headless --path world --script res://scripts/diagnostics/solve_activity_poses.gd

const AvatarMesh = preload("res://scripts/agents/avatar_mesh.gd")
const MotionClip = preload("res://scripts/animation/motion_clip.gd")
const SOURCE := "res://data/agents/activity_poses.json"
const TARGET := "res://data/agents/activity_motions.json"

func _initialize() -> void:
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
	var rig: Skeleton3D = AvatarMesh.build().rig
	var chains: Dictionary = spec.chains
	var out := {}
	for kind: String in spec.activities:
		var activity: Dictionary = spec.activities[kind]
		var keys: Array = activity["keys"]
		var bones: Array[String] = []
		for key: Dictionary in keys:
			for group in ["turn", "aim"]:
				for bone: String in key.get(group, {}):
					if bone not in bones:
						bones.append(bone)
		bones.sort_custom(func(a: String, b: String) -> bool: return rig.find_bone(a) < rig.find_bone(b))
		var tracks := {}
		for bone in bones:
			tracks[bone] = []
		for key: Dictionary in keys:
			var source: Dictionary = keys[int(key.same_as)] if key.has("same_as") else key
			var solved := _solve(rig, chains, source)
			for bone in bones:
				tracks[bone].append({"time": float(key.time), "rotation": solved.get(bone, [0.0, 0.0, 0.0])})
		var clip := {"name": "Agent " + kind, "duration": float(activity.duration), "interpolation": "smooth",
			"keyframes": [{"time": 0.0, "offset": [0, 0, 0], "rotation": [0, 0, 0], "pose": [0, 0]},
				{"time": float(activity.duration), "offset": [0, 0, 0], "rotation": [0, 0, 0], "pose": [0, 0]}],
			"joint_tracks": bones.map(func(bone: String) -> Dictionary: return {"joint": bone, "keyframes": tracks[bone]})}
		assert(MotionClip.valid(clip), "Solved clip for %s is not a valid motion clip." % kind)
		out[kind] = {"clip": clip}
		if activity.has("prop"):
			out[kind]["prop"] = activity.prop
	var document := {"version": 1, "about": "Agent activity motions: one looping joint clip (and an optional holographic prop) per kind of activity, played while an agent reads, edits, runs, searches, thinks, uses a tool or speaks. Solved from activity_poses.json by scripts/diagnostics/solve_activity_poses.gd; agents can revise a clip in the world with the animation tools (target activity:<kind>).",
		"activities": out, "props": spec.get("props", {}), "aliases": spec.get("aliases", {})}
	var file := FileAccess.open(TARGET, FileAccess.WRITE)
	file.store_string(JSON.stringify(document, "  ", false) + "\n")
	file.close()
	print("ACTIVITY_POSES_SOLVED ", out.keys())
	quit()

## Local joint rotations, in degrees relative to rest, for one keyframe of turns and aims.
func _solve(rig: Skeleton3D, chains: Dictionary, key: Dictionary) -> Dictionary:
	var turns: Dictionary = key.get("turn", {})
	var aims: Dictionary = key.get("aim", {})
	var pose := {}
	var global := {}
	var result := {}
	for index in rig.get_bone_count():
		var rest := rig.get_bone_rest(index).basis.get_rotation_quaternion()
		var parent := rig.get_bone_parent(index)
		var above: Quaternion = global[parent] if parent >= 0 else Quaternion.IDENTITY
		var local := rest
		var name := rig.get_bone_name(index)
		if turns.has(name):
			var angles: Array = turns[name]
			var turn := Quaternion.from_euler(Vector3(angles[0], angles[1], angles[2]) * (PI / 180.0))
			local = (above.inverse() * turn * above) * local
		if aims.has(name) and chains.has(name):
			var child := rig.find_bone(str(chains[name]))
			var along := rig.get_bone_rest(child).origin
			# The child's offset is in the bone's own frame; its rest path may pass through intermediate bones.
			var walk := rig.get_bone_parent(child)
			while walk != index and walk >= 0:
				along = rig.get_bone_rest(walk) * along
				walk = rig.get_bone_parent(walk)
			var wanted: Array = aims[name]
			var target := above.inverse() * Vector3(wanted[0], wanted[1], wanted[2]).normalized()
			var current := (local * along).normalized()
			if current.cross(target).length() > 0.0001:
				local = Quaternion(current, target) * local
		pose[index] = local
		global[index] = above * local
		if turns.has(name) or aims.has(name):
			var euler := (rest.inverse() * local).get_euler() * (180.0 / PI)
			result[name] = [snappedf(euler.x, 0.1), snappedf(euler.y, 0.1), snappedf(euler.z, 0.1)]
	return result
