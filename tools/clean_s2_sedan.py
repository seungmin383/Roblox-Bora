"""Measured regional rebuild of the selected Tripo P2 sedan; candidate assets only.
Source-normalized coordinates are used until the final physical scale conversion.
"""
import bpy,bmesh,math,json,sys,hashlib
import numpy as np
from mathutils import Vector,Matrix
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from vehicle_mesh_ops import partition,box
from s2_fair_surfaces import FairBody,repair_micro_geometry
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'assets/vehicles/retopology'
SCALE=Vector((4.35,4.68,4.31));built=[];report={}
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.open_mainfile(filepath=str(OUT/'BoraS2_Source_Review.blend'))
source=bpy.data.objects['S2_Source']
for v in source.data.vertices:v.co/=4.68
source.data.update()
source.data.calc_loop_triangles()
SOURCE_BVH=BVHTree.FromPolygons([v.co for v in source.data.vertices],[t.vertices for t in source.data.loop_triangles],all_triangles=True)
source_mat=source.data.materials[0]
for o in list(bpy.data.objects):
 if o!=source:bpy.data.objects.remove(o,do_unlink=True)
def material(name,color,metal=0,rough=.4):
 m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);m.use_nodes=True;b=m.node_tree.nodes.get('Principled BSDF')
 b.inputs['Base Color'].default_value=(*color,1);b.inputs['Metallic'].default_value=metal;b.inputs['Roughness'].default_value=rough
 return m
paint=material('S2 • pearl silver paint',(.46,.52,.59),.38,.32)
bs=paint.node_tree.nodes.get('Principled BSDF');bs.inputs['Coat Weight'].default_value=.32;bs.inputs['Coat Roughness'].default_value=.22
rubber=material('S2 • rubber',(.014,.018,.023),0,.65)
trim=material('S2 • satin graphite',(.023,.030,.038),.20,.39)
chrome=material('S2 • satin aluminium',(.46,.49,.54),.82,.24)
seatmat=material('S2 • cloth upholstery',(.049,.062,.079),0,.85)
inside=material('S2 • cabin polymer',(.030,.039,.050),0,.65)
glass=material('S2 • actual laminated glass',(.94,.975,.995),0,.025)
gbs=glass.node_tree.nodes.get('Principled BSDF');gbs.inputs['Transmission Weight'].default_value=1;gbs.inputs['IOR'].default_value=1.45
gbs.inputs['Coat Weight'].default_value=.12
lamp=source_mat.copy();lamp.name='S2 • lamp graphics only'
lbs=lamp.node_tree.nodes.get('Principled BSDF');lbs.inputs['Metallic'].default_value=.20;lbs.inputs['Roughness'].default_value=.23
for node in lamp.node_tree.nodes:
 if node.type=='TEX_IMAGE' and node.image:
  im=node.image.copy();im.name='S2_LampGraphics';im.scale(2048,2048);im.filepath_raw=str(OUT/'BoraS2_LampGraphics.png');im.file_format='PNG';im.save();node.image=im;im.pack()
def finish(o,name,mat,group='Body',smooth=True):
 o.name=name;o['group']=group;o['asset']='BORA S2';built.append(o)
 o.data.materials.clear();o.data.materials.append(mat)
 for p in o.data.polygons:p.use_smooth=smooth
 return o
def meshobj(name,verts,faces,mat,group='Body',smooth=True,uv=None):
 me=bpy.data.meshes.new(name);me.from_pydata(verts,[],faces);me.update()
 o=bpy.data.objects.new(name,me);bpy.context.collection.objects.link(o);finish(o,name,mat,group,smooth)
 if uv is not None:
  layer=me.uv_layers.new(name='UVMap')
  for p,coords in zip(me.polygons,uv):
   for li,co in zip(p.loop_indices,coords):layer.data[li].uv=co
 bm=bmesh.new();bm.from_mesh(me);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=1e-7)
 bmesh.ops.dissolve_degenerate(bm,dist=1e-7,edges=list(bm.edges))
 bad=[f for f in bm.faces if f.calc_area()<1e-12]
 if bad:bmesh.ops.delete(bm,geom=bad,context='FACES')
 bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(me);bm.free();me.update()
 return o
def applymod(o,mod):
 bpy.context.view_layer.objects.active=o
 bpy.ops.object.modifier_apply(modifier=mod.name)
def shell(o,thickness):
 mod=o.modifiers.new('Manufactured shell thickness','SOLIDIFY');mod.thickness=thickness;mod.offset=-1;mod.use_even_offset=False;mod.thickness_clamp=1
 applymod(o,mod)
def bevel(o,width,segments=2):
 mod=o.modifiers.new('Small manufactured edge radii','BEVEL');mod.width=width;mod.segments=segments
 applymod(o,mod)
def cube(name,loc,size,mat,group='Body',rad=.002):
 bpy.ops.mesh.primitive_cube_add(size=1,location=loc);o=bpy.context.object;o.scale=size
 bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);finish(o,name,mat,group,False)
 if rad:bevel(o,min(rad,min(size)*.28))
 return o
