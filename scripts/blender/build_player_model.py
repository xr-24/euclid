"""Build Euclid's player GLBs from the non-root-motion Quaternius UAL Standard GLB."""

import argparse
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix


CLIPS = {
    "Idle_Loop", "Walk_Loop", "Jog_Fwd_Loop", "Jump_Start", "Jump_Loop",
    "Jump_Land", "Swim_Idle_Loop", "Swim_Fwd_Loop", "Interact",
}


def seal_boundaries(mesh):
    edges = [edge for edge in mesh.edges if edge.is_boundary]
    neighbors = {}
    for edge in edges:
        a, b = edge.verts
        neighbors.setdefault(a, []).append(b)
        neighbors.setdefault(b, []).append(a)
    if any(len(adjacent) != 2 for adjacent in neighbors.values()):
        raise ValueError("The mannequin crop has a branched seam.")

    remaining = set(neighbors)
    caps = []
    for edge in edges:
        loop = edge.link_loops[0]
        start, second = loop.link_loop_next.vert, loop.vert
        if start not in remaining:
            continue
        ring = [start, second]
        while True:
            a, b = neighbors[ring[-1]]
            following = b if a == ring[-2] else a
            if following == start:
                break
            ring.append(following)
        remaining.difference_update(ring)
        cap = mesh.faces.new(ring)
        cap.smooth = True
        cap.material_index = 0
        caps.append(cap)
    # A new center keeps the cap triangles distinct from the existing shell.
    mesh.normal_update()
    centers = bmesh.ops.poke(mesh, faces=caps, offset=-0.003)["verts"]
    deform = mesh.verts.layers.deform.active
    for vertex in centers:
        weights = vertex[deform]
        strongest = sorted(weights.items(), key=lambda influence: influence[1], reverse=True)[:4]
        total = sum(weight for _, weight in strongest)
        weights.clear()
        for group, weight in strongest:
            weights[group] = weight / total
    if any(edge.is_boundary for edge in mesh.edges):
        raise ValueError("The cropped mannequin still has an open seam.")


def isolate_mesh(source, name, bone_names, keep_inside=True, seal=False):
    obj = source.copy()
    obj.data = source.data.copy()
    obj.name = name
    obj.data.name = name
    bpy.context.collection.objects.link(obj)

    groups = {group.index for group in obj.vertex_groups if group.name in bone_names}
    mesh = bmesh.new()
    mesh.from_mesh(obj.data)
    if seal:
        # glTF splits vertices at shading seams. Weld them before sealing the crop.
        bmesh.ops.remove_doubles(mesh, verts=list(mesh.verts), dist=0.00001)
    deform = mesh.verts.layers.deform.active
    weights = {
        vertex: sum(weight for group, weight in vertex[deform].items() if group in groups)
        for vertex in mesh.verts
    }
    removed = [
        face for face in mesh.faces
        if (sum(weights[vertex] for vertex in face.verts) >= 0.5 * len(face.verts)) != keep_inside
    ]
    bmesh.ops.delete(mesh, geom=removed, context="FACES")
    if not mesh.faces:
        raise ValueError(f"The mannequin has no matching geometry for {name}.")
    if seal:
        # The visible shell follows the torso at the cuts. Shoulder and neck
        # vertices must not be pulled toward an arm or head that is now absent.
        rig = source.find_armature()
        by_name = {group.name: group.index for group in obj.vertex_groups}
        remap = {}
        for bone_name in bone_names:
            parent = rig.data.bones[bone_name].parent
            while parent.name in bone_names:
                parent = parent.parent
            remap[by_name[bone_name]] = by_name[parent.name]
        for vertex in mesh.verts:
            influences = vertex[deform]
            for group, weight in list(influences.items()):
                if group in remap:
                    del influences[group]
                    target = remap[group]
                    influences[target] = influences.get(target, 0.0) + weight
        seal_boundaries(mesh)
    mesh.to_mesh(obj.data)
    mesh.free()
    return obj


def export(path, objects, animated):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=str(path), export_format="GLB", use_selection=True,
        export_animations=animated, export_animation_mode="NLA_TRACKS",
        export_optimize_animation_size=True,
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(args.source.resolve()))
    source = bpy.data.objects["Mannequin"]
    for slot in source.material_slots:
        slot.material.use_backface_culling = True
    rig = source.find_armature()
    arm_bones = set()
    for side in ("l", "r"):
        bone = rig.data.bones[f"upperarm_{side}"]
        arm_bones.update(child.name for child in [bone, *bone.children_recursive])

    animation = rig.animation_data
    if not CLIPS.issubset({track.name for track in animation.nla_tracks}):
        raise ValueError("The source GLB is missing Standard locomotion animations.")
    animation.action = None
    for track in list(animation.nla_tracks):
        if track.name in CLIPS:
            track.mute = False
        else:
            animation.nla_tracks.remove(track)

    occluding_bones = arm_bones | {"Head", "neck_01"}
    body = isolate_mesh(source, "Body", occluding_bones, keep_inside=False, seal=True)
    occluders = isolate_mesh(source, "FirstPersonOccluders", occluding_bones)
    arms = isolate_mesh(source, "Arms", arm_bones)
    args.output.mkdir(parents=True, exist_ok=True)
    export(args.output / "mannequin.glb", [rig, body, occluders], True)
    rig.animation_data_clear()
    for bone in rig.pose.bones:
        bone.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()
    export(args.output / "mannequin_arms.glb", [rig, arms], False)


if __name__ == "__main__":
    main()
