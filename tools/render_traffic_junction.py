"""Render exported tool geometry, not a Studio screenshot or another Place."""
from pathlib import Path
import xml.etree.ElementTree as ET
import struct,math,sys
import bpy
from mathutils import Matrix,Vector
ROOT=Path(__file__).resolve().parents[1]
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
PEDESTRIAN='--pedestrians' in sys.argv
LANES='--lanes' in sys.argv
WALK='--walk' in sys.argv
PROTECTED='--protected' in sys.argv
doc=ET.parse(ROOT/'dist'/('ProtectedSignalJunction.rbxmx' if PROTECTED else 'LaneDirectionsJunction.rbxmx' if LANES else 'PedestrianJunction.rbxmx' if PEDESTRIAN else 'TrafficJunction.rbxmx')).getroot()
parents={child:parent for parent in doc.iter() for child in parent}
convert=Matrix(((1,0,0),(0,0,-1),(0,1,0)))
materials={};groups={}
def mat(color,texture=False,emission=False):
 key=(color,texture,emission)
 if key in materials:return materials[key]
 material=bpy.data.materials.new(str(key));material.use_nodes=True;bs=material.node_tree.nodes.get('Principled BSDF')
 rgb=tuple(((color>>s)&255)/255 for s in [16,8,0])+(1,)
 bs.inputs['Base Color'].default_value=rgb;bs.inputs['Roughness'].default_value=.8
 if texture:
  tex=material.node_tree.nodes.new('ShaderNodeTexImage');tex.image=bpy.data.images.load(str(ROOT/'assets/traffic/local'/texture))
  material.node_tree.links.new(tex.outputs['Color'],bs.inputs['Base Color'])
 if emission:bs.inputs['Emission Color'].default_value=rgb;bs.inputs['Emission Strength'].default_value=2
 materials[key]=material;return material
def vec(p):return Vector(tuple(float(p.findtext(k)) for k in 'XYZ'))
assets={}
def load_asset(filename):
 if filename in assets:return assets[filename]
 binary=(ROOT/'assets/traffic/local'/filename).read_bytes();base=len(b'version 2.00\n')
 _,stride,_,nv,nf=struct.unpack_from('<HBBII',binary,base);base+=12
 vertices=[];uvs=[]
 for i in range(nv):
  row=struct.unpack_from('<8f',binary,base+i*stride);vertices.append(Vector(row[:3]));uvs.append((row[6],1-row[7]))
 base+=nv*stride;faces=[struct.unpack_from('<III',binary,base+i*12) for i in range(nf)]
 assets[filename]=(vertices,uvs,faces);return assets[filename]
pedestrian_camera=None
vehicle_camera=None
def make(name,verts,faces,material,uv=None,smooth=False):
 mesh=bpy.data.meshes.new(name);mesh.from_pydata(verts,[],faces);mesh.update()
 if uv:
  layer=mesh.uv_layers.new()
  for loop in mesh.loops:layer.data[loop.index].uv=uv[loop.vertex_index]
 obj=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(obj);mesh.materials.append(material)
 for face in mesh.polygons:face.use_smooth=smooth
 return obj
