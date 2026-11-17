"""Inspect the saved asset, not only values returned by its construction code."""
from pathlib import Path
import bpy,bmesh,json
ROOT=Path(__file__).resolve().parents[1]
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'assets/traffic/retopology/TrafficSignal_Clean.blend'))
obj=bpy.data.objects['TrafficSignal_Clean'];mesh=obj.data
tag=mesh.attributes['HoodFace'];stored=mesh.attributes['HoodNormal']
errors=[]
for face in mesh.polygons:
    if tag.data[face.index].value:
        for lid in face.loop_indices:errors.append((mesh.corner_normals[lid].vector-stored.data[lid].vector).length)
print('Saved normal error',max(errors),flush=True)
assert max(errors)<.001,'Original noisy shading leaked into remade sunshades'
bm=bmesh.new();bm.from_mesh(mesh);tag=bm.faces.layers.int['HoodFace'];todo={f for f in bm.faces if f[tag]};components=[]
while todo:
    seed=todo.pop();stack=[seed];component={seed}
    while stack:
        face=stack.pop()
        for edge in face.edges:
            for linked in edge.link_faces:
                if linked in todo:todo.remove(linked);component.add(linked);stack.append(linked)
    edges={e for f in component for e in f.edges};verts={v for f in component for v in f.verts}
    assert all(len(e.link_faces)==2 for e in edges),'Saved shade/flange has an open boundary'
    z0=min(v.co.z for v in verts);z1=max(v.co.z for v in verts)
    components.append({'faces':len(component),'vertices':len(verts),'depthMeters':z1-z0})
bm.free()
assert len(components)==6
assert sum(c['faces']==146 for c in components)==3
assert sum(c['faces']==128 for c in components)==3
assert sum(c['depthMeters']>.30 for c in components)==3
report={'closedManufacturedComponents':components,'maximumStoredNormalError':max(errors),'sourceNormalsExcluded':True}
(ROOT/'dist/saved-signal-hood-validation.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print('PASS: saved asset contains three closed thick shades and three closed flanges; clean normals survive save/reload.',flush=True)