def uvgrid(name,fun,us,vs,mat,group='Body',thickness=0):
 verts=[tuple(fun(u,v)) for v in vs for u in us];nu=len(us);faces=[];uv=[]
 for j in range(len(vs)-1):
  for i in range(nu-1):
   faces.append((j*nu+i,j*nu+i+1,(j+1)*nu+i+1,(j+1)*nu+i))
   uv.append(((us[i],vs[j]),(us[i+1],vs[j]),(us[i+1],vs[j+1]),(us[i],vs[j+1])))
 o=meshobj(name,verts,faces,mat,group,True,uv)
 if thickness:shell(o,thickness)
 return o
def line(name,points,radius,mat,group='Body',closed=False,sides=6):
 # Closed circular cross sections, capped at ends. No open decorative tubes.
 vv=[];ff=[];pts=[Vector(p) for p in points]
 for i,p in enumerate(pts):
  tangent=pts[(i+1)%len(pts)]-pts[i-1] if closed else pts[min(i+1,len(pts)-1)]-pts[max(0,i-1)]
  tangent.normalize();a=tangent.cross(Vector((0,0,1)))
  if a.length<.01:a=tangent.cross(Vector((0,1,0)))
  a.normalize();b=tangent.cross(a).normalized()
  vv += [tuple(p+radius*(math.cos(k*2*math.pi/sides)*a+math.sin(k*2*math.pi/sides)*b)) for k in range(sides)]
 for i in range(len(pts) if closed else len(pts)-1):
  j=(i+1)%len(pts)
  for k in range(sides):ff.append((i*sides+k,i*sides+(k+1)%sides,j*sides+(k+1)%sides,j*sides+k))
 if not closed:ff.extend([tuple(reversed(range(sides))),tuple((len(pts)-1)*sides+k for k in range(sides))])
 return meshobj(name,vv,ff,mat,group,True)
def component_rows(obj):
 bm=bmesh.new();bm.from_mesh(obj.data);remaining=set(bm.verts);parts=[]
 while remaining:
  seed=remaining.pop();vs={seed};stack=[seed]
  while stack:
   v=stack.pop()
   for e in v.link_edges:
    w=e.other_vert(v)
    if w in remaining:remaining.remove(w);vs.add(w);stack.append(w)
  parts.append(vs)
 parts.sort(key=len,reverse=True);uv=bm.loops.layers.uv.active;rows=[]
 for vs in parts:
  fs={f for v in vs for f in v.link_faces}
  rows.append([[tuple(l.vert.co)+tuple(l[uv].uv) for l in f.loops] for f in fs])
 bm.free();return rows
parts=component_rows(source)
fairbody=FairBody(parts[0])
report['source']={'vertices':len(source.data.vertices),'editableFaces':len(source.data.polygons),'components':len(parts)}
def polyobj(name,polys,mat,group='Body'):
 verts=[];faces=[];uv=[]
 for p in polys:
  if len(p)<3:continue
  start=len(verts);verts.extend([v[:3] for v in p]);faces.append(tuple(range(start,start+len(p))));uv.append([v[3:5] for v in p])
 o=meshobj(name,verts,faces,mat,group,True,uv)
 stitch_t_junctions(o)
 return o
def stitch_t_junctions(o):
 me=o.data;bm=bmesh.new();bm.from_mesh(me);bm.verts.ensure_lookup_table()
 bounds={v.index for e in bm.edges if e.is_boundary for v in e.verts};kd=KDTree(len(bounds))
 for i in bounds:kd.insert(me.vertices[i].co,i)
 kd.balance();inserts={}
 for e in bm.edges:
  if not e.is_boundary:continue
  a,b=[v.index for v in e.verts];p=me.vertices[a].co;q=me.vertices[b].co;delta=q-p;ll=delta.length_squared
  if ll<1e-13:continue
  candidates=[]
  for co,i,d in kd.find_range((p+q)*.5,math.sqrt(ll)*.501+2e-7):
   if i in (a,b):continue
   t=(co-p).dot(delta)/ll
   if 1e-5<t<1-1e-5 and (co-p-t*delta).length<2e-7:candidates.append((t,i))
  if candidates:inserts[(a,b)]=sorted(candidates)
 bm.free()
 if not inserts:return
 vv=[tuple(v.co) for v in me.vertices];ff=[];uu=[];layer=me.uv_layers.active
 for p in me.polygons:
  ids=list(p.vertices);lis=list(p.loop_indices);f=[];uv=[]
  for j,a in enumerate(ids):
   b=ids[(j+1)%len(ids)];ta=layer.data[lis[j]].uv.copy();tb=layer.data[lis[(j+1)%len(ids)]].uv.copy();f.append(a);uv.append(tuple(ta))
   extra=inserts.get((a,b))
   if extra is None:extra=[(1-t,i) for t,i in reversed(inserts.get((b,a),[]))]
   for t,i in extra:f.append(i);uv.append(tuple(ta.lerp(tb,t)))
  ff.append(f);uu.append(uv)
 new=bpy.data.meshes.new(me.name+'_stitched');new.from_pydata(vv,[],ff);new.update();new.materials.append(o.data.materials[0]);uv=new.uv_layers.new()
 for p,tex in zip(new.polygons,uu):
  p.use_smooth=True
  for li,co in zip(p.loop_indices,tex):uv.data[li].uv=co
 o.data=new
def clipmany(polys,planes):
 ins=[];outs=[]
 for p in polys:
  a,b=partition(p,planes)
  if a:ins.append(a)
  outs+=b
 return ins,outs
