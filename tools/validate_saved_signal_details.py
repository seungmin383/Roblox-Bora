"""Check closed simplified fittings while preserving all approved large parts."""
import bpy,bmesh,json,hashlib
from collections import Counter
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'assets/traffic/retopology/TrafficSignal_Clean.blend'))
mesh=bpy.data.objects['TrafficSignal_Clean'].data
baseline=json.loads((ROOT/'dist/signal-details-baseline.json').read_text())
for tag,digest in baseline.items():
    mark=mesh.attributes[tag]
    faces=sorted(tuple(sorted(tuple(round(x,7) for x in mesh.vertices[v].co) for v in f.vertices)) for f in mesh.polygons if mark.data[f.index].value)
    assert hashlib.sha256(repr(faces).encode()).hexdigest()==digest,tag+' approved geometry changed'
mark=mesh.attributes['DetailFace'];expected=mesh.attributes['DetailNormal']
normal_error=max((mesh.corner_normals[lid].vector-expected.data[lid].vector).length for face in mesh.polygons if mark.data[face.index].value for lid in face.loop_indices)
assert normal_error<.001,('Detail flat normals changed',normal_error)
bm=bmesh.new();bm.from_mesh(mesh);tag=bm.faces.layers.int['DetailFace'];kind=bm.faces.layers.int['DetailKind']
remaining={f for f in bm.faces if f[tag]};components=[];max_planarity=0
while remaining:
    seed=remaining.pop();faces={seed};stack=[seed]
    while stack:
        f=stack.pop()
        for edge in f.edges:
            for other in edge.link_faces:
                if other in remaining:remaining.remove(other);faces.add(other);stack.append(other)
    edges={edge for face in faces for edge in face.edges};vertices={vertex for face in faces for vertex in face.verts}
    assert all(len(e.link_faces)==2 for e in edges),'Simplified fitting has an open or nonmanifold edge'
    assert len(vertices)-len(edges)+len(faces)==2,'Fitting contains a hole or disconnected shell'
    assert len(faces)<150,'Small fitting has excessive topology'
    assert all(face.calc_area()>1e-10 for face in faces),'Detail contains a degenerate face'
    for face in faces:
        origin=face.verts[0].co
        max_planarity=max(max_planarity,max(abs((v.co-origin).dot(face.normal)) for v in face.verts))
    categories={f[kind] for f in faces};assert len(categories)==1
    components.append({'kind':categories.pop(),'faces':len(faces),'closed':True})
bm.free();counts=Counter(c['kind'] for c in components)
assert counts=={1:6,2:6,3:12},counts
assert max_planarity<.000001,'Replacement detail has a warped plane'
report=next(r for r in json.loads((ROOT/'assets/traffic/retopology/cleanup-report.json').read_text()) if r['asset']=='TrafficSignal')
assert len(report['housing']['rebuiltDetails'])==24
assert report['after']['triangles']<8978,'Fitting cleanup should reduce the previous candidate triangle count'
assert report['simplifiedSourceDetailDistanceMm']<50 and report['simplifiedExposedDetailDistanceMm']<50
result={'approvedHousingShadesAndOpticsUnchanged':True,'closedDetailParts':components,'maximumFacePlanarityErrorMm':max_planarity*1000,'maximumSavedNormalError':normal_error,'nativeTrianglesBefore':8978,'nativeTrianglesAfter':report['after']['triangles']}
(ROOT/'dist/saved-signal-details-validation.json').write_text(json.dumps(result,indent=2))
print('PASS: 24 closed simple fittings, planar faces, preserved flat normals, fewer triangles, and unchanged approved housing/shades/optics.',flush=True)
