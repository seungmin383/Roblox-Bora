"""Reload, audit, export and render only the cleaned candidate sedan."""
import bpy,bmesh,json,math,struct,hashlib,sys
import numpy as np
from pathlib import Path
from mathutils import Vector,Matrix
from collections import defaultdict
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'assets/vehicles/retopology'
FIT_FIX='--fit-fix' in sys.argv
BASENAME='BoraS2_FitFix' if FIT_FIX else 'BoraS2_Clean'
bpy.ops.wm.open_mainfile(filepath=str(OUT/(BASENAME+'.blend')))
bpy.context.view_layer.update();scene=bpy.context.scene
objects=[o for o in scene.objects if o.type=='MESH' and o.get('asset')=='BORA S2']
records=[];errors=[];total=0
for o in objects:
 me=o.data;me.calc_loop_triangles();bm=bmesh.new();bm.from_mesh(me)
 badcoords=sum(not all(math.isfinite(c) for c in v.co) for v in me.vertices)
 baduv=sum(not all(math.isfinite(c) for c in d.uv) for uv in me.uv_layers for d in uv.data)
 badnorm=sum(not all(math.isfinite(c) for c in n.vector) or abs(n.vector.length-1)>.001 for n in me.corner_normals)
 degenerate=sum((me.vertices[t.vertices[1]].co-me.vertices[t.vertices[0]].co).cross(me.vertices[t.vertices[2]].co-me.vertices[t.vertices[0]].co).length<1e-11 for t in me.loop_triangles)
 boundary=sum(e.is_boundary for e in bm.edges);nonmanifold=sum(not e.is_manifold for e in bm.edges)
 row={'name':o.name,'group':o['group'],'vertices':len(me.vertices),'editableFaces':len(me.polygons),'triangles':len(me.loop_triangles),'boundaryEdges':boundary,'nonManifoldEdges':nonmanifold,'degenerateTriangles':degenerate,'badCoordinates':badcoords,'badUVs':baduv,'badNormals':badnorm}
 records.append(row);total+=row['triangles'];bm.free()
 if badcoords or baduv or badnorm or degenerate:errors.append(row)
 # Every retained skin and reconstructed solid must be closed in this delivery.
 if nonmanifold:errors.append({'solidNotClosed':o.name,'edges':nonmanifold})
coords=[o.matrix_world@v.co for o in objects for v in o.data.vertices]
lo=[min(v[i] for v in coords) for i in range(3)];hi=[max(v[i] for v in coords) for i in range(3)]
wheelchecks={}
for o in objects:
 if not o.name.endswith('_Tire'):continue
 p=o.location;points=[o.matrix_world@v.co for v in o.data.vertices]
 # The outer crown ring is a mathematical circle, checked at all 48 vertices.
 radial=[math.hypot(v.y-p.y,v.z-p.z) for v in points]
 crown=[r for r in radial if r>.337]
 wheelchecks[o['group']]={'outerRadiusMin':min(crown),'outerRadiusMax':max(crown),'radiusError':max(abs(r-.338) for r in crown),'center':list(p),'groundContactZ':min(v.z for v in points)}
 if max(abs(r-.338) for r in crown)>1e-5:errors.append({'nonCircularWheel':o.name})
