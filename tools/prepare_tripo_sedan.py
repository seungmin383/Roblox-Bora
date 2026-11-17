"""Optimize the actual Tripo sedan, split functional parts and repair its cabin.
Run in background Blender. Keep original GLB/UVs and never write a Place.
"""
from pathlib import Path
from collections import defaultdict
import bpy,bmesh,math,json,struct
from mathutils import Vector,Matrix
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'assets/vehicles/local';PREVIEW=ROOT/'dist/preview'
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(ROOT/'assets/vehicles/source/BoraCN7_Tripo_Source.glb'))
source=next(o for o in bpy.context.scene.objects if o.type=='MESH')
bpy.context.view_layer.objects.active=source;bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
lo=Vector(tuple(min(v.co[i] for v in source.data.vertices) for i in range(3)))
hi=Vector(tuple(max(v.co[i] for v in source.data.vertices) for i in range(3)))
factor=4.68/(hi.y-lo.y);center=(lo+hi)*.5;center.z=lo.z
for v in source.data.vertices:v.co=(v.co-center)*factor
original=len(source.data.polygons)
material=source.data.materials[0];shader=material.node_tree.nodes.get('Principled BSDF')
texture=shader.inputs['Base Color'].links[0].from_node.image
texture.scale(2048,2048);texture.filepath_raw=str(OUT/'TripoSedan.png');texture.file_format='PNG';texture.save()
for key,value in [('Roughness',.32),('Metallic',.45)]:
 for link in list(shader.inputs[key].links):material.node_tree.links.remove(link)
 shader.inputs[key].default_value=value
for key in ['Normal','Alpha']:
 for link in list(shader.inputs[key].links):material.node_tree.links.remove(link)
shader.inputs['Alpha'].default_value=1
bm=bmesh.new();bm.from_mesh(source.data);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.00004);bm.to_mesh(source.data);bm.free()
mod=source.modifiers.new('Roblox optimized exterior','DECIMATE');mod.ratio=48000/len(source.data.polygons);mod.use_collapse_triangulate=True
bpy.ops.object.modifier_apply(modifier=mod.name);source.data.calc_loop_triangles()
print('TRIPO_OPTIMIZED',original,len(source.data.polygons),flush=True)
# Face regions retain original exterior UVs; glass and hidden solid cabin fills
# are replaced so first-person rendering has a real open passenger volume.
regions=defaultdict(list);uv=source.data.uv_layers.active
for tri in source.data.loop_triangles:
 points=[source.data.vertices[source.data.loops[l].vertex_index].co.copy() for l in tri.loops]
 c=sum(points,Vector())/3;x,y,z=c;side='L' if x<0 else 'R'
 # A generated opaque greenhouse contains bumpy window surfaces and baked
 # interior silhouettes. Replace this whole region with clean glazing/frames,
 # rather than making those distorted opaque surfaces translucent.
 if -1.04<y<1.50 and z>.87:continue
 wheel=None
 for axle,cy in [('F',-1.36),('R',1.36)]:
  if abs(x)>.59 and (y-cy)**2+(z-.325)**2<.325**2 and z<.67:wheel='Wheel'+axle+side;break
 if wheel:group,key=wheel,'Tripo'
 elif -.99<y<-.36 and z>.925 and abs(x)<.79:
  group,key='Body','Glass'
 elif .85<y<1.55 and z>.90 and abs(x)<.79:
  group,key='Body','Glass'
 elif -.84<y<1.22 and abs(x)>.65 and .37<z<1.38:
  group='Door'+('F' if y<.30 else 'R')+side
  # Keep the roof-side rail fixed; glass tapers below it.
  roof=1.40 if y<.68 else 1.40-(y-.68)*.95
  if z>roof-.035:group='Body'
  key='Glass' if .94<z<roof-.035 else 'Tripo'
 elif abs(x)<.71 and -.88<y<1.33 and .35<z<1.20:
  continue
 else:group,key='Body','Tripo'
 rows=[]
 for lid,p in zip(tri.loops,points):rows.append((p,source.data.corner_normals[lid].vector.copy(),tuple(uv.data[lid].uv)))
 regions[(group,key)].append(rows)

