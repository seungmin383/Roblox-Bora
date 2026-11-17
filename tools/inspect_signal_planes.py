from pathlib import Path
import bpy,numpy as np,json
ROOT=Path(__file__).resolve().parents[1]
for name in ('TrafficSignal','PedestrianSignal'):
 bpy.ops.wm.open_mainfile(filepath=str(ROOT/'assets/traffic/local'/f'{name}.blend'))
 o=next(o for o in bpy.context.scene.objects if o.type=='MESH');o.data.calc_loop_triangles()
 p=np.array([v.co[:] for v in o.data.vertices]);f=np.array([tuple(t.vertices) for t in o.data.loop_triangles]);a,b,c=p[f[:,0]],p[f[:,1]],p[f[:,2]];cross=np.cross(b-a,c-a);area=np.linalg.norm(cross,axis=1)/2;n=cross/(2*area[:,None]);centers=p[f].mean(axis=1)
 report={'name':name,'bounds':[p.min(axis=0).tolist(),p.max(axis=0).tolist()],'planes':[]}
 for axis in range(3):
  for sign in (-1,1):
   ids=np.where(n[:,axis]*sign>.92)[0];bins=np.round(centers[ids,axis]/.002).astype(int)
   best=sorted(set(bins),key=lambda k:-area[ids[np.abs(bins-k)<=1]].sum())[:8]
   report['planes'].append({'axis':axis,'sign':sign,'peaks':[(round(k*.002,4),round(float(area[ids[np.abs(bins-k)<=1]].sum()),4)) for k in best]})
 print(json.dumps(report),flush=True)
