from pathlib import Path
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[1]
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'assets/traffic/local/TrafficSignal.blend'))
o=next(o for o in bpy.context.scene.objects if o.type=='MESH');o.data.calc_loop_triangles()
tree=BVHTree.FromPolygons([v.co for v in o.data.vertices],[tuple(t.vertices) for t in o.data.loop_triangles],all_triangles=True)
for y in [-.35,-.33,-.30,0,.28,.31,.33,.35]:
 row=[]
 for x in [0,.90,.95,.96,.97,.98,.99,1.00,1.01,1.03]:
  hit=tree.ray_cast(Vector((x,y,2)),Vector((0,0,-1)))
  row.append((x,round(hit[0].z,4) if hit[0] else None))
 print('Back surface Y',y,row,flush=True)
