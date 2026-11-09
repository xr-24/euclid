"""Deterministic example asset build. Only run in a disposable background Blender."""
import bpy
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'assets' / 'source'
OUTPUT = ROOT / 'world' / 'assets' / 'generated'
SOURCE.mkdir(parents=True, exist_ok=True)
OUTPUT.mkdir(parents=True, exist_ok=True)

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
material = bpy.data.materials.new('Warm limestone')
material.use_nodes = True
principled = next(node for node in material.node_tree.nodes if node.type == 'BSDF_PRINCIPLED')
principled.inputs['Base Color'].default_value = (0.81, 0.72, 0.54, 1)
principled.inputs['Roughness'].default_value = 0.78

# Metres, bottom origin, Z up in Blender; glTF exporter converts to Godot's Y up.
profile = [(0, .5), (.15, .5), (.2, .42), (.3, .42), (.38, .32), (3.9, .27), (4.02, .38), (4.15, .44), (4.3, .44)]
segments = 32
vertices = [(radius * math.cos(i * math.tau / segments), radius * math.sin(i * math.tau / segments), height) for height, radius in profile for i in range(segments)]
faces = []
for ring in range(len(profile) - 1):
    for i in range(segments):
        a = ring * segments + i
        b = ring * segments + (i + 1) % segments
        faces.append((a, b, b + segments, a + segments))
faces.extend([tuple(reversed(range(segments))), tuple((len(profile)-1)*segments+i for i in range(segments))])
mesh = bpy.data.meshes.new('Column mesh')
mesh.from_pydata(vertices, [], faces)
mesh.update()
column = bpy.data.objects.new('VillaColumn', mesh)
bpy.context.collection.objects.link(column)
column.data.materials.append(material)
column['asset_id'] = 'villa.column.limestone'
column['units'] = 'metres'
for polygon in mesh.polygons:
    polygon.use_smooth = len(polygon.vertices) == 4
bpy.context.view_layer.objects.active = column
column.select_set(True)
triangulate = column.modifiers.new('Export triangles', 'TRIANGULATE')
assert abs(column.dimensions.z - 4.3) < 0.01, 'Column height validation failed'
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE / 'villa_column.blend'))
bpy.ops.export_scene.gltf(filepath=str(OUTPUT / 'villa_column.glb'), export_format='GLB', use_selection=True, export_apply=True, export_extras=True, export_yup=True)
print('CONSTRUCT_ASSET_OK: villa_column.glb; height 4.3 metres')
