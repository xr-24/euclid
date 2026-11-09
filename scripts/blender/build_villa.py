"""Build Villa Aurelia in disposable Blender, never in the user's live scene:
    blender --background --factory-startup --python scripts/blender/build_villa.py

A Roman seaside villa in the spirit of the Getty Villa (itself modelled on the Villa dei Papiri),
standing on a bluff high above a cove. From south to north (-z is north, toward the hills):

- Outer peristyle: the long garden court with its reflecting pool, hedged beds and fresco-lined
  colonnades, open at the south end to the sea. Doors in the side colonnades lead out to the herb
  garden terraces (east) and the west lawn.
- The house, a two-storey block entered from the outer peristyle:
  south range: an entrance hall (tablinum) between two galleries;
  inner peristyle: a smaller colonnaded court with a long, narrow pool and bronzes;
  west wing: the atrium, roofed toward a central opening over its rain pool (impluvium);
  east wing: the hall of Herakles;
  north range: the library, a long hall of papyrus shelves.
- East garden: a walled garden with a round fountain and a lion-head wall fountain.
- Herb garden: three terraces stepping down east and south of the court, held by stone walls.
- Theatre: a semicircle of stone seats facing the house's west door, as at the Getty.

Everything is authored in Godot coordinates and converted (see arch_kit.py). Outputs
(world/assets/generated):
- villa_estate.glb: architecture and hedges, one mesh per material; COL_ meshes collide,
  'Invisible' meshes collide but are not drawn (stair ramps).
- villa_pool_bottom.bin / villa_pool_state.bin / villa_pool.json: seabed for the reflecting
  pool's water solver.
- villa_layout.json: everything the game needs to dress the villa (beds, pools, fountains, rooms).
- hedge_leaves.png / hedge_leaves_n.png: the generated leaf atlas for the hedges.
The landscape is built separately by build_coast.py.
"""
import json
import math
import sys
from pathlib import Path

import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
import arch_kit as kit  # noqa: E402
from arch_kit import box, wall, column, stairs  # noqa: E402
from hedges import HedgeBuilder, leaf_atlas  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
from water_bake import bake_pool  # noqa: E402
OUT = ROOT / 'world/assets/generated'
SOURCE = ROOT / 'assets/source'

# ---------------------------------------------------------------- plan (metres)
GX = 15.0                  # outer court half-width (column line)
GZ0, GZ1 = -30.0, 40.0     # outer court north / south column lines
DEPTH = 4.5                # portico depth
STYLOBATE = 0.15           # portico and house floor level
COL_H = 4.6
ENT_TOP = 5.9
WALL_TOP = 7.1
POOL = (-2.0, 2.0, -19.0, 29.0)
WATER_Y = -0.12
POOL_FLOOR = -0.62
POOL_RAMP_LENGTH = 3.4
SIDE_DOOR = (-11.5, -8.5)  # doors in the side colonnade walls (z range)

HX0, HX1 = -32.0, 32.0     # house outer faces
HZ0, HZ1 = -82.0, GZ0 - DEPTH  # house north face, south face (-34.5)
EXT = 0.7                  # exterior wall thickness
INT = 0.5                  # interior wall thickness
HOUSE_TOP = 10.2           # eaves of the two-storey house
CEIL = 6.0                 # interior ceilings
SOUTH_RANGE = -42.0        # wall between the south range and the inner peristyle
NORTH_RANGE = -70.0        # wall between the inner peristyle and the library
WING = 14.0                # walls between the inner peristyle and the wings (x = +-14)
IPC = (-10.5, 10.5, -66.5, -45.5)  # inner peristyle column line (open court)
IPOOL = (-1.0, 1.0, -63.0, -49.0)  # inner peristyle pool
IP_WATER = 0.0
ATRIUM_OPEN = (-25.5, -20.5, -59.0, -53.0)  # compluvium / impluvium
EG = (32.0, 55.0, -76.0, -40.0)    # east garden (x0 meets the house's east face, x1, z0, z1)
EG_FOUNTAIN = (44.0, -58.0, 3.2)   # centre x, z, radius
TERRACES = [(-34.2, 0.0, -0.9), (0.0, 22.0, -2.4), (22.0, 47.0, -3.9)]  # herb garden (z0, z1, y)
HERB_X = (21.0, 63.0)
THEATRE = (-40.0, -56.0, 7.0, 19.0, 14)  # orchestra centre x, z; inner, outer radius; rows
GROUND_Y = -1.1            # the levelled ground round the house (matches coast_terrain.PLATEAU_Y)

hedges = HedgeBuilder()
layout = {'lights': [], 'hedges': [], 'beds': [], 'pools': [], 'fountains': [], 'spouts': [], 'rooms': {}}


