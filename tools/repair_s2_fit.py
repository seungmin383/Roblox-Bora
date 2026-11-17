"""Localized S2 nose/scuttle assembly repair, preserving the open delivery file.

Replaces only the damaged source nose ahead of the front wheel. The hood,
fenders and all moving assemblies behind the measured cut remain in place.
"""
import bpy,bmesh,math,json,hashlib,sys
import numpy as np
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree
from mathutils.geometry import barycentric_transform
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'assets/vehicles/retopology'
sys.path.insert(0,str(ROOT/'tools'))
from vehicle_mesh_ops import partition
SOURCE=OUT/'BoraS2_Clean.blend';DEST=OUT/'BoraS2_FitFix.blend'
bpy.ops.wm.open_mainfile(filepath=str(SOURCE));scene=bpy.context.scene
scene.render.resolution_x=1200;scene.render.resolution_y=900;scene.cycles.samples=32
paint=bpy.data.materials['S2 • pearl silver paint'];trim=bpy.data.materials['S2 • satin graphite'];chrome=bpy.data.materials['S2 • satin aluminium'];grille=bpy.data.materials['S2 • grille texture pattern']
body=bpy.data.objects['Body_paint'];body.data.calc_loop_triangles()
tree=BVHTree.FromPolygons([body.matrix_world@v.co for v in body.data.vertices],[t.vertices for t in body.data.loop_triangles],all_triangles=True)
CUT=-1.640;CZ=.53

def signature(o):
 h=hashlib.sha256()
 for v in o.data.vertices:h.update(np.asarray(v.co,dtype='<f4').tobytes())
 for p in o.data.polygons:h.update(np.asarray(p.vertices,dtype='<i4').tobytes())
 h.update(np.asarray(o.matrix_world,dtype='<f4').tobytes());return h.hexdigest()
before={o.name:signature(o) for o in scene.objects if o.type=='MESH' and o.get('asset')}
changed={'Body_paint','Front_grille_shallow_panel','Front_grille_surround','Lower_grille_shallow_panel','Lower_grille_surround','Front_plate','Dashboard_upper','Dashboard_lower','Instrument_binnacle','Instrument_display'}
old_rear_faces={tuple(sorted(tuple(round(c,7) for c in body.data.vertices[i].co) for i in p.vertices)) for p in body.data.polygons if all(body.data.vertices[i].co.y>CUT+1e-5 for i in p.vertices)}

def mesh(name,verts,faces,mat,smooth=True,uv=None):
 me=bpy.data.meshes.new(name);me.from_pydata(verts,[],faces);me.update()
 o=bpy.data.objects.new(name,me);bpy.data.collections['S2_Body'].objects.link(o);o['asset']='BORA S2';o['group']='Body';me.materials.append(mat)
 if uv:
  layer=me.uv_layers.new(name='UVMap')
  for f,coords in zip(me.polygons,uv):
   for li,co in zip(f.loop_indices,coords):layer.data[li].uv=co
 bm=bmesh.new();bm.from_mesh(me);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(me);bm.free()
 for f in me.polygons:f.use_smooth=smooth
 return o

def thick(o,t):
 bpy.context.view_layer.objects.active=o
 mod=o.modifiers.new('Closed fitted skin','SOLIDIFY');mod.thickness=t;mod.offset=-1;mod.use_even_offset=False
 bpy.ops.object.modifier_apply(modifier=mod.name)
 # Split only manufactured returns; broad fitted surfaces stay continuous.
 bm=bmesh.new();bm.from_mesh(o.data)
 for e in bm.edges:
  if e.is_manifold:e.smooth=e.calc_face_angle(0)<math.radians(55)
 bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(o.data);bm.free();o.data.update()

def remove(name):
 o=bpy.data.objects.get(name)
 if o:bpy.data.objects.remove(o,do_unlink=True)

