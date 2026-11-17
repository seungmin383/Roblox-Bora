"""Build a watertight mature ginkgo skeleton and crown attachment points in Blender.

The fork surfaces are voxel-unioned before decimation. The entire wood surface
uses one transform at runtime, so its forks cannot separate while growing.
"""
from pathlib import Path
import json
import math
import random
import struct
import bpy
import bmesh
from mathutils import Vector, Matrix

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/tree/local'
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
rng = random.Random(42)
pieces, anchors = [], []


def tube(name, points, radii, sides=12):
    points = [Vector(p) for p in points]
    verts, faces = [], []
    for i, (p, radius) in enumerate(zip(points, radii)):
        tangent = (points[min(i + 1, len(points)-1)] - points[max(0, i-1)]).normalized()
        normal = tangent.cross(Vector((0, 1, 0))).normalized()
        bitangent = tangent.cross(normal).normalized()
        for j in range(sides):
            angle = j * math.tau / sides
            # Broad, restrained bark undulation; fine ridges come from the bake.
            r = radius * (1 + .035 * math.sin(j*2.7 + i*.65))
            verts.append(p + r * (math.cos(angle)*normal + math.sin(angle)*bitangent))
    for i in range(len(points)-1):
        for j in range(sides):
            a = i*sides+j
            b = i*sides+(j+1)%sides
            faces.append((a,b,b+sides,a+sides))
    faces.append(tuple(reversed(range(sides))))
    faces.append(tuple((len(points)-1)*sides+j for j in range(sides)))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    pieces.append(obj)
    return points


trunk = [(0,0,0),(.02,0,.3),(.03,.04,1.0),(-.08,.09,3),
         (-.18,.08,5.3),(-.12,.02,7.6),(.12,.09,9.8),(.30,.15,12),
         (.22,.12,14.3),(.4,.06,16.2),(.35,.04,18)]
tube('Leader', trunk, [1.5,1.28,1.05,.91,.76,.63,.48,.36,.25,.14,.055], 20)
for i in range(6):
    angle = i*math.tau/6+.18
    tube('Root', [(0,0,.68),(math.cos(angle)*.95,math.sin(angle)*.95,.3),
                  (math.cos(angle)*1.72,math.sin(angle)*1.72,.04)], [.52,.35,.045])

def center(z):
    for a,b in zip(trunk,trunk[1:]):
        if a[2] <= z <= b[2]:
            return Vector(a).lerp(Vector(b),(z-a[2])/(b[2]-a[2]))
    return Vector(trunk[-1])

for i in range(9):
    angle = i*2.399963+.35
    z = 5.7+i*.98
    reach = [5.2,5.7,5.4,5.5,5.1,4.8,4.2,3.6,2.8][i]
    direction = Vector((math.cos(angle),math.sin(angle),0))
    side = Vector((-math.sin(angle),math.cos(angle),0))
    a = center(z)
    points = [a, a+direction*.65+Vector((0,0,.38)),
              a+direction*(reach*.35)+side*.12+Vector((0,0,1.1)),
              a+direction*(reach*.7)+side*.33+Vector((0,0,2.05)),
              a+direction*reach+side*.48+Vector((0,0,3.05))]
    radius = .49-i*.027
    tube('Scaffold', points, [radius,radius*.90,radius*.63,radius*.32,.055])
    anchors.append(tuple(points[-1]+Vector((0,0,.2))))
    for j in range(2):
        t = .48+j*.25
        start = points[2].lerp(points[3], (t-.35)/.35) if t <= .7 else points[3].lerp(points[4],(t-.7)/.3)
        theta = angle + (-.68 if j == 0 else .7)
        offset = Vector((math.cos(theta),math.sin(theta),0))*(1.6+(8-i)*.10)
        end = start+offset+Vector((0,0,1.6+j*.15))
        tube('Secondary', [start,start+offset*.35+Vector((0,0,.65)),end],
             [radius*.40,radius*.28,.035],10)
        anchors.append(tuple(end+Vector((0,0,.18))))
