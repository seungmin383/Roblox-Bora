"""Fit smooth manufactured surface fields to THIS Tripo body envelope.

No primitive sedan is substituted. Exterior ray samples constrain local side
surfaces and separate hood, deck and bumper polynomials. Position and normal
fields share the same derivatives, so smoothing does not fake a different body.
"""
import math,bpy,bmesh
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree
SCALE=Vector((4.35,4.68,4.31))
class FairBody:
 def __init__(self,polygons):
  vv=[];ff=[]
  for p in polygons:
   s=len(vv);vv.extend(v[:3] for v in p);ff.append(tuple(range(s,len(vv))))
  self.tree=BVHTree.FromPolygons(vv,ff)
  side=[]
  for y in np.linspace(-.455,.465,100):
   for z in np.linspace(.052,.258,38):
    p,n,idx,dist=self.tree.ray_cast(Vector((.4,y,z)),Vector((-1,0,0)),.4)
    if p is not None and .145<p.x<.216 and abs(n.x)>.28:
     if -.16<y<-.07 and z>.215:continue
     side.append((p.x,y,z))
  self.side=np.array(side);self.side_cache={};self.kd=KDTree(len(side))
  for i,(x,y,z) in enumerate(side):self.kd.insert((y/.10,z/.052,0),i)
  self.kd.balance();self.fields={}
  for name,y0,y1,zmin in [('hood',-.485,-.239,.16),('deck',.414,.489,.205)]:
   pts=[]
   for x in np.linspace(-.19,.19,35):
    for y in np.linspace(y0,y1,36):
     p,n,idx,d=self.tree.ray_cast(Vector((x,y,.29)),Vector((0,0,-1)),.18)
     if p is not None and p.z>zmin and n.z>.35:pts.append((p.x,p.y,p.z))
   self.fields[name]=self.fitfield(pts,2)
  for name,y,z0,z1,di in [('front',-.55,.054,.145,1),('rear',.55,.054,.201,-1)]:
   pts=[]
   for x in np.linspace(-.177,.177,35):
    for z in np.linspace(z0,z1,24):
     p,n,idx,d=self.tree.ray_cast(Vector((x,y,z)),Vector((0,di,0)),.15)
     if p is not None and abs(n.y)>.4:pts.append((p.x,p.z,p.y))
   self.fields[name]=self.fitfield(pts,2)
 def fitfield(self,points,unused):
  a=np.array(points);x=a[:,0];v=a[:,1];A=np.array([np.ones(len(a)),v,v*v,x*x,x*x*v,x**4]).T
  coef=np.linalg.lstsq(A,a[:,2],rcond=None)[0]
  for _ in range(3):
   residual=A@coef-a[:,2];weights=1/(1+(residual/.0025)**2);coef=np.linalg.lstsq(A*weights[:,None],a[:,2]*weights,rcond=None)[0]
  return coef
 def polynomial(self,name,x,t):
  a,b,c,d,e,f=self.fields[name]
  value=a+b*t+c*t*t+d*x*x+e*x*x*t+f*x**4
  dx=2*d*x+2*e*x*t+4*f*x**3;dt=b+2*c*t+e*x*x
  return value,dx,dt
 def sidefield(self,y,z):
  key=(round(y,6),round(z,6))
  if key in self.side_cache:return self.side_cache[key]
  hits=self.kd.find_range(Vector((y/.10,z/.052,0)),1.10)
  ids=[i for co,i,dist in hits if (self.side[i,2]-(.204+.025*self.side[i,1]))*(z-(.204+.025*y))>=0]
  if len(ids)<12:ids=[i for co,i,dist in hits]
  if len(ids)<8:return None
  pts=self.side[ids];dy=(pts[:,1]-y)/.10;dz=(pts[:,2]-z)/.052
  A=np.array([np.ones(len(ids)),dy,dz,dy*dy,dy*dz,dz*dz]).T;w=np.exp(-3*(dy*dy+dz*dz))
  coef=np.linalg.lstsq(A*w[:,None],pts[:,0]*w,rcond=None)[0]
  value=(float(coef[0]),float(coef[1]/.10),float(coef[2]/.052));self.side_cache[key]=value;return value
 def evaluate(self,p):
  x,y,z=p;ax=abs(x);side=-1 if x<0 else 1
  if ax>.169 and -.445<y<.448 and .063<z<.248:
   val=self.sidefield(y,z)
   if val is not None:
    a,b,c=val;return 0,side*a,Vector((side,-b,-c)).normalized()
  if -.484<y<-.239 and z>.172 and ax<.172:
   if ax>.112 and y<-.387 and z<.195:return None
   a,b,c=self.polynomial('hood',x,y);return 2,a,Vector((-b,-c,1)).normalized()
  if .414<y<.493 and z>.208 and ax<.17:
   a,b,c=self.polynomial('deck',x,y);return 2,a,Vector((-b,-c,1)).normalized()
  if y<-.432 and .057<z<.145 and ax<.176:
   a,b,c=self.polynomial('front',x,z);return 1,a,Vector((b,-1,c)).normalized()
  if y>.435 and .057<z<.199 and ax<.176:
   a,b,c=self.polynomial('rear',x,z);return 1,a,Vector((-b,1,-c)).normalized()
  return None
 def project(self,o):
  protected={i for f in o.data.polygons if f.material_index==1 for i in f.vertices}
  moved=0;maxmove=0
  for v in o.data.vertices:
   if v.index in protected:continue
   fit=self.evaluate(v.co)
   if fit is None:continue
   axis,value,normal=fit;delta=max(-.005,min(.005,value-v.co[axis]));v.co[axis]+=delta;moved+=1;maxmove=max(maxmove,abs(delta))
  o.data.update();return {'movedVertices':moved,'maxMoveSourceUnits':maxmove}
 def normals(self,objects):
  count=0
  for o in objects:
   if not o.name.endswith('_paint'):continue
   me=o.data;me.update();normals=[v.vector.copy() for v in me.corner_normals]
   for e in me.edges:e.use_edge_sharp=False
   for face in me.polygons:
    face.use_smooth=True
    if face.material_index==1:continue
    for li in face.loop_indices:
     p=o.matrix_world@me.vertices[me.loops[li].vertex_index].co;p=Vector(tuple(p[k]/SCALE[k] for k in range(3)))
     fit=self.evaluate(p)
     if fit is None:continue
     axis,value,n=fit;n=Vector(tuple(n[k]/SCALE[k] for k in range(3))).normalized()
     if n.dot(face.normal)>.38 and abs(p[axis]-value)<.007:normals[li]=n;count+=1
   splitkeys=set()
   for face in me.polygons:
    if any(normals[li].length<.9 for li in face.loop_indices):
     splitkeys.update(tuple(sorted(k)) for k in face.edge_keys)
     for li in face.loop_indices:normals[li]=face.normal.copy()
   for edge in me.edges:
    if tuple(sorted(edge.vertices)) in splitkeys:edge.use_edge_sharp=True
   for face in me.polygons:
    for li in face.loop_indices:
     if normals[li].length<.9:normals[li]=face.normal.copy() if face.normal.length>.9 else Vector((0,0,1))
   me.normals_split_custom_set(normals);me.update()
  return count
