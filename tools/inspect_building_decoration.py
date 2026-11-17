"""Inspect the original Tripo lamp, keep its geometry untouched, render views."""
from pathlib import Path
import bpy,json,math,sys
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(ROOT/'assets/buildings/source/WallSconce_Tripo.glb'))
meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
report=[]
for o in meshes:
    o.data.calc_loop_triangles()
    points=[o.matrix_world@Vector(c) for c in o.bound_box]
    report.append({'name':o.name,'vertices':len(o.data.vertices),'triangles':len(o.data.loop_triangles),
                   'min':[min(p[i] for p in points) for i in range(3)],'max':[max(p[i] for p in points) for i in range(3)]})
(ROOT/'dist/building-decoration-source.json').write_text(json.dumps(report,indent=2))
allp=[o.matrix_world@Vector(c) for o in meshes for c in o.bound_box]
lo=Vector([min(p[i] for p in allp) for i in range(3)]);hi=Vector([max(p[i] for p in allp) for i in range(3)]);center=(lo+hi)*.5
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=12;scene.cycles.use_denoising=True
scene.world.color=(.25,.25,.25);scene.render.resolution_x=800;scene.render.resolution_y=1000;scene.render.resolution_percentage=100
scene.view_settings.view_transform='AgX'
bpy.ops.object.light_add(type='AREA',location=(2,-4,5));bpy.context.object.data.energy=500;bpy.context.object.data.shape='DISK';bpy.context.object.data.size=4
bpy.ops.object.camera_add();cam=bpy.context.object;scene.camera=cam
for name,offset in ([] if '--wire-only' in sys.argv else [('front',(0,-3,.1)),('side',(2,-2,.4))]):
    cam.location=center+Vector(offset);cam.rotation_euler=(center-cam.location).to_track_quat('-Z','Y').to_euler()
    cam.data.type='ORTHO';cam.data.ortho_scale=max(hi-lo)*1.35
    scene.render.filepath=str(ROOT/f'dist/preview/building-sconce-source-{name}.png');bpy.ops.render.render(write_still=True)
wire=bpy.data.materials.new('Source actual triangle edges');wire.use_nodes=True
nodes=wire.node_tree.nodes;nodes.clear();output=nodes.new('ShaderNodeOutputMaterial');bs=nodes.new('ShaderNodeBsdfPrincipled')
edge=nodes.new('ShaderNodeWireframe');edge.use_pixel_size=True;edge.inputs['Size'].default_value=.65
mix=nodes.new('ShaderNodeMixRGB');mix.inputs[1].default_value=(.55,.61,.64,1);mix.inputs[2].default_value=(.015,.025,.035,1)
wire.node_tree.links.new(edge.outputs[0],mix.inputs[0]);wire.node_tree.links.new(mix.outputs[0],bs.inputs['Base Color']);wire.node_tree.links.new(bs.outputs[0],output.inputs['Surface'])
for o in meshes:o.data.materials.clear();o.data.materials.append(wire)
target=Vector((.13,-.18,.77));cam.location=target+Vector((.2,-2,.4));cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=.16
scene.render.filepath=str(ROOT/'dist/preview/building-sconce-source-wire.png');bpy.ops.render.render(write_still=True)
print(json.dumps(report))
