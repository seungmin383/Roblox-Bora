"""Inspect the saved display shells, planar walls and untouched approved assets."""
import bpy,bmesh,json,hashlib
from pathlib import Path
from collections import Counter
ROOT=Path(__file__).resolve().parents[1]
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'assets/traffic/retopology/PedestrianSignal_Clean.blend'))
mesh=bpy.data.objects['PedestrianSignal_Clean'].data
baseline=json.loads((ROOT/'dist/pedestrian-display-baseline.json').read_text())
mark=mesh.attributes['HousingFace']
faces=sorted(tuple(sorted(tuple(round(x,7) for x in mesh.vertices[v].co) for v in f.vertices)) for f in mesh.polygons if mark.data[f.index].value)
assert hashlib.sha256(repr(faces).encode()).hexdigest()==baseline['housing'],'Approved pedestrian case changed'
for ext in ('blend','mesh','png'):
    p=ROOT/f'assets/traffic/retopology/TrafficSignal_Clean.{ext}'
    assert hashlib.sha256(p.read_bytes()).hexdigest()==baseline['TrafficSignal.'+ext],'Vehicle signal candidate changed'
normal_error=0
for prefix in ('Display','Detail'):
    tag=mesh.attributes[prefix+'Face'];normals=mesh.attributes[prefix+'Normal']
    for face in mesh.polygons:
        if not tag.data[face.index].value:continue
        for lid in face.loop_indices:normal_error=max(normal_error,(mesh.corner_normals[lid].vector-normals.data[lid].vector).length)
assert normal_error<.001,('Manufactured normals changed after save',normal_error)
bm=bmesh.new();bm.from_mesh(mesh);tag=bm.faces.layers.int['DisplayFace'];category=bm.faces.layers.int['DisplayKind']
remaining={f for f in bm.faces if f[tag]};components=[];max_straight_error=0
while remaining:
    seed=remaining.pop();faces={seed};stack=[seed]
    while stack:
        face=stack.pop()
        for edge in face.edges:
            for other in edge.link_faces:
                if other in remaining:remaining.remove(other);faces.add(other);stack.append(other)
    vertices={v for f in faces for v in f.verts};edges={e for f in faces for e in f.edges};kinds={f[category] for f in faces}
    assert len(kinds)==1;kind=kinds.pop()
    assert all(len(e.link_faces)==2 for e in edges),'Open edge or nonmanifold display shell'
    assert len(vertices)-len(edges)+len(faces)==(0 if kind==2 else 2)
    if kind==2:
        assert all(len(f.verts)==4 for f in faces)
        # The external long sides must be actual planes with vertical lines.
        walls=[f for f in faces if any(abs(v.co.z+.006)<1e-6 for v in f.verts) and min(v.co.z for v in f.verts)<-.050]
        assert len(walls)==24
        for f in walls:
            origin=f.verts[0].co
            max_straight_error=max(max_straight_error,max(abs((v.co-origin).dot(f.normal)) for v in f.verts))
        assert max_straight_error<.000001,'A long external wall is warped'
        width=max(v.co.x for v in vertices)-min(v.co.x for v in vertices)
        assert abs(width-.302)<.000001
    if kind==3:
        front=[v.co.z for v in vertices if abs(v.co.z+.0185)<1e-6]
        assert len(front)==24,'Display front must be one flat, complete rounded rectangle'
    components.append({'kind':kind,'faces':len(faces),'closed':True})
assert Counter(c['kind'] for c in components)=={1:2,2:2,3:2}
assert sum(e.is_boundary for e in bm.edges)==0,'Saved pedestrian signal contains an open edge'
# Small fasteners are independent closed solids, not partial source fragments.
detail=bm.faces.layers.int['DetailFace'];remaining={f for f in bm.faces if f[detail]};bolts=0
while remaining:
    seed=remaining.pop();faces={seed};stack=[seed]
    while stack:
        face=stack.pop()
        for e in face.edges:
            for other in e.link_faces:
                if other in remaining:remaining.remove(other);faces.add(other);stack.append(other)
    edges={e for f in faces for e in f.edges};vertices={v for f in faces for v in f.verts}
    assert all(len(e.link_faces)==2 for e in edges) and len(vertices)-len(edges)+len(faces)==2
    bolts+=1
assert bolts==11
bm.free()
result={'approvedCaseUnchanged':True,'vehicleSignalCandidateUnchanged':True,'displayShells':components,
        'closedFasteners':bolts,'maximumLongWallPlanarityErrorMm':max_straight_error*1000,'maximumSavedNormalError':normal_error,'openEdges':0}
(ROOT/'dist/saved-pedestrian-display-validation.json').write_text(json.dumps(result,indent=2))
print('PASS: two closed thick rectangular shades, flat panels, closed plates and 11 fasteners; straight walls, saved normals, original case and vehicle signal preserved.',flush=True)
