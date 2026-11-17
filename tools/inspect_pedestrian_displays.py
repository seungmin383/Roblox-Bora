import bpy,sys,json,hashlib,math,numpy as np
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[1]
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'assets/traffic/retopology/PedestrianSignal_Clean.blend'))
mesh=bpy.data.objects['PedestrianSignal_Clean'].data;mark=mesh.attributes['HousingFace']
faces=sorted(tuple(sorted(tuple(round(x,7) for x in mesh.vertices[v].co) for v in f.vertices)) for f in mesh.polygons if mark.data[f.index].value)
baseline={'housing':hashlib.sha256(repr(faces).encode()).hexdigest()}
for ext in ('blend','mesh','png'):
    p=ROOT/f'assets/traffic/retopology/TrafficSignal_Clean.{ext}';baseline['TrafficSignal.'+ext]=hashlib.sha256(p.read_bytes()).hexdigest()
path=ROOT/'dist/pedestrian-display-baseline.json'
if not path.exists():path.write_text(json.dumps(baseline,indent=2))
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'assets/traffic/local/PedestrianSignal.blend'))
obj=next(o for o in bpy.context.scene.objects if o.type=='MESH');mesh=obj.data;mesh.calc_loop_triangles()
tree=BVHTree.FromPolygons([v.co for v in mesh.vertices],[tuple(t.vertices) for t in mesh.loop_triangles],all_triangles=True)
points=np.array([v.co[:] for v in mesh.vertices]);report=[]
for cy in (.205,-.205):
    p=points[(abs(points[:,1]-cy)<.19)&(points[:,2]<.009)];print('Front bounds',cy,p.min(axis=0),p.max(axis=0),flush=True)
    for z in (-.130,-.110,-.090,-.070,-.050,-.030,-.010,.005):
        near=p[abs(p[:,2]-z)<.01]
        if len(near):print('z section',z,'bounds',np.round(near.min(axis=0),4),np.round(near.max(axis=0),4),flush=True)
    rows=[]
    for dy in (-.16,-.14,-.12,-.08,0,.08,.12,.14,.16):
        row=[]
        for x in (-.16,-.14,-.12,-.08,0,.08,.12,.14,.16):
            loc,normal,_,_=tree.ray_cast(Vector((x,cy+dy,-1)),Vector((0,0,1)),2)
            row.append(None if loc is None else round(loc.z,4))
        rows.append([dy,row])
    report.append({'centerY':cy,'frontGrid':rows})
print(json.dumps(report),flush=True)
(ROOT/'dist/pedestrian-display-measurements.json').write_text(json.dumps(report,indent=2))
