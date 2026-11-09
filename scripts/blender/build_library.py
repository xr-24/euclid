"""Build the placeable-asset library from downloaded Sketchfab scans. Disposable Blender only:
    blender --background --factory-startup --python scripts/blender/build_library.py [-- id ...] [--preview]

For every model in scripts/assets/sketchfab.json that has been fetched into .local/sketchfab/raw:
import it flat, apply the manifest's orientation fix, scale it to its real-world size, reduce it
to its triangle budget, rest it on the ground with its footprint centred on the origin, cap its
textures and export world/assets/library/<licence>/<id>/<id>.glb plus an asset.json describing it.
Models are grouped into folders by licence so a whole licence class can be removed in one step.
With --preview a front and a side view are rendered to .local/library-previews/<id>.png.

Conventions of the built asset: metres, Y up in Godot, the base at y = 0 and the figure's front
facing +Z (towards a viewer standing in front of it at yaw 0).
"""
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import mesh_tools as mt  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / 'scripts/assets/sketchfab.json'
RAW = ROOT / '.local/sketchfab/raw'
LIBRARY = ROOT / 'world/assets/library'
PREVIEWS = ROOT / '.local/library-previews'
LICENCE_DIRS = {'cc0': 'cc0', 'by': 'cc-by', 'by-sa': 'cc-by-sa', 'by-nc': 'cc-by-nc', 'by-nc-sa': 'cc-by-nc-sa'}


def build(model: dict, preview: bool):
    source = RAW / model['uid']
    meta = json.loads((source / 'meta.json').read_text(encoding='utf-8'))
    mt.reset_scene()
    meshes = mt.import_flat(source / 'model.glb')
    # glTF front is +Z, which Blender imports as -Y; 'rotate' fixes scans that face elsewhere.
    mt.transform(meshes, rotate_deg=model.get('rotate', (0, 0, 0)))
    mt.transform(meshes, scale=mt.fit_scale(meshes, model['fit']))
    before, after = mt.reduce_to(meshes, model['budget'])
    size = mt.rest_on_ground(meshes)
    mt.cap_textures(model['texture'])
    mt.smooth(meshes)
    folder = LIBRARY / LICENCE_DIRS[meta['licence']] / model['id']
    mt.export_glb(folder / f'{model["id"]}.glb')
    blender_size = size  # x, y (depth), z (height) in Blender axes
    asset = {
        'id': model['id'],
        'title': model['title'],
        'category': model['category'],
        'tags': model.get('tags', []),
        'size_m': {'width': blender_size[0], 'depth': blender_size[1], 'height': blender_size[2]},
        'triangles': after,
        'source': {
            'site': 'Sketchfab',
            'title': meta['title'],
            'page': meta['page'],
            'author': meta['author'],
            'author_page': meta['author_page'],
            'licence': meta['licence'],
            'licence_label': meta['licence_label'],
            'licence_url': meta['licence_url'],
            'changes': (f'Reduced from {before} to {after} triangles, ' if after < before else '')
                       + f'rescaled to real size, textures capped at {model["texture"]} px, re-centred.',
        },
    }
    (folder / 'asset.json').write_text(json.dumps(asset, indent=1, ensure_ascii=False), encoding='utf-8')
    print(f'CONSTRUCT_LIBRARY {model["id"]}: {before} -> {after} triangles, size {size}, {meta["licence"]}', flush=True)
    if preview:
        render_preview(model['id'], meshes)


def render_preview(asset_id: str, meshes):
    PREVIEWS.mkdir(parents=True, exist_ok=True)
    pts = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
    lo = Vector([min(p[i] for p in pts) for i in range(3)])
    hi = Vector([max(p[i] for p in pts) for i in range(3)])
    centre, radius = (lo + hi) / 2, (hi - lo).length / 2
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_WORKBENCH'
    scene.display.shading.light = 'STUDIO'
    scene.display.shading.color_type = 'TEXTURE'
    scene.render.resolution_x = 420
    scene.render.resolution_y = 560
    cam = bpy.data.objects.new('cam', bpy.data.cameras.new('cam'))
    bpy.context.collection.objects.link(cam)
    scene.camera = cam
    views = []
    # Front: looking from -Y (the side that becomes +Z, the asset's front, in Godot); then from +X.
    for name, direction in (('front', Vector((0, -1, 0.12))), ('side', Vector((1, 0, 0.12)))):
        cam.location = centre + direction.normalized() * radius * 2.4
        cam.rotation_euler = (centre - cam.location).to_track_quat('-Z', 'Y').to_euler()
        path = PREVIEWS / f'{asset_id}_{name}.png'
        scene.render.filepath = str(path)
        bpy.ops.render.render(write_still=True)
        views.append(path)
    print(f'CONSTRUCT_LIBRARY_PREVIEW {asset_id}', flush=True)


def main():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    preview = '--preview' in argv
    wanted = {a for a in argv if not a.startswith('--')}
    models = json.loads(MANIFEST.read_text(encoding='utf-8'))['models']
    built = 0
    for model in models:
        if wanted and model['id'] not in wanted:
            continue
        if not (RAW / model['uid'] / 'model.glb').exists() or not (RAW / model['uid'] / 'meta.json').exists():
            print(f'CONSTRUCT_LIBRARY_MISSING {model["id"]}: run scripts/assets/fetch_sketchfab.py first', flush=True)
            continue
        try:
            build(model, preview)
            built += 1
        except Exception as error:
            print(f'CONSTRUCT_LIBRARY_FAILED {model["id"]}: {error!r}', flush=True)
    print(f'CONSTRUCT_LIBRARY_OK {built}', flush=True)


main()
