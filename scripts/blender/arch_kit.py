"""Geometry kit for the procedural architecture builds (disposable Blender only).

Everything is authored in Godot coordinates (x east, y up, -z north) in metres and converted to
Blender's on creation. Each piece is a named object carrying a material name; names starting with
COL_ get trimesh collision in Godot. join_by_material() merges the pieces into one mesh per
(material, collision) pair for export, so a whole estate costs a handful of draw calls.
"""
import math

import bpy
from mathutils import Vector, noise

objects = []


def reset():
    objects.clear()


def smoothstep(a, b, x):
    t = min(max((x - a) / (b - a), 0.0), 1.0)
    return t * t * (3 - 2 * t)


def fbm(x, z, scale, octaves=4, seed=0.71):
    return noise.fractal(Vector((x / scale, z / scale, seed)), 0.55, 2.0, octaves, noise_basis='PERLIN_NEW')


def to_b(x, y, z):
    return (x, -z, y)


def mesh_obj(name, verts, faces, mat, uvs=None, normals=None):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([to_b(*v) for v in verts], [], faces)
    if uvs is not None:
        layer = mesh.uv_layers.new(name='UVMap')
        for poly in mesh.polygons:
            for li in poly.loop_indices:
                layer.data[li].uv = uvs[mesh.loops[li].vertex_index]
    mesh.update()
    if normals is not None:
        mesh.normals_split_custom_set_from_vertices([to_b(*n) for n in normals])
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj['mat'] = mat
    objects.append(obj)
    return obj


def box(name, x0, x1, y0, y1, z0, z1, mat):
    x0, x1 = min(x0, x1), max(x0, x1)
    z0, z1 = min(z0, z1), max(z0, z1)
    v = [(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1), (x0, y1, z0), (x1, y1, z0), (x1, y1, z1), (x0, y1, z1)]
    # Godot -> Blender flips handedness, so this winding faces outward after conversion.
    f = [(0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)]
    return mesh_obj(name, v, f, mat)


def box_with_hole(name, x0, x1, y0, y1, z0, z1, hole, mat):
    """A slab with a rectangular opening (hx0, hx1, hz0, hz1) cut through it."""
    hx0, hx1, hz0, hz1 = hole
    box(name, x0, x1, y0, y1, z0, hz0, mat)
    box(name, x0, x1, y0, y1, hz1, z1, mat)
    box(name, x0, hx0, y0, y1, hz0, hz1, mat)
    box(name, hx1, x1, y0, y1, hz0, hz1, mat)


def quad_slab(name, corners, thickness, mat):
    """A sloped slab from four top corners (Godot coords), extruded straight down."""
    top = list(corners)
    bottom = [(x, y - thickness, z) for x, y, z in corners]
    f = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    return mesh_obj(name, top + bottom, f, mat)


def tri_slab(name, corners, thickness, mat):
    """A sloped triangular slab from three top corners, extruded straight down (closed, so its
    normals can be made consistent)."""
    top = list(corners)
    bottom = [(x, y - thickness, z) for x, y, z in corners]
    f = [(0, 2, 1), (3, 4, 5), (0, 1, 4, 3), (1, 2, 5, 4), (2, 0, 3, 5)]
    return mesh_obj(name, top + bottom, f, mat)


def lathe(name, x, y, z, profile, mat, flutes=0, flute_range=(0.0, 0.0), segments=32):
    """Surface of revolution from (height, radius) pairs, optionally fluted between two heights."""
    verts = []
    for height, radius in profile:
        for i in range(segments):
            a = i * math.tau / segments
            r = radius
            if flutes and flute_range[0] < height < flute_range[1]:
                r -= 0.014 * radius / 0.3 * (0.5 + 0.5 * math.cos(a * flutes))
            verts.append((x + r * math.cos(a), y + height, z + r * math.sin(a)))
    faces = []
    rings = len(profile)
    for ring in range(rings - 1):
        for i in range(segments):
            a = ring * segments + i
            b = ring * segments + (i + 1) % segments
            faces.append((a, a + segments, b + segments, b))
    faces.append(tuple(range(segments)))
    faces.append(tuple(reversed(range((rings - 1) * segments, rings * segments))))
    obj = mesh_obj(name, verts, faces, mat)
    for p in obj.data.polygons:
        p.use_smooth = len(p.vertices) == 4
    return obj


