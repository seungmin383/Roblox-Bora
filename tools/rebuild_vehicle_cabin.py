"""Keep the Tripo roof/body; cut exact door and transparent-window apertures."""
from pathlib import Path
from collections import defaultdict
import bpy,bmesh,math
from mathutils import Vector
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'assets/vehicles/local'
bpy.ops.wm.open_mainfile(filepath=str(OUT/'BoraTripoSedan.blend'))
bpy.context.preferences.filepaths.save_version=0
source=next(o for o in bpy.context.scene.objects if o.type=='MESH' and not o.get('group') and len(o.data.polygons)>40000)
source.data.calc_loop_triangles();atlas=source.data.materials[0];uv=source.data.uv_layers.active
roof_tree=BVHTree.FromPolygons([v.co.copy() for v in source.data.vertices],[tuple(t.vertices) for t in source.data.loop_triangles],all_triangles=True)
triangles=[]
for tri in source.data.loop_triangles:
 triangles.append([tuple(source.data.vertices[source.data.loops[l].vertex_index].co)+tuple(source.data.corner_normals[l].vector)+tuple(uv.data[l].uv) for l in tri.loops])
for obj in list(bpy.context.scene.objects):bpy.data.objects.remove(obj,do_unlink=True)

def split(poly,normal,offset):
 inside=[];outside=[]
 for a,b in zip(poly,poly[1:]+poly[:1]):
  da=sum(a[i]*normal[i] for i in range(3))-offset;db=sum(b[i]*normal[i] for i in range(3))-offset
  (inside if da<=1e-8 else outside).append(a)
  if (da< -1e-8 and db>1e-8) or (da>1e-8 and db< -1e-8):
   t=da/(da-db);p=tuple(a[i]+t*(b[i]-a[i]) for i in range(8));inside.append(p);outside.append(p)
 return inside,outside
def partition(poly,planes):
 if any(all(sum(v[i]*normal[i] for i in range(3))-offset>1e-8 for v in poly) for normal,offset in planes):return [],[poly]
 inside=poly;outside=[]
 for normal,offset in planes:
  if len(inside)<3:return [],outside
  inside,cut=split(inside,normal,offset)
  if len(cut)>=3:outside.append(cut)
 return inside,outside
def box(lo,hi):
 return [((1 if i==j else 0 for i in range(3)),hi[j]) for j in range(3)]
def box_planes(x0,x1,y0,y1,z0,z1):
 return [((1,0,0),x1),((-1,0,0),-x0),((0,1,0),y1),((0,-1,0),-y0),((0,0,1),z1),((0,0,-1),-z0)]
def yz_planes(polygon,x0,x1):
 # Polygon is clockwise in longitudinal/height coordinates.
 result=[((1,0,0),x1),((-1,0,0),-x0)]
 for a,b in zip(polygon,polygon[1:]+polygon[:1]):
  dy,dz=b[0]-a[0],b[1]-a[1];result.append(((0,-dz,dy),-dz*a[0]+dy*a[1]))
 return result
def fit_side(polygon):
 result=[]
 for y,z in polygon:
  if z>1.30:
   hit=roof_tree.ray_cast(Vector((.60,y,2)),Vector((0,0,-1)))
   if hit[0] is not None and hit[0].z>1.25:z=min(z,hit[0].z-.025)
  result.append((y,z))
 return result
front_side=fit_side([(-.82,1.00),(-.32,1.375),(.29,1.425),(.29,1.00)])
rear_side=fit_side([(.38,1.00),(.38,1.425),(.98,1.365),(1.40,1.115),(1.28,1.035)])
front_cut=box_planes(-1,1,-1.04,-.42,.99,1.48)
front_cut[:2]=[((1,.12/.62,0),.80-.12/.62*1.04),((-1,.12/.62,0),.80-.12/.62*1.04)]
rear_cut=box_planes(-1,1,.98,1.70,1.105,1.48)
rear_cut[:2]=[((1,-.08/.72,0),.69-.08/.72*.98),((-1,-.08/.72,0),.69-.08/.72*.98)]
windows=[front_cut,rear_cut]
for x0,x1 in [(-1.10,-.62),(.62,1.10)]:
 windows.extend([yz_planes(front_side,x0,x1),yz_planes(rear_side,x0,x1)])
for x0,x1 in [(-1.15,-.915),(.915,1.15)]:windows.append(box_planes(x0,x1,-.99,-.56,.90,1.16))
door_volumes=[]
for side,x0,x1 in [('L',-1.08,-.70),('R',.70,1.08)]:
 for axle,y0,y1 in [('F',-.84,.30),('R',.30,1.22)]:door_volumes.append(('Door'+axle+side,box_planes(x0,x1,y0,y1,.37,1.00)))
