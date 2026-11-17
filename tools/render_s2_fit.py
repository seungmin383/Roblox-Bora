"""Visual checks at the reported nose and windscreen problem angles."""
import bpy,sys
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'assets/vehicles/retopology'
bpy.ops.wm.open_mainfile(filepath=str(OUT/'BoraS2_FitFix.blend'))
scene=bpy.context.scene;cam=scene.camera;scene.render.resolution_x=1200;scene.render.resolution_y=900;scene.cycles.samples=24
if '--fast' in sys.argv:scene.render.resolution_x=1000;scene.render.resolution_y=750;scene.cycles.samples=16
if '--quick' in sys.argv:scene.render.resolution_percentage=75;scene.cycles.samples=12
for name,loc,target,lens in [('s2-fit-nose.png',(2.5,-3.8,1.38),(.35,-1.98,.66),60),('s2-fit-glass.png',(2.3,-2.6,3.4),(0,-.65,1.04),58),('s2-fit-front.png',(5.3,-6.2,2.7),(0,0,.65),52),('s2-fit-nose-high.png',(1.6,-3.4,2.8),(.15,-1.88,.68),57)]:
 cam.location=loc;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.lens=lens;scene.render.filepath=str(OUT/name);bpy.ops.render.render(write_still=True)
 if '--quick' in sys.argv:break
if '--wire' in sys.argv:
 gray=bpy.data.materials.new('Fit QA solid');gray.use_nodes=True;gray.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value=(.30,.36,.43,1)
 black=bpy.data.materials.new('Fit QA wire');black.use_nodes=True;black.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value=(.004,.006,.009,1)
 for o in scene.objects:
  if o.type!='MESH' or not o.get('asset'):continue
  if any('glass' in m.name.lower() for m in o.data.materials):o.hide_render=True;continue
  o.data.materials.clear();o.data.materials.append(gray);o.data.materials.append(black)
  for p in o.data.polygons:p.material_index=0
  mod=o.modifiers.new('QA true edges','WIREFRAME');mod.thickness=.0006;mod.use_replace=False;mod.use_even_offset=False;mod.material_offset=1
 cam.location=(2.5,-3.8,1.6);cam.rotation_euler=(Vector((.15,-1.94,.64))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.lens=58;scene.render.filepath=str(OUT/'s2-fit-nose-wire.png');bpy.ops.render.render(write_still=True)
