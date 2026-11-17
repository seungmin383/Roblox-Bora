"""Render the actual staged Roblox parts; this is not a Studio screenshot."""
from pathlib import Path
import math,struct,json,sys,xml.etree.ElementTree as ET
import bpy
from mathutils import Vector,Matrix
ROOT=Path(__file__).resolve().parents[1]
plan=json.loads((ROOT/'dist/neighborhood-plan.json').read_text(encoding='utf-8'))
center=Vector(plan['Center']);S=.28
convert=Matrix(((1,0,0),(0,0,-1),(0,1,0)))
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
building_mode='--buildings' in sys.argv or '--building-cafe' in sys.argv
apartment_mode='--apartment' in sys.argv
if apartment_mode:center=Vector((0,0,0))
doc=ET.parse(ROOT/('dist/BuildingApartmentPreview.rbxmx' if apartment_mode else 'dist/BuildingPreview.rbxmx' if building_mode else 'dist/NeighborhoodPreview.rbxmx')).getroot()
if '--building-cafe' in sys.argv:
    root=doc.find('Item')
    for building in list(root.findall('Item')):
        if building.findtext("Properties/string[@name='Name']")!='SlowCoffee':root.remove(building)
parents={c:p for p in doc.iter() for c in p}
def name(item):return item.findtext("Properties/string[@name='Name']",'')
def vec(element):return Vector(tuple(float(element.findtext(k)) for k in 'XYZ'))
def frame(item):
    p=item.find('Properties');cf=p.find("CoordinateFrame[@name='CFrame']")
    return vec(cf),Matrix([[float(cf.findtext(f'R{i}{j}')) for j in range(3)] for i in range(3)])
def point(p):return convert@((p-center)*S)
materials={};groups={};mesh_cache={}
def material(color,alpha=1,texture=None,glass=False,emission=False):
    key=(color,round(alpha,3),texture,glass,emission)
    if key in materials:return materials[key]
    m=bpy.data.materials.new(str(key));m.use_nodes=True;bs=m.node_tree.nodes.get('Principled BSDF')
    rgb=tuple(((color>>s)&255)/255 for s in (16,8,0))
    bs.inputs['Base Color'].default_value=(*rgb,1);bs.inputs['Roughness'].default_value=.7
    if glass:
        bs.inputs['Transmission Weight'].default_value=.7;bs.inputs['Roughness'].default_value=.16
        bs.inputs['Base Color'].default_value=(.70,.82,.83,1);bs.inputs['IOR'].default_value=1.45
    elif alpha<1:bs.inputs['Alpha'].default_value=alpha
    if emission:bs.inputs['Emission Color'].default_value=(*rgb,1);bs.inputs['Emission Strength'].default_value=1.5
    if texture:
        tex=m.node_tree.nodes.new('ShaderNodeTexImage');tex.image=bpy.data.images.load(str(ROOT/'assets/traffic/local'/texture))
        m.node_tree.links.new(tex.outputs['Color'],bs.inputs['Base Color'])
    materials[key]=m;return m
def add_geometry(key,verts,faces,uv=None):
    if key not in groups:groups[key]=[[],[],[]]
    vv,ff,uu=groups[key];offset=len(vv);vv.extend(verts);ff.extend(tuple(i+offset for i in f) for f in faces)
    uu.extend(uv if uv else [(0,0)]*len(verts))
def asset(filename):
    if filename in mesh_cache:return mesh_cache[filename]
    folder=ROOT/('assets/buildings/local' if filename.startswith('WallSconce_') else 'assets/traffic/local')
    raw=(folder/filename).read_bytes();base=len(b'version 2.00\n')
    _,stride,_,nv,nf=struct.unpack_from('<HBBII',raw,base);base+=12
    rows=[struct.unpack_from('<8f',raw,base+i*stride) for i in range(nv)];base+=nv*stride
    result=([Vector(v[:3]) for v in rows],[struct.unpack_from('<III',raw,base+i*12) for i in range(nf)],[(v[6],1-v[7]) for v in rows])
    mesh_cache[filename]=result;return result