def yzregion(poly,side):
 # Convex CCW yz outline, plus side isolation.
 area=sum(a[0]*b[1]-b[0]*a[1] for a,b in zip(poly,poly[1:]+poly[:1]))
 if area<0:poly=list(reversed(poly))
 planes=[((side*-1,0,0),-.15)]
 for a,b in zip(poly,poly[1:]+poly[:1]):
  dy=b[0]-a[0];dz=b[1]-a[1]
  planes.append(((0,dz,-dy),dz*a[0]-dy*a[1]))
 return planes
# Remove only the damaged greenhouse above the measured belt plane. The new
# roof/window shell below follows landmarks of this Tripo generation.
belt=lambda y:.236+.038*y
greenplanes=[((0,-1,0),.239),((0,1,0),.414),((0,.038,-1),-.236)]
oldgreen,bodypolys=clipmany(parts[0],greenplanes)
oldinside,bodypolys=clipmany(bodypolys,box(-.154,.154,-.23,.295,.082,.266))
GRILLE_OUTLINE=[(-.119,.158),(-.103,.177),(-.072,.179),(.072,.179),(.103,.177),(.119,.158),(.104,.143),(.070,.138),(-.070,.138),(-.104,.143)]
LOWER_OUTLINE=[(-.115,.079),(-.103,.094),(.103,.094),(.115,.079),(.105,.073),(-.105,.073)]
def xz_prism(outline):
 poly=list(outline);area=sum(a[0]*b[1]-b[0]*a[1] for a,b in zip(poly,poly[1:]+poly[:1]))
 if area<0:poly.reverse()
 planes=[((0,-1,0),.53),((0,1,0),-.439)]
 for a,b in zip(poly,poly[1:]+poly[:1]):
  dx=b[0]-a[0];dz=b[1]-a[1];planes.append(((dz,0,-dx),dz*a[0]-dx*a[1]))
 return planes
for outline in [GRILLE_OUTLINE,LOWER_OUTLINE]:_,bodypolys=clipmany(bodypolys,xz_prism(outline))
report['regionalRebuild']={'greenhouseRemovedFaces':len(oldgreen),'landmarks':'P2 roof crown, windshield/c-pillar endpoints and beltline; no S1 panels appended'}
# Remove the generated mirror lumps before adding clean caps at their measured
# locations; source body width here is below .20, mirror extremities above it.
for side in (-1,1):
 planes=box(.192,.26,-.153,-.075,.214,.275) if side==1 else box(-.26,-.192,-.153,-.075,.214,.275)
 _,bodypolys=clipmany(bodypolys,planes)
# Separate the real door skins from this same surface. Their closed shape is
# conserved; the 2 mm joint is created by a small in-plane contraction.
dooroutlines={
 'F':[(-.200,.067),(.025,.067),(.047,.238),(-.183,.229)],
 'R':[(.028,.069),(.171,.069),(.234,.126),(.278,.247),(.048,.238)]}
doorpolys={}
for side,letter in [(-1,'L'),(1,'R')]:
 for row,outline in dooroutlines.items():
  group='Door'+row+letter;skin,bodypolys=clipmany(bodypolys,yzregion(outline,side));doorpolys[group]=skin
# Distinguish lamp graphics from clean paint; all badges are independent source
# components and deliberately omitted. Keep no baked dents on painted panels.
def category(p):
 x,y,z=np.mean(np.array([v[:3] for v in p]),axis=0)
 if abs(x)>.12 and y<-.388 and .142<z<.200:return 'lamp'
 if abs(x)>.117 and y>.417 and .189<z<.24:return 'lamp'
 if abs(x)>.214 and -.23<y<-.10 and z<.235:return 'trim'
 if y<-.405 and .069<z<.10 and abs(x)>.11:return 'trim'
 return 'paint'
def fill_small_holes(o):
 bm=bmesh.new();bm.from_mesh(o.data);remaining={e for e in bm.edges if e.is_boundary};filled=0
 while remaining:
  seed=remaining.pop();es={seed};stack=[seed];vs=set(seed.verts)
  while stack:
   e=stack.pop()
   for v in e.verts:
    for q in v.link_edges:
     if q in remaining:remaining.remove(q);es.add(q);stack.append(q);vs.update(q.verts)
  dims=[max(v.co[k] for v in vs)-min(v.co[k] for v in vs) for k in range(3)]
  if max(dims)<.055 and all(sum(e in es for e in v.link_edges)==2 for v in vs):
   result=bmesh.ops.holes_fill(bm,edges=list(es),sides=0);filled+=len(result.get('faces',[]))
 bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(o.data);bm.free();o.data.update();return filled
