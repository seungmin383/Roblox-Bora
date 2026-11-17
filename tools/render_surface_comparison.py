"""Render the exact old/new exported wood surfaces without foliage or bark."""
from pathlib import Path
import json
import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[1]
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
conversion = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))
mat = bpy.data.materials.new('Neutral wood inspection')
mat.diffuse_color = (.52, .43, .33, 1)
for name, source, x in (
    ('BEFORE', ROOT/'archive/tree-surface-v041/parametric-geometry.json', -8),
    ('AFTER', ROOT/'dist/parametric-geometry.json', 8),
):
    data = json.loads(source.read_text())['9']
    center = Vector(data['Center'])
    points = [conversion @ (Vector(p)+center)+Vector((x, 0, 0)) for p in data['Vertices']]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(points, [], [[v-1 for v in f] for f in data['Faces']])
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    mesh.normals_split_custom_set_from_vertices([conversion @ Vector(n) for n in data['Normals']])
    bpy.ops.object.text_add(location=(x, -2, .1), rotation=(1.5708, 0, 0))
    text = bpy.context.object
    text.data.body = name
    text.data.align_x = 'CENTER'
    text.data.size = .65

bpy.ops.object.light_add(type='AREA', location=(0, -15, 23))
bpy.context.object.data.energy = 3500
bpy.context.object.data.size = 15
bpy.ops.object.light_add(type='AREA', location=(7, 6, 17))
bpy.context.object.data.energy = 2500
bpy.context.object.data.size = 10
bpy.ops.object.camera_add(location=(0, -45, 15))
camera = bpy.context.object
camera.rotation_euler = (Vector((0, 0, 9))-camera.location).to_track_quat('-Z', 'Y').to_euler()
camera.data.type = 'ORTHO'
camera.data.ortho_scale = 33
scene = bpy.context.scene
scene.camera = camera
scene.world.color = (.15, .15, .15)
scene.render.engine = 'CYCLES'
scene.cycles.samples = 24
scene.cycles.use_denoising = True
scene.render.resolution_x = 2000
scene.render.resolution_y = 1400
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
scene.render.filepath = str(ROOT/'dist/preview/wood_surface_before_after.png')
bpy.ops.render.render(write_still=True)
