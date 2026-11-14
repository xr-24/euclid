"""Download the CC0 Poly Haven assets used by the villa and beach art pass.

Runs with any Python 3 (Blender's bundled Python works):
    blender --background --factory-startup --python scripts/blender/fetch_polyhaven.py

Everything is cached: re-running only downloads what is missing.
- HDRIs and PBR texture sets go straight into the Godot project (world/assets/thirdparty/polyhaven).
- Raw scanned models (often millions of polygons) go to .local/polyhaven/models, outside Git and Godot.
  scripts/blender/optimize_models.py turns them into real-time GLBs.
All Poly Haven assets are CC0 (https://polyhaven.com/license).
"""
import json
import os
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GODOT_ASSETS = ROOT / 'world/assets/thirdparty/polyhaven'
RAW_MODELS = ROOT / '.local/polyhaven/models'
API = 'https://api.polyhaven.com'
HEADERS = {'User-Agent': 'Construct-asset-build'}

HDRIS = {
    # Bright Mediterranean midday with towering cumulus for the villa courtyard.
    'kloofendal_48d_partly_cloudy_puresky': '4k',
    # Low golden sun over the sea for the shore.
    'kloppenheim_06_puresky': '4k',
}
TEXTURES = {
    'floor_tiles_02': '2k',        # travertine courtyard paving
    'marble_rock_02': '2k',        # columns, trims, cornices
    'patterned_clay_plaster': '2k',  # warm lime plaster for walls, ceilings and terracotta
    'clay_roof_tiles_02': '2k',    # roof coping
    'granite_tile': '2k',          # dark inlays and the pool basin
    'brown_mud_leaves_01': '1k',   # planter earth
    'aerial_beach_01': '2k',       # wind-rippled dry sand (30 m scan)
    'damp_beach_sand': '2k',       # wet sand at the waterline
    'coast_sand_rocks_02': '2k',   # pebbly sand near rocks
    'oak_wood_planks': '2k',       # desk and boardwalk timber
    # Roman villa
    'red_plaster_weathered': '2k', # Pompeian red fresco ground
    'gravel_ground_01': '2k',      # garden paths
    'forest_leaves_02': '2k',      # clipped hedges
    'aerial_grass_rock': '2k',     # hillside
    'dry_ground_01': '2k',         # hillside soil
    'marble_01': '2k',             # portico floors and pool coping
    'white_plaster_02': '2k',      # house walls
    'dark_wooden_planks': '2k',    # doors and portico ceilings
    # Coastal bluff and the whole villa
    'cliff_side': '2k',            # sandstone bluff faces
    'rocky_terrain_02': '2k',      # broken ground and cliff tops
    'sparse_grass': '2k',          # dry coastal grassland
    'coast_sand_01': '2k',         # the cove beach
    'old_mosaic_floor': '2k',      # house floors
    'marble_mosaic_tiles': '2k',   # mosaic niches and fountain
    'sandstone_blocks_08': '2k',   # retaining walls and foundations
    'leafy_grass': '2k',           # lawns in the inner peristyle
    # House wall finishes (world/data/pieces/finishes.json names these).
    'plastered_wall_04': '2k', 'white_stucco': '2k', 'beige_wall_001': '2k',
    'plaster_grey_04': '2k', 'whitewashed_brick': '2k', 'brick_wall_001': '2k', 'large_red_bricks': '2k',
    'white_planks_clean': '2k', 'wooden_panels': '2k', 'long_white_tiles': '2k', 'rounded_square_tiled_wall': '2k',
    'stone_tile_wall': '2k', 'terrazzo_tiles': '2k', 'granite_tile_03': '2k', 'concrete_slab_wall': '2k',
    'exterior_wall_cladding_03': '2k', 'stacked_stone_wall': '2k', 'weathered_plank_siding': '2k',
    # Floor finishes: carpets (fabric scans), tiles, wood and pool-deck paving.
    'curly_teddy_natural': '2k', 'hessian_230': '2k', 'knitted_fleece': '2k', 'poly_wool_herringbone': '2k',
    'large_floor_tiles_02': '2k', 'patio_tiles': '2k', 'interior_tiles': '2k', 'terracotta_floor_tiles': '2k',
    'patterned_terracotta_tiling': '2k', 'floor_tiles_08': '2k', 'square_tiles': '2k', 'marble_tiles': '2k',
    'slate_floor_02': '2k', 'herringbone_parquet': '2k', 'laminate_floor_02': '2k', 'wood_floor': '2k',
    'rectangular_paving': '2k', 'precast_stone_paving': '2k', 'large_square_pattern_01': '2k', 'stone_pavers': '2k',
}
TEXTURE_MAPS = {'Diffuse': 'diff', 'nor_gl': 'nor_gl', 'arm': 'arm'}
MODELS = [
    # Villa
    'tree_small_02', 'potted_plant_01', 'potted_plant_02', 'antique_ceramic_vase_01',
    'marble_bust_01', 'classic_laptop', 'round_wooden_table_01', 'shrub_sorrel_01',
    # Shore
    'island_tree_03', 'island_tree_02', 'coast_rocks_05', 'sand_rocks_small_01', 'coast_land_rocks_03',
    'modular_wooden_pier', 'lambis_shell', 'outdoor_table_chair_set_01',
    'wooden_lantern_01', 'wine_barrel_01', 'wooden_crate_01', 'ocean_buoy',
    # Roman villa
    'jacaranda_tree', 'island_tree_01', 'searsia_lucida', 'shrub_01', 'shrub_03', 'lion_head',
    'horse_statue_01',
    # Coastal bluff planting and rocks
    'crystalline_iceplant', 'cheiridopsis_succulent', 'flower_gazania', 'shrub_02', 'shrub_04',
    'wild_rooibos_bush', 'grass_medium_02', 'rock_face_01', 'rock_face_02', 'boulder_01',
    'coastal_cliff_01', 'coast_line_02', 'searsia_burchellii', 'wooden_bookshelf_worn',
] + [
    # House furnishings (world/data/pieces/house_furnishings.json picks among these).
    'sofa_02', 'sofa_03', 'modern_arm_chair_01', 'mid_century_lounge_chair', 'Ottoman_01', 'GreenChair_01',
    'modern_coffee_table_01', 'coffee_table_round_01', 'CoffeeTable_01', 'side_table_01', 'side_table_tall_01',
    'dining_chair_02', 'bar_chair_round_01', 'modern_wooden_cabinet', 'drawer_cabinet', 'vintage_cabinet_01',
    'wooden_display_shelves_01', 'steel_frame_shelves_03', 'Shelf_01', 'painted_wooden_nightstand',
    'ClassicNightstand_01', 'modern_ceiling_lamp_01', 'hanging_picture_frame_01', 'hanging_picture_frame_02',
    'hanging_picture_frame_03', 'ceiling_fan',
]