font=bpy.data.fonts.load('C:/Windows/Fonts/malgun.ttf')
for item in doc.iter('Item'):
    kind=item.get('class')
    if kind not in ('Part','WedgePart'):continue
    p=item.find('Properties');alpha=1-float(p.findtext("float[@name='Transparency']",'0'))
    if alpha<=0:continue
    pos,rot=frame(item);size=vec(p.find("Vector3[@name='size']"))
    color=int(p.findtext("Color3uint8[@name='Color3uint8']",'16777215'))&0xffffff
    token=p.findtext("token[@name='Material']",'256')
    glass=token=='1568';emission=token=='288'
    special=item.find("Item[@class='SpecialMesh']")
    url=special.findtext("Properties/Content[@name='MeshContent']/uri",'') if special is not None else ''
    if url:
        filename=url.rsplit('/',1)[-1];verts,faces,uv=asset(filename)
        scale=vec(special.find("Properties/Vector3[@name='Scale']"))
        texture=special.findtext("Properties/Content[@name='TextureContent']/uri",'').rsplit('/',1)[-1] or None
        key=(color,alpha,texture,False,False)
        add_geometry(key,[point(pos+rot@Vector(tuple(v[i]*scale[i] for i in range(3)))) for v in verts],faces,uv)
    else:
        sphere=p.findtext("token[@name='shape']",p.findtext("token[@name='Shape']",''))=='0' or special is not None
        if sphere:
            verts=[];faces=[]
            for j in range(7):
                lat=-math.pi/2+j*math.pi/6
                for i in range(12):
                    theta=i*2*math.pi/12;verts.append(Vector((math.cos(lat)*math.cos(theta)*.5,math.cos(lat)*math.sin(theta)*.5,math.sin(lat)*.5)))
            for j in range(6):
                for i in range(12):faces.append((j*12+i,j*12+(i+1)%12,(j+1)*12+(i+1)%12,(j+1)*12+i))
        elif kind=='WedgePart':
            verts=[Vector(v) for v in [(-.5,-.5,-.5),(.5,-.5,-.5),(-.5,-.5,.5),(.5,-.5,.5),(-.5,.5,.5),(.5,.5,.5)]]
            faces=[(0,1,3,2),(2,3,5,4),(0,4,5,1),(0,2,4),(1,5,3)]
        else:
            verts=[Vector((x,y,z)) for x in (-.5,.5) for y in (-.5,.5) for z in (-.5,.5)]
            faces=[(0,1,3,2),(4,6,7,5),(0,4,5,1),(2,3,7,6),(0,2,6,4),(1,5,7,3)]
        add_geometry((color,alpha,None,glass,emission),[point(pos+rot@Vector(tuple(v[i]*size[i] for i in range(3)))) for v in verts],faces)
    gui=item.find("Item[@class='SurfaceGui']")
    if gui is not None:
        text=gui.findtext("Item[@class='TextLabel']/Properties/string[@name='Text']",'')
        if text:
            curve=bpy.data.curves.new('SignLettering','FONT');curve.body=text;curve.font=font;curve.align_x='CENTER';curve.align_y='CENTER';curve.size=.55
            obj=bpy.data.objects.new(text,curve);bpy.context.collection.objects.link(obj)
            obj.matrix_world=(convert@rot).to_4x4()@Matrix.Rotation(math.pi,4,'Y')
            obj.location=point(pos+rot@Vector((0,0,-size.z*.5-.006/S)))
            curve.materials.append(material(0xf5f1de))
            bpy.context.view_layer.update()
            maxwidth=size.x*S*.88
            local_width=max(c[0] for c in obj.bound_box)-min(c[0] for c in obj.bound_box)
            local_height=max(c[1] for c in obj.bound_box)-min(c[1] for c in obj.bound_box)
            if local_width>0:
                factor=min(maxwidth/max(local_width,.001),size.y*S*.72/max(local_height,.001))
                obj.scale*=factor
for key,(verts,faces,uvs) in groups.items():
    mesh=bpy.data.meshes.new('RobloxParts');mesh.from_pydata(verts,[],faces);mesh.update()
    obj=bpy.data.objects.new('Actual Roblox geometry',mesh);bpy.context.collection.objects.link(obj);mesh.materials.append(material(*key))
    layer=mesh.uv_layers.new()
    for loop in mesh.loops:layer.data[loop.index].uv=uvs[loop.vertex_index]
bpy.ops.mesh.primitive_plane_add(size=1400,location=(0,0,-.07));bpy.context.object.data.materials.append(material(0x6d7c5d))
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=24;scene.cycles.use_denoising=True
scene.world.use_nodes=True;scene.world.node_tree.nodes.get('Background').inputs[0].default_value=(.66,.75,.82,1)
scene.world.node_tree.nodes.get('Background').inputs[1].default_value=.6
bpy.ops.object.light_add(type='SUN',location=(0,0,60));bpy.context.object.rotation_euler=(.45,-.4,-.6);bpy.context.object.data.energy=2.4;bpy.context.object.data.angle=.15
scene.view_settings.view_transform='AgX'
bpy.ops.object.camera_add();cam=bpy.context.object;scene.camera=cam
scene.render.resolution_x=1600;scene.render.resolution_y=1100;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG';out=ROOT/'dist/preview';out.mkdir(exist_ok=True)
views=[
    ('neighborhood-overview.png',(52,-67,53),(0,0,2.8),108),
    ('neighborhood-street.png',(-17,-23,1.7),(7,11,3.0),None),
    ('neighborhood-cafe.png',(20,25,15),(6,16,2.5),47),
]
if building_mode:views=[('building-editor-block.png',(52,-67,53),(0,0,3),108),('building-editor-cafe.png',(-15,9,10),(4.5,21.5,3.2),25)]
if '--building-cafe' in sys.argv:views=[views[-1]]
if apartment_mode:views=[('building-editor-apartment.png',(39,52,36),(0,0,18),75)]
for filename,position,target,ortho in views:
    cam.location=Vector(position);cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler()
    cam.data.type='ORTHO' if ortho else 'PERSP'
    if ortho:cam.data.ortho_scale=ortho
    else:cam.data.lens=24
    scene.render.filepath=str(out/filename);bpy.ops.render.render(write_still=True)
print('Rendered staged native scene; no Studio or Place serialization.')
