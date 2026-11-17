"""Render the actual exported Roblox geometry for a review image (not a Studio capture)."""
from pathlib import Path
import struct
import sys
import xml.etree.ElementTree as ET
import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / 'assets/tree/local'
OUT = ROOT / 'dist/preview'
OUT.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
conversion = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))
materials = {}

def material(texture, leaf=False):
    key = texture or 'wood'
    if key in materials:
        return materials[key]
    mat = bpy.data.materials.new(key)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Roughness'].default_value = .85
    if texture:
        image = mat.node_tree.nodes.new('ShaderNodeTexImage')
        image.image = bpy.data.images.load(str(ASSETS / texture))
        mat.node_tree.links.new(image.outputs['Color'], shader.inputs['Base Color'])
        if leaf:
            threshold = mat.node_tree.nodes.new('ShaderNodeMath')
            threshold.operation = 'GREATER_THAN'
            threshold.inputs[1].default_value = .28
            mat.node_tree.links.new(image.outputs['Alpha'], threshold.inputs[0])
            mat.node_tree.links.new(threshold.outputs[0], shader.inputs['Alpha'])
            mat.surface_render_method = 'DITHERED'
    else:
        shader.inputs['Base Color'].default_value = (.25, .17, .10, 1)
    materials[key] = mat
    return mat

def vector(prop):
    return Vector(tuple(float(prop.findtext(a)) for a in 'XYZ'))

quality = '--quality' in sys.argv
document = ET.parse(ROOT / ('dist/TreeQualityPreview.rbxlx' if quality else 'dist/TreeGrowthPreview.rbxlx'))
for part in document.findall('.//Item[@class="Part"]'):
    meshitem = part.find('Item[@class="SpecialMesh"]')
    sprite = part.find('Item[@class="SurfaceGui"]/Item[@class="ImageLabel"]')
    if meshitem is None and sprite is None:
        continue
    props = part.find('Properties')
    meshprops = meshitem.find('Properties') if meshitem is not None else sprite.find('Properties')
    meshname = meshprops.find('Content[@name="MeshContent"]/uri').text.rsplit('/', 1)[-1] if meshitem is not None else 'LeafCard.mesh'
    textureprop = meshprops.find('Content[@name="TextureContent"]/uri') if meshitem is not None else meshprops.find('Content[@name="ImageContent"]/uri')
    texture = textureprop.text.rsplit('/', 1)[-1] if textureprop is not None else None
    data = (ASSETS / meshname).read_bytes()
    offset = len(b'version 2.00\n')
    _, stride, _, nv, nf = struct.unpack_from('<HBBII', data, offset)
    offset += 12
    vertices, uv = [], []
    for i in range(nv):
        row = struct.unpack_from('<8f', data, offset + i * stride)
        vertices.append(row[:3])
        uv.append((row[6], 1-row[7]))
    offset += nv * stride
    faces = [struct.unpack_from('<III', data, offset + i * 12) for i in range(nf)]
    # Opposite-side triangles in the Roblox card are redundant in Blender's two-sided material.
    if meshname == 'LeafCard.mesh':
        faces = faces[:2]
    scale = vector(meshprops.find('Vector3[@name="Scale"]')) if meshitem is not None else vector(props.find('Vector3[@name="size"]'))
    frame = props.find('CoordinateFrame[@name="CFrame"]')
    position = vector(frame)
    rotation = Matrix(tuple(tuple(float(frame.findtext(f'R{i}{j}')) for j in range(3)) for i in range(3)))
    transformed = [conversion @ (position + rotation @ Vector(tuple(v[j]*scale[j] for j in range(3)))) for v in vertices]
    mesh = bpy.data.meshes.new(meshname)
    mesh.from_pydata(transformed, [], faces)
    mesh.update()
    layer = mesh.uv_layers.new()
    for loop in mesh.loops:
        layer.data[loop.index].uv = uv[loop.vertex_index]
    obj = bpy.data.objects.new(props.findtext('string[@name="Name"]'), mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(material(texture, meshname == 'LeafCard.mesh'))
    for polygon in mesh.polygons:
        polygon.use_smooth = meshname != 'LeafCard.mesh'

bpy.ops.mesh.primitive_plane_add(size=2000)
ground = bpy.context.object
ground.name = 'Review ground'
ground.data.materials.append(material(None))
ground.data.materials[0] = bpy.data.materials.new('Ground')
ground.data.materials[0].diffuse_color = (.10, .16, .11, 1)
for x, label in ([(-18, 'MATURE'), (0, 'VARIATION'), (18, 'CONNECTED WOOD')] if quality else [(-14, '0%'), (0, '50%'), (14, '100%')]):
    bpy.ops.object.text_add(location=(x, -4, .05))
    obj = bpy.context.object
    obj.data.body, obj.data.align_x, obj.data.size = label, 'CENTER', 1.2
    obj.data.materials.append(bpy.data.materials.new('Label'))
    obj.data.materials[0].diffuse_color = (.9, .9, .8, 1)

bpy.ops.object.light_add(type='AREA', location=(0, -10, 30))
bpy.context.object.data.energy = 3500
bpy.context.object.data.shape = 'DISK'
bpy.context.object.data.size = 25
bpy.ops.object.light_add(type='SUN', location=(0, 0, 25))
bpy.context.object.rotation_euler = (.35, -.5, -.5)
bpy.context.object.data.energy = 2.0
bpy.ops.object.camera_add(location=(32, -58, 29))
camera = bpy.context.object
camera.rotation_euler = (Vector((0, 0, 8)) - camera.location).to_track_quat('-Z', 'Y').to_euler()
camera.data.type, camera.data.ortho_scale = 'ORTHO', 61 if quality else 48
scene = bpy.context.scene
scene.camera = camera
scene.render.engine = 'CYCLES'
scene.cycles.samples = 16
scene.cycles.use_denoising = True
scene.world.color = (.25, .25, .25)
scene.render.resolution_x, scene.render.resolution_y = 1440, 900
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
scene.render.filepath = str(OUT / ('tree_quality_v3.png' if quality else 'tree_growth_v3.png'))
bpy.ops.render.render(write_still=True)
if quality:
    # Show the actual exported mature tree from two further directions.
    for obj in bpy.context.scene.objects:
        if obj.type == 'MESH' and obj.name != 'Review ground':
            xs = [v.co.x for v in obj.data.vertices]
            if xs and sum(xs)/len(xs) > -9: obj.hide_render = True
        if obj.type == 'FONT': obj.hide_render = True
    for name, position, target, scale in [
        ('tree_quality_mature.png',(-1,-31,15),(-18,0,9.5),23),
        ('tree_quality_overhead.png',(-2,-20,39),(-18,0,11),24),
    ]:
        camera.location=position
        camera.rotation_euler=(Vector(target)-camera.location).to_track_quat('-Z','Y').to_euler()
        camera.data.ortho_scale=scale
        scene.render.resolution_x, scene.render.resolution_y = 1080,1080
        scene.render.filepath=str(OUT/name)
        bpy.ops.render.render(write_still=True)