regions=defaultdict(list)
def emit(group,poly):
 for i in range(1,len(poly)-1):
  tri=(poly[0],poly[i],poly[i+1]);a,b,c=[Vector(v[:3]) for v in tri]
  x,y,z=(a+b+c)/3;key='Tripo'
  if group.startswith('Door'):
   handle=(.02<y<.32 and .78<z<.91) if group.startswith('DoorF') else (.83<y<1.14 and .83<z<1.00)
   if z<.94 and not handle:key='CarPaint'
  elif group=='Body':
   hood=abs(x)<.85 and -2.14<y<-1.04 and z>.70
   roof=-.4<y<1.1 and z>1.375
   fender=abs(x)>.80 and -1.94<y<-.84 and .38<z<.94
   rear_quarter=abs(x)>.80 and 1.22<y<2.15 and .38<z<.62
   if hood or roof or fender or rear_quarter:key='CarPaint'
  if (b-a).cross(c-a).length>1e-10:regions[(group,key)].append(tri)
for tri in triangles:
 c=sum((Vector(v[:3]) for v in tri),Vector())/3;x,y,z=c
 wheel=None
 for axle,cy in [('F',-1.36),('R',1.36)]:
  if abs(x)>.59 and (y-cy)**2+(z-.325)**2<.325**2 and z<.67:wheel='Wheel'+axle+('L' if x<0 else 'R');break
 if wheel:emit(wheel,tri);continue
 pieces=[list(tri)]
 if -.95<y<1.50 and z<1.40:
  _,pieces=partition(list(tri),box_planes(-.65,.65,-.88,1.40,.36,1.32))
 if z>.88 and -1.15<y<1.82:
  for volume in windows:
   next_pieces=[]
   for poly in pieces:
    _,outside=partition(poly,volume);next_pieces.extend(outside)
   pieces=next_pieces
   if not pieces:break
 for group,volume in door_volumes:
  remaining=[]
  for poly in pieces:
   inside,outside=partition(poly,volume)
   if len(inside)>=3:emit(group,inside)
   remaining.extend(outside)
  pieces=remaining
 for poly in pieces:emit('Body',poly)
carpaint=bpy.data.materials.new('Clean automotive paint');carpaint.use_nodes=True
bs=carpaint.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=(.64,.69,.72,1);bs.inputs['Metallic'].default_value=.45;bs.inputs['Roughness'].default_value=.32
for (group,key),triangles in regions.items():
 vertices=[];faces=[];tex=[];normals=[]
 for tri in triangles:
  base=len(vertices);vertices.extend(v[:3] for v in tri);normals.extend(v[3:6] for v in tri);tex.extend(v[6:8] for v in tri);faces.append((base,base+1,base+2))
 mesh=bpy.data.meshes.new(group+'Tripo');mesh.from_pydata(vertices,[],faces);mesh.update();layer=mesh.uv_layers.new()
 for loop in mesh.loops:layer.data[loop.index].uv=tex[loop.vertex_index]
 for face in mesh.polygons:face.use_smooth=True
 if key=='CarPaint':
  bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.00002);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(mesh);bm.free();mesh.update()
  for face in mesh.polygons:face.use_smooth=True
  # Smooth the lighting normals along the same surface, keeping every Tripo
  # position and crease silhouette. This removes noisy foil-like reflections.
  mesh.normals_split_custom_set_from_vertices([(0.,0.,0.)]*len(mesh.vertices));mesh.update()
  normals=[v.normal.copy() for v in mesh.vertices];neighbors=[set() for _ in mesh.vertices]
  for e in mesh.edges:
   a,b=e.vertices;neighbors[a].add(b);neighbors[b].add(a)
  for _ in range(10):
   normals=[(n*.35+sum((normals[j] for j in neighbors[i]),Vector())*(.65/max(1,len(neighbors[i])))).normalized() for i,n in enumerate(normals)]
  mesh.normals_split_custom_set_from_vertices(normals)
 else:mesh.normals_split_custom_set_from_vertices(normals)
 obj=bpy.data.objects.new(group+key,mesh);bpy.context.collection.objects.link(obj);obj['group']=group;obj['material']=key;mesh.materials.append(carpaint if key=='CarPaint' else atlas)

def material(name,color,alpha=1):
 m=bpy.data.materials.new(name);m.use_nodes=True;p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*color,1);p.inputs['Alpha'].default_value=alpha;p.inputs['Roughness'].default_value=.22
 if alpha<1:m.surface_render_method='DITHERED'
 return m