# ---------------------------------------------------------------- outer peristyle
def portico(axis, fixed, a0, a1, outward, back='wall', wall_ext=0.0, doors=()):
    """One portico wing between a0 and a1. axis 'x' runs along x at z=fixed, 'z' along z at
    x=fixed; outward points away from the court. back: 'wall' (frescoed, with optional doors),
    'parapet' (open to the view) or 'none' (the house closes it)."""
    d = DEPTH * outward

    def rect(name, u0, u1, y0, y1, w0, w1, mat):
        if axis == 'z':
            return box(name, fixed + min(w0, w1), fixed + max(w0, w1), y0, y1, u0, u1, mat)
        return box(name, u0, u1, y0, y1, fixed + min(w0, w1), fixed + max(w0, w1), mat)
    rect('COL_Portico floor', a0, a1, -0.3, STYLOBATE, -0.6 * outward, d, 'Marble floor')
    if axis == 'z':
        x_edge, x_low = fixed - 0.6 * outward, fixed - 1.15 * outward
        kit.quad_slab('COL_Stylobate ramp', [(x_low, 0.0, a0), (x_low, 0.0, a1), (x_edge, STYLOBATE, a1), (x_edge, STYLOBATE, a0)], 0.2, 'Marble floor')
    else:
        z_edge, z_low = fixed - 0.6 * outward, fixed - 1.15 * outward
        kit.quad_slab('COL_Stylobate ramp', [(a0, 0.0, z_low), (a1, 0.0, z_low), (a1, STYLOBATE, z_edge), (a0, STYLOBATE, z_edge)], 0.2, 'Marble floor')
    rect('Architrave', a0, a1, STYLOBATE + COL_H + 0.14, STYLOBATE + COL_H + 0.62, -0.42 * outward, 0.42 * outward, 'Limestone')
    rect('Frieze', a0, a1, STYLOBATE + COL_H + 0.62, ENT_TOP - 0.22, -0.38 * outward, 0.38 * outward, 'Fresco frieze')
    rect('Cornice', a0, a1, ENT_TOP - 0.22, ENT_TOP, -0.62 * outward, 0.5 * outward, 'Limestone')
    rect('Ceiling', a0, a1, ENT_TOP - 0.42, ENT_TOP - 0.3, 0.4 * outward, d, 'Timber')
    for k in range(int((a1 - a0) / 1.5) + 1):
        u = a0 + 0.2 + k * 1.5
        if u < a1 - 0.1:
            rect('Beam', u - 0.09, u + 0.09, ENT_TOP - 0.62, ENT_TOP - 0.42, 0.4 * outward, d, 'Timber')
    w0, w1 = a0 - wall_ext, a1 + wall_ext
    centre = fixed + d + 0.3 * outward
    if back == 'wall':
        wall('COL_Back wall', axis, centre, w0, w1, -0.3, WALL_TOP, 0.6, 'Plaster',
             openings=[(u0, u1, STYLOBATE, 4.3) for u0, u1 in doors], skins=[('Fresco', -outward, ENT_TOP - 0.42)])
    elif back == 'parapet':
        rect('COL_Parapet', w0, w1, -0.3, 1.05, d, d + 0.45 * outward, 'Plaster')
        rect('Parapet coping', w0, w1, 1.05, 1.15, d - 0.05 * outward, d + 0.5 * outward, 'Limestone')
        for k in range(int((a1 - a0) / 3.0) + 1):
            u = a0 + k * 3.0
            rect('COL_Pier', u - 0.3, u + 0.3, -0.3, WALL_TOP, d, d + 0.45 * outward, 'Plaster')
    lo_w, hi_w = -0.9 * outward, d + 0.65 * outward
    lo_y, hi_y = ENT_TOP + 0.05, WALL_TOP + 0.35
    if axis == 'z':
        corners = [(fixed + lo_w, lo_y, a0 - 1.2), (fixed + lo_w, lo_y, a1 + 1.2), (fixed + hi_w, hi_y, a1 + 1.2), (fixed + hi_w, hi_y, a0 - 1.2)]
    else:
        corners = [(a0 - 1.2, lo_y, fixed + lo_w), (a1 + 1.2, lo_y, fixed + lo_w), (a1 + 1.2, hi_y, fixed + hi_w), (a0 - 1.2, hi_y, fixed + hi_w)]
    kit.quad_slab('Roof', corners, 0.16, 'Roof tiles')


