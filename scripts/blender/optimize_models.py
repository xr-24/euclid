"""Turn raw Poly Haven scans into real-time GLBs for Godot. Run in a disposable Blender only:
    blender --background --factory-startup --python scripts/blender/optimize_models.py [-- asset_id ...]

For each asset: import the cached glTF, flatten transforms, reduce to a triangle budget, put the
origin at the centre of the footprint on the ground, downsize textures, and export a GLB into
world/assets/thirdparty/polyhaven/models. Foliage is reduced by collapsing every leaf to a few
triangles and then thinning whole leaves (each survivor grows slightly to keep canopy density),
which keeps leaf silhouettes intact instead of melting them like a plain decimate would.
"""
import json
import sys
from pathlib import Path

import bpy
import bmesh
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / '.local/polyhaven/models'
OUT = ROOT / 'world/assets/thirdparty/polyhaven/models'
OUT.mkdir(parents=True, exist_ok=True)

# Triangle budgets and maximum texture edge per asset. Unlisted assets keep their geometry.
BUDGETS = {
    'tree_small_02': (180_000, 2048),
    'island_tree_01': (260_000, 2048),
    'island_tree_02': (220_000, 2048),
    'island_tree_03': (280_000, 2048),
    'coast_rocks_05': (45_000, 2048),
    'sand_rocks_small_01': (45_000, 2048),
    'coast_land_rocks_03': (70_000, 2048),
    'grass_bermuda_01': (70_000, 1024),
    'potted_plant_01': (70_000, 2048),
    'potted_plant_02': (70_000, 2048),
    'modular_wooden_pier': (90_000, 2048),
    'jacaranda_tree': (220_000, 2048),
    'searsia_lucida': (70_000, 2048),
    'shrub_01': (40_000, 1024),
    'shrub_03': (40_000, 1024),
    # Coastal bluff: many instances, so lean budgets (they fade out with distance in the game)
    'crystalline_iceplant': (6_000, 1024),
    'cheiridopsis_succulent': (8_000, 1024),
    'flower_gazania': (5_000, 1024),
    'shrub_02': (16_000, 1024),
    'shrub_04': (6_000, 1024),
    'wild_rooibos_bush': (10_000, 1024),
    'grass_medium_02': (12_000, 1024),
    'rock_face_01': (14_000, 2048),
    'rock_face_02': (14_000, 2048),
    'boulder_01': (8_000, 2048),
    'coastal_cliff_01': (120_000, 2048),
    'coast_line_02': (120_000, 2048),
    'searsia_burchellii': (60_000, 2048),
    # House furnishings: seen up close indoors, so keep shape but cap the heavy ones.
    'dining_chair_02': (8_000, 1024),
    'bar_chair_round_01': (6_000, 1024),
    'modern_wooden_cabinet': (12_000, 2048),
    'drawer_cabinet': (12_000, 2048),
    'vintage_cabinet_01': (20_000, 2048),
    'modern_arm_chair_01': (9_000, 2048),
    'mid_century_lounge_chair': (7_000, 2048),
    'sofa_03': (8_000, 2048),
    'modern_coffee_table_02': (8_000, 1024),
    'CoffeeTable_01': (8_000, 1024),
    'side_table_tall_01': (5_000, 1024),
    'steel_frame_shelves_03': (8_000, 1024),
    'ceiling_fan': (8_000, 1024),
}
DEFAULT_TEXTURE = 1024
FOLIAGE_WORDS = ('leaf', 'leaves', 'foliage', 'twig', 'grass', 'blade', 'needle', 'petal', 'flower')


def triangles(objects):
    return sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in objects)


def is_foliage(obj):
    name = (obj.name + ' ' + ' '.join(m.name for m in obj.data.materials if m)).lower()
    if any(w in name for w in FOLIAGE_WORDS):
        return True
    for mat in obj.data.materials:
        if mat and mat.use_nodes:
            for node in mat.node_tree.nodes:
                if node.type == 'BSDF_PRINCIPLED' and node.inputs['Alpha'].is_linked:
                    return True
    return False


