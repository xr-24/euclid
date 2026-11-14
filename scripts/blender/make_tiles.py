"""Generate tiled PBR texture sets (pool mosaics, glazed and patterned tiles) that Poly Haven does not have.

Runs under Blender (bpy saves the images) or plain Python with numpy and Pillow:
    blender --background --factory-startup --python scripts/blender/make_tiles.py [-- id ...]

Each set is written to world/assets/generated/textures/<id>/<id>_{diff,nor_gl,arm}_2k.png, the layout the
texture library reads (world/scripts/world_art.gd). The textures are generated here, so they carry no
third-party licence. A set's "repeat" is the metres one image covers: use it as texture_size.
"""
import math
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'world/assets/generated/textures'
SIZE = 2048

SETS = {
    # Glass mosaics, 25 mm chips: 32 across one 0.8 m repeat.
    'pool_mosaic_blue': {'tiles': 32, 'grout': 0.11, 'grout_color': '#c9cdcf', 'gloss': 0.07, 'bevel': 0.22,
                         'palette': ['#1d5f9e', '#2470b4', '#2f7fc2', '#3a8fd0', '#1a548c', '#4a9cd8', '#2a78b9']},
    'pool_mosaic_aqua': {'tiles': 32, 'grout': 0.11, 'grout_color': '#d3d8d8', 'gloss': 0.07, 'bevel': 0.22,
                         'palette': ['#3db4c6', '#55c4d2', '#2ba2b6', '#76d0da', '#9edde2', '#46bccb', '#3399ad']},
    'pool_mosaic_midnight': {'tiles': 32, 'grout': 0.11, 'grout_color': '#3b4045', 'gloss': 0.08, 'bevel': 0.22,
                             'palette': ['#262c31', '#2f363c', '#20262b', '#384148', '#2a3238', '#1c2226', '#34404a']},
    'pool_mosaic_sand': {'tiles': 32, 'grout': 0.11, 'grout_color': '#d9d6cf', 'gloss': 0.09, 'bevel': 0.22,
                         'palette': ['#e9e3d5', '#f2ede3', '#ddd3c1', '#e4dccb', '#f5f1ea', '#d6cbb8']},
    # A waterline blend: deep blues and pearl with the odd gold chip.
    'pool_waterline_glass': {'tiles': 32, 'grout': 0.11, 'grout_color': '#c4c9cc', 'gloss': 0.05, 'bevel': 0.22,
                             'palette': ['#123f66', '#1b5687', '#2a6fa8', '#e6ecef', '#cfdbe2', '#174c79', '#e6ecef'],
                             'accent': '#c9a35a', 'accent_share': 0.04},
    # Glazed 150 mm tiles: 8 across one 1.2 m repeat.
    'pool_tile_white': {'tiles': 8, 'grout': 0.02, 'grout_color': '#b9bec1', 'gloss': 0.06, 'bevel': 0.04,
                        'palette': ['#f4f6f6', '#eff2f3', '#f7f8f8', '#ebeff0']},
    'pool_tile_blue': {'tiles': 8, 'grout': 0.02, 'grout_color': '#c3c9cc', 'gloss': 0.06, 'bevel': 0.04,
                       'palette': ['#4f86b8', '#4a81b3', '#5590c2', '#4679ab']},
    # Hand-painted Talavera-style tiles, 150 mm: 4 across one 0.6 m repeat.
    'pool_tile_talavera': {'tiles': 4, 'grout': 0.02, 'grout_color': '#cfc8b8', 'gloss': 0.1, 'bevel': 0.035,
                           'palette': ['#f1ead9', '#efe6d2', '#f3eddf'], 'pattern': 'talavera',
                           'ink': '#1f4e9a', 'ink2': '#d9a23a'},
}


def rgb(value):
    value = value.lstrip('#')
    return np.array([int(value[i:i + 2], 16) / 255.0 for i in (0, 2, 4)], dtype=np.float32)


