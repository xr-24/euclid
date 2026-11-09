"""Build the coastal landscape around Villa Aurelia in disposable Blender, never the user's scene:
    blender --background --factory-startup --python scripts/blender/build_coast.py

Outputs (world/assets/generated):
- villa_coast.glb      the walkable landscape within 300 m of the villa (COL_Coast, collision)
- villa_coast_far.glb  a coarse ring of hills and sea floor out to 2 km for the horizon
- villa_coast_height.bin / .json  the height field (float32, metres) the game samples to
  place rocks and plants, with its origin and spacing
The shape itself is defined in coast_terrain.py.
"""
import json
import sys
from pathlib import Path

import bpy
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import arch_kit as kit  # noqa: E402
import coast_terrain as coast  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'world/assets/generated'
NEAR = (-300.0, 300.0, -320.0, 280.0)  # x0, x1, z0, z1
NEAR_STEP = 2.5
FAR = 2000.0
FAR_STEP = 20.0


def grid_mesh(name, x0, x1, z0, z1, step, height_fn, skip=None, drop=0.0):
    nx = int(round((x1 - x0) / step)) + 1
    nz = int(round((z1 - z0) / step)) + 1
    verts = []
    for iz in range(nz):
        z = z0 + iz * step
        for ix in range(nx):
            x = x0 + ix * step
            verts.append(kit.to_b(x, height_fn(x, z) - drop, z))
    faces = []
    for iz in range(nz - 1):
        for ix in range(nx - 1):
            if skip:
                cx, cz = x0 + (ix + 0.5) * step, z0 + (iz + 0.5) * step
                if skip(cx, cz):
                    continue
            a = iz * nx + ix
            faces.append((a, a + nx, a + nx + 1, a + 1))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    for p in mesh.polygons:
        p.use_smooth = True
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(bpy.data.materials.get('Coast') or bpy.data.materials.new('Coast'))
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    return obj


def decimate(obj, ratio):
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    mod = obj.modifiers.new('Budget', 'DECIMATE')
    mod.ratio = ratio
    bpy.ops.object.modifier_apply(modifier=mod.name)
    tri = obj.modifiers.new('Tri', 'TRIANGULATE')
    bpy.ops.object.modifier_apply(modifier=tri.name)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    OUT.mkdir(parents=True, exist_ok=True)
    x0, x1, z0, z1 = NEAR
    near = grid_mesh('COL_Coast', x0, x1, z0, z1, NEAR_STEP, coast.height)
    decimate(near, 0.55)
    kit.export([near], OUT / 'villa_coast.glb')
    inner = (x0 + 12, x1 - 12, z0 + 12, z1 - 12)
    far = grid_mesh('ART_Coast_far', -FAR, FAR, -FAR, FAR, FAR_STEP, coast.height, drop=0.6,
                    skip=lambda cx, cz: inner[0] < cx - FAR_STEP / 2 and cx + FAR_STEP / 2 < inner[1]
                    and inner[2] < cz - FAR_STEP / 2 and cz + FAR_STEP / 2 < inner[3])
    kit.export([far], OUT / 'villa_coast_far.glb')
    step = 2.0
    xs = np.arange(x0, x1 + 1e-6, step)
    zs = np.arange(z0, z1 + 1e-6, step)
    field = np.array([[coast.height(x, z) for x in xs] for z in zs], dtype='<f4')
    (OUT / 'villa_coast_height.bin').write_bytes(field.tobytes())
    (OUT / 'villa_coast_height.json').write_text(json.dumps({
        'x0': x0, 'z0': z0, 'step': step, 'nx': len(xs), 'nz': len(zs), 'sea_y': coast.SEA_Y,
        'beach_back_y': coast.BEACH_BACK_Y}, indent=1))
    print(f'CONSTRUCT_COAST_OK: near {len(near.data.polygons)} triangles, far {len(far.data.polygons)} faces, '
          f'height field {len(xs)}x{len(zs)}')


main()