def get_json(path):
    with urllib.request.urlopen(urllib.request.Request(API + path, headers=HEADERS), timeout=60) as r:
        return json.loads(r.read())


def download(url, dest, size=None):
    dest = Path(dest)
    if dest.exists() and (size is None or dest.stat().st_size == size):
        return False
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_suffix(dest.suffix + '.part')
    with urllib.request.urlopen(urllib.request.Request(url, headers=HEADERS), timeout=300) as r, open(tmp, 'wb') as f:
        while chunk := r.read(1 << 20):
            f.write(chunk)
    os.replace(tmp, dest)
    return True


def fetch_model(asset):
    files = get_json('/files/' + asset)
    gltf = files['gltf']['2k']['gltf']
    folder = RAW_MODELS / asset
    download(gltf['url'], folder / Path(gltf['url']).name, gltf['size'])
    for rel, info in gltf.get('include', {}).items():
        download(info['url'], folder / rel, info['size'])
    alpha = files.get('Alpha', {}).get('2k', {}).get('jpg')
    if alpha:
        download(alpha['url'], folder / 'textures' / f'{asset}_alpha_2k.jpg', alpha['size'])
    print('MODEL', asset, flush=True)


def fetch_models_only():
    """Fetch just the model ids given after "--" (no HDRIs, textures or credits rewrite)."""
    ids = sys.argv[sys.argv.index('--') + 1:]
    for asset in ids:
        fetch_model(asset)
    print('CONSTRUCT_FETCH_OK', len(ids), flush=True)


def fetch_textures_only():
    """Fetch just the texture sets (after "-- --textures"), without HDRIs, models or a credits rewrite."""
    for asset, res in TEXTURES.items():
        files = get_json('/files/' + asset)
        for key, suffix in TEXTURE_MAPS.items():
            info = files[key][res]['jpg']
            download(info['url'], GODOT_ASSETS / 'textures' / asset / f'{asset}_{suffix}_{res}.jpg', info['size'])
        print('TEXTURE', asset, flush=True)
    print('CONSTRUCT_FETCH_OK', len(TEXTURES), flush=True)


def main():
    credits = []
    if '--textures' in sys.argv:
        return fetch_textures_only()
    if '--' in sys.argv:
        return fetch_models_only()
    for asset, res in HDRIS.items():
        info = get_json('/files/' + asset)['hdri'][res]['hdr']
        download(info['url'], GODOT_ASSETS / 'hdri' / f'{asset}_{res}.hdr', info['size'])
        credits.append(asset)
        print('HDRI', asset, flush=True)
    for asset, res in TEXTURES.items():
        files = get_json('/files/' + asset)
        for key, suffix in TEXTURE_MAPS.items():
            info = files[key][res]['jpg']
            download(info['url'], GODOT_ASSETS / 'textures' / asset / f'{asset}_{suffix}_{res}.jpg', info['size'])
        credits.append(asset)
        print('TEXTURE', asset, flush=True)
    for asset in MODELS:
        files = get_json('/files/' + asset)
        gltf = files['gltf']['2k']['gltf']
        folder = RAW_MODELS / asset
        download(gltf['url'], folder / Path(gltf['url']).name, gltf['size'])
        for rel, info in gltf.get('include', {}).items():
            download(info['url'], folder / rel, info['size'])
        # Leaf cards keep their cut-out in a separate alpha map (the glTF's colour maps are JPEG).
        alpha = files.get('Alpha', {}).get('2k', {}).get('jpg')
        if alpha:
            download(alpha['url'], folder / 'textures' / f'{asset}_alpha_2k.jpg', alpha['size'])
        credits.append(asset)
        print('MODEL', asset, flush=True)
    (GODOT_ASSETS / 'CREDITS.md').write_text(
        '# Poly Haven assets\n\nAll assets in this folder come from https://polyhaven.com and are CC0 '
        '(public domain, no attribution required). Models were decimated for real time by '
        'scripts/blender/optimize_models.py.\n\n' + '\n'.join(f'- https://polyhaven.com/a/{a}' for a in credits) + '\n',
        encoding='utf-8')
    print('CONSTRUCT_FETCH_OK', len(credits), flush=True)


if __name__ == '__main__':
    try:
        main()
    except Exception as exc:  # surface failures as a non-zero exit for build-assets.ps1
        print('CONSTRUCT_FETCH_FAILED', exc, flush=True)
        sys.exit(1)
