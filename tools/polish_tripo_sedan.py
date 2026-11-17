"""Repair the Tripo exterior's paint surfaces and complete its real cabin."""
from pathlib import Path
import bpy,bmesh,math,numpy as np
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'assets/vehicles/local'
bpy.ops.wm.open_mainfile(filepath=str(OUT/'BoraTripoSedan.blend'))
bpy.context.preferences.filepaths.save_version=0
paint=next(o.data.materials[0] for o in bpy.context.scene.objects if o.type=='MESH' and o.get('material')=='Paint')
shader=paint.node_tree.nodes.get('Principled BSDF');shader.inputs['Base Color'].default_value=(.42,.47,.51,1);shader.inputs['Metallic'].default_value=.65;shader.inputs['Roughness'].default_value=.25
# Fit continuous broad surfaces to the generated car itself. Project every
# source group through the same fit, including shared panel-border vertices.
source_objects=[o for o in bpy.context.scene.objects if o.type=='MESH' and o.get('material')=='Tripo' and not o.get('group','').startswith('Wheel')]
points=np.array([tuple(v.co) for o in source_objects for v in o.data.vertices])
def fit_height(mask):
 p=points[mask];x,y=p[:,0],p[:,1]
 return np.linalg.lstsq(np.column_stack([np.ones(len(p)),y,y*y,x*x]),p[:,2],rcond=None)[0]
hood_fit=fit_height((np.abs(points[:,0])<.75)&(points[:,1]>-2.13)&(points[:,1]<-1.02)&(points[:,2]>.70))
trunk_fit=fit_height((np.abs(points[:,0])<.73)&(points[:,1]>1.52)&(points[:,1]<2.16)&(points[:,2]>.79)&(points[:,2]<1.1))
samples=[]
for y in np.linspace(-1.95,2.10,22):
 p=points[(np.abs(points[:,1]-y)<.11)&(np.abs(points[:,0])>.82)&(points[:,2]>.48)&(points[:,2]<.83)]
 if len(p):samples.append((y,np.quantile(np.abs(p[:,0]),.70)))
width_fit=np.polyfit([p[0] for p in samples],[p[1] for p in samples],4)
for obj in source_objects:
 for vertex in obj.data.vertices:
  x,y,z=vertex.co
  if abs(x)<.85 and -2.14<y<-.99 and .69<z<1.05:
   c=hood_fit;vertex.co.z=float(c[0]+c[1]*y+c[2]*y*y+c[3]*x*x)
  elif abs(x)<.83 and 1.49<y<2.18 and .79<z<1.11:
   c=trunk_fit;vertex.co.z=float(c[0]+c[1]*y+c[2]*y*y+c[3]*x*x)
  elif abs(x)>.80 and -1.94<y<2.12 and .35<z<.90:
   width=float(np.polyval(width_fit,y))-.020*((z-.66)/.32)**2
   blend=min(1,max(0,(abs(x)-.80)/.05));vertex.co.x=math.copysign(abs(x)+(width-abs(x))*blend,x)
count=0
for obj in list(bpy.context.scene.objects):
 if obj.type!='MESH' or obj.get('material')!='Tripo' or obj.get('group','').startswith('Wheel'):continue
 group=obj['group'];bpy.context.view_layer.objects.active=obj
 bm=bmesh.new();bm.from_mesh(obj.data);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.00002);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
 boundary={tuple(round(c,6) for c in v.co) for edge in bm.edges if len(edge.link_faces)!=2 for v in edge.verts}
 bm.to_mesh(obj.data);bm.free();obj.data.update()
 def is_paint(p):
  x,y,z=p
  if group.startswith('Door'):return True
  return (abs(x)<.86 and -2.15<y<-.92 and z>.69) or (abs(x)>.65 and -1.94<y<-.78 and z>.38) or (abs(x)>.65 and 1.19<y<2.20 and .37<z<.68) or (abs(x)<.83 and 1.45<y<2.21 and z>.80)
 chosen={v.index for v in obj.data.vertices if is_paint(v.co) and tuple(round(c,6) for c in v.co) not in boundary}
 vg=obj.vertex_groups.new(name='Broad manufactured surfaces');vg.add(list(chosen),1,'REPLACE')
 smooth=obj.modifiers.new('Remove generated surface chatter','SMOOTH');smooth.vertex_group=vg.name;smooth.factor=.35;smooth.iterations=2
 bpy.ops.object.modifier_apply(modifier=smooth.name)
 for poly in obj.data.polygons:poly.use_smooth=True
 obj.data.normals_split_custom_set_from_vertices([(0.,0.,0.)]*len(obj.data.vertices))
 obj.data.update();obj.data.calc_loop_triangles();uv=obj.data.uv_layers.active
 sets={'CarPaint':[],'Tripo':[]}
 for tri in obj.data.loop_triangles:
  center=sum((obj.data.vertices[obj.data.loops[l].vertex_index].co for l in tri.loops),Vector())/3
  key='CarPaint' if is_paint(center) else 'Tripo'
  sets[key].append([(obj.data.vertices[obj.data.loops[l].vertex_index].co.copy(),obj.data.corner_normals[l].vector.copy(),tuple(uv.data[l].uv)) for l in tri.loops])
 original_material=obj.data.materials[0]
 for key,triangles in sets.items():
  if not triangles:continue
  vertices=[];faces=[];tex=[];normals=[]
  for tri in triangles:
   n=len(vertices);vertices.extend(v[0] for v in tri);normals.extend(v[1] for v in tri);tex.extend(v[2] for v in tri);faces.append((n,n+1,n+2))
  mesh=bpy.data.meshes.new(group+key+'Polished');mesh.from_pydata(vertices,[],faces);mesh.update();layer=mesh.uv_layers.new()
  for loop in mesh.loops:layer.data[loop.index].uv=tex[loop.vertex_index]
  for poly in mesh.polygons:poly.use_smooth=True
  mesh.normals_split_custom_set_from_vertices(normals)
  new=bpy.data.objects.new(group+key+'Polished',mesh);bpy.context.collection.objects.link(new);new.matrix_world=obj.matrix_world.copy();new['group']=group;new['material']=key
  mesh.materials.append(paint if key=='CarPaint' else original_material)
  if key=='CarPaint':count+=len(triangles)
 bpy.data.objects.remove(obj,do_unlink=True)