def island_labels(mesh):
    """Connected-component label per vertex (numpy label propagation with pointer jumping)."""
    nv = len(mesh.vertices)
    edges = np.empty(len(mesh.edges) * 2, dtype=np.int64)
    mesh.edges.foreach_get('vertices', edges)
    a, b = edges[0::2], edges[1::2]
    labels = np.arange(nv, dtype=np.int64)
    for _ in range(10_000):
        m = np.minimum(labels[a], labels[b])
        before = labels.copy()
        np.minimum.at(labels, a, m)
        np.minimum.at(labels, b, m)
        labels = labels[labels]
        if np.array_equal(before, labels):
            break
    return labels


def thin_leaves(obj, keep, rng):
    """Delete whole small islands (leaves), scaling survivors about their centres."""
    mesh = obj.data
    labels = island_labels(mesh)
    unique, inverse, counts = np.unique(labels, return_inverse=True, return_counts=True)
    # Foliage meshes hold only leaves (split by material), so every island is a leaf or leaf
    # cluster; only the very largest (a stray twig mesh) are always kept.
    small = counts <= max(64, np.percentile(counts, 99.5))
    keep_island = ~small | (rng.random(len(unique)) < keep)
    co = np.empty(len(mesh.vertices) * 3, dtype=np.float64)
    mesh.vertices.foreach_get('co', co)
    co = co.reshape(-1, 3)
    centres = np.stack([np.bincount(inverse, co[:, i]) for i in range(3)], 1) / counts[:, None]
    grow = np.where(small & keep_island, (1.0 / max(keep, 1e-3)) ** 0.28, 1.0)[inverse]
    co = centres[inverse] + (co - centres[inverse]) * grow[:, None]
    mesh.vertices.foreach_set('co', co.ravel())
    drop = np.nonzero(~keep_island[inverse])[0]
    if len(drop):
        bm = bmesh.new()
        bm.from_mesh(mesh)
        bm.verts.ensure_lookup_table()
        bmesh.ops.delete(bm, geom=[bm.verts[i] for i in drop], context='VERTS')
        bm.to_mesh(mesh)
        bm.free()
    mesh.update()


def decimate(obj, ratio):
    if ratio >= 0.999:
        return
    bpy.context.view_layer.objects.active = obj
    mod = obj.modifiers.new('Budget', 'DECIMATE')
    mod.ratio = max(ratio, 0.002)
    mod.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier=mod.name)


def use_alpha_map(mat, path):
    """Clip the material with a separate alpha map (glTF alphaMode MASK at 0.5; the exporter packs
    the map into the base colour's alpha)."""
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
    for link in list(bsdf.inputs['Alpha'].links):
        nt.links.remove(link)
    base = next((l.from_node for l in bsdf.inputs['Base Color'].links if l.from_node.type == 'TEX_IMAGE'), None)
    tex = nt.nodes.new('ShaderNodeTexImage')
    tex.image = bpy.data.images.load(str(path), check_existing=True)
    tex.image.colorspace_settings.name = 'Non-Color'
    if base is not None and base.inputs['Vector'].links:
        nt.links.new(base.inputs['Vector'].links[0].from_socket, tex.inputs['Vector'])
    clip = nt.nodes.new('ShaderNodeMath')
    clip.operation = 'GREATER_THAN'
    clip.inputs[1].default_value = 0.5
    nt.links.new(tex.outputs['Color'], clip.inputs[0])
    nt.links.new(clip.outputs['Value'], bsdf.inputs['Alpha'])
    if hasattr(mat, 'surface_render_method'):
        mat.surface_render_method = 'DITHERED'


