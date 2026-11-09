extends RefCounted

const BODY_SCENE: PackedScene = preload("res://assets/agents/projection_body.glb")

## Return only the sampled splats. ProjectionBody is retained in the GLB as an
## anatomy reference and never attached to an agent or written to scene depth.
static func build() -> Dictionary:
	var scene := BODY_SCENE.instantiate()
	var body := scene.find_child("ProjectionPoints", true, false) as MeshInstance3D
	assert(body != null, "The projection GLB must contain ProjectionPoints")
	var mesh := body.mesh as ArrayMesh
	assert(mesh.get_blend_shape_count() == 2, "Export the Lift and Drift hover poses")
	var rig := body.get_node_or_null(body.skeleton) as Skeleton3D
	assert(rig != null and body.skin != null, "Export the projection skin and skeleton")
	var skin := body.skin
	rig.get_parent().remove_child(rig)
	if rig.is_ancestor_of(body):
		body.free()
	rig.name = "ProjectionRig"
	scene.free()
	return {"mesh": mesh, "skin": skin, "rig": rig}