for item in doc.iter('Item'):
 kind=item.get('class')
 if kind not in ('Part','WedgePart'):continue
 props=item.find('Properties');name=props.findtext("string[@name='Name']")
 transparency=float(props.findtext("float[@name='Transparency']",'0'))
 if WALK:
  ancestor=parents.get(item)
  while ancestor is not None:
   group_name=ancestor.findtext("Properties/string[@name='Name']")
   if group_name=='WalkIcon':transparency=0;break
   if group_name=='StopIcon':transparency=1;break
   ancestor=parents.get(ancestor)
 if transparency>=1:continue
 size=vec(props.find("Vector3[@name='size']"));cf=props.find("CoordinateFrame[@name='CFrame']");pos=vec(cf)
 rot=Matrix(tuple(tuple(float(cf.findtext(f'R{i}{j}')) for j in range(3)) for i in range(3)))
 transform=lambda p:convert@(pos+rot@p)
 color=int(props.findtext("Color3uint8[@name='Color3uint8']",'16777215'));special=item.find("Item[@class='SpecialMesh']")
 if special is not None and special.find("Properties/Content[@name='MeshContent']") is not None:
  filename=special.findtext("Properties/Content[@name='MeshContent']/uri").rsplit('/',1)[-1]
  meshVertices,uvs,meshFaces=load_asset(filename)
  texture=special.findtext("Properties/Content[@name='TextureContent']/uri").rsplit('/',1)[-1]
  scale=vec(special.find("Properties/Vector3[@name='Scale']"))
  make(name,[transform(Vector(tuple(v[i]*scale[i] for i in range(3)))) for v in meshVertices],meshFaces,mat(color,texture),uvs,True)
  if name=='TripoPedestrianHead' and pedestrian_camera is None:
   pedestrian_camera=(convert@pos,convert@(rot@Vector((0,0,-1))),convert@(rot@Vector((1,0,0))))
  if name=='TripoHead' and parents[item].find("Item/Properties/string[@name='Name'][.='Left']") is not None:
   vehicle_camera=(convert@pos,convert@(rot@Vector((0,0,-1))),convert@(rot@Vector((1,0,0))))
 elif special is not None:
  bpy.ops.mesh.primitive_uv_sphere_add(segments=20,ring_count=10,location=convert@pos)
  obj=bpy.context.object;obj.name=name;obj.scale=tuple(size[i]*.5 for i in range(3));obj.rotation_euler=(convert@rot).to_euler();obj.data.materials.append(mat(color,emission=props.findtext("token[@name='Material']")=='288'))
 else:
  # WedgePart cross section slopes from the -Z bottom to the +Z top.
  if kind=='WedgePart':
   coords=[(-.5,-.5,-.5),(.5,-.5,-.5),(-.5,-.5,.5),(.5,-.5,.5),(-.5,.5,.5),(.5,.5,.5)]
   faces=[(0,1,3,2),(2,3,5,4),(0,4,5,1),(0,2,4),(1,5,3)]
  else:
   coords=[(x,y,z) for x in [-.5,.5] for y in [-.5,.5] for z in [-.5,.5]]
   faces=[(0,1,3,2),(4,6,7,5),(0,4,5,1),(2,3,7,6),(0,2,6,4),(1,5,7,3)]
  verts=[transform(Vector(tuple(p[i]*size[i] for i in range(3)))) for p in coords]
  key=(color,props.findtext("token[@name='Material']")=='288')
  if key not in groups:groups[key]=([],[])
  vv,ff=groups[key];offset=len(vv);vv.extend(verts);ff.extend(tuple(i+offset for i in f) for f in faces)
for (color,emission),(verts,faces) in groups.items():make('Road geometry',verts,faces,mat(color,emission=emission))
bpy.ops.mesh.primitive_plane_add(size=1200,location=(0,0,-.7));bpy.context.object.data.materials.append(mat(0x34523a))
scene=bpy.context.scene;scene.world.color=(.3,.3,.3);scene.render.engine='CYCLES';scene.cycles.samples=16;scene.cycles.use_denoising=True
bpy.ops.object.light_add(type='SUN',location=(0,0,150));bpy.context.object.rotation_euler=(.3,-.4,-.5);bpy.context.object.data.energy=2
bpy.ops.object.light_add(type='AREA',location=(0,-80,130));bpy.context.object.data.energy=12000;bpy.context.object.data.size=100
bpy.ops.object.camera_add(location=(115,-165,190) if LANES else (115,-165,160));cam=bpy.context.object;cam.rotation_euler=(Vector((0,0,4) if LANES else (0,-30,4))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=220 if LANES else 160;scene.camera=cam
scene.render.resolution_x=1200;scene.render.resolution_y=900;scene.render.resolution_percentage=100;scene.render.image_settings.file_format='PNG';scene.render.filepath=str(ROOT/'dist/preview'/('protected-signal-junction.png' if PROTECTED else 'lane-directions-junction.png' if LANES else 'pedestrian-junction.png' if PEDESTRIAN else 'traffic-junction.png'))
bpy.ops.render.render(write_still=True)
if PROTECTED and vehicle_camera:
 position,normal,right=vehicle_camera
 target=position-right*1.0
 cam.location=target+normal*16+Vector((0,0,.5))
 cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=11.5
 scene.render.resolution_x=1100;scene.render.resolution_y=600;scene.render.filepath=str(ROOT/'dist/preview/protected-left-signal-detail.png')
 bpy.ops.render.render(write_still=True)
if pedestrian_camera and not LANES and not PROTECTED:
 position,normal,right=pedestrian_camera
 cam.location=position+normal*7+Vector((0,0,1.2))+right*.8
 cam.rotation_euler=(position-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=4.2
 scene.render.resolution_x=700;scene.render.resolution_y=900;scene.render.filepath=str(ROOT/'dist/preview'/('pedestrian-walk-detail.png' if WALK else 'pedestrian-stop-detail.png'))
 bpy.ops.render.render(write_still=True)
print('Rendered exported junction/roads/Tripo heads without Studio')
