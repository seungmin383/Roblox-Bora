"""Run Blender in background. Optimize the generated Tripo head, retaining UVs."""
from pathlib import Path
import bpy,bmesh
import numpy as np
import json,struct,math,sys
from mathutils import Matrix,Vector

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets/traffic/local';OUT.mkdir(parents=True,exist_ok=True)
PEDESTRIAN='--pedestrian' in sys.argv
NAME='PedestrianSignal' if PEDESTRIAN else 'TrafficSignal'
SOURCE='BoraPedestrianSignal.glb' if PEDESTRIAN else 'BoraTrafficSignal.glb'
TASK='18113186-2d02-4423-8ea5-c805f7780b75' if PEDESTRIAN else 'ce30b66d-2fca-4301-81d8-824268179ce4'
BUDGET=4200 if PEDESTRIAN else 6500
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(ROOT/'assets/traffic/source'/SOURCE))
objects=[o for o in bpy.context.scene.objects if o.type=='MESH']
bpy.ops.object.select_all(action='DESELECT')
for o in objects:o.select_set(True)
bpy.context.view_layer.objects.active=objects[0]
if len(objects)>1:bpy.ops.object.join()
obj=bpy.context.view_layer.objects.active
bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
original=len(obj.data.polygons)
positions=np.array([v.co[:] for v in obj.data.vertices])
lo,hi=positions.min(axis=0),positions.max(axis=0)
# Blender Z-up to Roblox Y-up, then face local -Z instead of glTF +Z.
conversion=Matrix(((-1,0,0),(0,0,1),(0,1,0)))
scale=(.82/(hi[2]-lo[2])) if PEDESTRIAN else (2.1/(hi[0]-lo[0]));center=Vector(((hi+lo)*.5).tolist())
for vertex in obj.data.vertices:vertex.co=(vertex.co-center)*scale
texture=None
for slot in obj.material_slots:
 if slot.material and slot.material.use_nodes:
  shader=next((n for n in slot.material.node_tree.nodes if n.type=='BSDF_PRINCIPLED'),None)
  if shader and shader.inputs['Base Color'].links:
   node=shader.inputs['Base Color'].links[0].from_node
   if node.type=='TEX_IMAGE':texture=node.image;break
assert texture,'No generated albedo found'
texture.filepath_raw=str(OUT/f'{NAME}.png');texture.file_format='PNG';texture.save()
# glTF splits vertices at normal/UV boundaries. Weld coincident positions so
# tiny disconnected triangles do not prevent simplification; loop UVs remain.
bm=bmesh.new();bm.from_mesh(obj.data)
bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.00002)
if PEDESTRIAN:
 # Tripo produced a third unused compartment. Keep the upper two displays,
 # close the metal housing and retain their generated UVs/material.
 bottom=min(v.co.z for v in bm.verts);top=max(v.co.z for v in bm.verts)
 cut=bottom+(top-bottom)*.475
 result=bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),plane_co=Vector((0,0,cut)),plane_no=Vector((0,0,1)),dist=.000001,clear_inner=True,clear_outer=False)
 edges=[e for e in result['geom_cut'] if isinstance(e,bmesh.types.BMEdge) and e.is_boundary]
 capped=bmesh.ops.holes_fill(bm,edges=edges,sides=0)
 uv_layer=bm.loops.layers.uv.active
 if uv_layer:
  for face in capped.get('faces',[]):
   for loop in face.loops:loop[uv_layer].uv=(.5,.5)
 kept=np.array([v.co[:] for v in bm.verts]);low,high=kept.min(axis=0),kept.max(axis=0)
 origin=Vector(((low+high)*.5).tolist());factor=.82/(high[2]-low[2])
 for v in bm.verts:v.co=(v.co-origin)*factor
bm.to_mesh(obj.data);bm.free();obj.data.update()
mod=obj.modifiers.new('Game mesh','DECIMATE');mod.ratio=min(1,BUDGET/len(obj.data.polygons))
bpy.ops.object.modifier_apply(modifier=mod.name)
obj.data.update();obj.data.calc_loop_triangles()
mesh=obj.data;uv=mesh.uv_layers.active
rows,faces,index=[],[],{}
for tri in mesh.loop_triangles:
 face=[]
 for lid in tri.loops:
  loop=mesh.loops[lid];p=conversion@mesh.vertices[loop.vertex_index].co;n=conversion@mesh.corner_normals[lid].vector
  tex=uv.data[lid].uv
  packed=struct.pack('<8f4b4B',*p,*n,tex.x,1-tex.y,0,0,0,127,255,255,255,255)
  if packed not in index:index[packed]=len(rows);rows.append(packed)
  face.append(index[packed])
 faces.append(face)
