"""Repair graphic orientation on the existing S3 candidate, preserving geometry."""
import bpy,math,hashlib
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'assets/vehicles/BoraS3'
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.open_mainfile(filepath=str(OUT/'BoraS3.blend'),load_ui=False)
objects=[o for o in bpy.context.scene.objects if o.type=='MESH' and o.get('asset')=='BORA S3']
def coordinates():
    h=hashlib.sha256()
    for o in sorted(objects,key=lambda o:o.name):
        h.update(o.name.encode())
        h.update(str([tuple(o.matrix_world@v.co) for v in o.data.vertices]).encode())
    return h.hexdigest()
before=coordinates()
up=Vector((0,-math.sin(math.radians(12)),math.cos(math.radians(12))));right=Vector((-1,0,0))
for name,center,w,h in [('Instrument cluster',(.405,-.598,1.025),.315,.122),('Centre navigation',(-.12,-.479,1.008),.32,.168)]:
    o=bpy.data.objects[name+' | display panel'];uv=o.data.uv_layers.active
    for loop in o.data.loops:
        delta=(o.matrix_world@o.data.vertices[loop.vertex_index].co)-Vector(center)
        uv.data[loop.index].uv=(delta.dot(right)/w+.5,delta.dot(up)/h+.5)
for name,facing in [('Front plate',-1),('Rear plate',1)]:
    o=bpy.data.objects[name+' | printed face'];uv=o.data.uv_layers.active
    zlo=min((o.matrix_world@v.co).z for v in o.data.vertices);zhi=max((o.matrix_world@v.co).z for v in o.data.vertices)
    for loop in o.data.loops:
        co=o.matrix_world@o.data.vertices[loop.vertex_index].co
        uv.data[loop.index].uv=(-facing*co.x/.368+.5,(co.z-zlo)/(zhi-zlo))
assert coordinates()==before
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'BoraS3.blend'))
for o in bpy.context.selected_objects:o.select_set(False)
for o in objects:o.select_set(True)
bpy.context.view_layer.objects.active=objects[0]
bpy.ops.export_scene.gltf(filepath=str(OUT/'BoraS3.glb'),export_format='GLB',use_selection=True,export_yup=True,export_apply=True,export_extras=True,export_cameras=False,export_lights=False)
print('Graphic orientation updated; geometry hash unchanged:',before,flush=True)