glass=material('Real transparent glass',(.10,.15,.18),.22);black=material('Window seals',(.008,.012,.016))
def skin(name,vertices,faces,group,key,mat):
 mesh=bpy.data.meshes.new(name);mesh.from_pydata(vertices,[],faces);mesh.update();obj=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(obj);obj['group']=group;obj['material']=key;mesh.materials.append(mat)
 for f in mesh.polygons:f.use_smooth=True
 return obj
def edge(a,b,group):
 a,b=Vector(a),Vector(b);bpy.ops.mesh.primitive_cube_add(size=1,location=(a+b)/2);o=bpy.context.object;o.scale=(.018,.018,(b-a).length);o.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler();bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o['group']=group;o['material']='Black';o.data.materials.append(black)
def pane(name,points,group,frame=True):
 skin(name,points,[tuple(range(len(points)))],group,'Glass',glass)
 if frame:
  for a,b in zip(points,points[1:]+points[:1]):edge(a,b,group)
for side in (-1,1):
 suffix='L' if side<0 else 'R'
 for name,polygon in [('F',front_side),('R',fit_side([(.38,1.00),(.38,1.425),(.98,1.365),(1.20,1.235),(1.20,1.02)]))]:
  points=[(side*(.902-.18*min(1,max(0,(z-1.0)/.425))),y,z) for y,z in polygon]
  pane('Clear door '+name+suffix,points,'Door'+name+suffix)
 polygon=[(1.245,1.04),(1.245,1.215),(1.39,1.115)]
 pane('Fixed quarter glass',[(side*(.902-.18*(z-1.)/.425),y,z) for y,z in polygon],'Body')
pane('Clear windshield',[(-.80,-1.04,1.012),(.80,-1.04,1.012),(.68,-.42,1.382),(-.68,-.42,1.382)],'Body',False)
pane('Clear rear glass',[(-.69,.98,1.374),(.69,.98,1.374),(.77,1.70,1.12),(-.77,1.70,1.12)],'Body',False)

# Interior construction geometry is reused; the exterior roof/pillars remain
# the original Tripo geometry instead of a cabin of unrelated proportions.
prefixes=('Undertray','Cabin floor','Interior door trim','Door armrest','Door pull','Dashboard','Display surround','Gauge glass','Navigation glass','Air vent','Dash metal trim','Center console','Console armrest','Shift selector','Cup holder','Seat base','Seat back','Headrest','Seat bolster','Seat seam','Rear bench','Rear backrest','Rear headrest','Rear view mirror','Steering column','Steering rim','Steering hub','Steering spoke','Lower spoke','Mirror stem','Mirror shell','Mirror glass')
with bpy.data.libraries.load(str(OUT/'BoraSedan.blend'),link=False) as (available,loaded):loaded.objects=[n for n in available.objects if n.startswith(prefixes)]
for obj in loaded.objects:
 if obj:
  bpy.context.collection.objects.link(obj)
  if obj.name.startswith(('Mirror stem','Mirror shell','Mirror glass')):obj.location.z+=.10
  elif obj.name.startswith('Interior door trim'):obj.location.z+=.055
liner_material=next(o.data.materials[0] for o in bpy.context.scene.objects if o.type=='MESH' and o.get('material')=='Cabin')
vertices=[];faces=[];nx,ny=16,18
for j in range(ny+1):
 y=-.30+1.06*j/ny
 for i in range(nx+1):
  x=-.65+1.30*i/nx;hit=roof_tree.ray_cast(Vector((x,y,2.0)),Vector((0,0,-1)))
  vertices.append((x,y,hit[0].z-.025 if hit[0] is not None else 1.36))
for j in range(ny):
 for i in range(nx):
  a=j*(nx+1)+i;faces.append((a,a+nx+1,a+nx+2,a+1))
skin('Roof liner fitted to source',vertices,faces,'Body','Cabin',liner_material)
# Additional cabin controls from the repaired construction scene.
prefixes=('Pedal','Steering stalk','Climate control fascia','Climate key','Headrest support','Vent slat')
with bpy.data.libraries.load(str(OUT/'BoraTripoSedan_Polished.blend'),link=False) as (available,loaded):loaded.objects=[n for n in available.objects if n.startswith(prefixes)]
for obj in loaded.objects:
 if obj:bpy.context.collection.objects.link(obj)
bpy.context.view_layer.update()
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'BoraTripoSedan_Refit.blend'))
print('Tripo roof/body retained; exact door cuts and transparent windows fitted to actual cabin.',sum(len(t) for t in regions.values()),'source-derived triangles.',flush=True)
