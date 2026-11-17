"""Render the exact delivered native meshes, glazing and pivots without Studio."""
from pathlib import Path
import bpy,bmesh,json,struct,math,sys
from mathutils import Vector,Matrix
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'assets/vehicles/local';PREVIEW=ROOT/'dist/preview'
m=json.loads((OUT/'manifest.json').read_text(encoding='utf-8'))
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
materials={};objects=[];convert=Matrix(((1,0,0),(0,0,1),(0,1,0)))
def linear(x):return x/12.92 if x<=.04045 else ((x+.055)/1.055)**2.4
for part in m['Parts']:
 key=(tuple(part['Color']),part['Material'],part.get('Texture'),part['Transparency'])
 if key not in materials:
  mat=bpy.data.materials.new(part['Material']);mat.use_nodes=True;bs=mat.node_tree.nodes.get('Principled BSDF')
  color=tuple(linear(v/255) for v in part['Color'])+(1,);bs.inputs['Base Color'].default_value=color;bs.inputs['Roughness'].default_value=.38
  if part.get('Texture'):
   tex=mat.node_tree.nodes.new('ShaderNodeTexImage');tex.image=bpy.data.images.load(str(OUT/part['Texture']));mat.node_tree.links.new(tex.outputs['Color'],bs.inputs['Base Color']);bs.inputs['Metallic'].default_value=.45
  if part['Material']=='Glass':bs.inputs['Alpha'].default_value=1-part['Transparency'];mat.surface_render_method='DITHERED';bs.inputs['Roughness'].default_value=.15
  if part['Material']=='Screen':bs.inputs['Emission Color'].default_value=color;bs.inputs['Emission Strength'].default_value=.15
  if part['Material'] in ('Paint','CarPaint'):bs.inputs['Metallic'].default_value=.45;bs.inputs['Roughness'].default_value=.32
  materials[key]=mat
 data=(OUT/part['File']).read_bytes();base=len(b'version 2.00\n');_,stride,_,nv,nf=struct.unpack_from('<HBBII',data,base);base+=12
 values=[struct.unpack_from('<8f',data,base+i*stride) for i in range(nv)]
 pivot=Vector(m['Pivots'][part['Group']]);vertices=[convert@(Vector(row[:3])+pivot) for row in values]
 faces=[tuple(reversed(struct.unpack_from('<III',data,base+nv*stride+i*12))) for i in range(nf)]
 mesh=bpy.data.meshes.new(part['File']);mesh.from_pydata(vertices,[],faces);mesh.update();uv=mesh.uv_layers.new()
 for loop in mesh.loops:row=values[loop.vertex_index];uv.data[loop.index].uv=(row[6],1-row[7])
 for poly in mesh.polygons:poly.use_smooth=True
 if part['Material'] in ('Tripo','Debadged','CarPaint'):
  mesh.normals_split_custom_set_from_vertices([convert@Vector(row[3:6]) for row in values])
 if part['Material']=='Paint':
  bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.000005);bm.to_mesh(mesh);bm.free();mesh.update()
 obj=bpy.data.objects.new(part['File'],mesh);bpy.context.collection.objects.link(obj);mesh.materials.append(materials[key]);obj['group']=part['Group'];objects.append(obj)
floor=bpy.data.materials.new('Ground');floor.diffuse_color=(.07,.09,.11,1)
bpy.ops.mesh.primitive_plane_add(size=300,location=(0,0,-.015));bpy.context.object.data.materials.append(floor)
# A strip of roadway makes first-person visibility easier to assess.
road=bpy.data.materials.new('Road');road.diffuse_color=(.09,.10,.11,1)
bpy.ops.mesh.primitive_plane_add(size=1,location=(0,-25,-.008));o=bpy.context.object;o.scale=(7,60,1);o.data.materials.append(road)
line=bpy.data.materials.new('Road stripe');line.diffuse_color=(.8,.78,.65,1)
for y in range(-4,-60,-5):
 bpy.ops.mesh.primitive_cube_add(size=1,location=(-1.7,y,0));o=bpy.context.object;o.scale=(.06,2,.004);o.data.materials.append(line)
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=24;scene.cycles.use_denoising=True;scene.world.color=(.4,.4,.4)
for location,energy,size in [((1,-4,6),1200,6),((-4,1,4),950,5),((3,4,4),1200,5)]:
 bpy.ops.object.light_add(type='AREA',location=location);o=bpy.context.object;o.data.energy=energy;o.data.size=size;o.rotation_euler=(Vector((0,0,.5))-o.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.light_add(type='SUN',location=(0,0,10));bpy.context.object.data.energy=.8;bpy.context.object.rotation_euler=(.3,-.2,-.4)
bpy.ops.object.camera_add(location=(-5,-6,3));cam=bpy.context.object;scene.camera=cam
def render(name,location,target,lens=52):
 cam.location=location;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.lens=lens
 scene.render.resolution_x,scene.render.resolution_y=1300,850;scene.render.resolution_percentage=100
 scene.render.image_settings.file_format='PNG';scene.render.filepath=str(PREVIEW/name);bpy.ops.render.render(write_still=True)
render('bora-s1-exterior.png',(-5.1,-6.6,3.05),(0,-.05,.60))
if '--front-only' in sys.argv:
 print('Front preview complete.',flush=True)
 raise SystemExit(0)
render('bora-s1-rear.png',(5.1,6.6,2.9),(0,.15,.64))
render('bora-s1-cockpit.png',(-.43,.08,1.20),(-.43,-20,1.20),25)
pivot=convert@Vector(m['Pivots']['DoorFL']);rotation=Matrix.Rotation(math.radians(65),4,'Z')
for obj in objects:
 if obj['group']=='DoorFL':obj.matrix_world=Matrix.Translation(pivot)@rotation@Matrix.Translation(-pivot)@obj.matrix_world
render('bora-s1-door-open.png',(-4,-4,2.8),(-.20,0,.72))
print('Rendered delivered BORA S1 native assets:',m['TotalTriangles'],'triangles.',flush=True)
