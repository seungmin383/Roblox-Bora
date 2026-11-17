"""Measured rebuild of the generated lamp: flat plate, turned ribs, real glass.

The generated silhouette is the reference. Broken opaque glass is intentionally
replaced by a closed transparent shell; source baked shadows are not transferred.
"""
from pathlib import Path
from collections import defaultdict
import bpy,bmesh,math,json,struct,hashlib
import numpy as np
from mathutils import Vector,Matrix
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'assets/buildings';LOCAL=OUT/'local';LOCAL.mkdir(parents=True,exist_ok=True)
SRC=OUT/'source/WallSconce_Tripo.glb';source_hash=hashlib.sha256(SRC.read_bytes()).hexdigest()
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(SRC))
source=next(o for o in bpy.context.scene.objects if o.type=='MESH');source.data.calc_loop_triangles();source_triangles=len(source.data.loop_triangles)
coords=np.empty(len(source.data.vertices)*3,dtype=np.float32);source.data.vertices.foreach_get('co',coords);coords=coords.reshape(-1,3)
mat=np.array(source.matrix_world);coords=coords@mat[:3,:3].T+mat[:3,3]
lo,hi=coords.min(axis=0),coords.max(axis=0);height=float(hi[2]-lo[2]);factor=.4/height
# Densely sampled source cross-sections provide axial widths and front depth.
sections=[]
for z in np.arange(.05,.951,.05):
    points=coords[np.abs((coords[:,2]-lo[2])/height-z)<.008]
    sections.append({'heightRatio':float(z),'xRange':np.quantile(points[:,0],[.01,.99]).tolist(),
                     'yRange':np.quantile(points[:,1],[.01,.99]).tolist()})
measurement={'sourceSha256':source_hash,'sourceTriangles':source_triangles,'sourceBounds':[lo.tolist(),hi.tolist()],
             'metresPerSourceUnit':factor,'sections':sections,'mountBackY':float(hi[1]),'mountHeightZ':float((lo[2]+hi[2])*.5)}