glass=bpy.data.materials.new('Clear repaired glass');glass.use_nodes=True
bs=glass.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=(.10,.16,.20,1);bs.inputs['Alpha'].default_value=.22;bs.inputs['Roughness'].default_value=.14;glass.surface_render_method='DITHERED'
source.hide_render=True;source.hide_viewport=True
objects=[]
for (group,key),faces in regions.items():
 vertices=[];indices=[];texcoords=[];normals=[]
 for face in faces:
  offset=len(vertices);vertices.extend([v[0] for v in face]);texcoords.extend([v[2] for v in face]);normals.extend([v[1] for v in face]);indices.append((offset,offset+1,offset+2))
 data=bpy.data.meshes.new(group+key);data.from_pydata(vertices,[],indices);data.update()
 layer=data.uv_layers.new()
 for loop in data.loops:layer.data[loop.index].uv=texcoords[loop.vertex_index]
 obj=bpy.data.objects.new(group+key,data);bpy.context.collection.objects.link(obj);obj['group']=group;obj['material']=key
 data.materials.append(material if key=='Tripo' else glass)
 for f in data.polygons:f.use_smooth=key=='Tripo'
 if key=='Tripo':data.normals_split_custom_set_from_vertices(normals)
 objects.append(obj)

# Reuse only the accurately positioned interior and steering components from
# the construction rig. Its hand-modeled exterior is not included.
prefixes=('Undertray','Cabin floor','Interior door trim','Door armrest','Door pull','Dashboard',
 'Display surround','Gauge glass','Navigation glass','Air vent','Dash metal trim','Center console',
 'Console armrest','Shift selector','Cup holder','Seat base','Seat back','Headrest','Seat bolster',
 'Seat seam','Rear bench','Rear backrest','Rear headrest','Roof liner','Rear view mirror',
 'Steering column','Steering rim','Steering hub','Steering spoke','Lower spoke',
 'Roof','A pillar','B pillar','C pillar','Side glass','Window frame','Windshield','Rear windshield')
with bpy.data.libraries.load(str(OUT/'BoraSedan.blend'),link=False) as (available,loaded):
 loaded.objects=[name for name in available.objects if name.startswith(prefixes)]
for obj in loaded.objects:
 if obj is not None:
  bpy.context.collection.objects.link(obj);objects.append(obj)
  if obj['material']=='Glass':
   obj.data.materials.clear();obj.data.materials.append(glass)
