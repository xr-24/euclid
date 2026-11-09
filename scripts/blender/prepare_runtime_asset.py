"""Prepare an untrusted glTF/GLB in disposable background Blender.

Arguments after -- are the downloaded source and output GLB paths.
"""
import json
import math
from pathlib import Path
import struct
import sys
from urllib.parse import unquote

import bpy
import numpy as np
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from optimize_models import triangles, decimate


def validate_source(source):
    data = source.read_bytes()
    if source.suffix.lower() == ".glb":
        if data[:4] != b"glTF" or len(data) < 20:
            raise ValueError("Invalid binary glTF")
        length, kind = struct.unpack_from("<II", data, 12)
        if kind != 0x4E4F534A or length > len(data) - 20:
            raise ValueError("Invalid glTF JSON chunk")
        document = json.loads(data[20:20 + length])
    else:
        document = json.loads(data)
    for item in document.get("buffers", []) + document.get("images", []):
        uri = item.get("uri", "")
        if not uri or uri.startswith("data:"):
            continue
        name = unquote(uri)
        if ":" in name or "\\" in name or not (source.parent / name).resolve().is_relative_to(source.parent):
            raise ValueError("Model references files outside its download directory")


def main():
    source_name, target_name, *options = sys.argv[sys.argv.index("--") + 1:]
    rigged = "--preserve-rig" in options
    source, target = Path(source_name).resolve(), Path(target_name).resolve()
    validate_source(source)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(source))
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH" and len(obj.data.polygons)]
    if not meshes or len(meshes) > 128 or triangles(meshes) > 2_000_000:
        raise ValueError("Model exceeds the runtime import geometry budget")
    before = triangles(meshes)
    if rigged:
        prepare_rigged(meshes)
    else:
        prepare_static(meshes, before)
    for image in bpy.data.images:
        width, height = image.size
        longest = max(width, height)
        if longest > 1024:
            image.scale(max(1, round(width * 1024 / longest)), max(1, round(height * 1024 / longest)))
    bpy.ops.export_scene.gltf(filepath=str(target), export_format="GLB", use_selection=True,
        export_animations=rigged, export_skins=rigged, export_morph=rigged,
        export_extras=False, export_cameras=False, export_lights=False, export_apply=not rigged)
    report = {"triangles": triangles(meshes), "source_triangles": before, "normalized_extent": 1.0, "rigged": rigged}
    target.with_name(target.name + ".json").write_text(json.dumps(report), encoding="utf-8")
    print("EUCLID_RUNTIME_ASSET_OK", json.dumps(report))


def prepare_static(meshes, before):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    bpy.ops.object.make_single_user(object=True, obdata=True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for obj in list(bpy.context.scene.objects):
        if obj not in meshes:
            bpy.data.objects.remove(obj, do_unlink=True)
    for obj in meshes:
        if before > 30000:
            decimate(obj, 30000 / before)
    coordinates = []
    for obj in meshes:
        values = np.empty(len(obj.data.vertices) * 3)
        obj.data.vertices.foreach_get("co", values)
        coordinates.append(values.reshape(-1, 3))
    coordinates = np.concatenate(coordinates)
    low, high = coordinates.min(axis=0), coordinates.max(axis=0)
    extent = float((high - low).max())
    if not math.isfinite(extent) or extent < 0.000001:
        raise ValueError("Invalid model dimensions")
    center = np.array([(low[0] + high[0]) / 2, (low[1] + high[1]) / 2, low[2]])
    for obj in meshes:
        values = np.empty(len(obj.data.vertices) * 3)
        obj.data.vertices.foreach_get("co", values)
        values = (values.reshape(-1, 3) - center) / extent
        obj.data.vertices.foreach_set("co", values.ravel())
        obj.data.update()
        obj.modifiers.clear()


def prepare_rigged(meshes):
    armatures = [obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE"]
    if len(armatures) != 1:
        raise ValueError("EUCLID_RIG_REQUIRED")
    rig = armatures[0]
    skinned = [obj for obj in meshes if any(mod.type == "ARMATURE" and mod.object == rig for mod in obj.modifiers)]
    if not skinned:
        raise ValueError("EUCLID_RIG_REQUIRED")
    if len(rig.data.bones) > 256:
        raise ValueError("EUCLID_RIG_BUDGET")
    # Drop unrelated meshes such as a scan's stage floor. Keep rigid accessories
    # attached to the skeleton alongside the skinned meshes.
    attached = [obj for obj in rig.children if obj.parent_type == "BONE"]
    kept = set(skinned)
    for accessory in attached:
        kept.update(obj for obj in [accessory, *accessory.children_recursive] if obj in meshes)
    for obj in meshes:
        if obj not in kept:
            bpy.data.objects.remove(obj, do_unlink=True)
    meshes[:] = sorted(kept, key=lambda obj: obj.name)
    if triangles(meshes) > 100_000:
        raise ValueError("EUCLID_RIG_BUDGET")
    corners = np.array([tuple(obj.matrix_world @ Vector(corner)) for obj in skinned for corner in obj.bound_box])
    low, high = corners.min(axis=0), corners.max(axis=0)
    extent = float((high - low).max())
    if not math.isfinite(extent) or extent < 0.000001:
        raise ValueError("Invalid model dimensions")
    center = Vector(((low[0] + high[0]) * 0.5, (low[1] + high[1]) * 0.5, low[2]))
    # Put normalization above the hierarchy. Bone binds and source action keys stay local.
    objects = list(bpy.context.scene.objects)
    normalization = bpy.data.objects.new("ModelPlacement", None)
    bpy.context.collection.objects.link(normalization)
    for obj in objects:
        if obj.parent is None:
            obj.parent = normalization
        obj.select_set(True)
    normalization.matrix_world = Matrix.Scale(1 / extent, 4) @ Matrix.Translation(-center)
    normalization.select_set(True)


if __name__ == "__main__":
    main()