def fairpaint(o):
 # Tangential dimensions stay fixed. Fit only broad side panels and hood crown;
 # blend to source positions around arches, lamps, panel breaks and margins.
 samples=[]
 for v in o.data.vertices:
  x,y,z=v.co
  if abs(x)>.17 and -.19<y<.24 and .082<z<.185:samples.append((abs(x),y,z))
 if len(samples)>12:
  aa=np.array(samples);Y=aa[:,1];Z=aa[:,2];A=np.array([np.ones(len(Y)),Y,Z,Y*Y,Y*Z,Z*Z,Y**3]).T
  coef=SIDE_COEF
  for v in o.data.vertices:
   x,y,z=v.co
   if abs(x)>.17 and -.19<y<.24 and .082<z<.185:
    target=float(np.array([1,y,z,y*y,y*z,z*z,y**3])@coef)
    w=min(1,(z-.082)/.018,(.185-z)/.018,(y+.19)/.025,(.24-y)/.025)
    v.co.x+=math.copysign(1,x)*max(-.001,min(.001,target-abs(x)))*max(0,w)
 # Conservative noise removal away from open boundaries and sharp creases.
 bm=bmesh.new();bm.from_mesh(o.data)
 for repeat in range(3):
  moves={}
  for v in bm.verts:
   if v.is_boundary or len(v.link_edges)<3:continue
   if any(e.is_manifold and e.calc_face_angle(0)>.65 for e in v.link_edges):continue
   avg=sum((e.other_vert(v).co for e in v.link_edges),Vector())/len(v.link_edges)
   normal=v.normal.normalized();delta=normal*((avg-v.co).dot(normal))*.2
   if delta.length>.0006:delta*=.0006/delta.length
   moves[v]=v.co+delta
  for v,co in moves.items():v.co=co
  bm.normal_update()
 bm.to_mesh(o.data);bm.free();o.data.update()
side_samples=np.array([v[:3] for p in parts[0] for v in p if abs(v[0])>.17 and -.19<v[1]<.24 and .082<v[2]<.185])
sy=side_samples[:,1];sz=side_samples[:,2]
SIDE_COEF=np.linalg.lstsq(np.array([np.ones(len(sy)),sy,sz,sy*sy,sy*sz,sz*sz,sy**3]).T,np.abs(side_samples[:,0]),rcond=None)[0]
for group,polys in [('Body',bodypolys)]+list(doorpolys.items()):
 o=polyobj(group+'_paint',polys,paint,group)
 # Material changes do not split the surface or its vertex normals.
 o.data.materials.append(lamp);o.data.materials.append(trim)
 report.setdefault('repairedSmallOpenings',{})[o.name]=fill_small_holes(o)
 for face in o.data.polygons:
  pp=[tuple(o.data.vertices[i].co) for i in face.vertices]
  face.material_index={'paint':0,'lamp':1,'trim':2}[category(pp)]
 report.setdefault('fittedBodySurfaces',{})[o.name]=fairbody.project(o)
 bm=bmesh.new();bm.from_mesh(o.data)
 # Separate genuine source multi-sheet junctions before thickness is built.
 bad=[e for e in bm.edges if len(e.link_faces)>2]
 if bad:bmesh.ops.split_edges(bm,edges=bad)
 for f in bm.faces:f.smooth=True
 bm.to_mesh(o.data);bm.free()
 shell(o,.0012 if group=='Body' else .005)
# Flush source handles are preserved and faired, not replacements from S1.
for index in [22,23,24,25]:
 pp=parts[index];center=np.mean([v[:3] for p in pp for v in p],axis=0);group='Door'+('F' if center[1]<.10 else 'R')+('L' if center[0]<0 else 'R')
 o=polyobj(group+'_handle',pp,chrome,group);fill_small_holes(o)
# Roof crown and glazing fit this source car, with regular grids and actual
# thickness. Continuous parameters keep the front, sides and rear joined.
def roof(u,v):
 y=(-.072+.009*u*u)*(1-v)+(.267-.027*u*u)*v
 width=.133*(1-v)+.128*v+.009*math.sin(math.pi*v)
 z=.324+.019*math.sin(math.pi*v)-(.009+.010*math.sin(math.pi*v)+.008*v)*u*u
 return Vector((u*width,y,z))
roof_shell=uvgrid('Roof_source_fitted_crown',roof,np.linspace(-1,1,17),np.linspace(0,1,17),paint,thickness=.002)
roof_shell.data.materials.append(inside)
for face in roof_shell.data.polygons:
 if face.normal.z<-.2:face.material_index=1
uvgrid('Roof_fitted_lining',lambda u,v:roof(u,v)-Vector((0,0,.004)),np.linspace(-.97,.97,13),np.linspace(.02,.98,13),inside,thickness=.001)
def windshield(u,v,rear=False):
 if not rear:base=Vector((u*.175,-.232+.035*u*u,belt(-.232+.035*u*u)+.0002));top=roof(u,0)
 else:base=Vector((u*.160,.406-.063*u*u,belt(.406-.063*u*u)+.0002));top=roof(u,1)
 p=base.lerp(top,v);p.y+=(-1 if not rear else 1)*.004*math.sin(math.pi*v)*(1-u*u)
 return p
for rear in (False,True):
 label='Rear' if rear else 'Front';fun=lambda u,v:windshield(u,v,rear)
 uvgrid(label+'_Glass',fun,np.linspace(-.971,.971,13),np.linspace(.038,.968,9),glass,thickness=.00046)
 for name,us,vs,mat in [('lower_seal',np.linspace(-1,1,13),[0,.04],trim),('upper_seal',np.linspace(-1,1,13),[.967,1],trim),('L_pillar',[-1,-.972],np.linspace(0,1,9),paint),('R_pillar',[.972,1],np.linspace(0,1,9),paint)]:
  uvgrid(label+'_'+name,fun,us,vs,mat,thickness=.0015)
