"""Only replace the S3 steering support; preserve all other saved geometry."""
import bpy,bmesh,sys,json,hashlib,struct
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'assets/vehicles/BoraS3'
sys.path.insert(0,str(ROOT/'tools'))
from car_surface_tools import tube,box
TARGET='Steering | column';MOUNT='Steering | lower dashboard mount'
protected=[ROOT/'Ro.rbxlx',ROOT/'assets/example/Car/temp.blend']
file_hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in protected}
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.open_mainfile(filepath=str(OUT/'BoraS3.blend'),load_ui=False)
bpy.context.view_layer.update()
def signatures():
    result={}
    for o in bpy.context.scene.objects:
        if o.type!='MESH' or o.name in {TARGET,MOUNT}:continue
        h=hashlib.sha256()
        for v in o.data.vertices:h.update(struct.pack('<3f',*v.co))
        for f in o.data.polygons:h.update(str(tuple(f.vertices)).encode())
        for layer in o.data.uv_layers:
            for v in layer.data:h.update(struct.pack('<2f',*v.uv))
        h.update(str(tuple(tuple(row) for row in o.matrix_world)).encode())
        h.update(str([m.name if m else '' for m in o.data.materials]).encode())
        result[o.name]=h.hexdigest()
    return result
before=signatures();old=bpy.data.objects[TARGET]
parent=old.parent;collections=list(old.users_collection);mat=old.data.materials[0]
existing=bpy.data.objects.get(MOUNT)
if existing:bpy.data.objects.remove(existing,do_unlink=True)
driver_normal=Vector((0,.8660254038,.5))
shaft_top=Vector((.405,-.37,.963))-driver_normal*.02 if bpy.data.objects['Steering | pivot'].get('DriverFacingCorrected') else Vector((.405,-.374,.950))
new=tube('Steering support temporary',[(.405,-.404,.736),(.405,-.376,.779),tuple(shaft_top)],.016,mat,'Interior',sides=16)
inverse=old.matrix_world.inverted()
for v in new.data.vertices:v.co=inverse@v.co
old.data=new.data
bpy.data.objects.remove(new,do_unlink=True)
mount=box(MOUNT,(.405,-.389,.744),(.085,.026,.058),mat,'Interior',radius=.012)
bpy.context.view_layer.update();world=mount.matrix_world.copy()
for c in list(mount.users_collection):c.objects.unlink(mount)
for c in collections:c.objects.link(mount)
mount.parent=parent;mount.matrix_world=world
layer=mount.data.uv_layers.new(name='UVMap')
for loop in mount.data.loops:
    co=mount.data.vertices[loop.vertex_index].co
    layer.data[loop.index].uv=(co.x/.085+.5,co.z/.058+.5)
bpy.context.view_layer.update()
assert signatures()==before,'Unrelated geometry or placement changed'
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'BoraS3.blend'))
bpy.ops.wm.open_mainfile(filepath=str(OUT/'BoraS3.blend'),load_ui=False)
bpy.context.view_layer.update()
assert signatures()==before,'Unrelated saved geometry changed on reload'
def tree(o):
    o.data.calc_loop_triangles()
    return BVHTree.FromPolygons([o.matrix_world@v.co for v in o.data.vertices],[t.vertices[:] for t in o.data.loop_triangles],all_triangles=True)
column=bpy.data.objects[TARGET];rim=bpy.data.objects['Steering | stitched leather rim']
assert not tree(column).overlap(tree(rim)),'New shaft intersects wheel rim'
assets=[o for o in bpy.context.scene.objects if o.type=='MESH' and o.get('asset')=='BORA S3']
for o in bpy.context.selected_objects:o.select_set(False)
for o in assets:o.select_set(True)
bpy.context.view_layer.objects.active=column
bpy.ops.export_scene.gltf(filepath=str(OUT/'BoraS3.glb'),export_format='GLB',use_selection=True,export_yup=True,export_apply=True,export_extras=True,export_cameras=False,export_lights=False)
assert all(hashlib.sha256((ROOT/p).read_bytes()).hexdigest()==h for p,h in file_hashes.items())
report={'changedObjects':[TARGET,MOUNT],'unchangedOtherMeshes':len(before),'unchangedOtherSignatures':before,
 'wheelRimPreserved':True,'shaftRimIntersection':False,'basePositionMetres':[.405,-.404,.736],
 'protectedUnchanged':True,'installedInPlace':False}
(OUT/'steering-mount-change.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print('Steering mount updated; other meshes preserved:',len(before),flush=True)
# A close view at the user's reported angle; review edits are not saved.
scene=bpy.context.scene;cam=scene.camera;cam.hide_set(False)
for o in scene.objects:
    if o.type=='LIGHT':o.hide_set(False)
cam.location=(.70,.45,1.13);target=Vector((.405,-.37,.86))
cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.lens=36
scene.render.engine='CYCLES';scene.cycles.samples=20;scene.cycles.use_denoising=True
scene.render.resolution_x=1150;scene.render.resolution_y=1000;scene.render.resolution_percentage=100
scene.render.filepath=str(OUT/'S3_SteeringMount.png');bpy.ops.render.render(write_still=True)
