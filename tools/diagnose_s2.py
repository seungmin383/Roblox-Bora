import bpy,bmesh,json,math
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'assets/vehicles/retopology'
bpy.ops.wm.open_mainfile(filepath=str(OUT/'BoraS2_Source_Review.blend'))
o=bpy.data.objects['S2_Source'];bm=bmesh.new();bm.from_mesh(o.data)
remaining=set(bm.verts);parts=[]
while remaining:
 seed=remaining.pop();vv={seed};stack=[seed]
 while stack:
  v=stack.pop()
  for e in v.link_edges:
   w=e.other_vert(v)
   if w in remaining:remaining.remove(w);vv.add(w);stack.append(w)
 parts.append(vv)
parts.sort(key=len,reverse=True)
rows=[]
for i,vs in enumerate(parts):
 rows.append({'id':i,'vertices':len(vs),'lo':[min(v.co[k] for v in vs)/4.68 for k in range(3)],'hi':[max(v.co[k] for v in vs)/4.68 for k in range(3)],'boundary':sum(e.is_boundary for v in vs for e in v.link_edges)//2})
(OUT/'obj-components.json').write_text(json.dumps(rows,indent=2))
body=parts[0]
(OUT/'body-vertices.json').write_text(json.dumps([{'i':v.index,'co':[round(c/4.68,6) for c in v.co],'boundary':v.is_boundary} for v in body]))
# Orthographic projection with a coordinate grid in source units.
for p in o.data.polygons:p.use_smooth=False
o.data.materials.clear();mat=bpy.data.materials.new('Diagnostic');mat.diffuse_color=(.33,.39,.46,1);o.data.materials.append(mat)
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=8;scene.cycles.use_denoising=True
scene.render.resolution_x=1600;scene.render.resolution_y=800
cam=scene.camera;cam.data.type='ORTHO';cam.data.ortho_scale=5.5;cam.location=(-8,0,.82);cam.rotation_euler=(Vector((0,0,.82))-cam.location).to_track_quat('-Z','Y').to_euler()
for y in range(-5,6):
 bpy.ops.object.text_add(location=(-1.3,y*.1*4.68,0));t=bpy.context.object;t.data.body=f'Y{y/10:.1f}';t.data.size=.08;t.rotation_euler=cam.rotation_euler
for z in range(1,5):
 bpy.ops.object.text_add(location=(-1.3,2.45,z*.1*4.68));t=bpy.context.object;t.data.body=f'Z{z/10:.1f}';t.data.size=.08;t.rotation_euler=cam.rotation_euler
scene.render.filepath=str(OUT/'s2-diagnostic-side.png');bpy.ops.render.render(write_still=True)
o.show_wire=True;o.show_all_edges=True;scene.display.shading.show_xray=False
wire=o.modifiers.new('QA wire','WIREFRAME');wire.thickness=.003;wire.use_replace=False
scene.render.filepath=str(OUT/'s2-diagnostic-wire.png');bpy.ops.render.render(write_still=True)
