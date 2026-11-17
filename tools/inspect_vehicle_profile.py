from pathlib import Path
import bpy,numpy as np,sys
from mathutils import Vector
root=Path(__file__).resolve().parents[1]
refit='--refit' in sys.argv
bpy.ops.wm.open_mainfile(filepath=str(root/'assets/vehicles/local'/('BoraTripoSedan_Refit.blend' if refit else 'BoraTripoSedan.blend')))
if not refit:
 source=next(o for o in bpy.context.scene.objects if o.type=='MESH' and not o.get('group') and len(o.data.polygons)>40000)
 p=np.array([tuple(v.co) for v in source.data.vertices])
 for y in np.arange(-2.1,2.31,.2):
  a=p[(abs(p[:,1]-y)<.06)&(abs(p[:,0])<.5)]
  if len(a):print('PROFILE',round(y,2),'top',round(np.quantile(a[:,2],.99),3),flush=True)
 for o in list(bpy.context.scene.objects):
  if o!=source:bpy.data.objects.remove(o,do_unlink=True)
 source.hide_render=False;source.hide_viewport=False
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=16;scene.cycles.use_denoising=True;scene.world.color=(.4,.4,.4)
for loc in [(1,-4,6),(-4,1,5),(3,4,4)]:
 bpy.ops.object.light_add(type='AREA',location=loc);o=bpy.context.object;o.data.energy=1200;o.data.size=5;o.rotation_euler=(-o.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.mesh.primitive_plane_add(size=200)
bpy.ops.object.camera_add(location=(-5.1,-6.6,3.05));cam=bpy.context.object;cam.rotation_euler=(Vector((0,-.05,.6))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.lens=52;scene.camera=cam
scene.render.resolution_x=1300;scene.render.resolution_y=850;scene.render.resolution_percentage=100;scene.render.filepath=str(root/'dist/preview'/('tripo-refit-direct.png' if refit else 'tripo-source-unaltered.png'));bpy.ops.render.render(write_still=True)