anchors.append((.35,.04,17.5))

for obj in pieces: obj.select_set(True)
bpy.context.view_layer.objects.active = pieces[0]
bpy.ops.object.join()
wood = bpy.context.object
wood.name = 'GinkgoConnectedWood'
remesh = wood.modifiers.new('Continuous fork surfaces','REMESH')
remesh.mode, remesh.voxel_size, remesh.use_smooth_shade = 'VOXEL', .052, True
bpy.ops.object.modifier_apply(modifier=remesh.name)
smooth = wood.modifiers.new('Round branch collars','SMOOTH')
smooth.factor, smooth.iterations = .72, 5
bpy.ops.object.modifier_apply(modifier=smooth.name)
# Tiny tips narrower than a voxel can leave detached specks. Keep the joined
# tree only, and fail if the discarded material includes a substantial limb.
bm = bmesh.new(); bm.from_mesh(wood.data)
remaining = set(bm.verts); islands = []
while remaining:
    island = {remaining.pop()}; stack = list(island)
    while stack:
        vertex = stack.pop()
        for edge in vertex.link_edges:
            other = edge.other_vert(vertex)
            if other in remaining:
                remaining.remove(other); island.add(other); stack.append(other)
    islands.append(island)
islands.sort(key=len,reverse=True)
print('Voxel components:', [len(island) for island in islands])
assert sum(map(len,islands[1:])) < len(islands[0])*.01, 'A substantial branch failed to join'
if len(islands)>1:
    bmesh.ops.delete(bm,geom=list(set.union(*islands[1:])),context='VERTS')
bm.to_mesh(wood.data); bm.free()
decimate = wood.modifiers.new('Game topology','DECIMATE')
decimate.ratio = min(1, 7800/max(1, len(wood.data.polygons)*2))
bpy.ops.object.modifier_apply(modifier=decimate.name)
for polygon in wood.data.polygons: polygon.use_smooth = True

# Validate the actual exported surface, rather than assuming that overlap joins it.
bm = bmesh.new(); bm.from_mesh(wood.data)
remaining = set(bm.verts); components = 0
while remaining:
    components += 1; stack = [remaining.pop()]
    while stack:
        vertex = stack.pop()
        for edge in vertex.link_edges:
            other = edge.other_vert(vertex)
            if other in remaining: remaining.remove(other); stack.append(other)
assert components == 1, f'Disconnected wood: {components}'
assert all(e.is_manifold for e in bm.edges), 'Open/non-manifold fork surface'
bm.free()

# Neutral grey-brown longitudinal bark, baked into one atlas for Studio/FBX.
mat = bpy.data.materials.new('Ginkgo bark'); mat.use_nodes = True
nodes, links = mat.node_tree.nodes, mat.node_tree.links
shader = nodes.get('Principled BSDF'); shader.inputs['Roughness'].default_value = .92
texcoord = nodes.new('ShaderNodeTexCoord')
mapping = nodes.new('ShaderNodeVectorMath'); mapping.operation = 'MULTIPLY'
mapping.inputs[1].default_value = (6,6,.55)
links.new(texcoord.outputs['Object'],mapping.inputs[0])
noise = nodes.new('ShaderNodeTexNoise'); noise.inputs['Scale'].default_value = 3
noise.inputs['Detail'].default_value = 3.5; noise.inputs['Roughness'].default_value = .72
links.new(mapping.outputs['Vector'],noise.inputs['Vector'])
ramp = nodes.new('ShaderNodeValToRGB')
ramp.color_ramp.elements[0].position = .22
ramp.color_ramp.elements[0].color = (.075,.063,.048,1)
ramp.color_ramp.elements[1].position = .76
ramp.color_ramp.elements[1].color = (.31,.26,.20,1)
links.new(noise.outputs['Fac'],ramp.inputs[0]); links.new(ramp.outputs[0],shader.inputs['Base Color'])
wood.data.materials.clear(); wood.data.materials.append(mat)
bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.uv.smart_project(angle_limit=1.1,island_margin=.015)
bpy.ops.object.mode_set(mode='OBJECT')
image = bpy.data.images.new('ConnectedBark',1024,1024,alpha=False)
target = nodes.new('ShaderNodeTexImage'); target.image=image; nodes.active=target
scene = bpy.context.scene; scene.render.engine='CYCLES'; scene.cycles.samples=1
scene.render.bake.use_pass_direct=False; scene.render.bake.use_pass_indirect=False
scene.render.bake.use_pass_color=True; scene.render.bake.margin=8
bpy.ops.object.bake(type='DIFFUSE')
image.filepath_raw=str(OUT/'ConnectedBark.png'); image.file_format='PNG'; image.save()
links.new(target.outputs['Color'],shader.inputs['Base Color'])