def sidefun(t,v,side):
 top=roof(side,t);bottom_y=-.197+.540*t
 bottom=Vector((side*(.175+.010*math.sin(math.pi*t)-.015*t),bottom_y,belt(bottom_y)+.0002))
 p=bottom.lerp(top,v);p.x+=side*.0015*math.sin(math.pi*v)*math.sin(math.pi*t)
 return p
for side,letter in [(-1,'L'),(1,'R')]:
 fun=lambda t,v:sidefun(t,v,side)
 # Each moving door carries its own original-fit glass/frame section.
 sections=[(0,.028,'A_pillar',paint,'Body'),(.028,.425,'FrontGlass',glass,'DoorF'+letter),(.425,.47,'B_pillar',trim,'Body'),(.47,.772,'RearGlass',glass,'DoorR'+letter),(.772,.796,'Quarter_divider',trim,'Body'),(.796,.89,'QuarterGlass',glass,'Body'),(.89,1,'C_pillar',paint,'Body')]
 for a,b,label,mat,group in sections:
  ts=np.linspace(a,b,max(2,math.ceil((b-a)*22)))
  if mat==glass:
   uvgrid(letter+'_'+label,fun,ts,np.linspace(.04,.965,7),mat,group,.00046)
   uvgrid(letter+'_'+label+'_belt_seal',fun,ts,[0,.04],trim,group,.0012)
   uvgrid(letter+'_'+label+'_roof_seal',fun,ts,[.965,1],trim,group,.0012)
  else:uvgrid(letter+'_'+label,fun,ts,np.linspace(0,1,7),mat,group,.002)
 # A narrow bright belt trim, fitted to the same lower curve.
 for a,b,group in [(0,.445,'DoorF'+letter),(.445,.79,'DoorR'+letter),(.79,1,'Body')]:
  line(letter+'_window_belt_trim', [fun(t,0) for t in np.linspace(a,b,14)],.00065,chrome,group)
 group='DoorF'+letter
 line(letter+'_mirror_stem',[(side*.183,-.143,.229),(side*.214,-.124,.238)],.0045,trim,group)
 cube(letter+'_mirror_cap',(side*.219,-.120,.243),(.049,.040,.018),paint,group,rad=.007)
 cube(letter+'_mirror_glass',(side*.219,-.099,.242),(.039,.0015,.012),chrome,group,rad=.003)
# Fitted belt flanges bridge the measured body cut and the new glass. They are
# actual closed strips rather than black gaps hidden by dark window textures.
def sideflange(t,v,side):
 p=sidefun(t,0,side);hit=SOURCE_BVH.ray_cast(Vector((side*.5,p.y,p.z)),Vector((-side,0,0)),1)[0]
 x=abs(hit.x) if hit is not None else abs(p.x)+.007
 x=max(abs(p.x)+.001,min(.207,x))
 return Vector((side*(abs(p.x)*(1-v)+x*v),p.y,p.z-.0002*v))
for side,letter in [(-1,'L'),(1,'R')]:
 for a,b,group in [(0,.425,'DoorF'+letter),(.425,.47,'Body'),(.47,.772,'DoorR'+letter),(.772,1,'Body')]:
  uvgrid(letter+'_fitted_belt_flange',lambda t,v:sideflange(t,v,side),np.linspace(a,b,max(3,round((b-a)*40))),[0,1],paint,group,thickness=.0015)
def cowl(u,v,rear):
 p=windshield(u,0,rear);outer=Vector((u*.187,.421 if rear else -.246,0))
 hit=SOURCE_BVH.ray_cast(Vector((outer.x,outer.y,.29)),Vector((0,0,-1)),.12)[0]
 outer.z=hit.z+.0003 if hit is not None else belt(outer.y)
 return p.lerp(outer,v)
for rear in [False,True]:uvgrid(('Rear' if rear else 'Front')+'_fitted_cowl',lambda u,v:cowl(u,v,rear),np.linspace(-1,1,31),np.linspace(0,1,5),paint,thickness=.0012)
# Clean shallow grille plate: no source lattice or emblems survives.
outline=GRILLE_OUTLINE
def grille_y(x):return -.489+.025*(abs(x)/.12)**2
vv=[(x,grille_y(x),z) for x,z in outline]
o=meshobj('Front_grille_shallow_panel',vv,[tuple(range(len(vv)))],trim,'Body',False)
shell(o,.0015)
line('Front_grille_surround',vv,.0012,chrome,closed=True,sides=6)
lower=LOWER_OUTLINE
vv2=[(x,-.483+.016*(abs(x)/.12)**2,z) for x,z in lower]
o=meshobj('Lower_grille_shallow_panel',vv2,[tuple(range(len(vv2)))],trim,smooth=False);shell(o,.0015)
line('Lower_grille_surround',vv2,.00075,trim,closed=True)
# Neutral plates without manufacturer marks or personal text.
for name,y,z in [('Front',-.499,.113),('Rear',.481,.199)]:
 cube(name+'_plate',(0,y,z),(.104,.0018,.029),chrome,rad=.001)