def column(x, z, base_y, height, radius=0.42, mat='Limestone', flutes=20):
    """An Ionic-proportioned column with base, fluted shaft and a square abacus."""
    k = radius / 0.42
    profile = [(0.0, 0.42 * k), (0.16 * k, 0.42 * k), (0.22 * k, 0.36 * k), (0.30 * k, 0.33 * k), (0.36 * k, 0.30 * k),
               (height - 0.55 * k, 0.26 * k), (height - 0.42 * k, 0.31 * k), (height - 0.30 * k, 0.36 * k),
               (height - 0.18 * k, 0.40 * k), (height, 0.40 * k)]
    lathe('COL_Column', x, base_y, z, profile, mat, flutes=flutes, flute_range=(0.35 * k, height - 0.6 * k))
    box('COL_Capital', x - 0.48 * k, x + 0.48 * k, base_y + height, base_y + height + 0.14 * k, z - 0.48 * k, z + 0.48 * k, mat)
    box('Plinth', x - 0.46 * k, x + 0.46 * k, base_y - 0.01, base_y + 0.12 * k, z - 0.46 * k, z + 0.46 * k, mat)


def wall(name, axis, fixed, a0, a1, y0, y1, thickness, mat, openings=(), skins=()):
    """A straight wall from a0 to a1 along 'x' (at z = fixed) or 'z' (at x = fixed), centred on
    fixed, with rectangular openings (u0, u1, v0, v1): u along the wall, v height. The solid parts
    are split into boxes around the openings, which get stone frames. skins is a list of
    (material, side, top): a thin painted skin up to height top on the face at
    fixed + side * thickness / 2 (side +1 or -1)."""
    h = thickness / 2
    cuts = sorted(openings)
    def piece(u0, u1, v0, v1):
        if u1 - u0 < 1e-3 or v1 - v0 < 1e-3:
            return
        if axis == 'x':
            box(name, u0, u1, v0, v1, fixed - h, fixed + h, mat)
        else:
            box(name, fixed - h, fixed + h, v0, v1, u0, u1, mat)
        for skin_mat, side, top in skins:
            vt = min(v1, top)
            if vt > v0:
                f0 = fixed + side * h
                f1 = f0 + side * 0.02
                if axis == 'x':
                    box('Skin', u0, u1, v0, vt, f0, f1, skin_mat)
                else:
                    box('Skin', f0, f1, v0, vt, u0, u1, skin_mat)
    u = a0
    for (o0, o1, v0, v1) in cuts:
        piece(u, o0, y0, y1)              # solid run before the opening
        piece(o0, o1, y0, v0)             # sill
        piece(o0, o1, v1, y1)             # lintel zone
        frame = 0.18
        if axis == 'x':                   # stone frame round the opening, slightly proud
            box('Frame', o0 - frame, o0, v0, v1 + frame, fixed - h - 0.06, fixed + h + 0.06, 'Limestone')
            box('Frame', o1, o1 + frame, v0, v1 + frame, fixed - h - 0.06, fixed + h + 0.06, 'Limestone')
            box('Frame', o0, o1, v1, v1 + frame, fixed - h - 0.06, fixed + h + 0.06, 'Limestone')
        else:
            box('Frame', fixed - h - 0.06, fixed + h + 0.06, v0, v1 + frame, o0 - frame, o0, 'Limestone')
            box('Frame', fixed - h - 0.06, fixed + h + 0.06, v0, v1 + frame, o1, o1 + frame, 'Limestone')
            box('Frame', fixed - h - 0.06, fixed + h + 0.06, v1, v1 + frame, o0, o1, 'Limestone')
        u = o1
    piece(u, a1, y0, y1)


