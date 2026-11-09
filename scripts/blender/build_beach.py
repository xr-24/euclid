"""Build the shore terrain in disposable Blender, never in the user's live scene:
    blender --background --factory-startup --python scripts/blender/build_beach.py

A sheltered cove: a flat walkable beach where the zone's anchors sit (height 0), a sand shelf that
slopes under the sea, low dunes behind the player and rocky headlands either side that run out into
the water. Heights are authored in Godot coordinates (x right, y up, -z toward the sea) and must
stay in sync with SEA_LEVEL in world/scripts/simulation/water_system.gd. Godot shades the terrain from height and
slope (dry sand, wet sand, rock), so no UVs or vertex colours are needed.
"""
import math
from pathlib import Path

import bpy
from mathutils import Vector, noise

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'world/assets/generated'
SOURCE = ROOT / 'assets/source'
SEA_LEVEL = -0.55
X_RANGE = (-110.0, 110.0)
Z_RANGE = (-120.0, 60.0)
STEP = 0.6


def smoothstep(a, b, x):
    t = min(max((x - a) / (b - a), 0.0), 1.0)
    return t * t * (3 - 2 * t)


def fbm(x, z, scale, octaves=5):
    return noise.fractal(Vector((x / scale, z / scale, 0.37)), 0.55, 2.0, octaves, noise_basis='PERLIN_NEW')


def height(x, z):
    # Walkable beach: exactly flat-ish where the player and anchors live.
    play = smoothstep(14.0, 10.0, abs(x)) * smoothstep(13.0, 9.0, z) * smoothstep(-11.0, -7.0, z)
    ripple = fbm(x, z, 9.0, 3) * 0.05
    # Seaward shelf: gentle at first, then dropping into deeper water.
    s = max(0.0, -7.5 - z)
    h = -(0.035 * s + 0.0042 * s * s)
    h = max(h, -9.0)
    # Dunes behind the beach.
    d = max(0.0, z - 11.0)
    h += 2.4 * smoothstep(0.0, 16.0, d) + fbm(x, z, 14.0, 4) * 0.9 * smoothstep(0.0, 8.0, d)
    # Rocky headlands framing the cove, wandering in and out along the coast.
    edge = abs(x) - (21.0 + 5.0 * math.sin(z * 0.06 + (1.3 if x > 0 else 0.2)) + 3.0 * fbm(x, z, 20.0, 2))
    head = smoothstep(0.0, 22.0, edge)
    # Rounded bluffs: broad low-frequency mass, gentle mid detail; the scanned rocks add crags.
    mass = fbm(x, z, 26.0, 3)
    h += head * (7.0 + 3.0 * mass) * smoothstep(-80.0, -18.0, z + 0.4 * abs(x))
    h += head * 0.9 * fbm(x, z, 9.0, 4)
    return h * (1.0 - play) + ripple * (0.25 + 0.75 * (1.0 - play))


# Shoreline solver domain (world/thirdparty/shorewaves): 608 x 608 cells of 8 cm covering the
# cove. The solver's x axis runs cross-shore (offshore wavemaker -> beach = world +z) and its
# second axis alongshore (world +x). world/scripts/simulation/water_system.gd reads shore_sim.json.
SIM_N = 608
SIM_DX = 0.08
SIM_X0 = -SIM_N * SIM_DX / 2   # alongshore start (world x)
SIM_Z0 = -55.0                 # offshore edge (world z)
SIM_DEPTH0 = 2.5               # flat still-water depth under the wavemaker