def outer_peristyle():
    n_long = 24
    for k in range(n_long + 1):
        z = GZ0 + k * (GZ1 - GZ0) / n_long
        column(-GX, z, STYLOBATE, COL_H)
        column(GX, z, STYLOBATE, COL_H)
    for k in range(1, 10):
        x = -GX + k * (2 * GX) / 10
        column(x, GZ0, STYLOBATE, COL_H)
        column(x, GZ1, STYLOBATE, COL_H)
    end = GX + DEPTH + 0.6
    portico('z', -GX, GZ0 + 0.6, GZ1 - 0.6, -1, wall_ext=DEPTH + 0.6, doors=[SIDE_DOOR])
    portico('z', GX, GZ0 + 0.6, GZ1 - 0.6, 1, wall_ext=DEPTH + 0.6, doors=[SIDE_DOOR])
    portico('x', GZ0, -end, end, -1, back='none')
    portico('x', GZ1, -end, end, 1, back='parapet')
    # Pediment over the centre of the north portico.
    pz = GZ0 - 0.62
    v = [(-6.5, ENT_TOP, pz), (6.5, ENT_TOP, pz), (0.0, ENT_TOP + 2.3, pz),
         (-6.5, ENT_TOP, pz - 1.0), (6.5, ENT_TOP, pz - 1.0), (0.0, ENT_TOP + 2.3, pz - 1.0)]
    kit.mesh_obj('Pediment', v, [(0, 2, 1), (3, 4, 5), (0, 3, 5, 2), (1, 2, 5, 4), (0, 1, 4, 3)], 'Limestone')
    # Court: gravel walks, the pool with marble coping and a ramp in at the south end.
    x0, x1, z0, z1 = POOL
    kit.box_with_hole('COL_Court ground', -GX - 0.6, GX + 0.6, -0.4, 0.0, GZ0 - 0.6, GZ1 + 0.6,
                      (x0 - 0.05, x1 + 0.05, z0 - 0.05, z1 + 0.05), 'Gravel')
    box('COL_Coping', x0 - 0.6, x1 + 0.6, 0.0, 0.06, z0 - 0.6, z0, 'Marble floor')
    box('COL_Coping', x0 - 0.6, x1 + 0.6, 0.0, 0.06, z1, z1 + 0.6, 'Marble floor')
    box('COL_Coping', x0 - 0.6, x0, 0.0, 0.06, z0, z1, 'Marble floor')
    box('COL_Coping', x1, x1 + 0.6, 0.0, 0.06, z0, z1, 'Marble floor')
    box('COL_Pool floor', x0, x1, POOL_FLOOR - 0.2, POOL_FLOOR, z0, z1, 'Pool basin')
    for wx in [(x0 - 0.05, x0), (x1, x1 + 0.05)]:
        box('Pool wall', wx[0], wx[1], POOL_FLOOR, 0.0, z0, z1, 'Pool basin')
    for wz in [(z0 - 0.05, z0), (z1, z1 + 0.05)]:
        box('Pool wall', x0, x1, POOL_FLOOR, 0.0, wz[0], wz[1], 'Pool basin')
    kit.quad_slab('COL_Pool ramp', [(x0, POOL_FLOOR, z1 - POOL_RAMP_LENGTH), (x1, POOL_FLOOR, z1 - POOL_RAMP_LENGTH), (x1, 0.0, z1), (x0, 0.0, z1)], 0.3, 'Marble floor')
    layout['spouts'] += [{'at': [x, 0.06, z0 - 0.32], 'yaw': 0.0, 'pedestal': True, 'water_y': WATER_Y} for x in (-1.1, 1.1)]
    # Planting beds either side of the central walk, crossed at mid-length, edged with box hedges.
    for sx in (-1, 1):
        for bz0, bz1 in [(-27.5, 3.0), (7.0, 37.5)]:
            bx0, bx1 = sorted([sx * 5.2, sx * 13.4])
            layout['beds'].append({'rect': [bx0, bx1, bz0, bz1], 'y': 0.03, 'zone': 'outer'})
            box('Bed earth', bx0, bx1, 0.0, 0.03, bz0, bz1, 'Soil')
            hedged_bed(bx0, bx1, bz0, bz1, 0.62, gap_axis='x')
    # Foundations: the court and its porticoes stand on a stone platform above the bluff.
    kit.box_with_hole('COL_Terrace', -20.7, 20.7, -7.0, -0.3, GZ0 - DEPTH, GZ1 + DEPTH + 3.0,
                      (x0 - 0.05, x1 + 0.05, z0 - 0.05, z1 + 0.05), 'Rubble')
    box('COL_Terrace', -20.7, 20.7, -0.3, 0.0, GZ1 + DEPTH + 0.5, GZ1 + DEPTH + 3.0, 'Marble floor')  # belvedere walk
    box('COL_Belvedere rail', -20.7, 20.7, 0.0, 1.0, GZ1 + DEPTH + 2.75, GZ1 + DEPTH + 3.0, 'Limestone')
    # Steps down from the side doors to the west lawn and the herb garden.
    stairs(-23.4, -20.75, SIDE_DOOR[0], SIDE_DOOR[1], GROUND_Y, STYLOBATE, 'e')
    stairs(20.75, 23.4, SIDE_DOOR[0], SIDE_DOOR[1], TERRACES[0][2], STYLOBATE, 'w')


def hedged_bed(bx0, bx1, bz0, bz1, h, gap_axis='x', base_y=0.0, gap=0.8, thickness=0.5):
    """Hedge all round a bed with an opening in the middle of each long side."""
    hedges.add(bx0, bx1, bz0, bz0 + thickness, h, base_y)
    hedges.add(bx0, bx1, bz1 - thickness, bz1, h, base_y)
    mid = (bz0 + bz1) / 2
    for hz0, hz1 in [(bz0 + thickness, mid - gap), (mid + gap, bz1 - thickness)]:
        hedges.add(bx0, bx0 + thickness, hz0, hz1, h, base_y)
        hedges.add(bx1 - thickness, bx1, hz0, hz1, h, base_y)
    layout['hedges'].append([bx0, bx1, bz0, bz1, h, base_y])


# ---------------------------------------------------------------- the house
def room_floor(x0, x1, z0, z1, mat):
    box('COL_Floor', x0, x1, -0.3, STYLOBATE, z0, z1, mat)


def ceiling(x0, x1, z0, z1, hole=None, beams=True):
    if hole:
        kit.box_with_hole('Ceiling', x0, x1, CEIL, CEIL + 0.2, z0, z1, hole, 'Timber')
    else:
        box('Ceiling', x0, x1, CEIL, CEIL + 0.2, z0, z1, 'Timber')
    if beams:  # coffering: a grid of beams under the ceiling
        nx, nz = max(1, int((x1 - x0) / 2.4)), max(1, int((z1 - z0) / 2.4))
        for i in range(1, nx):
            x = x0 + (x1 - x0) * i / nx
            if hole and hole[0] - 0.2 < x < hole[1] + 0.2:
                continue
            box('Beam', x - 0.1, x + 0.1, CEIL - 0.22, CEIL, z0, z1, 'Timber')
        for i in range(1, nz):
            z = z0 + (z1 - z0) * i / nz
            if hole and hole[2] - 0.2 < z < hole[3] + 0.2:
                continue
            box('Beam', x0, x1, CEIL - 0.22, CEIL, z - 0.1, z + 0.1, 'Timber')