def hip_roof(x0, x1, z0, z1, eave_y, rise, overhang=0.7, mat='Roof tiles'):
    """A hipped roof over a rectangle: four sloped slabs meeting at a ridge along the long axis."""
    ex0, ex1, ez0, ez1 = x0 - overhang, x1 + overhang, z0 - overhang, z1 + overhang
    w, d = ex1 - ex0, ez1 - ez0
    top = eave_y + rise
    if w >= d:
        inset = d / 2
        r0, r1, rz = ex0 + inset, ex1 - inset, (ez0 + ez1) / 2
        quad_slab('Roof', [(ex0, eave_y, ez1), (ex1, eave_y, ez1), (r1, top, rz), (r0, top, rz)], 0.2, mat)
        quad_slab('Roof', [(ex1, eave_y, ez0), (ex0, eave_y, ez0), (r0, top, rz), (r1, top, rz)], 0.2, mat)
        tri_slab('Roof', [(ex0, eave_y, ez0), (ex0, eave_y, ez1), (r0, top, rz)], 0.2, mat)
        tri_slab('Roof', [(ex1, eave_y, ez1), (ex1, eave_y, ez0), (r1, top, rz)], 0.2, mat)
    else:
        inset = w / 2
        r0, r1, rx = ez0 + inset, ez1 - inset, (ex0 + ex1) / 2
        quad_slab('Roof', [(ex1, eave_y, ez1), (ex1, eave_y, ez0), (rx, top, r0), (rx, top, r1)], 0.2, mat)
        quad_slab('Roof', [(ex0, eave_y, ez0), (ex0, eave_y, ez1), (rx, top, r1), (rx, top, r0)], 0.2, mat)
        tri_slab('Roof', [(ex0, eave_y, ez0), (rx, top, r0), (ex1, eave_y, ez0)], 0.2, mat)
        tri_slab('Roof', [(ex1, eave_y, ez1), (rx, top, r1), (ex0, eave_y, ez1)], 0.2, mat)


def shed_roof(x0, x1, z0, z1, low_y, high_y, high_side, overhang=0.8, mat='Roof tiles'):
    """A single-pitch roof over a rectangle, rising toward high_side ('n', 's', 'e' or 'w')."""
    ex0, ex1, ez0, ez1 = x0 - overhang, x1 + overhang, z0 - overhang, z1 + overhang
    y = {'n': (high_y, high_y, low_y, low_y), 's': (low_y, low_y, high_y, high_y),
         'w': (high_y, low_y, low_y, high_y), 'e': (low_y, high_y, high_y, low_y)}[high_side]
    # corners: (x0,z0) (x1,z0) (x1,z1) (x0,z1) -> heights y[0..3]
    quad_slab('Roof', [(ex0, y[0], ez0), (ex0, y[3], ez1), (ex1, y[2], ez1), (ex1, y[1], ez0)], 0.18, mat)