(OUT/'measurements.json').write_text(json.dumps(measurement,indent=2))
source.name='Tripo source reference';source.hide_render=True;source.hide_set(True)
collection=bpy.data.collections.new('Clean architecture decoration');bpy.context.scene.collection.children.link(collection)
metal=bpy.data.materials.new('Satin charcoal metal');metal.diffuse_color=(.045,.055,.059,1);metal.use_nodes=True
metal.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(.035,.045,.049,1)
metal.node_tree.nodes['Principled BSDF'].inputs['Metallic'].default_value=.7;metal.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value=.36
glass=bpy.data.materials.new('Clear manufactured glass');glass.diffuse_color=(.7,.8,.8,.2);glass.use_nodes=True
bs=glass.node_tree.nodes['Principled BSDF'];bs.inputs['Transmission Weight'].default_value=1;bs.inputs['Roughness'].default_value=.1;bs.inputs['IOR'].default_value=1.45
bulb=bpy.data.materials.new('Warm ivory lamp');bulb.diffuse_color=(.9,.82,.65,1);bulb.use_nodes=True
bs=bulb.node_tree.nodes['Principled BSDF'];bs.inputs['Base Color'].default_value=(.9,.82,.65,1);bs.inputs['Emission Color'].default_value=(1,.81,.5,1);bs.inputs['Emission Strength'].default_value=.35
objects=[];origin=Vector((0,float(hi[1]),float((lo[2]+hi[2])*.5)))
def mesh(name,verts,faces,material,smooth=False):
    data=bpy.data.meshes.new(name);data.from_pydata(verts,[],faces);data.update()
    bm=bmesh.new();bm.from_mesh(data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(data);bm.free()
    # Preserve the measured attachment plane as local origin, real 0.4 m height.
    for v in data.vertices:v.co=(v.co-origin)*factor
    obj=bpy.data.objects.new(name,data);collection.objects.link(obj);obj.data.materials.append(material);objects.append(obj)
    for f in data.polygons:f.use_smooth=smooth
    # Cylindrical sides shade smoothly; hard manufactured steps remain sharp.
    uv=data.uv_layers.new(name='MeasuredSurface')
    for f in data.polygons:
        for li in f.loop_indices:
            v=data.vertices[data.loops[li].vertex_index].co
            uv.data[li].uv=(v.x/.4+.5,v.z/.4+.5)
    return obj
def lathe(name,profile,material,cy=-.070,n=32):
    # Profile is an explicitly closed cross-section with no coincident axis rings.
    verts=[(r*math.cos(i*2*math.pi/n),cy+r*math.sin(i*2*math.pi/n),z) for r,z in profile for i in range(n)]
    faces=[]
    for row in range(len(profile)):
        nxt=(row+1)%len(profile)
        for i in range(n):j=(i+1)%n;faces.append((row*n+i,row*n+j,nxt*n+j,nxt*n+i))
    return mesh(name,verts,faces,material,True)
# The source has a rounded mounting plate with four visible fasteners.
width=float(hi[0]-lo[0])*.96;bottom=.065;top=.963;radius=.060;yback=float(hi[1]);thick=.025
outline=[]
for x,z,start in [(width*.5-radius,top-radius,0),(-width*.5+radius,top-radius,90),(-width*.5+radius,bottom+radius,180),(width*.5-radius,bottom+radius,270)]:
    for i in range(7):a=math.radians(start+i*15);outline.append((x+radius*math.cos(a),z+radius*math.sin(a)))
verts=[(x,y,z) for y in [yback-thick,yback] for x,z in outline];n=len(outline)
faces=[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
plate=mesh('Rounded flat back plate',verts,faces,metal)
# Source contours show ribbed conical caps; replace noise by concentric turned rings.
top_profile=[(.004,.875),(.074,.856),(.14,.833)]
for i in range(6):
    z=.826-i*.020;r=.14+i*.014
    top_profile.extend([(r,z),(r+.009,z-.005),(r+.009,z-.009),(r+.003,z-.013)])
top_profile.extend([(.249,.704),(.249,.682),(.225,.678),(.004,.678)])
lathe('Upper stepped cap',top_profile,metal)
bottom_profile=[(.004,.049),(.023,.049),(.026,.081),(.06,.094)]
for i in range(7):
    z=.105+i*.020;r=.066+i*.023
    bottom_profile.extend([(r,z),(r+.010,z+.004),(r+.010,z+.010),(r+.016,z+.014)])
bottom_profile.extend([(.249,.245),(.249,.270),(.004,.270)])
lathe('Lower stepped cap',bottom_profile,metal)
# Thick closed glass ring. The source's opaque shards are not kept as fake glass.
lathe('Glass enclosure',[(.219,.274),(.219,.677),(.211,.677),(.211,.274)],glass,n=40)
lathe('Lamp bulb',[(.006,.285),(.050,.291),(.075,.315),(.090,.358),(.085,.414),(.060,.476),(.040,.530),(.038,.578),(.006,.582)],bulb,n=24)
lathe('Lamp socket',[(.005,.575),(.053,.575),(.053,.667),(.005,.667)],metal,n=24)
# Four thin cage bars reproduce the source silhouette; all are closed tubes.
def rod(name,a,b,r=.009,n=10):
    a,b=Vector(a),Vector(b);axis=(b-a).normalized();u=axis.cross(Vector((1,0,0)))
    if u.length<.01:u=axis.cross(Vector((0,1,0)))
    u.normalize();v=axis.cross(u);verts=[]
    for center in [a,b]:
        for i in range(n):verts.append(center+r*(u*math.cos(i*2*math.pi/n)+v*math.sin(i*2*math.pi/n)))
    faces=[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    return mesh(name,verts,faces,metal,True)
for i in range(4):
    a=math.radians(45+i*90);x=.230*math.cos(a);y=-.070+.230*math.sin(a)
    rod('Cage bar '+str(i),(x,y,.265),(x,y,.687),.010)
# A bent arm, sampled along its circular elbow, no intersecting straight tubes.
centers=[(0,yback-.015,.908),(0,.015,.908)]
for i in range(1,7):
    t=i*math.pi/12;centers.append((0,.015-.085*math.sin(t),.823+.085*math.cos(t)))
verts=[];n=12
for i,p in enumerate(centers):
    p=Vector(p);tangent=(Vector(centers[min(i+1,len(centers)-1)])-Vector(centers[max(i-1,0)])).normalized()
    u=Vector((1,0,0));v=tangent.cross(u).normalized()
    for j in range(n):verts.append(p+.025*(u*math.cos(j*2*math.pi/n)+v*math.sin(j*2*math.pi/n)))
faces=[tuple(reversed(range(n))),tuple(range((len(centers)-1)*n,len(centers)*n))]
for i in range(len(centers)-1):
    for j in range(n):k=(j+1)%n;faces.append((i*n+j,i*n+k,(i+1)*n+k,(i+1)*n+j))
mesh('Curved mounting arm',verts,faces,metal,True)
for x in [-width*.5+.052,width*.5-.052]:
    for z in [bottom+.06,top-.06]:rod('Mount screw',(x,yback-.034,z),(x,yback-.023,z),.012,12)
# Closed components, generated normals and UV must survive saving/reloading.
for o in objects:
    bm=bmesh.new();bm.from_mesh(o.data)
    assert all(e.is_manifold for e in bm.edges),o.name
    assert all(f.calc_area()>1e-12 for f in bm.faces),o.name
    bm.free()
blend=OUT/'WallSconce_Clean.blend';bpy.context.preferences.filepaths.save_version=0
bpy.data.objects.remove(source,do_unlink=True)
bpy.ops.wm.save_as_mainfile(filepath=str(blend))
# Do not bake the noisy source's dark/light blotches into clean manufactured surfaces.
convert=Matrix(((-1,0,0),(0,0,1),(0,1,0)))
groups=defaultdict(list)
for o in objects:groups[o.data.materials[0].name].append(o)
catalog={'SourceTask':'eb6564a3-f49d-423b-ae56-eee45e722466','SourceSha256':source_hash,'SourceTriangles':source_triangles,'HeightMetres':.4,'Parts':[]}
settings={'Satin charcoal metal':('Metal',[49,58,61],0),'Clear manufactured glass':('Glass',[180,204,206],.72),'Warm ivory lamp':('SmoothPlastic',[245,227,188],0)}
for index,(material,items) in enumerate(groups.items()):
    rows=[];faces=[];lookup={};bounds=[Vector((math.inf,)*3),Vector((-math.inf,)*3)]
    for o in items:
        o.data.calc_loop_triangles();uv=o.data.uv_layers.active
        for tri in o.data.loop_triangles:
            face=[]
            for li in tri.loops:
                loop=o.data.loops[li];v=convert@o.data.vertices[loop.vertex_index].co;normal=convert@o.data.corner_normals[li].vector
                tex=uv.data[li].uv
                row=struct.pack('<8f4b4B',*v,*normal,tex.x,1-tex.y,0,0,0,127,255,255,255,255)
                if row not in lookup:
                    lookup[row]=len(rows);rows.append(row)
                    for k in range(3):bounds[0][k]=min(bounds[0][k],v[k]);bounds[1][k]=max(bounds[1][k],v[k])
                face.append(lookup[row])
            faces.append(face)
    filename=f'WallSconce_{index}.mesh';payload=b'version 2.00\n'+struct.pack('<HBBII',12,40,12,len(rows),len(faces))+b''.join(rows)+b''.join(struct.pack('<III',*f) for f in faces)
    (LOCAL/filename).write_bytes(payload);roblox,color,alpha=settings[material]
    catalog['Parts'].append({'File':filename,'Triangles':len(faces),'Color':color,'Material':roblox,'Transparency':alpha,'Bounds':list(bounds[1]-bounds[0])})
catalog['TotalTriangles']=sum(p['Triangles'] for p in catalog['Parts']);assert catalog['TotalTriangles']<7000
(LOCAL/'manifest.json').write_text(json.dumps(catalog,indent=2))
assert hashlib.sha256(SRC.read_bytes()).hexdigest()==source_hash
# Reopen exactly what was saved, then inspect solid and actual edit edges.
bpy.ops.wm.open_mainfile(filepath=str(blend),load_ui=False)
objects=list(bpy.data.collections['Clean architecture decoration'].objects)
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=24;scene.cycles.use_denoising=True
scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.4,.45,.5,1);scene.world.node_tree.nodes['Background'].inputs[1].default_value=.5
scene.render.resolution_x=900;scene.render.resolution_y=1050;scene.render.resolution_percentage=100
scene.view_settings.view_transform='AgX'
for pos,power in [((1,-2,2),120),((-1,1,1),80)]:
    bpy.ops.object.light_add(type='AREA',location=pos);bpy.context.object.data.energy=power;bpy.context.object.data.size=1.4
bpy.ops.object.camera_add();cam=bpy.context.object;scene.camera=cam;target=Vector((0,-.10,0))
cam.data.type='ORTHO';cam.data.ortho_scale=.52
for filename,position in [('building-sconce-clean',(0.65,-1,.25)),('building-sconce-clean-front',(0,-1,0))]:
    cam.location=position;cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler()
    scene.render.filepath=str(ROOT/f'dist/preview/{filename}.png');bpy.ops.render.render(write_still=True)
wire=bpy.data.materials.new('Actual edit edges');wire.diffuse_color=(.08,.14,.17,1)
for o in objects:
    verts=[v.co for v in o.data.vertices];segments=[(verts[e.vertices[0]],verts[e.vertices[1]]) for e in o.data.edges]
    curve=bpy.data.curves.new('Editable mesh edges','CURVE');curve.dimensions='3D';curve.bevel_depth=.00028;curve.bevel_resolution=0
    for a,b in segments:
        spline=curve.splines.new('POLY');spline.points.add(1);spline.points[0].co=(*a,1);spline.points[1].co=(*b,1)
    lines=bpy.data.objects.new('Actual mesh edges',curve);bpy.context.collection.objects.link(lines);curve.materials.append(wire)
cam.location=(.65,-1,.25);cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler()
scene.render.filepath=str(ROOT/'dist/preview/building-sconce-clean-wire.png');bpy.ops.render.render(write_still=True)
print('Clean measured wall sconce:',catalog['TotalTriangles'],'triangles; source unchanged.')
