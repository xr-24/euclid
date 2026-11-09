"""Render a quick textured preview of optimized models, for checking reductions by eye:
    blender --background --factory-startup --python scripts/blender/preview_models.py -- id [id ...]
Writes .local/model-previews/<id>.png. Disposable Blender only.
"""
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
MODELS = ROOT / 'world/assets/thirdparty/polyhaven/models'
OUT = ROOT / '.local/model-previews'
OUT.mkdir(parents=True, exist_ok=True)

for asset in sys.argv[sys.argv.index('--') + 1:]:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(MODELS / f'{asset}.glb'))
    meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    pts = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
    lo = Vector([min(p[i] for p in pts) for i in range(3)])
    hi = Vector([max(p[i] for p in pts) for i in range(3)])
    centre, radius = (lo + hi) / 2, (hi - lo).length / 2
    cam = bpy.data.objects.new('cam', bpy.data.cameras.new('cam'))
    bpy.context.collection.objects.link(cam)
    direction = Vector((0.75, -1.0, 0.35)).normalized()
    cam.location = centre + direction * radius * 2.6
    cam.rotation_euler = (centre - cam.location).to_track_quat('-Z', 'Y').to_euler()
    scene = bpy.context.scene
    scene.camera = cam
    scene.render.engine = 'BLENDER_WORKBENCH'
    scene.display.shading.light = 'STUDIO'
    scene.display.shading.color_type = 'TEXTURE'
    scene.display.shading.show_shadows = True
    scene.render.resolution_x = 640
    scene.render.resolution_y = 640
    scene.render.filepath = str(OUT / f'{asset}.png')
    bpy.ops.render.render(write_still=True)
    tris = sum(len(p.vertices) - 2 for o in meshes for p in o.data.polygons)
    print(f'CONSTRUCT_PREVIEW {asset}: {tris} triangles, size {[round(v, 2) for v in (hi - lo)]}', flush=True)
