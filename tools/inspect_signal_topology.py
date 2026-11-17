from pathlib import Path
import bpy,bmesh,json,math
ROOT=Path(__file__).resolve().parents[1]
report=[]
for name in ('TrafficSignal','PedestrianSignal'):
    bpy.ops.wm.open_mainfile(filepath=str(ROOT/'assets/traffic/local'/f'{name}.blend'))
    obj=next(o for o in bpy.context.scene.objects if o.type=='MESH')
    row={'asset':name,'vertices':len(obj.data.vertices),'faces':len(obj.data.polygons),'variants':[]}
    for angle in (.1,.5,1,2):
        bm=bmesh.new();bm.from_mesh(obj.data);bm.normal_update()
        bmesh.ops.dissolve_limit(bm,angle_limit=math.radians(angle),use_dissolve_boundaries=False,verts=list(bm.verts),edges=list(bm.edges),delimit={'UV','MATERIAL','SEAM','SHARP'})
        planar=len(bm.faces)
        bmesh.ops.join_triangles(bm,faces=list(bm.faces),angle_face_threshold=math.radians(20),angle_shape_threshold=math.radians(40),cmp_uvs=True,cmp_materials=True,cmp_seam=True,cmp_sharp=True)
        row['variants'].append({'degrees':angle,'afterPlanar':planar,'afterQuads':len(bm.faces),'quads':sum(len(f.verts)==4 for f in bm.faces),'ngons':sum(len(f.verts)>4 for f in bm.faces)})
        bm.free()
    report.append(row)
print(json.dumps(report,indent=2),flush=True)
(ROOT/'dist/signal-topology-inspection.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