def stitch(o):
 me=o.data;bm=bmesh.new();bm.from_mesh(me);bm.verts.ensure_lookup_table()
 bounds={v.index for e in bm.edges if e.is_boundary for v in e.verts};kd=KDTree(len(bounds))
 for i in bounds:kd.insert(me.vertices[i].co,i)
 kd.balance();inserts={}
 for e in bm.edges:
  if not e.is_boundary:continue
  a,b=[v.index for v in e.verts];p=me.vertices[a].co;q=me.vertices[b].co;d=q-p;ll=d.length_squared
  if ll<1e-14:continue
  candidates=[]
  for co,i,dist in kd.find_range((p+q)*.5,math.sqrt(ll)*.501+2e-6):
   if i in (a,b):continue
   t=(co-p).dot(d)/ll
   if 1e-5<t<1-1e-5 and (co-p-t*d).length<2e-6:candidates.append((t,i))
  if candidates:inserts[(a,b)]=sorted(candidates)
 bm.free()
 if not inserts:return
 verts=[tuple(v.co) for v in me.vertices];faces=[]
 for f in me.polygons:
  ids=list(f.vertices);row=[]
  for j,a in enumerate(ids):
   b=ids[(j+1)%len(ids)];row.append(a)
   extra=inserts.get((a,b))
   if extra is None:extra=[(1-t,i) for t,i in reversed(inserts.get((b,a),[]))]
   row.extend(i for t,i in extra)
  faces.append(row)
 new=bpy.data.meshes.new(me.name+'_stitched');new.from_pydata(verts,[],faces);new.materials.append(paint);new.update();o.data=new
 print('Stitched nose boundaries',len(inserts),flush=True)

# Retain the selected Tripo lamp graphic, rectified onto a clean insert.
me=body.data
lampmat=bpy.data.materials.new('S2 • clean headlamp optics');lampmat.use_nodes=True
lbs=lampmat.node_tree.nodes.get('Principled BSDF');lbs.inputs['Metallic'].default_value=.20;lbs.inputs['Roughness'].default_value=.23;lbs.inputs['Coat Weight'].default_value=.3
im=bpy.data.images.load(str(OUT/'BoraS2_FitLampBaked.png'),check_existing=True);im.name='S2_FitHeadlampOptics';im.pack()
node=lampmat.node_tree.nodes.new('ShaderNodeTexImage');node.image=im;lampmat.node_tree.links.new(node.outputs['Color'],lbs.inputs['Base Color'])

# Nose cross-section is measured directly on the retained Tripo body.
# Below the original open engine bay, use an inconspicuous flat undertray.
def rearpoint(phi,y=CUT):
 d=Vector((math.cos(phi),0,math.sin(phi)));c=Vector((0,y,CZ))
 p,n,idx,dist=tree.ray_cast(c+3*d,-d,3)
 if p is not None and (p-c).dot(d)>.12 and (abs(p.x)>.75 or p.z>.75):return p
 rx=.938;rz=(.958-CZ) if d.z>=0 else (CZ-.207)
 radius=((abs(d.x)/rx)**4+(abs(d.z)/rz)**4)**(-.25)
 return c+d*radius

# Save per-corner normals for untouched regions; a BMesh cut must not erase the
# previously approved side/door/arch shading.
normalmap={}
for p in me.polygons:
 if all(me.vertices[i].co.y>CUT+1e-5 for i in p.vertices):
  key=tuple(sorted(tuple(round(c,7) for c in me.vertices[i].co) for i in p.vertices))
  normalmap[key]={tuple(round(c,7) for c in me.vertices[me.loops[li].vertex_index].co):me.corner_normals[li].vector.copy() for li in p.loop_indices}