def optimise(asset):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    source = next((RAW / asset).glob('*.gltf'))
    bpy.ops.import_scene.gltf(filepath=str(source))
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
    # Scans often keep trunk, branches and leaves in one mesh: split by material so each part
    # gets the right treatment.
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.separate(type='MATERIAL')
    bpy.ops.object.mode_set(mode='OBJECT')
    meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH' and len(o.data.polygons)]
    before = triangles(meshes)
    budget, texture_size = BUDGETS.get(asset, (before, DEFAULT_TEXTURE))
    rng = np.random.default_rng(7)
    foliage = [o for o in meshes if is_foliage(o)]
    solid = [o for o in meshes if o not in foliage]
    # Leaf cards (alpha-masked in the source) get their cut-out from the separate alpha map;
    # modeled leaves become opaque and double-sided, so they shadow.
    cutout = {m['name'] for m in json.loads(source.read_text(encoding='utf-8')).get('materials', [])
              if m.get('alphaMode') in ('MASK', 'BLEND')}
    alpha_map = next((RAW / asset / 'textures').glob('*_alpha_*'), None) if (RAW / asset / 'textures').exists() else None
    for o in foliage:
        for mat in o.data.materials:
            if mat and mat.use_nodes:
                mat.use_backface_culling = False
                if alpha_map and mat.name.split('.')[0] in cutout:
                    use_alpha_map(mat, alpha_map)
                    continue
                for node in mat.node_tree.nodes:
                    if node.type == 'BSDF_PRINCIPLED':
                        for link in list(node.inputs['Alpha'].links):
                            mat.node_tree.links.remove(link)
                        node.inputs['Alpha'].default_value = 1.0
    if before > budget:
        f_tris, s_tris = triangles(foliage), triangles(solid)
        # Trunks, branches and rock bodies get up to 35% of the budget, leaves the rest.
        s_budget = min(s_tris, int(budget * (0.35 if foliage else 1.0)))
        for o in solid:
            decimate(o, s_budget / max(s_tris, 1))
        if foliage:
            f_budget = budget - triangles(solid)
            if f_tris > f_budget:
                for o in foliage:  # whole leaves are removed; survivors keep their shape
                    thin_leaves(o, f_budget / f_tris, rng)
    after = triangles(meshes)
    # Origin: centre of footprint, resting on the ground (Blender Z up).
    # Transforms were applied above, so local coordinates are world coordinates.
    coords = []
    for o in meshes:
        co = np.empty(len(o.data.vertices) * 3, dtype=np.float64)
        o.data.vertices.foreach_get('co', co)
        coords.append(co.reshape(-1, 3))
    coords = np.concatenate(coords)
    lo, hi = coords.min(0), coords.max(0)
    shift = -np.array([(lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, lo[2]])
    for o in meshes:
        o.location = (o.location.x + shift[0], o.location.y + shift[1], o.location.z + shift[2])
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)
    for image in bpy.data.images:
        if image.size[0] > texture_size:
            image.scale(texture_size, max(1, int(image.size[1] * texture_size / image.size[0])))
    for o in meshes:
        for p in o.data.polygons:
            p.use_smooth = True
    target = OUT / f'{asset}.glb'
    bpy.ops.export_scene.gltf(filepath=str(target), export_format='GLB', export_yup=True,
                              export_apply=True, export_image_format='AUTO')
    size = (hi - lo).round(3).tolist()
    print(f'CONSTRUCT_MODEL {asset}: {before} -> {after} triangles, size {size}', flush=True)
    return {'triangles': after, 'source_triangles': before, 'size_m': size}


def main():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    if not argv:  # default: exactly the models the fetch script lists
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        from fetch_polyhaven import MODELS
        argv = MODELS
    assets = argv
    report_path = OUT / 'models.json'
    report = json.loads(report_path.read_text()) if report_path.exists() else {}
    for asset in assets:
        report[asset] = optimise(asset)
        report_path.write_text(json.dumps(report, indent=1, sort_keys=True))
    print('CONSTRUCT_OPTIMIZE_OK', len(assets), flush=True)


if __name__ == '__main__':
    main()
