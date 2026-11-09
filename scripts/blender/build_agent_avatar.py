"""Build the projection body in disposable background Blender with MPFB 2.0.18.

Run Blender with --background --factory-startup --python-exit-code 1 and this
script, then pass -- --mpfb-root PATH_TO_MPFB_CHECKOUT. The editable source
retains the animated rig. The runtime GLB bakes its motion into the splats.
"""

import argparse
from importlib import import_module
from bisect import bisect_left
import math
from pathlib import Path
import random
import sys

import addon_utils
import bpy
from mathutils import Matrix, Vector


ROOT = Path(__file__).resolve().parents[2]
HOVER_FRAMES = 192
HOVER_CHANNELS = (
    ("Lift", Vector((0, 0, 0.045)), {
        "spine01": (2.5, 0, 1.5), "neck01": (-1.5, 0, 0), "head": (-3, 0, -2),
        "upperarm01.L": (3, 1, -2), "upperarm01.R": (-4, -1, 2),
        "lowerarm01.L": (7, 0, 0), "lowerarm01.R": (5, 0, 0),
        "wrist.L": (-5, 3, -2), "wrist.R": (-4, -3, 3),
        "upperleg02.L": (3, 0, 0), "upperleg02.R": (-2, 0, 0),
        "lowerleg01.L": (-5, 0, 0), "lowerleg01.R": (4, 0, 0),
        "foot.L": (5, 0, 0), "foot.R": (-4, 0, 0),
    }),
    ("Drift", Vector((0.028, 0, 0)), {
        "spine02": (1.5, 0, 3.0), "spine01": (0, -2, 1), "head": (1.5, 3, -3),
        "upperarm01.L": (4, 0, -4), "upperarm01.R": (-4, 0, -3),
        "lowerarm01.L": (3, 0, 2), "lowerarm01.R": (-4, 0, -2),
        "wrist.L": (4, 2, 0), "wrist.R": (-5, -3, 0),
        "upperleg02.L": (-4, 0, 1), "upperleg02.R": (5, 0, 2),
        "lowerleg01.L": (5, 0, 0), "lowerleg01.R": (-7, 0, 0),
        "foot.L": (-3, 0, 0), "foot.R": (4, 0, 0),
    }),
)


def aim_bone(rig, name, direction):
    """Point a posed bone in model space while preserving its current roll."""
    bpy.context.view_layer.update()
    bone = rig.pose.bones[name]
    rotation = bone.vector.normalized().rotation_difference(Vector(direction).normalized())
    orientation = rotation @ bone.matrix.to_quaternion()
    bone.matrix = Matrix.LocRotScale(bone.head, orientation, Vector((1, 1, 1)))
    bpy.context.view_layer.update()


def apply_hover(rig, neutral, origin, weights):
    """Apply signed lift and drift weights around the authored rest pose."""
    for name, base in neutral.items():
        bone = rig.pose.bones[name]
        bone.rotation_euler = base
        for weight, (_, _, rotations) in zip(weights, HOVER_CHANNELS):
            for axis, angle in enumerate(rotations.get(name, (0, 0, 0))):
                bone.rotation_euler[axis] += weight * math.radians(angle)
    root = rig.pose.bones["root"]
    movement = sum((motion * weight for weight, (_, motion, _) in zip(weights, HOVER_CHANNELS)), Vector())
    root.location = origin + root.bone.matrix_local.to_3x3().inverted() @ movement


def bake_hover(body, rig):
    scene = bpy.context.scene
    scene.render.fps = 30
    scene.frame_end = HOVER_FRAMES + 1
    neutral = {}
    for name in sorted({name for _, _, rotations in HOVER_CHANNELS for name in rotations}):
        bone = rig.pose.bones[name]
        basis = bone.matrix_basis.copy()
        bone.rotation_mode = "XYZ"
        bone.matrix_basis = basis
        neutral[name] = bone.rotation_euler.copy()
    origin = rig.pose.bones["root"].location.copy()

    meshes = []
    rest_bones = []
    for weights in ((0, 0), (1, 0), (0, 1)):
        apply_hover(rig, neutral, origin, weights)
        bpy.context.view_layer.update()
        evaluated = body.evaluated_get(bpy.context.evaluated_depsgraph_get())
        meshes.append(bpy.data.meshes.new_from_object(evaluated, preserve_all_data_layers=True,
                                                      depsgraph=bpy.context.evaluated_depsgraph_get()))
        if not rest_bones:
            rest_bones = [(bone.name, bone.parent.name if bone.parent else None, bone.matrix.copy(), bone.length)
                          for bone in rig.pose.bones]
    for frame in range(1, HOVER_FRAMES + 2, 8):
        phase = math.tau * (frame - 1) / HOVER_FRAMES
        apply_hover(rig, neutral, origin, (math.sin(phase), math.cos(phase)))
        for name in neutral:
            rig.pose.bones[name].keyframe_insert(data_path="rotation_euler", frame=frame, group=name)
        rig.pose.bones["root"].keyframe_insert(data_path="location", frame=frame, group="root")
    rig.animation_data.action.name = "Hover"
    scene.frame_set(1)
    return meshes[0], meshes[1:], rest_bones


