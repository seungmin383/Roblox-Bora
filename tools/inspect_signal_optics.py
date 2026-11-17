"""Measure the exposed lower optical profile without opening a desktop window."""
import bpy,sys,math,json,hashlib,numpy as np
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from signal_hoods import fit
def signature(obj,tag):
    mesh=obj.data;mark=mesh.attributes[tag]
    faces=sorted(tuple(sorted(tuple(round(x,7) for x in mesh.vertices[v].co) for v in f.vertices)) for f in mesh.polygons if mark.data[f.index].value)
    return hashlib.sha256(repr(faces).encode()).hexdigest()
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'assets/traffic/retopology/TrafficSignal_Clean.blend'))
obj=bpy.data.objects['TrafficSignal_Clean']
baseline={tag:signature(obj,tag) for tag in ('HousingFace','HoodFace')}
baseline_path=ROOT/'dist/signal-optics-baseline.json'
if not baseline_path.exists():baseline_path.write_text(json.dumps(baseline,indent=2))
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'assets/traffic/local/TrafficSignal.blend'))
obj=next(o for o in bpy.context.scene.objects if o.type=='MESH');obj.data.calc_loop_triangles()
tree=BVHTree.FromPolygons([v.co for v in obj.data.vertices],[tuple(t.vertices) for t in obj.data.loop_triangles],all_triangles=True)
report=[]
for spec in fit(obj):
    cx,cy=spec['center'];profile=[]
    for r in np.arange(0,.296,.005):
        samples=[]
        for angle in np.radians(np.linspace(165,195,13)):
            x=cx+r*math.sin(angle);y=cy+r*math.cos(angle)
            p,n,_,_=tree.ray_cast(Vector((x,y,-1)),Vector((0,0,1)),1)
            if p is not None:samples.append((p.z,n.z))
        if samples:
            z=np.array(samples)[:,0];profile.append([round(float(r),3),round(float(np.median(z)),5),round(float(z.min()),5),round(float(z.max()),5)])
    points=[]
    for r in np.linspace(0,.145,16):
        for a in np.linspace(0,2*math.pi,32,endpoint=False):
            p,_,_,_=tree.ray_cast(Vector((cx+r*math.sin(a),cy+r*math.cos(a),-1)),Vector((0,0,1)),1)
            if p is not None:points.append(tuple(p))
    points=np.array(points);coef=np.linalg.lstsq(np.column_stack((2*points,np.ones(len(points)))),np.sum(points*points,axis=1),rcond=None)[0]
    print('Lens sphere center',coef[:3],flush=True)
    angular=[]
    for degrees in range(0,360,15):
        a=math.radians(degrees);values=[]
        for r in (.17,.185,.20,.215,.23,.245,.26,.275):
            p,n,_,_=tree.ray_cast(Vector((cx+r*math.sin(a),cy+r*math.cos(a),-1)),Vector((0,0,1)),1)
            values.append(None if p is None else round(p.z,4))
        angular.append([degrees,values])
    report.append({'center':spec['center'],'profile':profile,'angular':angular})
print(json.dumps([r['angular'] for r in report]),flush=True)
(ROOT/'dist/signal-optics-measurements.json').write_text(json.dumps(report,indent=2))