bpy.context.view_layer.update()
catalog=json.loads((OUT/'manifest.json').read_text(encoding='utf-8'));pivots={k:Vector((v[0],v[2],v[1])) for k,v in catalog['Pivots'].items()}
catalog['Parts']=[];catalog['TotalTriangles']=0;catalog['Source']='Tripo Studio'
catalog['TaskId']='e52b36bb-be6a-4653-9036-5b1143b2a826';catalog['SourceTriangles']=original
catalog['Design']='Tripo CN7-inspired sedan / repaired articulated cabin'
catalog['Repairs']=['Four independently pivoted doors','Four independently rotating wheels','Replaced opaque glass','Removed solid cabin fill','Added usable cabin and steering wheel']
conversion=Matrix(((1,0,0),(0,0,1),(0,1,0)))
groups=defaultdict(list)
for o in objects:groups[(o['group'],o['material'])].append(o)
for (group,key),items in sorted(groups.items()):
 rows=[];faces=[];lookup={};lo=Vector((math.inf,)*3);hi=-lo
 for obj in items:
  obj.data.calc_loop_triangles();rotation=obj.matrix_world.to_3x3();uv=obj.data.uv_layers.active
  for tri in obj.data.loop_triangles:
   face=[]
   for lid in tri.loops:
    loop=obj.data.loops[lid];p=conversion@(obj.matrix_world@obj.data.vertices[loop.vertex_index].co-pivots[group])
    normal=(conversion@rotation@obj.data.corner_normals[lid].vector).normalized();tex=uv.data[lid].uv if uv else (0,0)
    lo=Vector(tuple(min(lo[i],p[i]) for i in range(3)));hi=Vector(tuple(max(hi[i],p[i]) for i in range(3)))
    packed=struct.pack('<8f4b4B',*p,*normal,tex[0],1-tex[1],0,0,0,127,255,255,255,255)
    if packed not in lookup:lookup[packed]=len(rows);rows.append(packed)
    face.append(lookup[packed])
   faces.append(tuple(reversed(face)))
 filename=group+'_'+key+'.mesh'
 (OUT/filename).write_bytes(b'version 2.00\n'+struct.pack('<HBBII',12,40,12,len(rows),len(faces))+b''.join(rows)+b''.join(struct.pack('<III',*f) for f in faces))
 if key=='Tripo':rgb=[255,255,255];alpha=0
 elif key=='Glass':rgb=[118,139,152];alpha=.78
 else:
  shader=items[0].data.materials[0].node_tree.nodes.get('Principled BSDF');color=shader.inputs['Base Color'].default_value
  rgb=[round((12.92*c if c<=.0031308 else 1.055*c**(1/2.4)-.055)*255) for c in color[:3]];alpha=0
 part={'Group':group,'Material':key,'File':filename,'Color':rgb,'Transparency':alpha,'Bounds':[max(.001,hi[i]-lo[i]) for i in range(3)],'Triangles':len(faces)}
 if key=='Tripo':part['Texture']='TripoSedan.png'
 catalog['Parts'].append(part);catalog['TotalTriangles']+=len(faces)
assert catalog['TotalTriangles']<80000
(OUT/'manifest.json').write_text(json.dumps(catalog,indent=2),encoding='utf-8')
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'BoraTripoSedan.blend'))
print('READY_TRIPO_SEDAN',catalog['TotalTriangles'],'triangles',len(catalog['Parts']),'components',flush=True)
# Render the repaired actual Tripo model, including its separate doors.
floor=bpy.data.materials.new('Neutral floor');floor.diffuse_color=(.12,.14,.16,1)
bpy.ops.mesh.primitive_plane_add(size=200);bpy.context.object.data.materials.append(floor)
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=24;scene.cycles.use_denoising=True;scene.world.color=(.3,.3,.3)
for location,energy,size in [((1,-4,6),1200,6),((-4,1,4),950,5),((3,4,4),1200,5)]:
 bpy.ops.object.light_add(type='AREA',location=location);o=bpy.context.object;o.data.energy=energy;o.data.size=size;o.rotation_euler=(Vector((0,0,.5))-o.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add(location=(-5,-6,3));cam=bpy.context.object;scene.camera=cam
def render(name,location,target,lens=52):
 cam.location=location;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.lens=lens
 scene.render.resolution_x,scene.render.resolution_y=1300,850;scene.render.resolution_percentage=100
 scene.render.image_settings.file_format='PNG';scene.render.filepath=str(PREVIEW/name);bpy.ops.render.render(write_still=True)
render('tripo-sedan-exterior.png',(-5.1,-6.6,3.05),(0,-.05,.60))
render('tripo-sedan-cockpit.png',(-.43,.08,1.20),(-.43,-4,1.18),25)
pivot=pivots['DoorFL'];rot=Matrix.Rotation(math.radians(65),4,'Z')
for obj in objects:
 if obj['group']=='DoorFL':obj.matrix_world=Matrix.Translation(pivot)@rot@Matrix.Translation(-pivot)@obj.matrix_world
render('tripo-sedan-door-open.png',(-4,-4,2.8),(-.20,0,.72))
