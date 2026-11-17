from pathlib import Path
import bpy
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'assets/vehicles/local/BoraS1_Retopology.blend'))
deps=bpy.context.evaluated_depsgraph_get()
for y,z in [(.8,.8),(.8,.65),(-.2,.8),(-1.1,.9),(-2.22,.8)]:
    hits=[]
    for o in bpy.context.scene.objects:
        if o.type!='MESH':continue
        inv=o.matrix_world.inverted();pos=inv@Vector((-2,y,z));direction=inv.to_3x3()@Vector((1,0,0))
        ok,co,no,idx=o.ray_cast(pos,direction,distance=3,depsgraph=deps)
        if ok:
            p=o.matrix_world@co;hits.append((round(p.x,5),o.name,tuple(round(a,3) for a in no)))
    print('Surface',y,z,sorted(hits)[:8],flush=True)
