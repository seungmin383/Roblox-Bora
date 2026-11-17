"""Export the repaired cached scene after updating all appended object matrices."""
from pathlib import Path
from collections import defaultdict
import bpy,json,math,struct,sys
from mathutils import Vector,Matrix
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'assets/vehicles/local'
scene_file='BoraS1_Retopology.blend' if '--retopo' in sys.argv else ('BoraTripoSedan_Refit.blend' if '--refit' in sys.argv else ('BoraTripoSedan_Polished.blend' if '--polished' in sys.argv else 'BoraTripoSedan.blend'))
bpy.ops.wm.open_mainfile(filepath=str(OUT/scene_file))
bpy.context.view_layer.update()
catalog=json.loads((OUT/'manifest.json').read_text(encoding='utf-8'))
catalog['Parts']=[]
for key in ['VirtualBrand','DisplayName','RemovedBadgeTriangles','PanelSeamsRefined']:catalog.pop(key,None)
catalog['VisualRevision']=4 if '--retopo' in sys.argv else (3 if '--refit' in sys.argv else (2 if '--polished' in sys.argv else 1))
catalog['Retopology']=('--retopo' in sys.argv)
groups=defaultdict(list)
for obj in bpy.context.scene.objects:
 if obj.type=='MESH' and 'group' in obj:groups[(obj['group'],obj['material'])].append(obj)
conversion=Matrix(((1,0,0),(0,0,1),(0,1,0)))
for (group,key),items in sorted(groups.items()):
 pivot=Vector(catalog['Pivots'][group]);rows=[];faces=[];lookup={};lo=Vector((math.inf,)*3);hi=-lo
 for obj in items:
  obj.data.calc_loop_triangles();rotation=obj.matrix_world.to_3x3();uv=obj.data.uv_layers.active
  for tri in obj.data.loop_triangles:
   face=[]
   for lid in tri.loops:
    loop=obj.data.loops[lid];p=conversion@(obj.matrix_world@obj.data.vertices[loop.vertex_index].co)-pivot
    normal=(conversion@rotation@obj.data.corner_normals[lid].vector).normalized();tex=uv.data[lid].uv if uv else (0,0)
    lo=Vector(tuple(min(lo[i],p[i]) for i in range(3)));hi=Vector(tuple(max(hi[i],p[i]) for i in range(3)))
    packed=struct.pack('<8f4b4B',*p,*normal,tex[0],1-tex[1],0,0,0,127,255,255,255,255)
    if packed not in lookup:lookup[packed]=len(rows);rows.append(packed)
    face.append(lookup[packed])
   faces.append(tuple(reversed(face)))
 filename=group+'_'+key+'.mesh'
 (OUT/filename).write_bytes(b'version 2.00\n'+struct.pack('<HBBII',12,40,12,len(rows),len(faces))+b''.join(rows)+b''.join(struct.pack('<III',*f) for f in faces))
 if key=='Tripo':rgb=[255,255,255];alpha=0
 elif key=='Glass':rgb=[118,139,152];alpha=.78
 else:
  shader=items[0].data.materials[0].node_tree.nodes.get('Principled BSDF');color=shader.inputs['Base Color'].default_value
  rgb=[round((12.92*c if c<=.0031308 else 1.055*c**(1/2.4)-.055)*255) for c in color[:3]];alpha=0
 part={'Group':group,'Material':key,'File':filename,'Color':rgb,'Transparency':alpha,'Bounds':[max(.001,hi[i]-lo[i]) for i in range(3)],'Triangles':len(faces)}
 if key=='Tripo':part['Texture']='TripoSedan.png'
 catalog['Parts'].append(part)
catalog['TotalTriangles']=sum(p['Triangles'] for p in catalog['Parts'])
(OUT/'manifest.json').write_text(json.dumps(catalog,indent=2),encoding='utf-8')
print('Exported updated matrices:',catalog['TotalTriangles'],'triangles.',flush=True)