def light(x, y, z, energy=3.2, rng=18.0, color=(1.0, 0.86, 0.68)):
    layout['lights'].append({'position': [x, y, z], 'energy': energy, 'range': rng, 'color': list(color)})


def house():
    door_h = 4.0
    xi0, xi1 = HX0 + EXT, HX1 - EXT          # interior faces of the exterior walls
    zi0, zi1 = HZ0 + EXT, HZ1 - EXT
    box('COL_House base', HX0 - 0.4, HX1 + 0.4, -7.0, -0.3, HZ0 - 0.4, HZ1, 'Rubble')
    # Exterior walls: the south face is frescoed where it closes the outer peristyle.
    fresco_band = GX + DEPTH + 0.6
    zs = HZ1 - EXT / 2
    wall('COL_Wall', 'x', zs, HX0, -fresco_band, -0.3, HOUSE_TOP, EXT, 'Plaster', skins=[('Fresco', -1, CEIL)])
    wall('COL_Wall', 'x', zs, -fresco_band, fresco_band, -0.3, HOUSE_TOP, EXT, 'Plaster',
         openings=[(-1.6, 1.6, STYLOBATE, 4.6)], skins=[('Fresco', 1, ENT_TOP - 0.42), ('Fresco', -1, CEIL)])
    wall('COL_Wall', 'x', zs, fresco_band, HX1, -0.3, HOUSE_TOP, EXT, 'Plaster', skins=[('Fresco', -1, CEIL)])
    wall('COL_Wall', 'x', HZ0 + EXT / 2, HX0, HX1, -0.3, HOUSE_TOP, EXT, 'Plaster', skins=[('Fresco', 1, CEIL)])
    wall('COL_Wall', 'z', HX0 + EXT / 2, HZ0 + EXT, HZ1 - EXT, -0.3, HOUSE_TOP, EXT, 'Plaster',
         openings=[(-57.2, -54.8, STYLOBATE, door_h)], skins=[('Fresco', 1, CEIL)])
    wall('COL_Wall', 'z', HX1 - EXT / 2, HZ0 + EXT, HZ1 - EXT, -0.3, HOUSE_TOP, EXT, 'Plaster',
         openings=[(-57.2, -54.8, STYLOBATE, door_h)], skins=[('Fresco', -1, CEIL)])
    # Upper-storey windows all round (the upper floor is not walkable).
    for x in range(-27, 28, 6):
        for z, s in ((HZ1, 1), (HZ0, -1)):
            box('Window', x - 0.7, x + 0.7, 7.9, 9.5, z - 0.02 if s > 0 else z - 0.04, z + 0.04 if s > 0 else z + 0.02, 'Window')
            box('Window frame', x - 0.85, x + 0.85, 7.75, 7.9, z - 0.12, z + 0.12, 'Limestone')
    for z in range(-78, -36, 6):
        for x in (HX0, HX1):
            box('Window', x - 0.04, x + 0.04, 7.9, 9.5, z - 0.7, z + 0.7, 'Window')
            box('Window frame', x - 0.12, x + 0.12, 7.75, 7.9, z - 0.85, z + 0.85, 'Limestone')
    # Cornice round the outer walls only: the inner peristyle and atrium stay open to the sky.
    c0, c1 = HOUSE_TOP, HOUSE_TOP + 0.35
    box('House cornice', HX0 - 0.4, HX1 + 0.4, c0, c1, HZ0 - 0.4, HZ0 + EXT, 'Limestone')
    box('House cornice', HX0 - 0.4, HX1 + 0.4, c0, c1, HZ1 - EXT, HZ1 + 0.4, 'Limestone')
    box('House cornice', HX0 - 0.4, HX0 + EXT, c0, c1, HZ0 + EXT, HZ1 - EXT, 'Limestone')
    box('House cornice', HX1 - EXT, HX1 + 0.4, c0, c1, HZ0 + EXT, HZ1 - EXT, 'Limestone')
    # Interior walls (floor to roof: they carry the ranges' roofs) with doorways.
    top = HOUSE_TOP
    wall('COL_Wall', 'x', SOUTH_RANGE, xi0, xi1, -0.3, top, INT, 'Plaster',
         openings=[(-WING + 0.6, -10.8, STYLOBATE, door_h), (-3.0, 3.0, STYLOBATE, 4.6), (10.8, WING - 0.6, STYLOBATE, door_h)],
         skins=[('Fresco', 1, CEIL), ('Fresco', -1, CEIL)])
    wall('COL_Wall', 'x', NORTH_RANGE, xi0, xi1, -0.3, top, INT, 'Plaster',
         openings=[(-1.5, 1.5, STYLOBATE, door_h)], skins=[('Fresco', 1, CEIL), ('Fresco', -1, CEIL)])
    for sx in (-1, 1):
        wall('COL_Wall', 'z', sx * WING, NORTH_RANGE + INT / 2, SOUTH_RANGE - INT / 2, -0.3, top, INT, 'Plaster',
             openings=[(-57.2, -54.8, STYLOBATE, door_h)], skins=[('Fresco', 1, CEIL), ('Fresco', -1, CEIL)])
        wall('COL_Wall', 'z', sx * 4.0, SOUTH_RANGE + INT / 2, zi1, -0.3, CEIL, INT, 'Plaster',
             openings=[(-39.6, -37.4, STYLOBATE, 3.6)], skins=[('Fresco', 1, CEIL), ('Fresco', -1, CEIL)])
    # Floors and ceilings, room by room.
    room_floor(xi0, xi1, SOUTH_RANGE, zi1, 'Mosaic floor')                       # south range
    ceiling(xi0, xi1, SOUTH_RANGE, zi1)
    room_floor(xi0, xi1, zi0, NORTH_RANGE, 'Mosaic floor')                       # library
    ceiling(xi0, xi1, zi0, NORTH_RANGE)
    room_floor(xi0, -WING, NORTH_RANGE, SOUTH_RANGE, 'Marble floor')             # atrium
    room_floor(WING, xi1, NORTH_RANGE, SOUTH_RANGE, 'Mosaic floor')              # hall of Herakles
    ceiling(WING, xi1, NORTH_RANGE, SOUTH_RANGE)
    atrium(xi0)
    inner_peristyle()
    # Roofs: hipped ranges round the inner court; the atrium wing roof slopes in to its opening.
    hip = 2.8
    kit.hip_roof(HX0, HX1, SOUTH_RANGE, HZ1, HOUSE_TOP + 0.3, hip)
    kit.hip_roof(HX0, HX1, HZ0, NORTH_RANGE, HOUSE_TOP + 0.3, hip)
    kit.hip_roof(WING, HX1, NORTH_RANGE - 0.5, SOUTH_RANGE + 0.5, HOUSE_TOP + 0.3, hip)
    compluviate_roof(HX0, -WING, NORTH_RANGE - 0.5, SOUTH_RANGE + 0.5)
    # Room lights: warm, low, shadowless lamps standing in for daylight bounced through doors.
    for x in (-22, -12, 12, 22):
        light(x, 4.6, -38.2)
    light(0, 4.6, -38.2, 2.2)
    for x in (-24, -12, 0, 12, 24):
        light(x, 4.6, -76.0)
    light(23, 4.8, -50.0)
    light(23, 4.8, -62.0)
    light(-23, 4.8, -46.0, 2.0)
    light(-23, 4.8, -66.0, 2.0)
    layout['rooms'] = {
        'entrance_hall': [-4.0, 4.0, SOUTH_RANGE, zi1], 'west_gallery': [xi0, -4.0, SOUTH_RANGE, zi1],
        'east_gallery': [4.0, xi1, SOUTH_RANGE, zi1], 'library': [xi0, xi1, zi0, NORTH_RANGE],
        'atrium': [xi0, -WING, NORTH_RANGE, SOUTH_RANGE], 'hall_of_herakles': [WING, xi1, NORTH_RANGE, SOUTH_RANGE],
        'inner_peristyle': [-WING, WING, NORTH_RANGE, SOUTH_RANGE]}
    # Steps from the west door down to the theatre lawn, and a ramp out to the east garden.
    stairs(HX0 - 2.6, HX0 - 0.05, -57.2, -54.8, GROUND_Y, STYLOBATE, 'e')
    kit.quad_slab('COL_Ramp', [(HX1, STYLOBATE, -57.2), (HX1, STYLOBATE, -54.8), (HX1 + 1.4, 0.0, -54.8), (HX1 + 1.4, 0.0, -57.2)], 0.2, 'Marble floor')