# Underbody, wheel tubs and a modest cabin. These are fitted to this new car.
cube('Cabin_floor',(0,.035,.071),(.334,.51,.014),inside,rad=.003)
cube('Rear_parcel_shelf',(0,.295,.242),(.29,.12,.012),inside,rad=.003)
cube('Dashboard_lower',(0,-.191,.192),(.323,.075,.062),inside,rad=.008)
dash=cube('Dashboard_upper',(0,-.199,.224),(.324,.075,.019),trim,rad=.008)
cube('Center_console',(0,-.055,.123),(.055,.223,.068),inside,rad=.006)
cube('Console_inlay',(0,-.067,.159),(.046,.12,.006),chrome,rad=.003)
cube('Gear_selector',(0,-.085,.17),(.009,.011,.018),trim,rad=.003)
cube('Center_screen',(0,-.147,.224),(.068,.005,.041),trim,rad=.002)
screenmat=material('S2 • display blue',(.025,.14,.21),.05,.4);sbs=screenmat.node_tree.nodes.get('Principled BSDF');sbs.inputs['Emission Color'].default_value=(.015,.10,.16,1);sbs.inputs['Emission Strength'].default_value=.4
cube('Instrument_binnacle',(-.083,-.168,.234),(.086,.035,.035),trim,rad=.007)
def screen(name,x,y,z,w,h,file):
 mat=material('S2 • '+name,(.05,.06,.07),0,.46);bs=mat.node_tree.nodes.get('Principled BSDF');node=mat.node_tree.nodes.new('ShaderNodeTexImage');node.image=bpy.data.images.load(str(OUT/file),check_existing=True);node.image.pack()
 mat.node_tree.links.new(node.outputs['Color'],bs.inputs['Base Color']);mat.node_tree.links.new(node.outputs['Color'],bs.inputs['Emission Color']);bs.inputs['Emission Strength'].default_value=.3
 vv=[(x-w/2,y,z-h/2),(x-w/2,y,z+h/2),(x+w/2,y,z+h/2),(x+w/2,y,z-h/2)]
 o=meshobj(name,vv,[(0,1,2,3)],mat,uv=[[(0,0),(0,1),(1,1),(1,0)]]);shell(o,.0003)
screen('Navigation_display',0,-.1438,.225,.060,.031,'BoraS2_Navigation.png')
screen('Instrument_display',-.083,-.1495,.233,.068,.020,'BoraS2_Instruments.png')
for x in [-.13,-.035,.035,.13]:
 cube('Dash_vent',(x,-.150,.211),(.027,.002,.009),rubber,rad=.001)
for x in [-.084,.084]:
 letter='L' if x<0 else 'R'
 cube('Front_'+letter+'_seat_cushion',(x,.018,.12),(.079,.126,.025),seatmat,rad=.009)
 seat=cube('Front_'+letter+'_seat_back',(x,.081,.190),(.082,.029,.132),seatmat,rad=.011);seat.rotation_euler.x=math.radians(8)
 cube('Front_'+letter+'_headrest',(x,.090,.279),(.049,.025,.035),seatmat,rad=.007)
 cube('Front_'+letter+'_seat_insert',(x,.064,.191),(.055,.004,.092),inside,rad=.006)
cube('Rear_bench_cushion',(0,.207,.125),(.273,.105,.028),seatmat,rad=.009)
rear=cube('Rear_bench_back',(0,.253,.188),(.276,.030,.122),seatmat,rad=.009);rear.rotation_euler.x=math.radians(9)
for x in [-.084,0,.084]:cube('Rear_headrest',(x,.264,.267),(.047,.026,.029),seatmat,rad=.006)
for side,letter in [(-1,'L'),(1,'R')]:
 for row,y in [('F',-.07),('R',.155)]:
  group='Door'+row+letter
  cube(group+'_inner_card',(side*.172,y,.165),(.009,.178,.097),inside,group,rad=.004)
  cube(group+'_armrest',(side*.160,y+.008,.154),(.027,.113,.014),trim,group,rad=.003)
  cube(group+'_inner_handle',(side*.153,y-.032,.191),(.004,.034,.005),chrome,group,rad=.001)
 # Inner pillars make the transparent cabin believable at eye level.
 line(letter+'_A_pillar_inner',[windshield(side,v) for v in np.linspace(0,1,9)],.003,inside)
 line(letter+'_C_pillar_inner',[windshield(side,v,True) for v in np.linspace(0,1,9)],.004,inside)
# Steering follows the new dash; left hand drive. Create in normalized units,
# regular tube and simple spokes, then keep an actual steering pivot.
steercenter=Vector((-.083,-.123,.211));axis=Vector((0,-.82,.57)).normalized();a=Vector((1,0,0));b=axis.cross(a).normalized()
points=[steercenter+.036*(a*math.cos(t)+b*math.sin(t)) for t in np.linspace(0,2*math.pi,33)[:-1]]
line('Steering_rim',points,.0034,trim,'Steering',True,8)
for t in [0,math.pi,1.5*math.pi]:line('Steering_spoke',[steercenter,steercenter+.033*(a*math.cos(t)+b*math.sin(t))],.004,trim,'Steering',sides=6)
cube('Steering_hub',steercenter,(.030,.014,.021),trim,'Steering',rad=.004)
line('Steering_column',[steercenter+axis*.012,steercenter-axis*.038],.008,inside)
# Scale the fitted car before generating true circular metric wheels.
for o in built:
 for v in o.data.vertices:v.co=Vector(v.co)*SCALE
 o.location=Vector(o.location)*SCALE
 # Nonuniform scale is deliberately applied before wheel generation.
 o.data.update()
 if o.name.startswith('Door') and o.name.endswith('_paint'):
  for axis,gap in [(1,.0025),(2,.002)]:
   low=min(v.co[axis] for v in o.data.vertices);high=max(v.co[axis] for v in o.data.vertices);center=(low+high)/2;factor=1-gap/(high-low)
   for v in o.data.vertices:v.co[axis]=center+(v.co[axis]-center)*factor
