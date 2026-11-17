"""Inspect the exact Luau-generated surface and card transforms in Blender."""
from pathlib import Path
import json
import math
import bpy
from mathutils import Matrix,Vector
ROOT=Path(__file__).resolve().parents[1]
ASSETS=ROOT/'assets/tree/local'
OUT=ROOT/'dist/preview'
data=json.loads((ROOT/'dist/parametric-geometry.json').read_text())
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)

# A repeating bark tile for newly generated UVs, independent of the old atlas.
mat=bpy.data.materials.new('Procedural ginkgo bark'); mat.use_nodes=True
nodes,links=mat.node_tree.nodes,mat.node_tree.links
shader=nodes.get('Principled BSDF'); shader.inputs['Roughness'].default_value=.9
uv=nodes.new('ShaderNodeTexCoord')
mapping=nodes.new('ShaderNodeVectorMath'); mapping.operation='MULTIPLY'; mapping.inputs[1].default_value=(12,1,1)
links.new(uv.outputs['UV'],mapping.inputs[0])
noise=nodes.new('ShaderNodeTexNoise'); noise.inputs['Scale'].default_value=5; noise.inputs['Detail'].default_value=3
links.new(mapping.outputs[0],noise.inputs['Vector'])
ramp=nodes.new('ShaderNodeValToRGB')
ramp.color_ramp.elements[0].position=.18; ramp.color_ramp.elements[0].color=(.075,.063,.049,1)
ramp.color_ramp.elements[1].position=.82; ramp.color_ramp.elements[1].color=(.25,.21,.17,1)
links.new(noise.outputs['Fac'],ramp.inputs[0]); links.new(ramp.outputs[0],shader.inputs['Base Color'])
bpy.ops.mesh.primitive_plane_add(size=2)
tileplane=bpy.context.object; tileplane.data.materials.append(mat)
tile=bpy.data.images.new('ProceduralBark',512,512,alpha=False)
target=nodes.new('ShaderNodeTexImage'); target.image=tile; nodes.active=target
scene=bpy.context.scene; scene.render.engine='CYCLES'; scene.cycles.samples=1
scene.render.bake.use_pass_direct=False; scene.render.bake.use_pass_indirect=False; scene.render.bake.use_pass_color=True
bpy.ops.object.bake(type='DIFFUSE')
tile.filepath_raw=str(ASSETS/'ProceduralBark.png'); tile.file_format='PNG'; tile.save()
links.new(target.outputs['Color'],shader.inputs['Base Color'])
bpy.data.objects.remove(tileplane,do_unlink=True)
leafmat=bpy.data.materials.new('Summer foliage'); leafmat.use_nodes=True
leafshader=leafmat.node_tree.nodes.get('Principled BSDF'); leafshader.inputs['Roughness'].default_value=.85
tex=leafmat.node_tree.nodes.new('ShaderNodeTexImage'); tex.image=bpy.data.images.load(str(ASSETS/'GinkgoCluster.png'))
leafmat.node_tree.links.new(tex.outputs['Color'],leafshader.inputs['Base Color'])
alpha=leafmat.node_tree.nodes.new('ShaderNodeMath'); alpha.operation='GREATER_THAN'; alpha.inputs[1].default_value=.28
leafmat.node_tree.links.new(tex.outputs['Alpha'],alpha.inputs[0]); leafmat.node_tree.links.new(alpha.outputs[0],leafshader.inputs['Alpha'])
leafmat.surface_render_method='DITHERED'
conversion=Matrix(((1,0,0),(0,0,-1),(0,1,0)))
for index,name in enumerate(('6','9','12')):
    specimen=data[name]; shift=Vector(((index-1)*18,0,0)); center=Vector(specimen['Center'])
    verts=[conversion@(Vector(v)+center)+shift for v in specimen['Vertices']]
    mesh=bpy.data.meshes.new('Connected wood '+name)
    mesh.from_pydata(verts,[],[tuple(i-1 for i in f) for f in specimen['Faces']]); mesh.update()
    layer=mesh.uv_layers.new()
    for loop in mesh.loops: layer.data[loop.index].uv=specimen['UVs'][loop.vertex_index]
    obj=bpy.data.objects.new(name+' branches',mesh); bpy.context.collection.objects.link(obj); obj.data.materials.append(mat)
    for p in mesh.polygons: p.use_smooth=True
    for li,item in enumerate(specimen['Leaves']):
        frame=item['Frame']; rotation=Matrix((frame[3:6],frame[6:9],frame[9:12]))
        size=item['Size']; pos=Vector(item['Center'])
        vertices=[conversion@(pos+rotation@Vector((x*size[0],y*size[1],0)))+shift for x,y in ((-.5,-.5),(.5,-.5),(.5,.5),(-.5,.5))]
        card=bpy.data.meshes.new('Card'); card.from_pydata(vertices,[],[(0,1,2,3)]); card.update()
        uv_layer=card.uv_layers.new()
        for loop in card.loops: uv_layer.data[loop.index].uv=((0,0),(1,0),(1,1),(0,1))[loop.vertex_index]
        leaf=bpy.data.objects.new('Leaves '+name+' '+str(li),card); bpy.context.collection.objects.link(leaf); leaf.data.materials.append(leafmat)
    bpy.ops.object.text_add(location=((index-1)*18,-5,.05))
    label=bpy.context.object; label.data.body=name+' BRANCHES'; label.data.align_x='CENTER'; label.data.size=.8
    label.data.materials.append(bpy.data.materials.new('Label'))
    label.data.materials[0].diffuse_color=(.8,.8,.75,1)
bpy.ops.mesh.primitive_plane_add(size=2000)
ground=bpy.context.object
ground.data.materials.append(bpy.data.materials.new('Ground'))
ground.data.materials[0].diffuse_color=(.22,.23,.21,1)
bpy.ops.object.light_add(type='AREA',location=(0,-12,32)); bpy.context.object.data.energy=4000; bpy.context.object.data.size=24
bpy.ops.object.light_add(type='SUN',location=(0,0,25)); bpy.context.object.rotation_euler=(.35,-.5,-.5); bpy.context.object.data.energy=2
bpy.ops.object.camera_add(location=(29,-65,28)); camera=bpy.context.object
camera.rotation_euler=(Vector((0,0,9))-camera.location).to_track_quat('-Z','Y').to_euler()
camera.data.type='ORTHO'; camera.data.ortho_scale=61
scene.camera=camera; scene.render.engine='CYCLES'; scene.cycles.samples=16; scene.cycles.use_denoising=True
scene.render.resolution_x,scene.render.resolution_y=1440,900; scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'; scene.render.filepath=str(OUT/'parametric_6_9_12.png')
bpy.ops.render.render(write_still=True)
bpy.ops.wm.save_as_mainfile(filepath=str(ASSETS/'ParametricComparison.blend'))