with (OUT/f'{NAME}.mesh').open('wb') as stream:
 stream.write(b'version 2.00\n');stream.write(struct.pack('<HBBII',12,40,12,len(rows),len(faces)))
 for row in rows:stream.write(row)
 for face in faces:stream.write(struct.pack('<III',*face))
coords=np.array([conversion@v.co for v in mesh.vertices]);bounds=coords.max(axis=0)-coords.min(axis=0)
print('ORIGINAL_FACES',original,'OPTIMIZED',len(faces),'BOUNDS',bounds.tolist(),flush=True)
assert len(faces)<15000,'Optimization did not reach the game mesh budget'
lamps=[]
if PEDESTRIAN:
 triangles=coords[np.array([list(t.vertices) for t in mesh.loop_triangles])]
 def front_at(x,y):
  a,b,c=triangles[:,0],triangles[:,1],triangles[:,2]
  denominator=(b[:,1]-c[:,1])*(a[:,0]-c[:,0])+(c[:,0]-b[:,0])*(a[:,1]-c[:,1])
  valid=np.abs(denominator)>1e-12
  alpha=np.zeros(len(a));beta=np.zeros(len(a))
  alpha[valid]=((b[valid,1]-c[valid,1])*(x-c[valid,0])+(c[valid,0]-b[valid,0])*(y-c[valid,1]))/denominator[valid]
  beta[valid]=((c[valid,1]-a[valid,1])*(x-c[valid,0])+(a[valid,0]-c[valid,0])*(y-c[valid,1]))/denominator[valid]
  valid&=(alpha>=-1e-5)&(beta>=-1e-5)&(alpha+beta<=1.00001)
  z=alpha*a[:,2]+beta*b[:,2]+(1-alpha-beta)*c[:,2]
  assert valid.any(),'No display surface at panel center'
  return float(z[valid].min())-.012
 for y in [.205,-.205]:lamps.append([0,y,front_at(0,y)])
else:
 for x in [-.66,0,.66]:
  nearby=coords[(np.abs(coords[:,0]-x)<.055)&(np.abs(coords[:,1]+.03)<.055)]
  assert len(nearby)>0,'No lens vertices at expected center'
  z=float(np.min(nearby[:,2]))-.012;lamps.append([x,-.03,z])
manifest={'source':'Tripo Studio','taskId':TASK,'url':f'https://studio.tripo3d.ai/ko/workspace/generate/{TASK}','credits':55,'originalTriangles':original,'triangles':len(faces),'vertices':len(rows),'boundsMeters':bounds.tolist(),'lampCentersMeters':lamps,'localStudioAsset':True}
if PEDESTRIAN:manifest['cleanup']='Removed third unused compartment, closed bottom cap, retained upper two generated displays and UVs'
(OUT/('pedestrian-manifest.json' if PEDESTRIAN else 'manifest.json')).write_text(json.dumps(manifest,indent=2),encoding='utf-8')
# Render the exact optimized asset for inspection without launching Studio.
for vertex in mesh.vertices:vertex.co=conversion@vertex.co
obj.name=NAME;obj.rotation_euler=(0,0,0)
for slot in obj.material_slots:
 if slot.material and slot.material.use_nodes:
  shader=next((n for n in slot.material.node_tree.nodes if n.type=='BSDF_PRINCIPLED'),None)
  if shader:
   for key,value in [('Roughness',.75),('Metallic',.1)]:
    for link in list(shader.inputs[key].links):slot.material.node_tree.links.remove(link)
    shader.inputs[key].default_value=value
   for link in list(shader.inputs['Normal'].links):slot.material.node_tree.links.remove(link)
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=16
scene.world.color=(.25,.25,.25)
def aim(item,target):
 direction=(Vector(target)-item.location).normalized();right=direction.cross(Vector((0,1,0))).normalized();up=right.cross(direction)
 item.rotation_euler=Matrix((right,up,-direction)).transposed().to_euler()
bpy.ops.object.camera_add(location=(.9,.5,-2.4) if PEDESTRIAN else (2.2,1.1,-4.5));cam=bpy.context.object;aim(cam,(0,0,0));cam.data.type='ORTHO';cam.data.ortho_scale=1.2 if PEDESTRIAN else 2.8;scene.camera=cam
for location,power,size in [((1,3,-3),350,3),((-3,1,-1),200,2),((0,2,3),400,2)]:
 bpy.ops.object.light_add(type='AREA',location=location);light=bpy.context.object;light.data.energy=power;light.data.shape='DISK';light.data.size=size;aim(light,(0,0,0))
scene.render.resolution_x=700 if PEDESTRIAN else 1000;scene.render.resolution_y=900 if PEDESTRIAN else 520;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG';scene.render.filepath=str(ROOT/'dist/preview'/('tripo-pedestrian-signal.png' if PEDESTRIAN else 'tripo-traffic-signal.png'))
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/f'{NAME}.blend'))
bpy.ops.render.render(write_still=True)
print('Traffic asset ready',flush=True)