def wheel(name,center,side):
 cx,cy,cz=center;N=48;verts=[];faces=[];profile=[(-.114,.245),(-.112,.299),(-.090,.332),(-.056,.338),(.056,.338),(.090,.332),(.112,.299),(.114,.245)]
 for xx,r in profile:
  for k in range(N):
   a=k*2*math.pi/N;verts.append((cx+xx,cy+r*math.sin(a),cz+r*math.cos(a)))
 for j in range(len(profile)):
  q=(j+1)%len(profile)
  for k in range(N):faces.append((j*N+k,j*N+(k+1)%N,q*N+(k+1)%N,q*N+k))
 meshobj(name+'_Tire',verts,faces,rubber,name,True)
 # Regular, shallow wheel rings and five broad cast spokes. No tiny mesh marks.
 outer=cx+side*.112;ringprof=[(-side*.01,.222),(0,.244),(side*.009,.247),(side*.014,.229),(side*.013,.214)]
 verts=[];faces=[];N=40
 for d,r in ringprof:
  for k in range(N):
   a=k*2*math.pi/N;verts.append((outer+d,cy+r*math.sin(a),cz+r*math.cos(a)))
 for j in range(len(ringprof)):
  q=(j+1)%len(ringprof)
  for k in range(N):faces.append((j*N+k,j*N+(k+1)%N,q*N+(k+1)%N,q*N+k))
 meshobj(name+'_Rim',verts,faces,chrome,name,True)
 for k in range(5):
  angle=k*math.tau/5+.12;points=[]
  for xx in [outer-side*.008,outer+side*.012]:
   for r,t in [(.055,angle-.26),(.226,angle-.075),(.226,angle+.075),(.055,angle+.26)]:points.append((xx,cy+r*math.sin(t),cz+r*math.cos(t)))
  ff=[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]
  o=meshobj(name+'_Spoke'+str(k+1),points,ff,chrome,name,False);bevel(o,.003,2)
 # A plain cap eliminates all real manufacturer's wheel badges.
 N=32;verts=[];faces=[]
 for xx,r in [(outer-side*.009,.059),(outer+side*.018,.052)]:
  for k in range(N):verts.append((xx,cy+r*math.sin(k*math.tau/N),cz+r*math.cos(k*math.tau/N)))
 faces=[tuple(reversed(range(N))),tuple(range(N,2*N))]+[(k,(k+1)%N,(k+1)%N+N,k+N) for k in range(N)]
 meshobj(name+'_Cap',verts,faces,trim,name,True)
 # Brake disc is a closed 32-sided cylinder.
 verts=[];faces=[]
 for xx in [outer-side*.038,outer-side*.046]:
  for k in range(N):verts.append((xx,cy+.196*math.sin(k*math.tau/N),cz+.196*math.cos(k*math.tau/N)))
 faces=[tuple(reversed(range(N))),tuple(range(N,2*N))]+[(k,(k+1)%N,(k+1)%N+N,k+N) for k in range(N)]
 meshobj(name+'_Brake',verts,faces,inside,name,True)
pivots={'Body':[0,0,0],'Steering':list(steercenter*SCALE)}
for side,letter in [(-1,'L'),(1,'R')]:
 for row,y in [('F',-.30688*4.68),('R',.28418*4.68)]:
  group='Wheel'+row+letter;center=(side*.184*4.35,y,.338);wheel(group,center,side);pivots[group]=list(center)
 for row,y in [('F',-.185),('R',.047)]:pivots['Door'+row+letter]=[side*.177*4.35,y*4.68,.215*4.31]
# Flat texture patterns supply the grille detail. UVs are x/z projected.
for name in ['Front_grille_shallow_panel','Lower_grille_shallow_panel']:
 o=bpy.data.objects[name];uv=o.data.uv_layers.get('UVMap') or o.data.uv_layers.new(name='UVMap')
 for loop in o.data.loops:
  x,y,z=o.data.vertices[loop.vertex_index].co;uv.data[loop.index].uv=(x/(.238*4.35)+.5,z/(.045*4.31))
