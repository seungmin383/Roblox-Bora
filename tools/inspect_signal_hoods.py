from pathlib import Path
import bpy,numpy as np,math,json
from mathutils import Vector
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[1]
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'assets/traffic/local/TrafficSignal.blend'))
o=next(o for o in bpy.context.scene.objects if o.type=='MESH');o.data.calc_loop_triangles()
tree=BVHTree.FromPolygons([v.co for v in o.data.vertices],[tuple(t.vertices) for t in o.data.loop_triangles],all_triangles=True)
p=np.array([v.co[:] for v in o.data.vertices]);reports=[]
for cx in [-.66,0,.66]:
 report={'cx':cx,'rays':[],'lip':[]}
 for z in [-.30,-.38,-.46,-.54]:
  row={'z':z,'radii':[]}
  for degrees in [0,30,60,90,120,150,180]:
   angle=math.radians(degrees);direction=Vector((math.sin(angle),math.cos(angle),0));origin=Vector((cx,-.03,z))+direction*.38;hits=[]
   for _ in range(6):
    hit=tree.ray_cast(origin,-direction,.45)
    if hit[0] is None:break
    radius=(hit[0]-Vector((cx,-.03,z))).dot(direction)
    if radius<0:break
    hits.append(round(radius,4));origin=hit[0]-direction*.0002
   row['radii'].append([degrees,hits])
  report['rays'].append(row)
 rho=np.hypot(p[:,0]-cx,p[:,1]+.03);phi=np.arctan2(p[:,0]-cx,p[:,1]+.03)
 for degrees in range(-180,181,30):
  delta=np.arctan2(np.sin(phi-math.radians(degrees)),np.cos(phi-math.radians(degrees)))
  cloud=p[(rho>.245)&(rho<.310)&(np.abs(delta)<math.radians(8))&(p[:,2]<-.27)]
  report['lip'].append([degrees,round(float(cloud[:,2].min()),4) if len(cloud) else None])
 reports.append(report)
print(json.dumps(reports,indent=2),flush=True)
(ROOT/'dist/signal-hood-inspection.json').write_text(json.dumps(reports,indent=2),encoding='utf-8')