def atrium(xi0):
    ox0, ox1, oz0, oz1 = ATRIUM_OPEN
    ceiling(xi0, -WING, NORTH_RANGE, SOUTH_RANGE, hole=ATRIUM_OPEN)
    # Light shaft from the ceiling opening up to the roof.
    for x in (ox0, ox1):
        box('Shaft', x - 0.1, x + 0.1, CEIL, HOUSE_TOP + 0.8, oz0, oz1, 'Plaster')
    for z in (oz0, oz1):
        box('Shaft', ox0, ox1, CEIL, HOUSE_TOP + 0.8, z - 0.1, z + 0.1, 'Plaster')
    # Impluvium: a shallow marble basin under the opening, with a column at each corner.
    ix0, ix1, iz0, iz1 = ox0 + 0.6, ox1 - 0.6, oz0 + 0.6, oz1 - 0.6
    box('COL_Impluvium rim', ix0 - 0.35, ix1 + 0.35, STYLOBATE, STYLOBATE + 0.22, iz0 - 0.35, iz0, 'Marble floor')
    box('COL_Impluvium rim', ix0 - 0.35, ix1 + 0.35, STYLOBATE, STYLOBATE + 0.22, iz1, iz1 + 0.35, 'Marble floor')
    box('COL_Impluvium rim', ix0 - 0.35, ix0, STYLOBATE, STYLOBATE + 0.22, iz0, iz1, 'Marble floor')
    box('COL_Impluvium rim', ix1, ix1 + 0.35, STYLOBATE, STYLOBATE + 0.22, iz0, iz1, 'Marble floor')
    box('Impluvium basin', ix0, ix1, STYLOBATE - 0.02, STYLOBATE, iz0, iz1, 'Pool basin')
    layout['pools'].append({'rect': [ix0, ix1, iz0, iz1], 'y': STYLOBATE + 0.12, 'name': 'impluvium'})
    for x in (ox0, ox1):
        for z in (oz0, oz1):
            column(x, z, STYLOBATE, CEIL - STYLOBATE - 0.14, radius=0.36)