grillemat=material('S2 • grille texture pattern',(.03,.04,.05),.35,.45)
im=bpy.data.images.new('S2_GrillePattern',width=512,height=256)
arr=np.ones((256,512,4),dtype=np.float32);arr[:,:,:3]=(.022,.028,.035)
yy,xx=np.mgrid[0:256,0:512];pattern=((xx//24+yy//22)%2==0)&(xx%24<17)&(yy%22<13)
arr[pattern,:3]=(.12,.145,.17);im.pixels[:]=arr.ravel();im.filepath_raw=str(OUT/'BoraS2_Grille.png');im.file_format='PNG';im.save();im.pack()
tex=grillemat.node_tree.nodes.new('ShaderNodeTexImage');tex.image=im;grillemat.node_tree.links.new(tex.outputs['Color'],grillemat.node_tree.nodes.get('Principled BSDF').inputs['Base Color'])
for name in ['Front_grille_shallow_panel','Lower_grille_shallow_panel']:bpy.data.objects[name].data.materials[0]=grillemat
# Put each moving assembly at its functional origin, with local mesh positions.
collection=bpy.data.collections.new('BORA S2 • cleaned game asset');bpy.context.scene.collection.children.link(collection)
for o in built:
 world=o.matrix_world.copy();p=Vector(pivots.get(o['group'],[0,0,0]));o.data.transform(world);o.matrix_world=Matrix.Identity(4)
 for v in o.data.vertices:v.co-=p
 o.location=p
 for c in list(o.users_collection):c.objects.unlink(o)
 collection.objects.link(o)
 # Split normals at manufactured sharp angles; retain smooth broad surfaces.
 bm=bmesh.new();bm.from_mesh(o.data);bm.normal_update()
 bmesh.ops.dissolve_degenerate(bm,dist=1e-7,edges=list(bm.edges))
 bad=[f for f in bm.faces if f.calc_area()<1e-12]
 if bad:bmesh.ops.delete(bm,geom=bad,context='FACES')
 if o.name.endswith('_paint'):
  ngons=[f for f in bm.faces if len(f.verts)>4]
  if ngons:bmesh.ops.triangulate(bm,faces=ngons,ngon_method='EAR_CLIP')
  bmesh.ops.dissolve_degenerate(bm,dist=1e-7,edges=list(bm.edges))
  bad=[f for f in bm.faces if f.calc_area()<1e-12]
  if bad:bmesh.ops.delete(bm,geom=bad,context='FACES')
 for e in bm.edges:
  if e.is_manifold:e.smooth=e.calc_face_angle(0)<math.radians(110 if o.name.endswith('_paint') else 48)
 bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(o.data);bm.free();o.data.update()
 repair_micro_geometry(o)
bpy.context.view_layer.update()
report['fittedSurfaceNormalLoops']=fairbody.normals(built)
o=source;bpy.data.objects.remove(o,do_unlink=True)
# Asset source metadata and closed/open assembly pivots are kept in the file.
scene=bpy.context.scene;scene['SourceTripoTask']='b1e76032-3d84-48ca-98b7-dbf272ea6cab';scene['BoraS2Pivots']=json.dumps(pivots)
report['pivotsBlenderMeters']=pivots;report['physicalScale']=list(SCALE);report['wheelRadiusMeters']=.338
report['changes']=['Measured new greenhouse and roof crown, real clear glazing','Same-surface door skins and functional origins','Flat texture grilles; no generated badge components','48-sided circular tires, consistent five-spoke rims','New fitted left-hand-drive modest cabin; no S1 panels']
report['installedInPlace']=False
(OUT/'cleanup-process.json').write_text(json.dumps(report,indent=2))
# A neutral studio QA setup, excluded from all exports.
ground=material('QA ground',(.055,.071,.093),0,.8)
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.008));floor=bpy.context.object;floor.name='QA_Ground';floor.data.materials.append(ground)
scene.render.engine='CYCLES';scene.cycles.samples=24;scene.cycles.use_denoising=True;scene.world.color=(.3,.3,.3)
for loc,power,size in [((-4,-4,6),1150,5),((4,3,6),900,4),((0,5,5),1400,4)]:
 bpy.ops.object.light_add(type='AREA',location=loc);l=bpy.context.object;l.name='QA_Softbox';l.data.energy=power;l.data.size=size;l.data.specular_factor=.35;l.visible_glossy=False;l.rotation_euler=(Vector((0,0,.65))-l.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add(location=(-5.3,-6.2,2.7));cam=bpy.context.object;cam.name='QA_Camera';scene.camera=cam;cam.data.lens=52;cam.rotation_euler=(Vector((0,0,.7))-cam.location).to_track_quat('-Z','Y').to_euler()
scene.render.resolution_x=1400;scene.render.resolution_y=900;scene.render.resolution_percentage=100
# Set a useful viewport without opening/activating any desktop application.
for screen in bpy.data.screens:
 for area in screen.areas:
  if area.type=='VIEW_3D':
   area.spaces.active.region_3d.view_distance=7;area.spaces.active.region_3d.view_location=(0,0,.7);area.spaces.active.clip_end=1000
bpy.ops.object.select_all(action='DESELECT');bpy.context.view_layer.objects.active=bpy.data.objects['Body_paint'];bpy.data.objects['Body_paint'].select_set(True)
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'BoraS2_Clean.blend'))
for name,loc,target in [('s2-clean-front.png',(-5.3,-6.2,2.7),(0,0,.65)),('s2-clean-side.png',(-7.5,0,1.8),(0,0,.7)),('s2-clean-rear.png',(5,6,2.8),(0,0,.7))]:
 cam.location=loc;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler();scene.render.filepath=str(OUT/name);bpy.ops.render.render(write_still=True)
print('S2 asset saved and three views rendered',flush=True)
