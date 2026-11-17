"""Read-only dimensional and rendered diagnosis of the saved S2 assembly."""
import bpy,bmesh,json,math
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'assets/vehicles/retopology'
bpy.ops.wm.open_mainfile(filepath=str(OUT/'BoraS2_Clean.blend'))
rows=[]
for o in bpy.context.scene.objects:
 if o.type!='MESH' or not o.get('asset'):continue
 pts=[o.matrix_world@v.co for v in o.data.vertices]
 if min(p.y for p in pts)<-1.8 or any(s in o.name.lower() for s in ['dash','front_glass','cowl','binnacle','screen','display']):
  rows.append({'name':o.name,'verts':len(pts),'bounds':[[min(p[k] for p in pts) for k in range(3)],[max(p[k] for p in pts) for k in range(3)]]})
body=bpy.data.objects['Body_paint'];me=body.data;me.calc_loop_triangles()
tree=BVHTree.FromPolygons([body.matrix_world@v.co for v in me.vertices],[t.vertices for t in me.loop_triangles],all_triangles=True)
samples=[]
for z in [.23,.33,.45,.59,.70,.80,.86,.92]:
 for x in [0,.2,.4,.6,.75,.85]:
  p,n,i,d=tree.ray_cast(Vector((x,-3,z)),Vector((0,1,0)),1.5)
  samples.append([x,z,list(p) if p is not None else None])
sections={}
for y in [-1.82,-1.88,-1.94,-2.0]:
 bm=bmesh.new();bm.from_mesh(me)
 res=bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),dist=1e-7,plane_co=(0,y,0),plane_no=(0,1,0))
 sections[str(y)]=[list(v.co) for v in res['geom_cut'] if isinstance(v,bmesh.types.BMVert)]
 bm.free()
report={'objects':rows,'frontRays':samples,'bodyCrossSections':sections}
(OUT/'BoraS2_FitDiagnosis.json').write_text(json.dumps(report,indent=2))
print(json.dumps(rows),flush=True)
scene=bpy.context.scene;cam=scene.camera;scene.render.resolution_x=1000;scene.render.resolution_y=750;scene.cycles.samples=16
for name,loc,target,lens in [('s2-before-nose.png',(2.5,-3.8,1.38),(.35,-1.98,.66),60),('s2-before-glass.png',(2.3,-2.6,3.4),(0,-.65,1.04),58)]:
 cam.location=loc;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.lens=lens;scene.render.filepath=str(OUT/name);bpy.ops.render.render(write_still=True)
