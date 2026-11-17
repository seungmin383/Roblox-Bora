"""Inspect and stage the selected P2 sedan. Never edits the live Place or S1 assets."""
import bpy,bmesh,json,math
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets/vehicles/retopology';SRC=ROOT/'assets/vehicles/source/BoraS2_Quad_OBJ'
bpy.context.preferences.filepaths.save_version=0
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
bpy.ops.wm.obj_import(filepath=str(SRC/'BoraS2_Tripo_Quad_OBJ.obj'),forward_axis='NEGATIVE_Z',up_axis='Y')
meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
for o in meshes:
 bpy.context.view_layer.objects.active=o;o.select_set(True)
 bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
 bm=bmesh.new();bm.from_mesh(o.data);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.000001)
 bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(o.data);bm.free()
 print('SOURCE',o.name,len(o.data.vertices),len(o.data.polygons),[tuple(v.co) for v in o.data.vertices][:2],flush=True)
 for v in o.data.vertices:v.co*=4.68
 for p in o.data.polygons:p.use_smooth=True
 o.name='S2_Source';o.data.update()
 for mat in o.data.materials:
  if mat and mat.use_nodes:
   bs=mat.node_tree.nodes.get('Principled BSDF');bs.inputs['Roughness'].default_value=.34;bs.inputs['Metallic'].default_value=.3
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=20;scene.cycles.use_denoising=True
scene.render.resolution_x=1200;scene.render.resolution_y=800;scene.render.resolution_percentage=100
scene.world.color=(.35,.35,.35)
for loc,power,size in [((-3,-4,6),1100,5),((4,0,5),1000,4),((0,5,4),1400,4)]:
 bpy.ops.object.light_add(type='AREA',location=loc);o=bpy.context.object;o.data.energy=power;o.data.shape='DISK';o.data.size=size;o.rotation_euler=(Vector((0,0,.7))-o.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.015));bpy.context.object.name='QA_Ground'
mat=bpy.data.materials.new('QA_Ground');mat.diffuse_color=(.07,.09,.12,1);bpy.context.object.data.materials.append(mat)
bpy.ops.object.camera_add();cam=bpy.context.object;scene.camera=cam
def render(name,loc,target,lens=52):
 cam.location=loc;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.lens=lens
 scene.render.filepath=str(OUT/name);bpy.ops.render.render(write_still=True)
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'BoraS2_Source_Review.blend'))
render('s2-source-front.png',(-5,-6,2.8),(0,0,.7))
render('s2-source-side.png',(-7,0,2.0),(0,0,.75))
render('s2-source-rear.png',(5,6,2.8),(0,0,.7))