def compluviate_roof(x0, x1, z0, z1):
    """Four slopes falling inward from the outer eaves to the atrium's central opening."""
    ox0, ox1, oz0, oz1 = ATRIUM_OPEN
    ov = 0.7
    ex0, ex1, ez0, ez1 = x0 - ov, x1 + ov, z0 - ov, z1 + ov
    hi, lo = HOUSE_TOP + 2.6, HOUSE_TOP + 0.8
    kit.quad_slab('Roof', [(ex0, hi, ez1), (ex1, hi, ez1), (ox1, lo, oz1), (ox0, lo, oz1)], 0.2, 'Roof tiles')
    kit.quad_slab('Roof', [(ex1, hi, ez0), (ex0, hi, ez0), (ox0, lo, oz0), (ox1, lo, oz0)], 0.2, 'Roof tiles')
    kit.quad_slab('Roof', [(ex0, hi, ez0), (ex0, hi, ez1), (ox0, lo, oz1), (ox0, lo, oz0)], 0.2, 'Roof tiles')
    kit.quad_slab('Roof', [(ex1, hi, ez1), (ex1, hi, ez0), (ox1, lo, oz0), (ox1, lo, oz1)], 0.2, 'Roof tiles')


def inner_peristyle():
    cx0, cx1, cz0, cz1 = IPC
    h = 3.9
    # Portico floors all round, a gravel court in the middle.
    room_floor(-WING, WING, NORTH_RANGE, SOUTH_RANGE, 'Marble floor')
    box('COL_Inner court', cx0 + 0.5, cx1 - 0.5, STYLOBATE, STYLOBATE + 0.02, cz0 + 0.5, cz1 - 0.5, 'Gravel')
    nx, nz = 8, 8
    for i in range(nx + 1):
        x = cx0 + (cx1 - cx0) * i / nx
        column(x, cz0, STYLOBATE, h, radius=0.34)
        column(x, cz1, STYLOBATE, h, radius=0.34)
    for i in range(1, nz):
        z = cz0 + (cz1 - cz0) * i / nz
        column(cx0, z, STYLOBATE, h, radius=0.34)
        column(cx1, z, STYLOBATE, h, radius=0.34)
    top = STYLOBATE + h + 0.12
    for z in (cz0, cz1):
        box('Architrave', cx0 - 0.4, cx1 + 0.4, top, top + 0.45, z - 0.36, z + 0.36, 'Limestone')
    for x in (cx0, cx1):
        box('Architrave', x - 0.36, x + 0.36, top, top + 0.45, cz0 - 0.4, cz1 + 0.4, 'Limestone')
    # Portico ceilings and shed roofs falling toward the court.
    eave, high = top + 0.5, top + 2.0
    w, n_ = WING - INT / 2, NORTH_RANGE + INT / 2
    s_ = SOUTH_RANGE - INT / 2
    box('Ceiling', -w, w, top + 0.3, top + 0.45, cz1 + 0.36, s_, 'Timber')
    box('Ceiling', -w, w, top + 0.3, top + 0.45, n_, cz0 - 0.36, 'Timber')
    box('Ceiling', -w, cx0 - 0.36, top + 0.3, top + 0.45, cz0 - 0.36, cz1 + 0.36, 'Timber')
    box('Ceiling', cx1 + 0.36, w, top + 0.3, top + 0.45, cz0 - 0.36, cz1 + 0.36, 'Timber')
    kit.shed_roof(-w, w, cz1 - 0.2, s_, eave, high, 's', overhang=0.5)
    kit.shed_roof(-w, w, n_, cz0 + 0.2, eave, high, 'n', overhang=0.5)
    kit.shed_roof(-w, cx0 + 0.2, cz0 + 0.2, cz1 - 0.2, eave, high, 'w', overhang=0.5)
    kit.shed_roof(cx1 - 0.2, w, cz0 + 0.2, cz1 - 0.2, eave, high, 'e', overhang=0.5)
    # The long narrow pool on the axis, with marble coping, and hedged lawns either side.
    x0, x1, z0, z1 = IPOOL
    for (a, b, c, d) in [(x0 - 0.45, x1 + 0.45, z0 - 0.45, z0), (x0 - 0.45, x1 + 0.45, z1, z1 + 0.45),
                         (x0 - 0.45, x0, z0, z1), (x1, x1 + 0.45, z0, z1)]:
        box('COL_Coping', a, b, STYLOBATE, STYLOBATE + 0.3, c, d, 'Marble floor')
    box('Pool floor', x0, x1, STYLOBATE - 0.02, STYLOBATE, z0, z1, 'Pool basin')
    layout['pools'].append({'rect': [x0, x1, z0, z1], 'y': STYLOBATE + 0.22, 'name': 'inner_peristyle'})
    for sx in (-1, 1):
        bx0, bx1 = sorted([sx * 3.4, sx * 8.6])
        box('Bed earth', bx0, bx1, STYLOBATE, STYLOBATE + 0.03, -63.5, -48.5, 'Lawn')
        layout['beds'].append({'rect': [bx0, bx1, -63.5, -48.5], 'y': STYLOBATE + 0.03, 'zone': 'inner'})
        hedged_bed(bx0, bx1, -63.5, -48.5, 0.48, base_y=STYLOBATE, thickness=0.4, gap=0.7)