def projection_rig(rest_bones, scale, base_height):
    skeleton = bpy.data.armatures.new("ProjectionSkeleton")
    runtime = bpy.data.objects.new("ProjectionSkeleton", skeleton)
    bpy.context.collection.objects.link(runtime)
    bpy.context.view_layer.objects.active = runtime
    bpy.ops.object.mode_set(mode="EDIT")
    for name, _, matrix, length in rest_bones:
        bone = skeleton.edit_bones.new(name)
        position = matrix.translation * scale
        position.z -= base_height
        bone.matrix = Matrix.LocRotScale(position, matrix.to_quaternion(), Vector((1, 1, 1)))
        bone.length = length * scale
    for name, parent, _, _ in rest_bones:
        if parent:
            skeleton.edit_bones[name].parent = skeleton.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    return runtime


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mpfb-root", type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    source = args.mpfb_root.resolve() / "src"
    if not (source / "mpfb" / "blender_manifest.toml").is_file():
        raise ValueError("--mpfb-root must point to an MPFB 2.0.18 source checkout")
    # This repository exists only in this Blender process. Never save preferences.
    bpy.ops.preferences.extension_repo_add(
        name="EuclidAvatarBuild", type="LOCAL", use_custom_directory=True,
        custom_directory=str(source))
    repo = next(item for item in bpy.context.preferences.extensions.repos
                if item.name == "EuclidAvatarBuild")
    package = f"bl_ext.{repo.module}.mpfb"
    if addon_utils.enable(package, default_set=True) is None:
        raise RuntimeError("Could not enable MPFB")
    human_service = import_module(f"{package}.services.humanservice").HumanService
    target_service = import_module(f"{package}.services.targetservice").TargetService

    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    shape = target_service.get_default_macro_info_dict()
    shape.update(gender=0.0, age=0.52, muscle=0.34, weight=0.36, cupsize=0.32, proportions=0.65)
    body = human_service.create_human(macro_detail_dict=shape)
    body.name = "ProjectionSource"
    rig = human_service.add_builtin_rig(body, "default")
    rig.name = "ProjectionRig"

    # A relaxed hover, with uneven shoulders, soft elbows and one bent knee.
    for name, angle in (("spine02", -1.5), ("neck01", 1.0), ("head", 2.0)):
        bone = rig.pose.bones[name]
        bone.rotation_mode = "XYZ"
        bone.rotation_euler.z = math.radians(angle)
    aim_bone(rig, "spine02", (-0.02, 0.005, 1))
    aim_bone(rig, "spine01", (0.008, 0.005, 1))
    aim_bone(rig, "head", (0.025, -0.005, 1))
    for side, sign in (("L", 1), ("R", -1)):
        for section in ("upperarm01", "upperarm02"):
            aim_bone(rig, f"{section}.{side}", (sign * (0.29 if side == "L" else 0.25), 0.02, -1))
        for section in ("lowerarm01", "lowerarm02"):
            aim_bone(rig, f"{section}.{side}", (sign * 0.25, -0.025, -1))
        for section in ("upperleg01", "upperleg02"):
            aim_bone(rig, f"{section}.{side}", (-sign * 0.095, -0.045 if side == "R" else 0.015, -1))
        for section in ("lowerleg01", "lowerleg02"):
            aim_bone(rig, f"{section}.{side}", (-sign * 0.015, 0.09 if side == "R" else 0.035, -1))
        aim_bone(rig, f"foot.{side}", (sign * 0.06, -0.65, -0.75))
        for finger in range(2, 6):
            for joint in (1, 2, 3):
                name = f"finger{finger}-{joint}.{side}"
                if name in rig.pose.bones:
                    bone = rig.pose.bones[name]
                    bone.rotation_mode = "XYZ"
                    bone.rotation_euler.x = math.radians(7 + joint * 3)

    bpy.context.view_layer.update()
    mesh, hover_poses, rest_bones = bake_hover(body, rig)
    source_path = ROOT / "assets/source/agent_projection.blend"
    bpy.ops.wm.save_as_mainfile(filepath=str(source_path))
    posed = bpy.data.objects.new("ProjectionBody", mesh)
    bpy.context.collection.objects.link(posed)
    # Blender faces -Y and exports to Godot +Z. Normalize to the existing
    # projection's two-metre local space before the shader sees the vertices.
    high = max(vertex.co.z for vertex in mesh.vertices)
    low = min(vertex.co.z for vertex in mesh.vertices)
    scale = 1.96 / (high - low)
    base_height = low * scale + 1.02
    for vertex in mesh.vertices:
        vertex.co *= scale
        vertex.co.z -= base_height
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    mesh.materials.clear()
    # White marks body vertices for the shared projection material. Hair has
    # its own lower-intensity vertex mask in the filament mesh.
    color = mesh.color_attributes.new(name="ProjectionMask", type="FLOAT_COLOR", domain="POINT")
    for value in color.data:
        value.color = (1, 1, 1, 1)
    mesh.update()
    mesh.calc_loop_triangles()
    # Sample the anatomical surface once at build time. The runtime renders
    # independent camera-facing splats, so empty space never writes body depth.
    rng = random.Random(61837)
    triangles = list(mesh.loop_triangles)
    cumulative = []
    area = 0.0
    for triangle in triangles:
        a, b, c = (mesh.vertices[index].co for index in triangle.vertices)
        area += (b - a).cross(c - a).length * 0.5
        cumulative.append(area)
    vertices, faces, colors, uvs = [], [], [], []
    hover_offsets = [[], []]
    groups = {group.index: group.name for group in body.vertex_groups if group.name in rig.pose.bones}
    skin_weights = []
    corners = ((0, 0), (1, 0), (1, 1), (0, 1))
    for sample in range(22000):
        triangle = triangles[bisect_left(cumulative, rng.random() * area)]
        a, b, c = (mesh.vertices[index] for index in triangle.vertices)
        root = math.sqrt(rng.random())
        split = rng.random()
        weights = (1 - root, root * (1 - split), root * split)
        neutral = a.co * weights[0] + b.co * weights[1] + c.co * weights[2]
        center = neutral.copy()
        normal = (a.normal * weights[0] + b.normal * weights[1] + c.normal * weights[2]).normalized()
        if sample % 7 == 0:
            center -= normal * rng.uniform(0.006, 0.028)
        influences = {}
        for vertex, weight in zip((a, b, c), weights):
            for group in vertex.groups:
                if group.group in groups:
                    name = groups[group.group]
                    influences[name] = influences.get(name, 0.0) + weight * group.weight
        strongest = sorted(influences.items(), key=lambda item: item[1], reverse=True)[:4]
        total = sum(weight for _, weight in strongest)
        skin_weights.append([(name, weight / total) for name, weight in strongest] if total > 0 else [("root", 1.0)])
        for offsets, pose in zip(hover_offsets, hover_poses):
            offset = sum((pose.vertices[i].co * weight for i, weight in zip(triangle.vertices, weights)), Vector()) * scale
            offset.z -= base_height
            offset -= neutral
            offsets.extend([offset] * 4)
        color = (normal.x * 0.5 + 0.5, normal.z * 0.5 + 0.5, -normal.y * 0.5 + 0.5, rng.random())
        start = len(vertices)
        for u, v in corners:
            # A tiny nondegenerate carrier quad survives glTF import. The
            # shader expands it in view space and uses its UV as a round splat.
            vertices.append(tuple(center + Vector(((u - 0.5) * 0.0002, 0, (v - 0.5) * 0.0002))))
            colors.append(color)
            uvs.append((u, v))
        faces.append(tuple(range(start, start + 4)))
    point_mesh = bpy.data.meshes.new("ProjectionPoints")
    point_mesh.from_pydata(vertices, [], faces)
    point_uv = point_mesh.uv_layers.new(name="Splat")
    for loop in point_mesh.loops:
        point_uv.data[loop.index].uv = uvs[loop.vertex_index]
    point_color = point_mesh.color_attributes.new(name="NormalAndSeed", type="FLOAT_COLOR", domain="POINT")
    for value, color in zip(point_color.data, colors):
        value.color = color
    points = bpy.data.objects.new("ProjectionPoints", point_mesh)
    bpy.context.collection.objects.link(points)
    points.shape_key_add(name="Basis")
    for (name, _, _), offsets in zip(HOVER_CHANNELS, hover_offsets):
        key = points.shape_key_add(name=name)
        for index, (vertex, offset) in enumerate(zip(vertices, offsets)):
            key.data[index].co = Vector(vertex) + offset
    assert len({name for weights in skin_weights for name, _ in weights}) > 30, "Missing projection skin weights"
    runtime_rig = projection_rig(rest_bones, scale, base_height)
    joints = {name: points.vertex_groups.new(name=name) for name, _, _, _ in rest_bones}
    for index, weights in enumerate(skin_weights):
        for name, weight in weights:
            joints[name].add(faces[index], weight, "REPLACE")
    points.parent = runtime_rig
    points.modifiers.new("Projection skin", "ARMATURE").object = runtime_rig
    bpy.ops.object.select_all(action="DESELECT")
    posed.select_set(True)
    points.select_set(True)
    runtime_rig.select_set(True)
    bpy.context.view_layer.objects.active = posed
    output = ROOT / "world/assets/agents/projection_body.glb"
    output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(output), export_format="GLB", use_selection=True,
        export_animations=False, export_skins=True, export_morph=True,
        export_materials="NONE", export_yup=True, export_extras=False)
    mesh.calc_loop_triangles()
    print(f"EUCLID_AVATAR_BUILD_OK {len(mesh.vertices)} vertices, {len(mesh.loop_triangles)} triangles")
    print(f"Source {source_path}")
    print(f"Runtime {output}")


if __name__ == "__main__":
    main()
