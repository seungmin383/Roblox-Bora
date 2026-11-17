"""Repair four pinched shading corners and give the roof's interior a lining material."""
import bpy,bmesh,math,sys,json
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'assets/vehicles/retopology'
sys.path.insert(0,str(ROOT/'tools'))
from s2_fair_surfaces import close_skin_junctions
bpy.ops.wm.open_mainfile(filepath=str(OUT/'BoraS2_Clean.blend'))
for obj in list(bpy.context.scene.objects):
 if obj.type=='MESH' and obj.get('asset'):close_skin_junctions(obj)
for o in bpy.context.scene.objects:
 if o.type!='MESH' or not o.get('asset'):continue
 me=o.data;me.update();normals=[n.vector.copy() for n in me.corner_normals];keys=set();count=0
 for f in me.polygons:
  if any(normals[li].length<.9 for li in f.loop_indices):
   keys.update(tuple(sorted(k)) for k in f.edge_keys)
   for li in f.loop_indices:normals[li]=f.normal.copy();count+=1
 if keys:
  for e in me.edges:
   if tuple(sorted(e.vertices)) in keys:e.use_edge_sharp=True
  me.normals_split_custom_set(normals);me.update();print('Fixed shading corners',o.name,count,flush=True)
if not bpy.context.scene.get('S2BlenderHandednessCorrected',False):
 for o in bpy.context.scene.objects:
  if o.type!='MESH' or o.get('asset')!='BORA S2':continue
  me=o.data;me.update();attr=me.attributes.new('S2_MirroredNormals','FLOAT_VECTOR','CORNER')
  for i,n in enumerate(me.corner_normals):attr.data[i].vector=(-n.vector.x,n.vector.y,n.vector.z)
  for v in me.vertices:v.co.x=-v.co.x
  o.location.x=-o.location.x
  bm=bmesh.new();bm.from_mesh(me);bmesh.ops.reverse_faces(bm,faces=list(bm.faces));bm.to_mesh(me);bm.free();me.update()
  attr=me.attributes['S2_MirroredNormals'];me.normals_split_custom_set([Vector(d.vector) for d in attr.data]);me.attributes.remove(attr);me.update()
 pivots=json.loads(bpy.context.scene['BoraS2Pivots'])
 for p in pivots.values():p[0]=-p[0]
 bpy.context.scene['BoraS2Pivots']=json.dumps(pivots);bpy.context.scene['S2BlenderHandednessCorrected']=True
 print('Normalized Blender handedness and maintained Roblox group orientation.',flush=True)
# Reversing the corner order can expose a pinched smooth fan at a source
# junction. Split these specific edges and preserve every other normal.
for o in bpy.context.scene.objects:
 if o.type!='MESH' or o.get('asset')!='BORA S2':continue
 me=o.data;me.update();normals=[n.vector.copy() for n in me.corner_normals];keys=set()
 for f in me.polygons:
  if any(normals[li].length<.9 for li in f.loop_indices):
   keys.update(tuple(sorted(k)) for k in f.edge_keys)
   for li in f.loop_indices:normals[li]=f.normal.copy()
 if keys:
  for e in me.edges:
   if tuple(sorted(e.vertices)) in keys:e.use_edge_sharp=True
  me.normals_split_custom_set(normals);me.update()
roof=bpy.data.objects['Roof_source_fitted_crown'];lining=bpy.data.materials['S2 • cabin polymer']
if lining not in list(roof.data.materials):roof.data.materials.append(lining)
lining_index=list(roof.data.materials).index(lining)
for f in roof.data.polygons:
 if f.normal.z<-.2:f.material_index=lining_index
for o in bpy.context.scene.objects:
 if o.type=='LIGHT':o.visible_glossy=False;o.visible_transmission=False;o.visible_camera=False
glass=bpy.data.materials['S2 • actual laminated glass'];glass.node_tree.nodes.get('Principled BSDF').inputs['IOR'].default_value=1.45
for name,location in [('QA_CabinFront',(0,-.35,1.24)),('QA_CabinRear',(0,.8,1.23))]:
 if name not in bpy.data.objects:
  bpy.ops.object.light_add(type='POINT',location=location);light=bpy.context.object;light.name=name;light.data.energy=12;light.data.shadow_soft_size=.4
  light.visible_camera=False;light.visible_glossy=False;light.visible_transmission=False
asset=bpy.data.collections['BORA S2 • cleaned game asset']
groups=sorted({o['group'] for o in bpy.context.scene.objects if o.type=='MESH' and o.get('asset')=='BORA S2'})
for group in groups:
 name='S2_'+group;coll=bpy.data.collections.get(name)
 if not coll:coll=bpy.data.collections.new(name);asset.children.link(coll)
 for o in list(bpy.context.scene.objects):
  if o.type=='MESH' and o.get('asset')=='BORA S2' and o['group']==group:
   if asset in o.users_collection:asset.objects.unlink(o)
   if coll not in o.users_collection:coll.objects.link(o)
scene=bpy.context.scene;cam=scene.camera;cam.location=(-5.3,-6.2,2.7);cam.rotation_euler=(Vector((0,0,.65))-cam.location).to_track_quat('-Z','Y').to_euler()
for o in bpy.context.scene.objects:
 if not o.get('asset'):o.hide_set(True)
for screen in bpy.data.screens:
 for area in screen.areas:
  if area.type=='VIEW_3D':
   area.spaces.active.region_3d.view_rotation=cam.rotation_euler.to_quaternion();area.spaces.active.region_3d.view_location=(0,0,.7);area.spaces.active.region_3d.view_distance=7
   area.spaces.active.shading.type='MATERIAL'
# Save an editable mesh as the active object, not the hidden QA light last added.
for o in bpy.context.view_layer.objects:
 o.select_set(False)
body=bpy.data.objects['Body_paint'];body.hide_set(False);body.select_set(True)
bpy.context.view_layer.objects.active=body
bpy.context.view_layer.update()
bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'BoraS2_Clean.blend'))
if '--no-render' in sys.argv:raise SystemExit(0)
for name,loc,target in [('s2-clean-front.png',(-5.3,-6.2,2.7),(0,0,.65)),('s2-clean-side.png',(-7.5,0,1.8),(0,0,.7)),('s2-clean-rear.png',(5,6,2.8),(0,0,.7))]:
 cam.location=loc;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler();scene.render.filepath=str(OUT/name);bpy.ops.render.render(write_still=True)
