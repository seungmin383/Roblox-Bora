"""Read source detail bounds and record geometry to preserve in the next pass."""
import bpy,sys,math,json,hashlib,numpy as np
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from signal_hoods import fit
from signal_optics import fit_optics
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'assets/traffic/retopology/TrafficSignal_Clean.blend'))
mesh=bpy.data.objects['TrafficSignal_Clean'].data
signatures={}
for tag in ('HousingFace','HoodFace','OpticFace'):
    marked=mesh.attributes[tag]
    faces=sorted(tuple(sorted(tuple(round(x,7) for x in mesh.vertices[v].co) for v in f.vertices)) for f in mesh.polygons if marked.data[f.index].value)
    signatures[tag]=hashlib.sha256(repr(faces).encode()).hexdigest()
path=ROOT/'dist/signal-details-baseline.json'
if not path.exists():path.write_text(json.dumps(signatures,indent=2))
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'assets/traffic/local/TrafficSignal.blend'))
source=next(o for o in bpy.context.scene.objects if o.type=='MESH');points=np.array([v.co[:] for v in source.data.vertices])
def bounds(p):return {'count':len(p),'low':p.min(axis=0).tolist(),'high':p.max(axis=0).tolist()} if len(p) else None
report=[]
for spec in fit(source):
    cx,cy=spec['center'];local=points-np.array((cx,cy,0));rho=np.hypot(local[:,0],local[:,1])
    optic=fit_optics(source,spec);ox,oy=optic['center'];delta=points-np.array((ox,oy,0));radius=np.hypot(delta[:,0],delta[:,1])
    mounts=[]
    for side in (-1,1):
        upper=local[(local[:,0]*side>.11)&(local[:,0]*side<.25)&(local[:,1]>.195)&(local[:,1]<.285)&(local[:,2]<-.24)]
        lower=local[(local[:,0]*side>.11)&(local[:,0]*side<.25)&(local[:,1]<-.12)&(local[:,1]>-.28)&(local[:,2]<-.37)]
        mounts.append({'side':side,'upper':bounds(upper),'lowerFront':bounds(lower)})
        front=delta[(delta[:,0]*side>.10)&(delta[:,1]<-.10)&(radius>.185)&(radius<.30)&(delta[:,2]<-.380)]
        angles=np.arctan2(front[:,0],front[:,1]);a=float(np.median(angles));t=np.array((math.cos(a),-math.sin(a),0));r=np.array((math.sin(a),math.cos(a),0))
        print('Latch fit',spec['center'],side,math.degrees(a),'tangent/radial/z bounds',bounds(np.column_stack((front@t,front@r,front[:,2]))),flush=True)
    report.append({'center':spec['center'],'mounts':mounts})
vents=points[(points[:,1]>.341)&(np.abs(points[:,0])<.98)]
for side in (-1,1):
    v=vents[vents[:,0]*side>0];print('Top ribs',side,bounds(v),flush=True)
    print('Top rib points',np.round(v,4).tolist(),flush=True)
print(json.dumps(report),flush=True)
(ROOT/'dist/signal-detail-measurements.json').write_text(json.dumps(report,indent=2))
