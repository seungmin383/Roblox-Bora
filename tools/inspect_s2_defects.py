import bpy,bmesh,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'assets/vehicles/retopology'
bpy.ops.wm.open_mainfile(filepath=str(OUT/'BoraS2_Clean.blend'))
rows=[]
for o in bpy.context.scene.objects:
 if o.type!='MESH' or not o.name.endswith('_paint'):continue
 me=o.data;me.calc_loop_triangles();bm=bmesh.new();bm.from_mesh(me)
 row={'name':o.name,'boundaries':[{'len':e.calc_length(),'coords':[list(v.co) for v in e.verts]} for e in bm.edges if e.is_boundary], 'zeroFaceEdges':sum(not e.link_faces for e in bm.edges),'overusedEdges':sum(len(e.link_faces)>2 for e in bm.edges),'badTriangles':[],'zeroNormalFaces':[]}
 for t in me.loop_triangles:
  vv=[me.vertices[i].co for i in t.vertices];area=(vv[1]-vv[0]).cross(vv[2]-vv[0]).length/2
  if area<5e-12:row['badTriangles'].append({'face':t.polygon_index,'tri':t.vertices[:],'area':area,'faceArea':me.polygons[t.polygon_index].area,'coords':[list(v) for v in vv]})
 for f in me.polygons:
  if any(me.corner_normals[li].vector.length<.9 for li in f.loop_indices):row['zeroNormalFaces'].append({'index':f.index,'verts':f.vertices[:],'normal':list(f.normal),'area':f.area})
 rows.append(row);bm.free()
(OUT/'remaining-defects.json').write_text(json.dumps(rows,indent=2))
print(json.dumps(rows),flush=True)