# Ground plane remains z=0 after centering, even though remeshing shifts bounds.
mins = Vector(tuple(min(v.co[k] for v in wood.data.vertices) for k in range(3)))
maxs = Vector(tuple(max(v.co[k] for v in wood.data.vertices) for k in range(3)))
height=maxs.z-mins.z
origin=Vector(((mins.x+maxs.x)/2,(mins.y+maxs.y)/2,mins.z))
# The native mesh is centered at its bounds; attachments use the same correction.
offset = Vector((origin.x, origin.y, mins.z+height/2))
for v in wood.data.vertices: v.co=(v.co-offset)/height
wood.data.update()
mesh=wood.data; mesh.calc_loop_triangles()
conversion=Matrix(((1,0,0),(0,0,1),(0,-1,0)))
rows, faces, indices=[], [], {}
for triangle in mesh.loop_triangles:
    face=[]
    for lid in triangle.loops:
        loop=mesh.loops[lid]; point=conversion@mesh.vertices[loop.vertex_index].co
        normal=conversion@mesh.corner_normals[lid].vector; uv=mesh.uv_layers.active.data[lid].uv
        row=struct.pack('<8f4b4B',*point,*normal,uv.x,1-uv.y,0,0,0,127,255,255,255,255)
        if row not in indices: indices[row]=len(rows); rows.append(row)
        face.append(indices[row])
    faces.append(face)
with (OUT/'ConnectedWood.mesh').open('wb') as f:
    f.write(b'version 2.00\n'); f.write(struct.pack('<HBBII',12,40,12,len(rows),len(faces)))
    for row in rows: f.write(row)
    for face in faces: f.write(struct.pack('<III',*face))
coords=[conversion@v.co for v in mesh.vertices]
bounds=[max(v[k] for v in coords)-min(v[k] for v in coords) for k in range(3)]
manifest=json.loads((OUT/'manifest.json').read_text())
manifest['qualityVersion']=3
manifest['source']='Blender connected skeleton; legacy Tripo parts retained as sources'
manifest['parts']['Wood']={'vertices':len(rows),'triangles':len(faces),'bounds':bounds,
                         'mesh':'ConnectedWood.mesh','texture':'ConnectedBark.png',
                         'connectedComponents':components,'manifold':True,'source':'Blender procedural surface union'}
# Coordinates normalized by the actual mesh height, measured from its ground pivot.
manifest['crownAnchors']=[[(p[0]-origin.x)/height,(p[2]-mins.z)/height,-(p[1]-origin.y)/height] for p in anchors]
manifest['woodHeight']=height
(OUT/'manifest.json').write_text(json.dumps(manifest,indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'ConnectedWood.blend'))
bpy.ops.export_scene.fbx(filepath=str(OUT/'ConnectedWood.fbx'),use_selection=True,
                        object_types={'MESH'},add_leaf_bones=False,axis_forward='-Z',axis_up='Y',
                        path_mode='COPY',embed_textures=True)
print('QUALITY WOOD:',json.dumps(manifest['parts']['Wood']), 'anchors',len(anchors))