# ---------------------------------------------------------------- gardens and theatre
def east_garden():
    x0, x1, z0, z1 = EG
    box('COL_Garden base', x0, x1 + 0.4, -7.0, 0.0, z0 - 0.4, z1 + 0.4, 'Rubble')
    box('COL_Garden ground', x0, x1, -0.2, 0.0, z0, z1, 'Gravel')
    wall_h = 3.4
    gate = ((42.0, 45.0, 0.0, 2.9),)
    wall('COL_Garden wall', 'x', z0 - 0.2, x0, x1 + 0.4, -0.3, wall_h, 0.4, 'Plaster', skins=[('Fresco', 1, 2.9)])
    wall('COL_Garden wall', 'x', z1 + 0.2, x0, x1 + 0.4, -0.3, wall_h, 0.4, 'Plaster', openings=gate, skins=[('Fresco', -1, 2.9)])
    wall('COL_Garden wall', 'z', x1 + 0.2, z0, z1, -0.3, wall_h, 0.4, 'Plaster', skins=[('Fresco', -1, 2.9)])
    for (a, b, c, d) in [(x0, x1 + 0.4, z0 - 0.45, z0 + 0.05), (x0, x1 + 0.4, z1 - 0.05, z1 + 0.45), (x1 - 0.05, x1 + 0.45, z0, z1)]:
        box('Coping', a, b, wall_h, wall_h + 0.12, c, d, 'Roof tiles')
    # Round fountain: a low basin wall and a central pedestal bowl.
    cx, cz, r = EG_FOUNTAIN
    seg = 28
    for i in range(seg):
        a0, a1 = i * math.tau / seg, (i + 1) * math.tau / seg
        kit.arc_band('COL_Fountain rim', cx, cz, r - 0.3, r, math.degrees(a0), math.degrees(a1), 0.0, 0.55, 'Marble floor', segments=2)
    box('Fountain floor', cx - r, cx + r, -0.15, -0.12, cz - r, cz + r, 'Pool basin')
    kit.lathe('COL_Fountain pedestal', cx, -0.15, cz, [(0.0, 0.45), (0.9, 0.3), (1.1, 0.22), (1.25, 0.9), (1.38, 1.05), (1.45, 1.05), (1.5, 0.2), (1.9, 0.12)], 'Marble floor', segments=28)
    layout['fountains'].append({'centre': [cx, cz], 'radius': r - 0.3, 'y': 0.38, 'jet': [cx, 1.9, cz]})
    # A lion-head wall fountain on the north wall, spilling into a half basin.
    box('COL_Wall basin', 41.6, 46.4, 0.0, 0.7, z0 + 0.05, z0 + 1.1, 'Marble floor')
    box('Wall basin water bed', 41.8, 46.2, 0.0, 0.5, z0 + 0.05, z0 + 0.95, 'Pool basin')
    box('Mosaic niche', 41.0, 47.0, 0.7, 3.0, z0 + 0.0, z0 + 0.05, 'Mosaic wall')
    layout['pools'].append({'rect': [41.8, 46.2, z0 + 0.05, z0 + 0.95], 'y': 0.62, 'name': 'wall_fountain'})
    layout['spouts'].append({'at': [44.0, 1.05, z0 + 0.12], 'yaw': 0.0, 'pedestal': False, 'water_y': 0.62})
    # Hedged corner beds and gravel walks in a cross.
    for bx0, bx1 in [(x0 + 1.0, cx - 4.5), (cx + 4.5, x1 - 1.0)]:
        for bz0, bz1 in [(z0 + 2.0, cz - 4.5), (cz + 4.5, z1 - 1.0)]:
            box('Bed earth', bx0, bx1, 0.0, 0.03, bz0, bz1, 'Soil')
            layout['beds'].append({'rect': [bx0, bx1, bz0, bz1], 'y': 0.03, 'zone': 'east'})
            hedged_bed(bx0, bx1, bz0, bz1, 0.55, thickness=0.45)
    # Stone benches along the walls.
    for x in (36.0, 52.0):
        box('COL_Bench', x - 1.2, x + 1.2, 0.0, 0.45, z0 + 0.4, z0 + 0.95, 'Limestone')
    # Gate steps down to the herb garden's top terrace.
    stairs(42.0, 45.0, z1 + 0.45, z1 + 2.6, TERRACES[0][2], 0.0, 'n')