def repair_micro_geometry(o):
 bm=bmesh.new();bm.from_mesh(o.data)
 # Keep intentionally separate touching sheets separate. A global weld here
 # would recreate the source's multi-sheet non-manifold junctions.
 bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=1e-5)
 bad=[f for f in bm.faces if f.calc_area()<1e-10]
 if bad:bmesh.ops.delete(bm,geom=bad,context='FACES')
 wire=[e for e in bm.edges if not e.link_faces]
 if wire:bmesh.ops.delete(bm,geom=wire,context='EDGES')
 isolated=[v for v in bm.verts if not v.link_edges]
 if isolated:bmesh.ops.delete(bm,geom=isolated,context='VERTS')
 boundaries={e for e in bm.edges if e.is_boundary}
 while boundaries:
  seed=boundaries.pop();es={seed};vs=set(seed.verts);stack=[seed]
  while stack:
   e=stack.pop()
   for v in e.verts:
    for q in v.link_edges:
     if q in boundaries:boundaries.remove(q);es.add(q);vs.update(q.verts);stack.append(q)
  span=max(max(v.co[k] for v in vs)-min(v.co[k] for v in vs) for k in range(3))
  if span<1e-4:
   center=sum((v.co for v in vs),Vector())/len(vs);bmesh.ops.pointmerge(bm,verts=list(vs),merge_co=center)
  elif span<.008 and len(es)>=3 and all(sum(e in es for e in v.link_edges)==2 for v in vs):bmesh.ops.holes_fill(bm,edges=list(es),sides=0)
 bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=1e-5)
 bad=[f for f in bm.faces if f.calc_area()<1e-10]
 if bad:bmesh.ops.delete(bm,geom=bad,context='FACES')
 wire=[e for e in bm.edges if not e.link_faces]
 if wire:bmesh.ops.delete(bm,geom=wire,context='EDGES')
 isolated=[v for v in bm.verts if not v.link_edges]
 if isolated:bmesh.ops.delete(bm,geom=isolated,context='VERTS')
 bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(o.data);bm.free();o.data.update()

