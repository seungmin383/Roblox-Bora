"""Render the real generated floor-plan model as an architectural cutaway."""
from pathlib import Path
import json,math,xml.etree.ElementTree as ET
import bpy,bmesh
from mathutils import Vector,Matrix
ROOT=Path(__file__).resolve().parents[1]
doc=ET.parse(ROOT/'dist/BuildingFloorPlanPreview.rbxmx').getroot()
example=json.loads((ROOT/'dist/building-floorplan-example.json').read_text(encoding='utf-8'))
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
convert=Matrix(((1,0,0),(0,0,-1),(0,1,0)))
materials={}
def material(color):
    if color in materials:return materials[color]
    m=bpy.data.materials.new(f'{color:06x}');m.diffuse_color=(*tuple(((color>>s)&255)/255 for s in (16,8,0)),1)
    m.use_nodes=True;bs=m.node_tree.nodes['Principled BSDF'];bs.inputs['Base Color'].default_value=m.diffuse_color;bs.inputs['Roughness'].default_value=.7
    materials[color]=m;return m
for item in doc.iter('Item'):
    if item.get('class')!='Part':continue
    p=item.find('Properties');name=p.findtext("string[@name='Name']",'')
    if float(p.findtext("float[@name='Transparency']",'0'))>=1:continue
    cf=p.find("CoordinateFrame[@name='CFrame']");size=p.find("Vector3[@name='size']")
    pos=Vector([float(cf.findtext(k))*.28 for k in 'XYZ']);dims=Vector([float(size.findtext(k))*.28 for k in 'XYZ'])
    rot=Matrix([[float(cf.findtext(f'R{i}{j}')) for j in range(3)] for i in range(3)])
    # Section plane at 1.55 m exposes the first floor's actual wall positions.
    yextent=sum(abs(rot[1][i])*dims[i]*.5 for i in range(3))
    if pos.y-yextent>=1.55:continue
    verts=[convert@(pos+rot@Vector((x*dims.x,y*dims.y,z*dims.z))) for x in (-.5,.5) for y in (-.5,.5) for z in (-.5,.5)]
    faces=[(0,1,3,2),(4,6,7,5),(0,4,5,1),(2,3,7,6),(0,2,6,4),(1,5,7,3)]
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(verts,[],faces);mesh.update()
    bm=bmesh.new();bm.from_mesh(mesh)
    bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),plane_co=(0,0,1.55),plane_no=(0,0,1),clear_outer=True,clear_inner=False,dist=.00001)
    boundary=[e for e in bm.edges if e.is_boundary]
    if boundary:bmesh.ops.holes_fill(bm,edges=boundary,sides=0)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(mesh);bm.free()
    obj=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(obj)
    color=int(p.findtext("Color3uint8[@name='Color3uint8']",'16777215'))&0xffffff
    # Use authored native colours; the section itself has no invented textures.
    mesh.materials.append(material(color))
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=32;scene.cycles.use_denoising=True
scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.65,.72,.78,1);scene.world.node_tree.nodes['Background'].inputs[1].default_value=.6
bpy.ops.object.light_add(type='AREA',location=(0,-2,14));bpy.context.object.data.energy=1800;bpy.context.object.data.size=9
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.21));bpy.context.object.data.materials.append(material(0x536164))
bpy.ops.object.camera_add(location=(14,19,22));cam=bpy.context.object;scene.camera=cam;target=Vector((0,0,.25))
cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=24
scene.view_settings.view_transform='AgX';scene.render.resolution_x=1400;scene.render.resolution_y=1050;scene.render.resolution_percentage=100
scene.render.filepath=str(ROOT/'dist/preview/building-floorplan-cutaway.png');bpy.ops.render.render(write_still=True)
# Matching plan diagram, with metre coordinates from the exact same JSON recipe.
from xml.sax.saxutils import escape
w,d=example['Config']['Width'],example['Config']['Depth'];scale=42;pad=70;W=w*scale+pad*2;H=d*scale+pad*2
def point(x,z):return pad+(x+w*.5)*scale,pad+(d*.5-z)*scale
svg=[f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">',f'<rect width="{W}" height="{H}" fill="#202831"/>',f'<rect x="{pad}" y="{pad}" width="{w*scale}" height="{d*scale}" fill="#3e4b55" stroke="#b1bfc5" stroke-width="8"/>']
for i in range(int(w)+1):
    x=pad+i*scale;svg.append(f'<path d="M{x},{pad}v{d*scale}" stroke="#52616c"/>')
for i in range(int(d)+1):
    y=pad+i*scale;svg.append(f'<path d="M{pad},{y}h{w*scale}" stroke="#52616c"/>')
for e in example['Plan']['Items']:
    if e.get('Floor',1)!=1:continue
    if e['Kind']=='Wall':
        a,b=point(e['X'],e['Z']),point(e['X2'],e['Z2']);svg.append(f'<path d="M{a[0]},{a[1]}L{b[0]},{b[1]}" stroke="#e1e5dc" stroke-width="{e["Thickness"]*scale}"/>')
    else:
        ww,dd=(3,4.8) if e['Kind']=='Stairs' else (2.8,2.8) if e['Kind']=='Elevator' else (e['Width'],e['Depth'])
        x,y=point(e['X']-ww*.5,e['Z']+dd*.5);color='#dbad54' if e['Kind']=='Stairs' else '#5bb0d1' if e['Kind']=='Elevator' else '#c7cfc4'
        svg.append(f'<rect x="{x}" y="{y}" width="{ww*scale}" height="{dd*scale}" fill="{color}"/>')
        if e['Kind']!='Block':
            title='계단 ↑ 2층' if e['Kind']=='Stairs' else '엘리베이터'
            svg.append(f'<text x="{x+ww*scale*.5}" y="{y+dd*scale*.5}" text-anchor="middle" font-family="Malgun Gothic" font-size="17" fill="#19262a">{escape(title)}</text>')
svg.append(f'<text x="{W*.5}" y="32" text-anchor="middle" font-family="Malgun Gothic" font-size="22" fill="#e5ebee">1층 도면 · 16 × 12 m</text>')
svg.append(f'<text x="{W*.5}" y="{H-24}" text-anchor="middle" font-family="Malgun Gothic" font-size="17" fill="#e5ebee">출입구 쪽 · 실제 생성 모델과 같은 위치</text></svg>')
(ROOT/'dist/preview/building-floorplan.svg').write_text(''.join(svg),encoding='utf-8')
print('Rendered actual first-floor section and matching metre plan; no Place write or Studio activation.')