old=json.loads((OUT/'preserved-files.json').read_text())
changed=[name for name,h in old.items() if not (ROOT/name).exists() or hashlib.sha256((ROOT/name).read_bytes()).hexdigest()!=h]
places=[str(p.relative_to(ROOT)) for ext in ['*.rbxl','*.rbxlx'] for p in ROOT.rglob(ext)]
audit={'status':'pass' if not errors else 'needs-repair','objects':records,'totalTriangles':total,'boundsMeters':[lo,hi],'dimensionsMeters':[hi[i]-lo[i] for i in range(3)],'wheelChecks':wheelchecks,'errors':errors,'preservedOriginalFilesChanged':changed,'placeFiles':places,'installedInPlace':False}
(OUT/('BoraS2_FitFix_Audit.json' if FIT_FIX else 'BoraS2_Audit.json')).write_text(json.dumps(audit,indent=2),encoding='utf-8')
print('AUDIT',json.dumps({k:v for k,v in audit.items() if k!='objects'}),flush=True)
if errors:raise RuntimeError('Saved candidate has mesh defects; export stopped.')
# Export exactly the reloaded asset, excluding the studio lights/floor.
bpy.ops.object.select_all(action='DESELECT')
for o in objects:o.select_set(True)
bpy.context.view_layer.objects.active=objects[0]
bpy.ops.export_scene.gltf(filepath=str(OUT/(BASENAME+'.glb')),export_format='GLB',use_selection=True,export_apply=True,export_yup=True,export_materials='EXPORT',export_texcoords=True,export_normals=True,export_extras=True)
manifest={'Name':'BORA S2','SourceTripoTask':scene['SourceTripoTask'],'Units':'meters','Axis':'Roblox X right, Y up, Z rear; native meshes are pivot-relative','Pivots':{},'Parts':[],'InstalledInPlace':False,'TotalTriangles':0}
conversion=Matrix(((-1,0,0),(0,0,1),(0,1,0))) if scene.get('S2BlenderHandednessCorrected') else Matrix(((1,0,0),(0,0,1),(0,1,0)))
pivots=json.loads(scene['BoraS2Pivots'])
manifest['Pivots']={g:list(conversion@Vector(p)) for g,p in pivots.items()}
manifest['BlenderToRobloxMatrix']=[list(row) for row in conversion]
groups=defaultdict(list)
for o in objects:
 for mi,mat in enumerate(o.data.materials):groups[(o['group'],mat.name)].append((o,mi,mat))
native=OUT/('native-fit' if FIT_FIX else 'native');native.mkdir(exist_ok=True)
for stale in native.glob('*.mesh'):stale.unlink()
for index,((group,matname),items) in enumerate(sorted(groups.items())):
 pivot=Vector(manifest['Pivots'][group]);rows=[];faces=[];lookup={};mat=items[0][2]
 for o,mi,_ in items:
  me=o.data;me.calc_loop_triangles();uv=me.uv_layers.active;rot=o.matrix_world.to_3x3()
  for t in me.loop_triangles:
   if me.polygons[t.polygon_index].material_index!=mi:continue
   face=[]
   for lid in t.loops:
    loop=me.loops[lid];pos=conversion@(o.matrix_world@me.vertices[loop.vertex_index].co)-pivot;normal=(conversion@rot@me.corner_normals[lid].vector).normalized();tex=uv.data[lid].uv if uv else (0,0)
    packed=struct.pack('<8f4b4B',*pos,*normal,float(tex[0]),1-float(tex[1]),0,0,0,127,255,255,255,255)
    if packed not in lookup:lookup[packed]=len(rows);rows.append(packed)
    face.append(lookup[packed])
   faces.append(tuple(reversed(face)) if conversion.determinant()<0 else tuple(face))
 if not faces:continue
 bs=mat.node_tree.nodes.get('Principled BSDF');color=bs.inputs['Base Color'].default_value
 rgb=[round((12.92*c if c<=.0031308 else 1.055*c**(1/2.4)-.055)*255) for c in color[:3]]
 part={'Group':group,'MaterialName':matname,'Color':rgb,'Transparency':.60 if 'glass' in matname.lower() else 0}
 if 'glass' in matname.lower():part['Material']='Glass'
 else:part['Material']='SmoothPlastic' if bs.inputs['Metallic'].default_value<.3 else 'Metal'
 for node in mat.node_tree.nodes:
  if node.type=='TEX_IMAGE' and node.image:
   if 'FitHeadlamp' in node.image.name:texture='BoraS2_FitLampBaked.png'
   elif 'Grille' in node.image.name:texture='BoraS2_Grille.png'
   elif 'Navigation' in node.image.name:texture='BoraS2_Navigation.png'
   elif 'Instruments' in node.image.name:texture='BoraS2_Instruments.png'
   else:texture='BoraS2_LampGraphics.png'
   part['Texture']='../'+texture;break
 # Keep individual native parts below 8,000 triangles for the existing game
 # asset pipeline. UV/normal splits are remapped independently in each chunk.
 for chunk,start in enumerate(range(0,len(faces),8000)):
  mapping={};chunkrows=[];chunkfaces=[]
  for face in faces[start:start+8000]:
   mapped=[]
   for i in face:
    if i not in mapping:mapping[i]=len(chunkrows);chunkrows.append(rows[i])
    mapped.append(mapping[i])
   chunkfaces.append(mapped)
  filename=f'{group}_{index:02d}_{chunk:02d}.mesh';data=b'version 2.00\n'+struct.pack('<HBBII',12,40,12,len(chunkrows),len(chunkfaces))+b''.join(chunkrows)+b''.join(struct.pack('<III',*face) for face in chunkfaces)
  (native/filename).write_bytes(data)
  points=[struct.unpack_from('<3f',row) for row in chunkrows]
  item=dict(part,File=filename,Triangles=len(chunkfaces),Vertices=len(chunkrows),Bounds=[max(.001,max(p[k] for p in points)-min(p[k] for p in points)) for k in range(3)])
  manifest['Parts'].append(item)
