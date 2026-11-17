from pathlib import Path
import bpy,json
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(ROOT/'assets/vehicles/source/BoraCN7_Tripo_Source.glb'))
objects=[o for o in bpy.context.scene.objects if o.type=='MESH']
for o in objects:
 coords=[o.matrix_world@v.co for v in o.data.vertices]
 lo=[min(p[i] for p in coords) for i in range(3)];hi=[max(p[i] for p in coords) for i in range(3)]
 print('CAR_OBJECT',o.name,len(o.data.vertices),len(o.data.polygons),'BOUNDS',lo,hi,flush=True)
 for slot in o.material_slots:
  if slot.material and slot.material.use_nodes:
   for n in slot.material.node_tree.nodes:
    if n.type=='TEX_IMAGE':print('CAR_TEXTURE',n.image.name,list(n.image.size),flush=True)
