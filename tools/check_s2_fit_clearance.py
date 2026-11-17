"""Reloaded assembly-level checks; closed meshes alone do not prove good fit."""
import bpy,json,math,hashlib
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'assets/vehicles/retopology'
bpy.ops.wm.open_mainfile(filepath=str(OUT/'BoraS2_FitFix.blend'))
def tree(o):
 o.data.calc_loop_triangles()
 return BVHTree.FromPolygons([o.matrix_world@v.co for v in o.data.vertices],[t.vertices for t in o.data.loop_triangles],all_triangles=True)
glass=tree(bpy.data.objects['Front_Glass']);nose=tree(bpy.data.objects['Front_continuous_fitted_skin'])
records=[];errors=[]
for o in bpy.context.scene.objects:
 if o.type!='MESH' or not o.get('asset'):continue
 if not (o['group']=='Steering' or o.name.startswith(('Dashboard','Instrument','Navigation','Center_screen','Dash_vent','Steering_column'))):continue
 me=o.data;me.calc_loop_triangles();tested=0;clearance=[]
 for tri in me.loop_triangles:
  a,b,c=[o.matrix_world@me.vertices[i].co for i in tri.vertices]
  for wa,wb,wc in [(1,0,0),(0,1,0),(0,0,1),(.5,.5,0),(.5,0,.5),(0,.5,.5),(1/3,1/3,1/3),(.6,.2,.2),(.2,.6,.2),(.2,.2,.6)]:
   p=a*wa+b*wb+c*wc;hit,n,idx,d=glass.ray_cast(Vector((p.x,-3,p.z)),Vector((0,1,0)),3)
   if hit is not None:clearance.append(p.y-hit.y)
   tested+=1
 minimum=min(clearance) if clearance else None
 row={'name':o.name,'surfaceSamples':tested,'samplesInFrontGlassProjection':len(clearance),'minimumClearanceMeters':minimum}
 records.append(row)
 if minimum is not None and minimum<.015:errors.append(row)
misses=[];covered=0
for i in range(81):
 x=-.79+i*1.58/80
 for j in range(41):
  z=.235+j*.54/40
  # Stay inside the measured cap, including both grille and lamp regions.
  if z>.85-.07*(x/.82)**2:continue
  p,n,idx,d=nose.ray_cast(Vector((x,-3,z)),Vector((0,1,0)),1.25)
  if p is None:misses.append([x,z])
  else:covered+=1
if misses:errors.append({'noseCoverageMisses':len(misses)})
retained=tree(bpy.data.objects['Body_paint']);cut=bpy.context.scene['S2FitRepairCutY'];seam=[]
for v in bpy.data.objects['Front_continuous_fitted_skin'].data.vertices:
 p=v.co
 if abs(p.y-(cut+.001))>2e-5:continue
 # The manufactured return underneath the engine bay has no retained skin.
 if p.z<.70:continue
 near,normal,idx,d=retained.find_nearest(p)
 seam.append(float(d))
seamcheck={'samples':len(seam),'maximumSeparationMeters':max(seam),'toleranceMeters':.004}
if max(seam)>.004:errors.append({'bodyNoseJoin':seamcheck})
insertchecks=[]
for name in ['Front_grille_shallow_panel','Lower_grille_shallow_panel','L_Front_lamp_fitted','R_Front_lamp_fitted']:
 o=bpy.data.objects[name];me=o.data;me.calc_loop_triangles();gaps=[]
 for t in me.loop_triangles:
  f=me.polygons[t.polygon_index]
  if f.normal.y>-.3:continue
  a,b,c=[o.matrix_world@me.vertices[i].co for i in t.vertices]
  for p in [a,b,c,(a+b+c)/3,(a+b)/2,(a+c)/2,(b+c)/2]:
   hit,n,idx,d=nose.ray_cast(Vector((p.x,-3,p.z)),Vector((0,1,0)),1.5)
   if hit is not None:gaps.append(hit.y-p.y)
 row={'name':name,'surfaceSamples':len(gaps),'minimumOutsideSkinMeters':min(gaps)};insertchecks.append(row)
 if min(gaps)<-.001:errors.append({'buriedFrontInsert':row})
original=OUT/'BoraS2_Clean.blend';source_hash=hashlib.sha256(original.read_bytes()).hexdigest()
assert source_hash==bpy.context.scene['S2FitRepairSourceSHA256'],'The source/open file was overwritten'
report={'status':'pass' if not errors else 'needs-repair','frontGlassChecks':records,'frontInsertChecks':insertchecks,'noseCoverageRays':covered,'noseCoverageMisses':misses,'bodyNoseJoin':seamcheck,'errors':errors,'originalBlendUnchanged':True,'installedInPlace':False}
(OUT/'BoraS2_FitFix_Clearance.json').write_text(json.dumps(report,indent=2))
print('FIT_CHECK',json.dumps(report),flush=True)
if errors:raise RuntimeError('Assembly clearance/coverage failed')
