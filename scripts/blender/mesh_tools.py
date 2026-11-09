"""Mesh helpers shared by the asset build scripts that run inside a disposable Blender.

Import a model flat (no hierarchy, transforms applied), count and reduce triangles, rotate and
scale it to real-world size, rest it on the ground with its footprint centred on the origin,
cap texture sizes and export a Godot-ready GLB. Nothing here touches files outside the paths
the caller passes in.
"""
import math
from pathlib import Path

import bpy
import numpy as np
from mathutils import Euler, Matrix


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_flat(path: Path) -> list:
    """Import a glTF/GLB and return its meshes with parents cleared and transforms applied."""
    bpy.ops.import_scene.gltf(filepath=str(path))
    meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    bpy.ops.object.select_all(action='DESELECT')
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.parent_clear(type='CLEAR_KEEP_TRANSFORM')
    bpy.ops.object.make_single_user(object=True, obdata=True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for o in [o for o in bpy.context.scene.objects if o.type != 'MESH']:
        bpy.data.objects.remove(o)
    return [o for o in bpy.context.scene.objects if o.type == 'MESH' and len(o.data.polygons)]


def triangles(objects) -> int:
    return sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in objects)


def decimate(obj, ratio: float):
    if ratio >= 0.999:
        return
    bpy.context.view_layer.objects.active = obj
    mod = obj.modifiers.new('Budget', 'DECIMATE')
    mod.ratio = max(ratio, 0.002)
    mod.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier=mod.name)


def reduce_to(objects, budget: int):
    """Decimate every mesh by the same ratio so the total fits the triangle budget."""
    before = triangles(objects)
    if before > budget:
        for o in objects:
            decimate(o, budget / before)
    return before, triangles(objects)


def vertices(objects) -> np.ndarray:
    out = []
    for o in objects:
        co = np.empty(len(o.data.vertices) * 3, dtype=np.float64)
        o.data.vertices.foreach_get('co', co)
        out.append(co.reshape(-1, 3) @ np.array(o.matrix_world)[:3, :3].T + np.array(o.matrix_world.translation))
    return np.concatenate(out)


def apply_all():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def transform(objects, rotate_deg=(0.0, 0.0, 0.0), scale=1.0):
    """Rotate (XYZ Euler, degrees, Blender axes) and uniformly scale about the origin.
    Done through the world matrix: glTF imports use quaternion rotation, which ignores Euler edits."""
    m = Matrix.Diagonal((scale, scale, scale, 1.0)) @ Euler([math.radians(a) for a in rotate_deg], 'XYZ').to_matrix().to_4x4()
    for o in objects:
        o.matrix_world = m @ o.matrix_world
    apply_all()


def fit_scale(objects, fit: dict) -> float:
    """Uniform scale that gives the model its real height or length (metres)."""
    co = vertices(objects)
    size = co.max(0) - co.min(0)
    if 'height' in fit:
        return fit['height'] / max(size[2], 1e-6)
    if 'length' in fit:
        return fit['length'] / max(size[0], size[1], 1e-6)
    return 1.0


def rest_on_ground(objects):
    """Origin at the centre of the footprint, resting on the ground (Blender Z up)."""
    co = vertices(objects)
    lo, hi = co.min(0), co.max(0)
    for o in objects:
        o.location.x -= (lo[0] + hi[0]) / 2
        o.location.y -= (lo[1] + hi[1]) / 2
        o.location.z -= lo[2]
    apply_all()
    co = vertices(objects)
    return (co.max(0) - co.min(0)).round(3).tolist()


def cap_textures(max_edge: int):
    for image in bpy.data.images:
        w, h = image.size
        if max(w, h) > max_edge:
            k = max_edge / max(w, h)
            image.scale(max(1, int(w * k)), max(1, int(h * k)))


def smooth(objects):
    """Smooth shading from the reduced geometry (imported custom normals no longer match it)."""
    for o in objects:
        bpy.context.view_layer.objects.active = o
        if o.data.has_custom_normals:
            bpy.ops.mesh.customdata_custom_splitnormals_clear()
        for p in o.data.polygons:
            p.use_smooth = True


def export_glb(path: Path):
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(path), export_format='GLB', export_yup=True,
                              export_apply=True, export_image_format='AUTO')