# Replace the block-shaped roof and broad rectangular C-pillars with a curved
# skin and tapered sheet-metal pillars. The car's proportions remain Tripo's.
for obj in list(bpy.context.scene.objects):
 if obj.type=='MESH' and (obj.name=='Roof' or obj.name.startswith('C pillar')):bpy.data.objects.remove(obj,do_unlink=True)
def panel(name,vertices,faces,material,group='Body',thickness=.018):
 mesh=bpy.data.meshes.new(name);mesh.from_pydata(vertices,[],faces);mesh.update()
 obj=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(obj);obj['group']=group;obj['material']=material.name if material==paint else 'Cabin';mesh.materials.append(material)
 if material==paint:obj['material']='Paint'
 bpy.context.view_layer.objects.active=obj
 if thickness:
  mod=obj.modifiers.new('Sheet thickness','SOLIDIFY');mod.thickness=thickness;bpy.ops.object.modifier_apply(modifier=mod.name)
 for poly in mesh.polygons:poly.use_smooth=True
 return obj
vertices=[];faces=[];nx,ny=12,14
for j in range(ny+1):
 t=j/ny;y=-.42+1.27*t;edge=1.39-.05*t+.055*math.sin(math.pi*t)
 for i in range(nx+1):
  u=-1+2*i/nx;vertices.append((u*(.72+.018*math.sin(math.pi*t)),y,edge+.022*(1-u*u)))
for j in range(ny):
 for i in range(nx):
  a=j*(nx+1)+i;faces.append((a,a+1,a+nx+2,a+nx+1))
panel('Curved roof skin',vertices,faces,paint)
for side in (-1,1):
 panel('Tapered C pillar',[(side*.735,.78,1.34),(side*.76,.89,1.32),(side*.91,1.49,.87),(side*.86,1.34,.88)],[(0,1,2,3)],paint,thickness=.025)

# Mirrors were removed with the generated opaque greenhouse. Attach actual
# mirror housings/glass to the front doors, and distinct handles to all doors.
prefixes=('Mirror stem','Mirror shell','Mirror glass','Exterior handle')
with bpy.data.libraries.load(str(OUT/'BoraSedan.blend'),link=False) as (available,loaded):
 loaded.objects=[n for n in available.objects if n.startswith(prefixes)]
for obj in loaded.objects:
 if obj:
  bpy.context.collection.objects.link(obj)
  if obj.get('material')=='Paint':obj.data.materials.clear();obj.data.materials.append(paint)

# Mechanical controls around the cabin complement the working screen GUI.
cabin=next(o.data.materials[0] for o in bpy.context.scene.objects if o.type=='MESH' and o.get('material')=='Cabin')
silver=next(o.data.materials[0] for o in bpy.context.scene.objects if o.type=='MESH' and o.get('material')=='Silver')
def cube(name,center,size,key='Cabin',bevel=.008):
 bpy.ops.mesh.primitive_cube_add(size=1,location=center);obj=bpy.context.object;obj.name=name;obj.scale=size;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 obj['group']='Body';obj['material']=key;obj.data.materials.append(cabin if key=='Cabin' else silver)
 mod=obj.modifiers.new('Rounded control edges','BEVEL');mod.width=bevel;mod.segments=3;bpy.ops.object.modifier_apply(modifier=mod.name)
 return obj
for x in (-.53,-.39):
 pedal=cube('Pedal', (x,-.66,.43),(.065,.09,.02),'Silver');pedal.rotation_euler.x=math.radians(35)
for x in (-.63,-.27):cube('Steering stalk',(x,-.55,.88),(.13,.025,.025))
cube('Climate control fascia',(.12,-.526,.78),(.43,.035,.09))
for x in (-.025,.265):
 bpy.ops.mesh.primitive_uv_sphere_add(segments=16,ring_count=8,radius=.025,location=(x,-.498,.78));obj=bpy.context.object;obj.scale=(1,.55,1);obj['group']='Body';obj['material']='Silver';obj.data.materials.append(silver)
for i in range(5):cube('Climate key',(.04+i*.04,-.501,.78),(.026,.009,.018),'Silver',.003)
for x in (-.43,.43):
 for dx in (-.075,.075):cube('Headrest support',(x+dx,.62,1.00),(.011,.011,.12),'Silver',.003)
for x in (-.69,.69):
 for i in range(5):cube('Vent slat',(x-.07+i*.035,-.515,.84),(.008,.018,.032),'Silver',.002)
bpy.context.view_layer.update()
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'BoraTripoSedan_Polished.blend'))
print('Polished Tripo-derived paint faces:',count,'; curved roof, tapered pillars, mirrors, handles and cabin controls.',flush=True)