def make(spec, seed):
    rng = np.random.default_rng(seed)
    n = int(spec['tiles'])
    cell = SIZE / n
    ys, xs = np.mgrid[0:SIZE, 0:SIZE].astype(np.float32)
    tx = np.floor(xs / cell).astype(np.int32) % n
    ty = np.floor(ys / cell).astype(np.int32) % n
    u = xs / cell - np.floor(xs / cell)  # 0..1 within the tile
    v = ys / cell - np.floor(ys / cell)
    grout = float(spec['grout']) * 0.5
    edge = np.minimum(np.minimum(u, 1 - u), np.minimum(v, 1 - v))  # distance to the tile's edge
    inside = edge > grout
    bevel = float(spec['bevel'])
    height = np.clip((edge - grout) / max(bevel, 1e-3), 0, 1)
    height = np.where(inside, np.sin(height * math.pi * 0.5), 0.0).astype(np.float32)
    # Each tile: a colour from the palette, a little brightness jitter and a slight tilt.
    palette = np.stack([rgb(c) for c in spec['palette']])
    pick = rng.integers(0, len(palette), size=(n, n))
    colours = palette[pick]
    if 'accent' in spec:
        colours[rng.random((n, n)) < float(spec['accent_share'])] = rgb(spec['accent'])
    colours *= (1.0 + rng.normal(0.0, 0.035, size=(n, n, 1))).astype(np.float32)
    albedo = colours[ty, tx]
    tilt_x = rng.normal(0.0, 0.08, size=(n, n)).astype(np.float32)[ty, tx]
    tilt_y = rng.normal(0.0, 0.08, size=(n, n)).astype(np.float32)[ty, tx]
    height = height + np.where(inside, (u - 0.5) * tilt_x + (v - 0.5) * tilt_y, 0.0) * 0.4
    # Fine glaze mottling.
    noise = rng.normal(0.0, 1.0, size=(SIZE // 8, SIZE // 8)).astype(np.float32)
    noise = np.kron(noise, np.ones((8, 8), dtype=np.float32))
    noise = (noise + np.roll(noise, 4, 0) + np.roll(noise, 4, 1) + np.roll(np.roll(noise, 4, 0), 4, 1)) * 0.25
    albedo = albedo * (1.0 + noise[..., None] * 0.025)
    if spec.get('pattern') == 'talavera':
        albedo = talavera(albedo, u, v, inside, spec)
    grout_rgb = rgb(spec['grout_color'])
    albedo = np.where(inside[..., None], albedo, grout_rgb * (1.0 + noise[..., None] * 0.05))
    # Normal (OpenGL: green points up the image) from the height field.
    strength = 3.0 * n / 32.0 + 1.0
    dx = (np.roll(height, -1, 1) - np.roll(height, 1, 1)) * 0.5 * strength
    dy = (np.roll(height, -1, 0) - np.roll(height, 1, 0)) * 0.5 * strength
    normal = np.stack([-dx, dy, np.ones_like(dx)], axis=-1)
    normal /= np.linalg.norm(normal, axis=-1, keepdims=True)
    normal = normal * 0.5 + 0.5
    # ARM: ambient occlusion, roughness, metallic.
    ao = np.where(inside, 1.0, 0.72) * (0.92 + 0.08 * np.clip(height, 0, 1))
    rough = np.where(inside, float(spec['gloss']) + noise * 0.02, 0.85)
    arm = np.stack([ao, rough, np.zeros_like(ao)], axis=-1)
    return np.clip(albedo, 0, 1), np.clip(normal, 0, 1), np.clip(arm, 0, 1)


def talavera(albedo, u, v, inside, spec):
    """A blue quatrefoil rosette with gold centres and corner quarter-motifs, mirrored on every tile."""
    ink = rgb(spec['ink'])
    ink2 = rgb(spec['ink2'])
    x = u - 0.5
    y = v - 0.5
    r = np.sqrt(x * x + y * y)
    angle = np.arctan2(y, x)
    petals = 0.27 + 0.1 * np.cos(4.0 * angle)
    rosette = (r < petals) & (r > petals - 0.045)
    centre = r < 0.07
    ring = (r > 0.1) & (r < 0.125)
    cx = np.minimum(np.abs(u), np.abs(1 - u))
    cy = np.minimum(np.abs(v), np.abs(1 - v))
    corner = np.sqrt(cx * cx + cy * cy)
    corners = (corner < 0.2) & (corner > 0.14)
    border = (np.minimum(np.minimum(u, 1 - u), np.minimum(v, 1 - v)) > 0.045) & \
        (np.minimum(np.minimum(u, 1 - u), np.minimum(v, 1 - v)) < 0.06)
    out = albedo.copy()
    for mask, colour in ((rosette | corners | border, ink), (centre | ring, ink2)):
        out = np.where((mask & inside)[..., None], colour * (0.95 + 0.05 * albedo), out)
    return out


def save(array, path, srgb):
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        import bpy
    except ImportError:
        bpy = None
    if bpy is None:
        from PIL import Image
        Image.fromarray((array * 255.0 + 0.5).astype(np.uint8), 'RGB').save(path)
        return
    image = bpy.data.images.new(path.stem, SIZE, SIZE, alpha=False)
    image.colorspace_settings.name = 'Non-Color'  # values are written as given
    rgba = np.concatenate([array, np.ones(array.shape[:2] + (1,), dtype=np.float32)], axis=-1)
    image.pixels.foreach_set(np.flipud(rgba).astype(np.float32).ravel())
    image.filepath_raw = str(path)
    image.file_format = 'PNG'
    image.save()
    bpy.data.images.remove(image)


def main():
    args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
    ids = [a for a in args if a in SETS] or list(SETS)
    for index, name in enumerate(ids):
        albedo, normal, arm = make(SETS[name], 1000 + sorted(SETS).index(name))
        folder = OUT / name
        save(albedo, folder / f'{name}_diff_2k.png', True)
        save(normal, folder / f'{name}_nor_gl_2k.png', False)
        save(arm, folder / f'{name}_arm_2k.png', False)
        print('CONSTRUCT_TILES', name, flush=True)
    print('CONSTRUCT_TILES_OK', len(ids), flush=True)


main()
