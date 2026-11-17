"""Correct the steering wheel driver-facing plane without moving the cabin."""
import bpy,sys,math,hashlib,struct,json
from pathlib import Path
from mathutils import Vector,Matrix
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'assets/vehicles/BoraS3'
sys.path.insert(0,str(ROOT/'tools'))
from car_surface_tools import tube
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.open_mainfile(filepath=str(OUT/'BoraS3.blend'),load_ui=False)
bpy.context.view_layer.update()
center=Vector((.405,-.37,.963));normal=Vector((0,math.cos(math.radians(30)),math.sin(math.radians(30))))
up=Vector((0,-math.sin(math.radians(30)),math.cos(math.radians(30))))
root=bpy.data.objects['Steering | pivot'];column=bpy.data.objects['Steering | column']
def signatures():
    result={}
    for o in bpy.context.scene.objects:
        if o.type!='MESH' or o.get('group')=='Steering' or o.name=='Steering | column':continue
        h=hashlib.sha256()
        for v in o.data.vertices:h.update(struct.pack('<3f',*v.co))
        for f in o.data.polygons:h.update(str(tuple(f.vertices)).encode())
        for layer in o.data.uv_layers:
            for v in layer.data:h.update(struct.pack('<2f',*v.uv))
        h.update(str(tuple(tuple(row) for row in o.matrix_world)).encode())
        result[o.name]=h.hexdigest()
    return result
before=signatures()
if not root.get('DriverFacingCorrected'):
    transform=Matrix.Translation(center)@Matrix.Rotation(math.radians(50),4,'X')@Matrix.Translation(-center)
    for o in bpy.context.scene.objects:
        if o.type=='MESH' and o.get('group')=='Steering':o.matrix_world=transform@o.matrix_world
rot=Matrix.Rotation(math.radians(30),4,'X')
for s in [-1,1]:
    p=center+Vector((s*.097,0,0))+normal*.024
    bpy.data.objects['Steering | control pad '+str(s)].matrix_world=Matrix.Translation(p)@rot
    for z in [-.007,.007]:
        bpy.data.objects['Steering | button '+str(s)+' '+str(z)].matrix_world=Matrix.Translation(p+normal*.014+up*z)@rot
temp=tube('New shaft temporary',[(.405,-.404,.736),(.405,-.376,.779),tuple(center-normal*.02)],.016,column.data.materials[0],'Interior',sides=16)
inverse=column.matrix_world.inverted()
for v in temp.data.vertices:v.co=inverse@v.co
column.data=temp.data;bpy.data.objects.remove(temp,do_unlink=True)
root['DriverFacingCorrected']=True;root['DriverFacingNormal']=list(normal)
bpy.context.view_layer.update()
assert signatures()==before,'Non-steering geometry changed'
pad=bpy.data.objects['Steering | airbag pad']
pad_normal=(pad.matrix_world.to_3x3()@Vector((0,1,0))).normalized()
eye=Vector((.405,.065,1.25));to_driver=(eye-center).normalized()
assert pad_normal.dot(to_driver)>.99,'Wheel face must look directly toward driver head'
rim=bpy.data.objects['Steering | stitched leather rim']
pts=[rim.matrix_world@v.co for v in rim.data.vertices]
# The top of the wheel belongs nearer the windshield; the bottom nearer the driver.
top=sum((p for p in pts if p.z>center.z+.14),Vector())/sum(p.z>center.z+.14 for p in pts)
bottom=sum((p for p in pts if p.z<center.z-.14),Vector())/sum(p.z<center.z-.14 for p in pts)
assert top.y<bottom.y
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'BoraS3.blend'))
bpy.ops.wm.open_mainfile(filepath=str(OUT/'BoraS3.blend'),load_ui=False);bpy.context.view_layer.update()
assert signatures()==before
def tree(o):
    o.data.calc_loop_triangles()
    return BVHTree.FromPolygons([o.matrix_world@v.co for v in o.data.vertices],[t.vertices[:] for t in o.data.loop_triangles],all_triangles=True)
assert not tree(bpy.data.objects['Steering | column']).overlap(tree(bpy.data.objects['Steering | stitched leather rim']))
assets=[o for o in bpy.context.scene.objects if o.type=='MESH' and o.get('asset')=='BORA S3']
for o in bpy.context.selected_objects:o.select_set(False)
for o in assets:o.select_set(True)
bpy.context.view_layer.objects.active=bpy.data.objects['Steering | airbag pad']
bpy.ops.export_scene.gltf(filepath=str(OUT/'BoraS3.glb'),export_format='GLB',use_selection=True,export_yup=True,export_apply=True,export_extras=True,export_cameras=False,export_lights=False)
(OUT/'steering-orientation.json').write_text(json.dumps({'driverFacingNormal':list(pad_normal),'alignmentWithDriver':pad_normal.dot(to_driver),'topY':top.y,'bottomY':bottom.y,'preservedOtherMeshCount':len(before),'wheelCentre':list(center),'baseUnchanged':True},indent=2),encoding='utf-8')
print('Driver-facing alignment:',pad_normal.dot(to_driver),flush=True)
scene=bpy.context.scene;cam=scene.camera;cam.hide_set(False)
for o in scene.objects:
    if o.type=='LIGHT':o.hide_set(False)
cam.location=(.405,.065,1.25);target=Vector((.405,-.70,.94))
cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.lens=23
scene.render.engine='CYCLES';scene.cycles.samples=20;scene.cycles.use_denoising=True
scene.render.resolution_x=1250;scene.render.resolution_y=1000;scene.render.resolution_percentage=100
scene.render.filepath=str(OUT/'S3_Cockpit.png');bpy.ops.render.render(write_still=True)
bpy.data.images['Render Result'].save_render(filepath=str(OUT/'S3_SteeringMount.png'),scene=scene)