bm=bmesh.new();bm.from_mesh(me)
bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),dist=1e-7,plane_co=(0,CUT,0),plane_no=(0,1,0),clear_inner=True)
boundary=[e for e in bm.edges if e.is_boundary]
caps=bmesh.ops.holes_fill(bm,edges=boundary,sides=0)['faces']
bmesh.ops.triangulate(bm,faces=caps,ngon_method='EAR_CLIP')
cutedges=[e for e in bm.edges if all(abs(v.co.y-CUT)<1e-6 for v in e.verts)]
bmesh.ops.dissolve_degenerate(bm,edges=cutedges,dist=1e-7)
bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(me);bm.free();me.update()
normals=[n.vector.copy() for n in me.corner_normals]
for p in me.polygons:
 key=tuple(sorted(tuple(round(c,7) for c in me.vertices[i].co) for i in p.vertices))
 if key in normalmap:
  for li in p.loop_indices:normals[li]=normalmap[key][tuple(round(c,7) for c in me.vertices[me.loops[li].vertex_index].co)]
me.normals_split_custom_set(normals);me.update()
for name in ['Front_grille_shallow_panel','Front_grille_surround','Lower_grille_shallow_panel','Lower_grille_surround']:remove(name)

# A single continuous cap replaces overlapping painted strips and source
# cavities. Grille and lamps are shallow conforming inserts on this SAME field.
def front_y(x,z):
 center=float(np.interp(z,[.205,.245,.32,.45,.53,.61,.72,.85],[-2.25,-2.27,-2.275,-2.296,-2.29,-2.257,-2.226,-2.18]))
 q=abs(x)/.9
 return center+.29*q*q+.05*q**4
def cap(u,v):
 x=u*(.835-.015*(2*v-1)**2);z=.214+.012*u*u+v*(.636-.058*u*u)
 return Vector((x,front_y(x,z),z))
NU=33;NV=17;vv=[tuple(cap(u,v)) for v in np.linspace(0,1,NV) for u in np.linspace(-1,1,NU)];ff=[]
for j in range(NV-1):
 for i in range(NU-1):a=j*NU+i;ff.append((a,a+1,a+1+NU,a+NU))
border=list(range(NU))+[j*NU+NU-1 for j in range(1,NV)]+list(range((NV-1)*NU+NU-2,(NV-1)*NU-1,-1))+[j*NU for j in range(NV-2,0,-1)]
frontpoints=[Vector(vv[i]) for i in border];back=[];tangents=[]
for p in frontpoints:
 phi=math.atan2(p.z-CZ,p.x);r=rearpoint(phi);r.y=CUT+.001
 # Tiny outward underlap prevents daylight at the retained body join.
 radial=Vector((r.x,0,r.z-CZ)).normalized();r+=radial*.0006;back.append(r)
 b=rearpoint(phi,CUT+.04);t=(r-b)/.04
 # The next station can be inside the wheel opening. Its missing silhouette
 # is not a valid surface derivative; keep the join tangent locally bounded.
 t.x=max(-.32,min(.32,t.x));t.z=max(-.28,min(.28,t.z));t.y=-1
 tangents.append(t)
previous=border
for t in [.82,.60,.38,.19,.07,0]:
 current=[]
 for k,(p,r) in enumerate(zip(frontpoints,back)):
  # t is distance from rear; use the measured body tangent at the joint and
  # fall smoothly onto the cap shoulder without a raised lamp/hood patch.
  d=(p-r);m=tangents[k]*abs(d.y);h00=2*t**3-3*t*t+1;h10=t**3-2*t*t+t;h01=-2*t**3+3*t*t
  q=r*h00+m*h10+p*h01+d*(t**3-t*t)
  current.append(len(vv));vv.append(tuple(q))
 for k in range(len(border)):l=(k+1)%len(border);ff.append((previous[k],previous[l],current[l],current[k]))
 previous=current
# Trim the same circular clearance through both side skins before adding
# thickness. This retains a real wheel opening instead of filling it with an
# artificial rear cap or sampling the inner engine wall as the outer fender.
planes=[];R=.39;cy=-1.43619835;cz=.338
for k in range(64):
 a=math.tau*k/64;ny=math.cos(a);nz=math.sin(a);planes.append(((0,ny,nz),ny*cy+nz*cz+R))
clipped=[]
for f in ff:
 inside,outside=partition([vv[i] for i in f],planes)
 clipped.extend(outside)