manifest['TotalTriangles']=sum(p['Triangles'] for p in manifest['Parts'])
(native/'manifest.json').write_text(json.dumps(manifest,indent=2))
assert manifest['TotalTriangles']==total
if '--export-only' in sys.argv:raise SystemExit(0)
cam=scene.camera
def render(name,loc,target,lens=52):
 cam.location=loc;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.lens=lens
 scene.render.filepath=str(OUT/name);bpy.ops.render.render(write_still=True)
# Only the QA camera sees a stretch of road; exported car assets contain none.
roadmat=bpy.data.materials.new('QA asphalt');roadmat.diffuse_color=(.035,.045,.06,1)
bpy.ops.mesh.primitive_plane_add(size=1,location=(0,-28,-.006));road=bpy.context.object;road.scale=(7,60,1);road.data.materials.append(roadmat)
stripemat=bpy.data.materials.new('QA stripe');stripemat.diffuse_color=(.85,.83,.61,1)
qaextra=[road]
for y in range(-5,-60,-5):
 bpy.ops.mesh.primitive_cube_add(size=1,location=((1.6 if scene.get('S2BlenderHandednessCorrected') else -1.6),y,.002));ob=bpy.context.object;ob.scale=(.07,2,.008);ob.data.materials.append(stripemat);qaextra.append(ob)
driver_x=pivots['Steering'][0]
render('s2-cockpit.png',(driver_x,.10,1.21),(driver_x,-4,1.17),24)
for ob in qaextra:bpy.data.objects.remove(ob,do_unlink=True)
original={o.name:o.matrix_world.copy() for o in objects}
p=Vector(pivots['DoorFL']);transform=Matrix.Translation(p)@Matrix.Rotation(math.radians(-64 if p.x>0 else 64),4,'Z')@Matrix.Translation(-p)
for o in objects:
 if o['group']=='DoorFL':o.matrix_world=transform@o.matrix_world
render('s2-door-open.png',((3.8 if p.x>0 else -3.8),-3.8,2.5),((.25 if p.x>0 else -.25),-.03,.72),46)
for o in objects:o.matrix_world=original[o.name]
# Actual edit topology: regular roof/window rings and source-faithful body.
gray=bpy.data.materials.new('QA neutral solid');gray.diffuse_color=(.3,.36,.43,1);gray.use_nodes=True;gray.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value=(.3,.36,.43,1)
wiremat=bpy.data.materials.new('QA wire');wiremat.diffuse_color=(.008,.012,.019,1);wiremat.use_nodes=True;wiremat.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value=(.008,.012,.019,1)
for o in objects:
 if 'Glass' in o.name:
  o.hide_render=True;continue
 o.data.materials.clear();o.data.materials.append(gray)
 for f in o.data.polygons:f.material_index=0
 o.data.materials.append(wiremat)
 mod=o.modifiers.new('QA actual edges','WIREFRAME');mod.thickness=.0008;mod.use_replace=False;mod.use_even_offset=False;mod.material_offset=1
render('s2-edit-wire.png',(-5.4,-6.4,3.1),(0,0,.7))
print('S2 reloaded, exported GLB/native and reviewed cockpit/door/wire',flush=True)
