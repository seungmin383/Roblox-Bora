from pathlib import Path
import bpy,struct,json
from mathutils import Vector,Matrix
root=Path(__file__).resolve().parents[1]/'assets/vehicles/local';m=json.loads((root/'manifest.json').read_text());convert=Matrix(((1,0,0),(0,0,1),(0,1,0)))
for p in m['Parts']:
 print('NORMALS',p['File'],flush=True)
 b=(root/p['File']).read_bytes();_,stride,_,nv,nf=struct.unpack_from('<HBBII',b,13);rows=[struct.unpack_from('<8f',b,25+i*stride) for i in range(nv)];faces=[tuple(reversed(struct.unpack_from('<III',b,25+nv*stride+i*12))) for i in range(nf)]
 mesh=bpy.data.meshes.new(p['File']);mesh.from_pydata([convert@Vector(r[:3]) for r in rows],[],faces);mesh.update()
 for f in mesh.polygons:f.use_smooth=True
 mesh.normals_split_custom_set_from_vertices([convert@Vector(r[3:6]) for r in rows])
 print('OK',flush=True)