def export_sim():
    """Bake the solver's seabed from the same height function as the visible terrain."""
    import json
    import numpy as np
    c = SIM_N + 1
    corners = np.empty((c, c), np.float32)  # [j alongshore, i cross-shore]
    for i in range(c):
        z = SIM_Z0 + i * SIM_DX
        # Flat bed under the wavemaker and sponge (first 6.4 m), easing into the real seabed.
        t = smoothstep(6.4, 12.0, i * SIM_DX)
        for j in range(c):
            b = max(height(SIM_X0 + j * SIM_DX, z) - SEA_LEVEL, -SIM_DEPTH0)
            corners[j, i] = -SIM_DEPTH0 * (1 - t) + b * t
    centre = (corners[:-1, :-1] + corners[:-1, 1:] + corners[1:, :-1] + corners[1:, 1:]) * 0.25
    east = (corners[:-1, 1:] + corners[1:, 1:]) * 0.5
    north = (corners[1:, :-1] + corners[1:, 1:]) * 0.5
    padded = np.pad(centre, 1, mode='edge')
    nb_max = np.max([padded[1 + dj:1 + dj + SIM_N, 1 + di:1 + di + SIM_N]
                     for dj in (-1, 0, 1) for di in (-1, 0, 1)], axis=0)
    bottom = np.stack([centre, east, north, nb_max], axis=-1).astype('<f4')
    state = np.zeros_like(bottom)
    state[..., 0] = np.maximum(centre, 0.0)  # lake at rest at still water level
    (OUT / 'shore_sim_bottom.bin').write_bytes(bottom.tobytes())
    (OUT / 'shore_sim_state.bin').write_bytes(state.tobytes())
    (OUT / 'shore_sim.json').write_text(json.dumps({
        'n': SIM_N, 'dx': SIM_DX, 'x0': SIM_X0, 'z0': SIM_Z0, 'depth0': SIM_DEPTH0,
        'sea_level': SEA_LEVEL}, indent=1))
    shoreline = int(np.argmax(centre[SIM_N // 2] > 0.0))
    print(f'CONSTRUCT_SHORE_SIM: {SIM_N}x{SIM_N} @ {SIM_DX} m, shoreline at world z={SIM_Z0 + shoreline * SIM_DX:.1f}')


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    nx = int((X_RANGE[1] - X_RANGE[0]) / STEP) + 1
    nz = int((Z_RANGE[1] - Z_RANGE[0]) / STEP) + 1
    verts = []
    for iz in range(nz):
        z = Z_RANGE[0] + iz * STEP
        for ix in range(nx):
            x = X_RANGE[0] + ix * STEP
            verts.append((x, -z, height(x, z)))  # Blender: x, -z, y
    faces = []
    for iz in range(nz - 1):
        for ix in range(nx - 1):
            a = iz * nx + ix
            # Rows advance toward -Y in Blender (Godot +z), so this order keeps normals facing up.
            faces.append((a, a + nx, a + nx + 1, a + 1))
    mesh = bpy.data.meshes.new('COL_Shore terrain')
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    for p in mesh.polygons:
        p.use_smooth = True
    obj = bpy.data.objects.new('COL_Shore_terrain', mesh)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    # Planar-aware reduction keeps detail on crags and ripples, merges the flat sea floor.
    mod = obj.modifiers.new('Runtime budget', 'DECIMATE')
    mod.ratio = 0.35
    bpy.ops.object.modifier_apply(modifier=mod.name)
    tri = obj.modifiers.new('Runtime triangles', 'TRIANGULATE')
    bpy.ops.object.modifier_apply(modifier=tri.name)
    mat = bpy.data.materials.new('Shore sand')
    obj.data.materials.append(mat)
    triangles = len(obj.data.polygons)
    assert triangles < 300_000, f'Terrain budget exceeded: {triangles}'
    # Spot checks that keep the world's anchors and portal on the sand.
    for x, z in [(0, -4), (0, 8), (0, 4), (-10, 10), (10, -6)]:
        assert abs(height(x, z)) < 0.06, (x, z, height(x, z))
    OUT.mkdir(parents=True, exist_ok=True)
    SOURCE.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE / 'shore_terrain.blend'))
    bpy.ops.export_scene.gltf(filepath=str(OUT / 'shore_terrain.glb'), export_format='GLB',
                              use_selection=True, export_apply=True, export_yup=True)
    print(f'CONSTRUCT_SHORE_OK: {triangles} triangles, waterline ~z={-7.5 - 8.0:.1f}')
    export_sim()


main()
