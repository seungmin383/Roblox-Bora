"""Inspect the newly generated sedan without changing existing vehicle assets."""
import bpy,bmesh,json,math,hashlib
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'assets/vehicles/retopology'
protected=[ROOT/'Ro.rbxlx']+list((ROOT/'assets/vehicles/local').glob('*'))+list((ROOT/'assets/traffic/retopology').glob('*.blend'))
hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in protected if p.is_file()}
(OUT/'preserved-files.json').write_text(json.dumps(hashes,indent=2))
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(ROOT/'assets/vehicles/source/BoraS2_Tripo_Quad_Source.glb'))
report=[]
for obj in [o for o in bpy.context.scene.objects if o.type=='MESH']:
    bpy.context.view_layer.objects.active=obj;obj.select_set(True);bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    mesh=obj.data;mesh.calc_loop_triangles();bm=bmesh.new();bm.from_mesh(mesh)
    row={'name':obj.name,'vertices':len(mesh.vertices),'faces':len(mesh.polygons),'triangles':len(mesh.loop_triangles),
         'boundsLow':[min(v.co[i] for v in mesh.vertices) for i in range(3)],'boundsHigh':[max(v.co[i] for v in mesh.vertices) for i in range(3)],
         'boundaryEdges':sum(e.is_boundary for e in bm.edges),'materials':[s.material.name if s.material else None for s in obj.material_slots],
         'UVs':[(u.name,len(u.data)) for u in mesh.uv_layers]}
    remaining=set(bm.verts);components=[]
    while remaining:
        seed=remaining.pop();vertices={seed};stack=[seed]
        while stack:
            v=stack.pop()
            for e in v.link_edges:
                other=e.other_vert(v)
                if other in remaining:remaining.remove(other);vertices.add(other);stack.append(other)
        components.append({'vertices':len(vertices),'low':[min(v.co[i] for v in vertices) for i in range(3)],'high':[max(v.co[i] for v in vertices) for i in range(3)]})
    row['components']=sorted(components,key=lambda c:c['vertices'],reverse=True);bm.free();report.append(row)
print(json.dumps(report),flush=True)
(OUT/'source-inspection.json').write_text(json.dumps(report,indent=2))