nv=[];nf=[]
for p in clipped:
 base=len(nv);nv.extend(p);nf.append(tuple(range(base,len(nv))))
nose=mesh('Front_continuous_fitted_skin',nv,nf,paint)
bm=bmesh.new();bm.from_mesh(nose.data);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=1e-7);bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=1e-7);bm.to_mesh(nose.data);bm.free()
stitch(nose)
bm=bmesh.new();bm.from_mesh(nose.data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
frontfaces=[f for f in bm.faces if abs(f.calc_center_median().x)<.15 and f.calc_center_median().y<-2.22]
if sum(f.normal.y*f.calc_area() for f in frontfaces)>0:bmesh.ops.reverse_faces(bm,faces=list(bm.faces))
bm.to_mesh(nose.data);bm.free()
for f in nose.data.polygons:f.use_smooth=True
thick(nose,.006)
nose.data.calc_loop_triangles();nose_tree=BVHTree.FromPolygons([v.co for v in nose.data.vertices],[t.vertices for t in nose.data.loop_triangles],all_triangles=True)
def insert_y(x,z):
 hit,n,idx,d=nose_tree.ray_cast(Vector((x,-3,z)),Vector((0,1,0)),1.5)
 if hit is None:raise ValueError(('Insert outside the nose skin',x,z))
 return hit.y

def panel(name,outline,mat,offset=.003):
 # Subdivide the convex outline into radial quad rings; a giant nonplanar
 # n-gon would interpolate through the nose and reopen the apparent holes.
 center=Vector((sum(x for x,z in outline)/len(outline),sum(z for x,z in outline)/len(outline)))
 edge=[]
 for a,b in zip(outline,outline[1:]+outline[:1]):
  steps=max(1,math.ceil(math.dist(a,b)/.035))
  for t in np.linspace(0,1,steps,endpoint=False):edge.append(Vector(a).lerp(Vector(b),float(t)))
 points=[];faces=[];n=len(edge)
 for r in [1,.72,.42,.14]:
  for e in edge:
   x,z=center.lerp(e,r);points.append((x,insert_y(x,z)-offset,z))
 for j in range(3):
  for k in range(n):l=(k+1)%n;faces.append((j*n+k,j*n+l,(j+1)*n+l,(j+1)*n+k))
 ci=len(points);points.append((center.x,insert_y(center.x,center.y)-offset,center.y))
 for k in range(n):faces.append((3*n+k,3*n+(k+1)%n,ci))
 uvs=[]
 for f in faces:
  coords=[]
  for idx in f:
   p=Vector(points[idx]);x,y,z=p
   if mat==lampmat:
    coords.append(((abs(x)-.532)/(.815-.532),(z-.638)/(.796-.638)))
   else:coords.append((x/1.03+.5,(z-.31)/.19))
  uvs.append(coords)
 o=mesh(name,points,faces,mat,uv=uvs);thick(o,.0025);return o

def surround(name,outline,mat,width=.0055):
 center=Vector((sum(x for x,z in outline)/len(outline),sum(z for x,z in outline)/len(outline)));outer=[];inner=[]
 for a,b in zip(outline,outline[1:]+outline[:1]):
  steps=max(1,math.ceil(math.dist(a,b)/.035))
  for t in np.linspace(0,1,steps,endpoint=False):
   p=Vector(a).lerp(Vector(b),float(t));d=(p-center).normalized();outer.append(p+d*width/2);inner.append(p-d*width/2)
 v=[(p.x,insert_y(p.x,p.y)-.005,p.y) for p in outer+inner];n=len(outer)
 o=mesh(name,v,[(k,(k+1)%n,(k+1)%n+n,k+n) for k in range(n)],mat);thick(o,.003);return o

main=[(-.505,.707),(-.445,.765),(.445,.765),(.505,.707),(.43,.617),(-.43,.617)]
lower=[(-.49,.361),(-.46,.412),(.46,.412),(.49,.361),(.455,.315),(-.455,.315)]
panel('Front_grille_shallow_panel',main,grille);surround('Front_grille_surround',main,chrome,.007)
panel('Lower_grille_shallow_panel',lower,grille);surround('Lower_grille_surround',lower,trim,.006)
for side,label in [(1,'L'),(-1,'R')]:
 outline=[(side*x,z) for x,z in [(.532,.753),(.770,.796),(.815,.745),(.748,.652),(.563,.638)]]
 panel(label+'_Front_lamp_fitted',outline,lampmat,offset=.0035);surround(label+'_Front_lamp_gasket',outline,trim,.008)
 # A simple textured dark insert, with a defined boundary instead of the
 # source's torn black polygons. Its backing is the continuous bumper skin.
 fog=[(side*x,z) for x,z in [(.59,.397),(.756,.43),(.79,.344),(.729,.295),(.57,.312)]]
 panel(label+'_Front_lower_insert',fog,trim,.0025)
plate=bpy.data.objects['Front_plate'];old_y=sum((plate.matrix_world@v.co).y for v in plate.data.vertices)/len(plate.data.vertices);plate.location.y+=front_y(0,.487)-.008-old_y

# The old rectangular dashboard intersected the curved lower windscreen.
# Front edge follows that glass base and sits 45 mm beneath it.
def glassbase(x):
 u=x/(.175*4.35);yn=-.232+.035*u*u
 return yn*4.68,(.236+.038*yn+.0002)*4.31
remove('Dashboard_upper')
us=np.linspace(-1,1,29);vs=np.linspace(0,1,8);dv=[];df=[]
for v in vs:
 for u in us:
  x=float(u*.694);gy,gz=glassbase(x);y=(gy+.060)*(1-v)+(-.751)*v;z=(gz-.045)*(1-v)+(.986-.012*u*u)*v
  dv.append((x,y,z))
for j in range(len(vs)-1):
 for i in range(len(us)-1):a=j*len(us)+i;df.append((a,a+1,a+1+len(us),a+len(us)))
dash=mesh('Dashboard_upper',dv,df,trim);thick(dash,.025)
lowerdash=bpy.data.objects['Dashboard_lower']
for v in lowerdash.data.vertices:
 world=lowerdash.matrix_world@v.co;gy,gz=glassbase(world.x)
 if world.y<gy+.058:world.y=gy+.058;v.co=lowerdash.matrix_world.inverted()@world
lowerdash.data.update()
for name in ['Instrument_binnacle','Instrument_display']:bpy.data.objects[name].location.y+=.085

unchanged=[o.name for o in scene.objects if o.type=='MESH' and o.name in before and o.name not in changed and signature(o)!=before[o.name]]
assert not unchanged,unchanged
now_faces={tuple(sorted(tuple(round(c,7) for c in body.data.vertices[i].co) for i in p.vertices)) for p in body.data.polygons}
assert old_rear_faces.issubset(now_faces),'An approved body face behind the repair cut was changed'
scene['S2FitRepair']='Continuous nose skin, conforming inserts, glass-fitted dashboard; no game installation'
scene['S2FitRepairSourceSHA256']=hashlib.sha256(SOURCE.read_bytes()).hexdigest()
scene['S2FitRepairCutY']=CUT
for o in scene.objects:o.select_set(False)
nose.hide_set(False);nose.select_set(True);bpy.context.view_layer.objects.active=nose
for screen in bpy.data.screens:
 for area in screen.areas:
  if area.type=='VIEW_3D':area.spaces.active.shading.type='MATERIAL'
bpy.context.view_layer.update();bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(DEST))
report={'source':str(SOURCE),'output':str(DEST),'cutY':CUT,'preservedObjects':len(before)-len(changed),'unexpectedChangedObjects':unchanged,'preservedBodyFacesBehindCut':len(old_rear_faces),'installedInPlace':False}
(OUT/'BoraS2_FitRepairProcess.json').write_text(json.dumps(report,indent=2))
print('FIT_REPAIR',json.dumps(report),flush=True)