def herb_garden():
    x0, x1 = HERB_X
    for i, (z0, z1, y) in enumerate(TERRACES):
        box('COL_Terrace ground', x0, x1, y - 0.25, y, z0, z1, 'Soil')
        box('COL_Terrace wall', x0, x1 + 0.6, -9.0, y, z1 - 0.01 if i == len(TERRACES) - 1 else z1 - 0.6, z1, 'Rubble')
        box('COL_Terrace wall', x1, x1 + 0.6, -9.0, y, z0, z1, 'Rubble')
        box('COL_Parapet', x1, x1 + 0.6, y, y + 0.9, z0, z1, 'Rubble')
        box('Coping', x1 - 0.05, x1 + 0.65, y + 0.9, y + 1.0, z0, z1, 'Limestone')
        # Gravel paths along the middle and the edges, beds between.
        box('Path', x0, x1, y, y + 0.02, (z0 + z1) / 2 - 1.0, (z0 + z1) / 2 + 1.0, 'Gravel')
        box('Path', 40.0, 43.0, y, y + 0.02, z0, z1, 'Gravel')
        for (bx0, bx1) in [(x0 + 1.5, 39.0), (44.0, x1 - 1.5)]:
            for (bz0, bz1) in [(z0 + 1.2, (z0 + z1) / 2 - 1.6), ((z0 + z1) / 2 + 1.6, z1 - 1.4)]:
                layout['beds'].append({'rect': [bx0, bx1, bz0, bz1], 'y': y, 'zone': f'herb{i + 1}'})
        if i < len(TERRACES) - 1:
            nxt = TERRACES[i + 1][2]
            stairs(40.0, 43.0, z1, z1 + 2.4, nxt, y, 'n')
    # The top terrace runs on north past the house to the east garden's gate.
    y1 = TERRACES[0][2]
    box('COL_Terrace ground', HX1 + 0.4, x1, y1 - 0.25, y1, EG[3] + 0.4, TERRACES[0][0], 'Soil')
    box('COL_Terrace wall', x1, x1 + 0.6, -9.0, y1, EG[3] + 0.4, TERRACES[0][0], 'Rubble')
    box('COL_Parapet', x1, x1 + 0.6, y1, y1 + 0.9, EG[3] + 0.4, TERRACES[0][0], 'Rubble')
    box('COL_Parapet', EG[1] + 0.4, x1 + 0.6, y1, y1 + 0.9, EG[3] + 0.4, EG[3] + 1.0, 'Rubble')
    box('Path', 40.0, 43.0, y1, y1 + 0.02, EG[3] + 2.6, TERRACES[0][0], 'Gravel')
    # The south terrace ends in a parapet over the bluff.
    z1, y = TERRACES[-1][1], TERRACES[-1][2]
    box('COL_Parapet', x0, x1 + 0.6, y, y + 0.9, z1 - 0.6, z1, 'Rubble')
    box('Coping', x0, x1 + 0.65, y + 0.9, y + 1.0, z1 - 0.65, z1 + 0.05, 'Limestone')
    # The west side of the terraces meets the court's platform; close the gap below the court.
    box('COL_Terrace wall', x0 - 0.3, x0, -9.0, 0.0, TERRACES[0][0], TERRACES[-1][1], 'Rubble')


def theatre():
    cx, cz, r0, r1, rows = THEATRE
    floor = GROUND_Y + 0.15
    kit.arc_band('COL_Orchestra', cx, cz, 0.0, r0, 90, 270, GROUND_Y - 0.3, floor, 'Marble floor', segments=24)
    box('COL_Stage', cx - 0.5, cx + 3.0, GROUND_Y - 0.3, floor + 0.6, cz - 7.0, cz + 7.0, 'Marble floor')
    depth = (r1 - r0) / rows
    rise = 0.42
    for k in range(rows):
        a, b = r0 + k * depth, r0 + (k + 1) * depth
        top = floor + rise * (k + 1)
        for a0, a1 in [(92, 175), (185, 268)]:  # leave the central aisle open
            kit.arc_band('COL_Seats', cx, cz, a, b, a0, a1, GROUND_Y - 0.3, top, 'Limestone', segments=10)
    # The aisle: steps up the middle (due west of the orchestra).
    stairs(cx - r1, cx - r0, cz - 1.15, cz + 1.15, floor, floor + rise * rows, 'w', mat='Limestone', steps=rows * 2)
    kit.arc_band('COL_Theatre wall', cx, cz, r1, r1 + 0.6, 88, 272, GROUND_Y - 0.3, floor + rise * rows + 1.0, 'Rubble', segments=24)
    layout['theatre'] = {'centre': [cx, cz], 'radii': [r0, r1], 'rows': rows, 'floor': floor, 'rise': rise}


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    kit.reset()
    OUT.mkdir(parents=True, exist_ok=True)
    SOURCE.mkdir(parents=True, exist_ok=True)
    leaf_atlas(OUT / 'hedge_leaves.png', OUT / 'hedge_leaves_n.png')
    outer_peristyle()
    house()
    east_garden()
    herb_garden()
    theatre()
    cards = hedges.finish()
    joined = kit.join_by_material()
    leaves = sum(len(o.data.polygons) for o in joined if o.name == 'ART_Hedge_leaves')
    triangles = sum(len(o.data.polygons) for o in joined) - leaves
    assert triangles < 400_000, f'Villa architecture budget exceeded: {triangles}'
    kit.export(joined, OUT / 'villa_estate.glb')
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE / 'villa_estate.blend'))
    bake_pool(OUT, POOL, POOL_FLOOR, WATER_Y, ramp_length=POOL_RAMP_LENGTH)
    layout.update({
        'court': [-GX, GX, GZ0, GZ1], 'depth': DEPTH, 'stylobate': STYLOBATE, 'pool': POOL,
        'water_y': WATER_Y, 'pool_floor': POOL_FLOOR, 'pool_ramp_length': POOL_RAMP_LENGTH, 'house': [HX0, HX1, HZ0, HZ1], 'east_garden': list(EG),
        'terraces': [[HERB_X[0], HERB_X[1], z0, z1, y] for z0, z1, y in TERRACES], 'ground_y': GROUND_Y,
        'side_doors': list(SIDE_DOOR)})
    (OUT / 'villa_layout.json').write_text(json.dumps(layout, indent=1))
    print(f'CONSTRUCT_VILLA_OK: {triangles} architecture triangles in {len(joined)} meshes, '
          f'{cards} hedge cards ({leaves} triangles)')


main()