def close_skin_junctions(o):
 """Close the few source contact junctions without welding touching sheets."""
 if not o.name.endswith('_paint'):return
 old=o.data;me=old.copy();o.data=me
 attr=me.attributes.get('S2_PreservedNormals') or me.attributes.new('S2_PreservedNormals','FLOAT_VECTOR','CORNER')
 for i,n in enumerate(me.corner_normals):attr.data[i].vector=n.vector
 bm=bmesh.new();bm.from_mesh(me);layer=bm.loops.layers.float_vector.get(attr.name)
 for iteration in range(3):
  multi=[e for e in bm.edges if len(e.link_faces)>2]
  if multi:bmesh.ops.split_edges(bm,edges=multi)
  remaining={e for e in bm.edges if e.is_boundary}
  while remaining:
   seed=remaining.pop();es={seed};vs=set(seed.verts);stack=[seed]
   while stack:
    e=stack.pop()
    for v in e.verts:
     for q in v.link_edges:
      if q in remaining:remaining.remove(q);es.add(q);vs.update(q.verts);stack.append(q)
   span=max(max(v.co[k] for v in vs)-min(v.co[k] for v in vs) for k in range(3))
   if span<.04 and len(es)>=3:bmesh.ops.holes_fill(bm,edges=list(es),sides=0)
 # The collapsed source mirror seam can leave an isolated 5–7 mm triangle.
 # It already owns every boundary edge, so a second coincident face cannot
 # close it. Remove this tiny sheet instead of fabricating a false volume.
 dangling=[f for f in bm.faces if f.calc_area()<1e-4 and all(e.is_boundary for e in f.edges)]
 if dangling:bmesh.ops.delete(bm,geom=dangling,context='FACES')
 bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
 wire=[e for e in bm.edges if not e.link_faces]
 if wire:bmesh.ops.delete(bm,geom=wire,context='EDGES')
 loose=[v for v in bm.verts if not v.link_edges]
 if loose:bmesh.ops.delete(bm,geom=loose,context='VERTS')
 remaining=sum(not e.is_manifold for e in bm.edges)
 if remaining:
  kinds={k:sum(len(e.link_faces)==k for e in bm.edges) for k in [0,1,3,4]};detail=[[list(v.co) for v in e.verts] for e in bm.edges if e.is_boundary];bm.free();o.data=old;bpy.data.meshes.remove(me);print('Preserved complex skin junction',o.name,remaining,kinds,detail,flush=True);return
 bm.to_mesh(me);bm.free();me.update();attr=me.attributes['S2_PreservedNormals'];normals=[]
 for p in me.polygons:
  for li in p.loop_indices:
   n=Vector(attr.data[li].vector);normals.append(n.normalized() if n.length>.5 else p.normal.copy())
 me.normals_split_custom_set(normals);me.update();me.attributes.remove(attr)
 print('Closed source skin junctions',o.name,flush=True)
 if old.users==0:bpy.data.meshes.remove(old)