def stairs(x0, x1, z0, z1, y0, y1, direction, mat='Limestone', steps=None):
    """A flight of steps rising from y0 to y1 toward direction ('n', 's', 'e', 'w') across the
    rectangle, plus an invisible collision ramp under the nosings so the player glides up."""
    rise = y1 - y0
    n = steps or max(2, round(rise / 0.17))
    for k in range(n):
        t0, t1 = k / n, (k + 1) / n
        top = y0 + rise * (k + 1) / n
        if direction == 'n':
            box('Step', x0, x1, y0 - 0.3, top, z1 - (z1 - z0) * t1, z1 - (z1 - z0) * t0, mat)
        elif direction == 's':
            box('Step', x0, x1, y0 - 0.3, top, z0 + (z1 - z0) * t0, z0 + (z1 - z0) * t1, mat)
        elif direction == 'e':
            box('Step', x0 + (x1 - x0) * t0, x0 + (x1 - x0) * t1, y0 - 0.3, top, z0, z1, mat)
        else:
            box('Step', x1 - (x1 - x0) * t1, x1 - (x1 - x0) * t0, y0 - 0.3, top, z0, z1, mat)
    lo, hi = y0 + 0.02, y1 + 0.02
    c = {'n': [(x0, hi, z0), (x1, hi, z0), (x1, lo, z1), (x0, lo, z1)],
         's': [(x0, lo, z0), (x1, lo, z0), (x1, hi, z1), (x0, hi, z1)],
         'e': [(x0, lo, z0), (x1, hi, z0), (x1, hi, z1), (x0, lo, z1)],
         'w': [(x0, hi, z0), (x1, lo, z0), (x1, lo, z1), (x0, hi, z1)]}[direction]
    # corners listed (x0,z0),(x1,z0),(x1,z1),(x0,z1); quad_slab wants them counter-clockwise from above
    quad_slab('COL_Stair ramp', [c[0], c[3], c[2], c[1]], 0.1, 'Invisible')


def arc_band(name, cx, cz, r0, r1, a0, a1, y0, y1, mat, segments=24):
    """A curved band (a ring sector between radii r0 < r1, angles a0..a1 in degrees measured from
    +x toward +z) filled from y0 to y1, e.g. one row of theatre seats."""
    verts, faces = [], []
    for i in range(segments + 1):
        a = math.radians(a0 + (a1 - a0) * i / segments)
        ca, sa = math.cos(a), math.sin(a)
        for r in (r0, r1):
            verts.append((cx + r * ca, y1, cz + r * sa))
            verts.append((cx + r * ca, y0, cz + r * sa))
    for i in range(segments):
        a, b = 4 * i, 4 * (i + 1)
        # top (inner-top a, outer-top a+2), outer wall, inner wall, bottom
        faces.append((a, b, b + 2, a + 2))
        faces.append((a + 2, b + 2, b + 3, a + 3))
        faces.append((a + 1, a, b, b + 1)[::-1])
        faces.append((a + 3, b + 3, b + 1, a + 1))
    faces.append((0, 1, 3, 2))
    s = 4 * segments
    faces.append((s, s + 2, s + 3, s + 1))
    obj = mesh_obj(name, verts, faces, mat)
    return obj


def join_by_material():
    """Merge everything into one mesh per (material, collision) pair, triangulated, with
    consistent outward normals. Returns the joined objects (names COL_<mat> or ART_<mat>)."""
    groups = {}
    for obj in objects:
        key = (obj['mat'], obj.name.startswith('COL_'))
        groups.setdefault(key, []).append(obj)
    joined = []
    for (mat_name, collision), objs in groups.items():
        bpy.ops.object.select_all(action='DESELECT')
        for o in objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        if len(objs) > 1:
            bpy.ops.object.join()
        j = bpy.context.view_layer.objects.active
        if not j.data.has_custom_normals:
            bpy.ops.object.mode_set(mode='EDIT')
            bpy.ops.mesh.select_all(action='SELECT')
            bpy.ops.mesh.normals_make_consistent(inside=False)
            bpy.ops.object.mode_set(mode='OBJECT')
        j.name = ('COL_' if collision else 'ART_') + mat_name.replace(' ', '_')
        mat = bpy.data.materials.get(mat_name) or bpy.data.materials.new(mat_name)
        j.data.materials.clear()
        j.data.materials.append(mat)
        tri = j.modifiers.new('Runtime triangles', 'TRIANGULATE')
        bpy.ops.object.modifier_apply(modifier=tri.name)
        joined.append(j)
    return joined


def export(objs, path):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.gltf(filepath=str(path), export_format='GLB', use_selection=True, export_apply=True,
                              export_yup=True, export_image_format='AUTO')
