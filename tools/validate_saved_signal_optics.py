"""Validate the saved optical loops and preserve the approved case and shades."""
import bpy,bmesh,json,hashlib,math
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'assets/traffic/retopology/TrafficSignal_Clean.blend'))
obj=bpy.data.objects['TrafficSignal_Clean'];mesh=obj.data
def signature(tag):
    mark=mesh.attributes[tag]
    faces=sorted(tuple(sorted(tuple(round(x,7) for x in mesh.vertices[v].co) for v in f.vertices)) for f in mesh.polygons if mark.data[f.index].value)
    return hashlib.sha256(repr(faces).encode()).hexdigest()
baseline=json.loads((ROOT/'dist/signal-optics-baseline.json').read_text())
assert baseline=={tag:signature(tag) for tag in baseline},'Previously approved housing or shades changed'
tag=mesh.attributes['OpticFace'];normal=mesh.attributes['OpticNormal']
normal_error=max((mesh.corner_normals[lid].vector-normal.data[lid].vector).length for face in mesh.polygons if tag.data[face.index].value for lid in face.loop_indices)
print('Maximum saved optical normal error',normal_error,flush=True)
assert normal_error<.001,('Optical custom normals were lost',normal_error)
bm=bmesh.new();bm.from_mesh(mesh);mark=bm.faces.layers.int['OpticFace'];kind=bm.faces.layers.int['OpticKind']
remaining={f for f in bm.faces if f[mark]};components=[]
while remaining:
    seed=remaining.pop();component={seed};stack=[seed]
    while stack:
        f=stack.pop()
        for e in f.edges:
            for other in e.link_faces:
                if other in remaining:remaining.remove(other);component.add(other);stack.append(other)
    edges={e for f in component for e in f.edges};vertices={v for f in component for v in f.verts}
    assert all(len([f for f in e.link_faces if f in component])==2 for e in edges),'Optical thickness has an open edge'
    types={f[kind] for f in component};assert len(types)==1
    component_kind=next(iter(types));euler=len(vertices)-len(edges)+len(component)
    assert euler==(0 if component_kind==1 else 2)
    if component_kind==1:assert all(len(f.verts)==4 for f in component)
    components.append({'kind':'bezel' if component_kind==1 else 'lens','faces':len(component),'euler':euler,'closed':True})
bm.free()
assert len(components)==6 and sum(c['kind']=='bezel' for c in components)==3
report=next(r for r in json.loads((ROOT/'assets/traffic/retopology/cleanup-report.json').read_text()) if r['asset']=='TrafficSignal')
max_loop_error=0
optic_vertices={vid for face in mesh.polygons if tag.data[face.index].value for vid in face.vertices}
for optical in report['housing']['rebuiltOptics']:
    cx,cy=optical['centerMeters'];profile=optical['bezelProfile'];rings=optical['lensRings'];radius=optical['lensRadiusMeters'];n=optical['radialSegments']
    found=[]
    for vertex in mesh.vertices:
        if vertex.index not in optic_vertices:continue
        r=math.hypot(vertex.co.x-cx,vertex.co.y-cy)
        if r<.31:found.append((r,vertex.co.z))
    # Every specified rim loop contains a complete, regular circle.
    for r,z in profile:
        points=[(pr,pz) for pr,pz in found if abs(pr-r)<.000002 and abs(pz-z)<.000002]
        assert len(points)==n,('Incomplete circular bezel loop',r,z,len(points))
        max_loop_error=max(max_loop_error,max(abs(pr-r) for pr,pz in points))
    assert optical['glassFitSamples']>400 and optical['rimFitSamples']>500
    assert radius>.16 and optical['minimumLensThicknessMm']==10
    rim_depths=sorted(pz for pr,pz in found if abs(pr-radius)<.000002)
    assert len(rim_depths)==2*n
    assert abs((rim_depths[-1]-rim_depths[0])-.010)<.000001,'Lens edge thickness changed'
    assert all(optical['lensPolynomial'][1]+2*optical['lensPolynomial'][2]*(radius*i/100)**2>0 for i in range(101)),'Lens has a ripple or depression'
result={'approvedHousingAndShadesUnchanged':True,'components':components,'maximumLoopRadiusErrorMm':max_loop_error*1000,'maximumCustomNormalError':normal_error,'minimumLensEdgeThicknessMm':10}
(ROOT/'dist/saved-signal-optics-validation.json').write_text(json.dumps(result,indent=2))
print('PASS: six closed optical shells, regular circular quad bezels, monotone convex lenses, preserved normals, and unchanged approved housing/shades.',flush=True)
