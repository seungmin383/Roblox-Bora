"""Fair broad panels sampled from Tripo; retain its lamps, grille and wheels.
All new surfaces are native geometry, with one shared cabin/window definition.
This script creates asset sources only and never writes a Roblox Place.
"""
from pathlib import Path
from collections import defaultdict
import sys,math,json
import bpy,bmesh,numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'assets/vehicles/local'
sys.path.insert(0,str(ROOT/'tools'))
from vehicle_mesh_ops import box as volume,partition

bpy.ops.wm.open_mainfile(filepath=str(OUT/'BoraTripoSedan.blend'))
bpy.context.preferences.filepaths.save_version=0
source=next(o for o in bpy.context.scene.objects if o.type=='MESH' and not o.get('group') and len(o.data.polygons)>40000)
source.data.calc_loop_triangles();atlas=source.data.materials[0];uv=source.data.uv_layers.active
tree=BVHTree.FromPolygons([v.co.copy() for v in source.data.vertices],[tuple(t.vertices) for t in source.data.loop_triangles],all_triangles=True)
triangles=[[(tuple(source.data.vertices[source.data.loops[l].vertex_index].co)+tuple(source.data.corner_normals[l].vector)+tuple(uv.data[l].uv)) for l in t.loops] for t in source.data.loop_triangles]
atlas_image=atlas.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].links[0].from_node.image
pixels=np.array(atlas_image.pixels[:],dtype=np.float32).reshape(atlas_image.size[1],atlas_image.size[0],4)

def hit_z(x,y):
    hit=tree.ray_cast(Vector((x,y,2.1)),Vector((0,0,-1)))
    return hit[0].z if hit[0] is not None else None

roof_samples=[];hood_samples=[];width_samples=[]
for y in np.linspace(-.38,.99,27):
    for x in np.linspace(-.60,.60,17):
        z=hit_z(x,y)
        if z and z>1.27:roof_samples.append((x,y,z))
for y in np.linspace(-2.12,-1.06,27):
    for x in np.linspace(-.57,.57,17):
        z=hit_z(x,y)
        if z and .65<z<1.08:hood_samples.append((x,y,z))
for y in np.linspace(-2.08,2.18,45):
    hit=tree.ray_cast(Vector((1.4,y,.83)),Vector((-1,0,0)))
    if hit[0] is not None and .72<hit[0].x<1.02:width_samples.append((y,hit[0].x))

def height_fit(samples):
    a=np.array(samples);x,y,z=a.T
    design=np.column_stack([np.ones(len(a)),y,y*y,y**3,x*x,x*x*y,x*x*y*y,x**4])
    return np.linalg.lstsq(design,z,rcond=None)[0]
roof_coeff=height_fit(roof_samples);hood_coeff=height_fit(hood_samples)
width_coeff=np.polyfit([a[0] for a in width_samples],[a[1] for a in width_samples],5)
def fitted(c,x,y):return float(c[0]+c[1]*y+c[2]*y*y+c[3]*y**3+c[4]*x*x+c[5]*x*x*y+c[6]*x*x*y*y+c[7]*x**4)
def roof_z(x,y):return fitted(roof_coeff,x,y)
def hood_z(x,y):return fitted(hood_coeff,x,y)
def width(y):return min(.925,max(.895,float(np.polyval(width_coeff,y))))
def belt(y):return float(np.interp(y,[-2.08,-1.94,-1.50,-.84,.30,1.22,1.70,2.18],[.78,.85,.96,1.00,1.015,1.045,1.09,1.025]))
def hood_width(y):return .63+(.84-.63)*min(1,max(0,(y+2.14)/.20))

for obj in list(bpy.context.scene.objects):bpy.data.objects.remove(obj,do_unlink=True)
materials={}
def mat(key,color,metal=0,rough=.4,alpha=1):
    m=bpy.data.materials.new(key);m.use_nodes=True;p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*color,1);p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=rough
    if alpha<1:p.inputs['Alpha'].default_value=alpha;m.surface_render_method='DITHERED'
    if key in ('LED','Tail'):p.inputs['Emission Color'].default_value=(*color,1);p.inputs['Emission Strength'].default_value=1.5
    materials[key]=m;return m
paint=mat('CarPaint',(.44,.49,.53),.5,.30)
black=mat('Black',(.012,.016,.020),.1,.35)
silver=mat('Silver',(.48,.53,.57),.7,.25)
glass=mat('Glass',(.09,.14,.17),.15,.15,.22)
mat('LED',(.78,.90,1),0,.25);mat('Tail',(.65,.012,.02),0,.25)
mat('Plate',(.82,.85,.87),.1,.45);mat('Ink',(.008,.012,.018),0,.50)

def mesh_obj(name,vertices,faces,key,group='Body',smooth=True,thickness=0,bevel=0):
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(vertices,[],faces);mesh.update()
    obj=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(obj);obj['group']=group;obj['material']=key;mesh.materials.append(materials[key])
    for f in mesh.polygons:f.use_smooth=smooth
    bpy.context.view_layer.objects.active=obj
    if thickness:
        mod=obj.modifiers.new('Panel gauge','SOLIDIFY');mod.thickness=thickness;mod.offset=-1;bpy.ops.object.modifier_apply(modifier=mod.name)
    if bevel:
        mod=obj.modifiers.new('Manufactured edge radius','BEVEL');mod.width=bevel;mod.segments=3;mod.limit_method='ANGLE';mod.angle_limit=.5;bpy.ops.object.modifier_apply(modifier=mod.name)
    return obj

def grid(name,fn,nu,nv,key='CarPaint',group='Body',thickness=0,reverse=False):
    vertices=[fn(i/nu,j/nv) for j in range(nv+1) for i in range(nu+1)];faces=[]
    for j in range(nv):
        for i in range(nu):
            a=j*(nu+1)+i;face=(a,a+1,a+nu+2,a+nu+1);faces.append(tuple(reversed(face)) if reverse else face)
    return mesh_obj(name,vertices,faces,key,group,thickness=thickness)

def cube(name,center,size,key='Black',group='Body',bevel=.008):
    bpy.ops.mesh.primitive_cube_add(size=1,location=center);o=bpy.context.object;o.name=name;o.scale=size;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    o['group']=group;o['material']=key;o.data.materials.append(materials[key])
    if bevel:
        mod=o.modifiers.new('Soft edge','BEVEL');mod.width=bevel;mod.segments=4;bpy.ops.object.modifier_apply(modifier=mod.name)
    for f in o.data.polygons:f.use_smooth=True
    return o

def tube(name,points,radius,key='Black',group='Body',sides=8):
    points=[Vector(p) for p in points];verts=[];faces=[]
    for i,p in enumerate(points):
        t=(points[min(i+1,len(points)-1)]-points[max(0,i-1)]).normalized();ref=Vector((1,0,0)) if abs(t.x)<.8 else Vector((0,1,0));u=t.cross(ref).normalized();v=t.cross(u).normalized()
        for j in range(sides):verts.append(tuple(p+radius*(math.cos(j*2*math.pi/sides)*u+math.sin(j*2*math.pi/sides)*v)))
    faces.append(tuple(reversed(range(sides))));faces.append(tuple((len(points)-1)*sides+j for j in range(sides)))
    for i in range(len(points)-1):
        for j in range(sides):a=i*sides+j;b=i*sides+(j+1)%sides;faces.append((a,b,b+sides,a+sides))
    return mesh_obj(name,verts,faces,key,group)

def line(a,b,n=8):return [tuple(Vector(a).lerp(Vector(b),i/n)) for i in range(n+1)]
def boolean_cut(obj,cutter):
    bpy.context.view_layer.objects.active=obj;mod=obj.modifiers.new('Precise opening','BOOLEAN');mod.operation='DIFFERENCE';mod.solver='EXACT';mod.object=cutter;bpy.ops.object.modifier_apply(modifier=mod.name);bpy.data.objects.remove(cutter,do_unlink=True)

# Only the generated fine details remain textured. Broad paintwork, the roof,
# panel boundaries and all glazing are rebuilt as smooth, connected surfaces.
cuts=[volume(-1.2,1.2,-1.12,1.69,.96,2),volume(-.73,.73,-.98,1.69,.35,1.50)]
for x0,x1 in [(-1.2,-.70),(.70,1.2)]:
    cuts.append(volume(x0,x1,-.84,1.80,.30,1.105))
hood_front=volume(-1,1,-2.14,-1.94,.65,1.2);slope=(.84-.63)/.20
hood_front[:2]=[((1,-slope,0),.63+slope*2.14),((-1,-slope,0),.63+slope*2.14)]
cuts.extend([hood_front,volume(-.84,.84,-1.94,-1.04,.65,1.2)])
regions=defaultdict(list)
def source_emit(group,poly):
    for i in range(1,len(poly)-1):
        tri=[poly[0],poly[i],poly[i+1]];a,b,c=[Vector(p[:3]) for p in tri]
        if (b-a).cross(c-a).length<1e-10:continue
        x,y,z=(a+b+c)/3;key='Tripo'
        regions[(group,key)].append(tri)
for tri in triangles:
    x,y,z=sum((Vector(p[:3]) for p in tri),Vector())/3;wheel=None
    for axle,cy in [('F',-1.36),('R',1.36)]:
        if abs(x)>.59 and (y-cy)**2+(z-.325)**2<.325**2 and z<.67:wheel='Wheel'+axle+('L' if x<0 else 'R');break
    if wheel:source_emit(wheel,list(tri));continue
    pieces=[list(tri)]
    for cut in cuts:
        after=[]
        for p in pieces:_,outside=partition(p,cut);after.extend(outside)
        pieces=after
        if not pieces:break
    for p in pieces:source_emit('Body',p)
for (group,key),tris in regions.items():
    vertices=[];faces=[];tex=[];normals=[]
    for tri in tris:
        a=len(vertices);vertices.extend(p[:3] for p in tri);normals.extend(p[3:6] for p in tri);tex.extend(p[6:8] for p in tri);faces.append((a,a+1,a+2))
    o=mesh_obj('Tripo detail '+group+key,vertices,faces,'CarPaint' if key=='CarPaint' else 'Black',group);o['material']=key;o.data.materials.clear();o.data.materials.append(paint if key=='CarPaint' else atlas)
    layer=o.data.uv_layers.new()
    for loop in o.data.loops:layer.data[loop.index].uv=tex[loop.vertex_index]
    # Rejoin coincident vertices before calculating smooth normals. Keeping
    # triangle soup here produced the old foil-like shading at panel edges.
    bm=bmesh.new();bm.from_mesh(o.data);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.000008);bm.to_mesh(o.data);bm.free();o.data.update()

# Resurfaced hood, with Tripo's crown/height profile and its angular silhouette.
def fair_hood(u,v):
    y=-2.14+1.10*v;x=(2*u-1)*hood_width(y)
    fitted_z=hood_z(x,y);original=hit_z(x,y)
    edge=max(abs(2*u-1),abs(2*v-1));blend=min(1,max(0,(edge-.60)/.40));blend=blend*blend*(3-2*blend)
    z=fitted_z*(1-blend)+(original if original is not None else fitted_z)*blend
    return (x,y,z)
grid('Fair hood',fair_hood,24,26,thickness=.016)
grid('Windshield lower cowl',lambda u,v:((2*u-1)*.88,-1.04+.065*v,1.008+.012*(1-(2*u-1)**2)-.008*v),24,3,thickness=.015)
def cowl_apron(u,v):
    x=(2*u-1)*.84;bottom=fair_hood(u,1)[2];top=1.008+.012*(1-(2*u-1)**2)
    return (x,-1.0402,bottom*(1-v)+top*v)
grid('Cowl front closure',cowl_apron,24,2,thickness=.010)
for sign in (-1,1):
    mesh_obj('Cowl side closure',[(sign*.90,-1.12,.94),(sign*.895,-.84,.97),(sign*.895,-.84,1.00),(sign*.87,-.98,1.008)],[(0,1,2,3)],'CarPaint',thickness=.014)

# Fair side skins, four separate doors and circular wheel openings.
for sign,suffix in [(-1,'L'),(1,'R')]:
    for group,y0,y1 in [('DoorF'+suffix,-.836,.296),('DoorR'+suffix,.304,1.216),('Body',1.224,1.80)]:
        def side_fn(u,v,sign=sign,y0=y0,y1=y1):
            y=y0+(y1-y0)*u;top=belt(y)
            crease=.72-.15*min(1,max(0,(y+.84)/2.06))
            heights=[.34,.40,.51,crease,top-.12,top]
            k=min(4,int(v*5));f=v*5-k;z=heights[k]*(1-f)+heights[k+1]*f
            offsets=[-.040,-.015,.005,.017,.003,-.012];off=offsets[k]*(1-f)+offsets[k+1]*f
            return (sign*(width(y)+off),y,z)
        o=grid('Fair side '+group+suffix+str(y0),side_fn,18,5,'CarPaint',group,thickness=.025,reverse=sign<0)
        for cy in (-1.36,1.36):
            if y0-.4<cy<y1+.4:
                bpy.ops.mesh.primitive_cylinder_add(vertices=80,radius=.370,depth=.9,location=(sign*.90,cy,.325),rotation=(0,math.pi/2,0));boolean_cut(o,bpy.context.object)
        bpy.context.view_layer.objects.active=o
        bevel=o.modifiers.new('Panel and arch edge radius','BEVEL');bevel.width=.004;bevel.segments=2;bevel.limit_method='ANGLE';bevel.angle_limit=.5;bpy.ops.object.modifier_apply(modifier=bevel.name)
        for f in o.data.polygons:f.use_smooth=True
    tube('Rocker sill '+suffix,[(sign*(width(y)-.015),y,.345) for y in np.linspace(-.95,1.30,24)],.033,'CarPaint')
    for y in (-.84,.30,1.22):tube('Door shut seal',[(sign*(width(y)-.027),y,z) for z in np.linspace(.37,belt(y),10)],.008,'Black')

# One mathematical roof definition controls the pillars, glass and headliner.
def roof_width(y):return .69+.035*math.sin(math.pi*min(1,max(0,(y+.40)/1.40)))
roof=grid('Fair roof',lambda u,v:((2*u-1)*roof_width(-.40+1.40*v),-.40+1.40*v,roof_z((2*u-1)*roof_width(-.40+1.40*v),-.40+1.40*v)),20,26,thickness=.022)
grid('Fitted headliner',lambda u,v:((2*u-1)*.65,-.32+1.22*v,roof_z((2*u-1)*.65,-.32+1.22*v)-.028),20,26,'Cabin' if 'Cabin' in materials else 'Black',reverse=True)

def glass_quad(name,corners,group,nu=12,nv=8,bow=.006):
    a,b,c,d=[Vector(p) for p in corners]
    def fn(u,v):
        p=(a*(1-u)+b*u)*(1-v)+(d*(1-u)+c*u)*v
        if group.startswith('Door'):p.x+=math.copysign(bow*math.sin(math.pi*u)*math.sin(math.pi*v),p.x)
        return tuple(p)
    o=grid(name,fn,nu,nv,'Glass',group)
    for start,end in [(a,b),(b,c),(c,d),(d,a)]:tube('Glass edge seal',line(start,end,12),.009,'Black',group)
    return o

for sign,suffix in [(-1,'L'),(1,'R')]:
    za=roof_z(.69,-.40);zb=roof_z(roof_width(.30),.30);zc=roof_z(.69,1.00)
    a=(sign*.715,-.38,za-.005);b=(sign*roof_width(.30),.30,zb-.01);c=(sign*.71,.98,zc-.005)
    tube('A pillar '+suffix,line((sign*.87,-.98,1.0),a,18),.028,'CarPaint',sides=12)
    tube('B pillar '+suffix,line((sign*.892,.30,1.005),b,16),.033,'Black',sides=12)
    tube('Roof side rail '+suffix,[(sign*roof_width(y),y,roof_z(roof_width(y),y)-.006) for y in np.linspace(-.40,1.00,28)],.018,'CarPaint',sides=10)
    # Tapered C-pillar sheet: its edges share the roof and rear glass endpoints.
    mesh_obj('C pillar '+suffix,[(sign*.69,.99,zc),(sign*.77,1.69,1.10),(sign*.90,1.48,1.065),(sign*.735,1.00,zc-.035)],[(0,1,2,3)],'CarPaint',thickness=.026,bevel=.008)
    glass_quad('Driver side glass '+suffix,[(sign*.895,-.81,1.00),(sign*.895,.264,1.012),(sign*.717,.264,zb-.033),(sign*.705,-.34,za-.028)],'DoorF'+suffix)
    glass_quad('Rear side glass '+suffix,[(sign*.895,.344,1.015),(sign*.895,1.216,1.045),(sign*.715,.95,zc-.030),(sign*.717,.344,zb-.033)],'DoorR'+suffix)
    mesh_obj('Quarter glazing '+suffix,[(sign*.884,1.255,1.052),(sign*.797,1.255,1.205),(sign*.881,1.445,1.085)],[(0,1,2)],'Glass')
    tube('Quarter glazing seal '+suffix,[(sign*.884,1.255,1.052),(sign*.797,1.255,1.205),(sign*.881,1.445,1.085),(sign*.884,1.255,1.052)],.009,'Black')
    tube('Belt window seal '+suffix,[(sign*.898,y,belt(y)+.004) for y in np.linspace(-.84,1.47,30)],.012,'Black')
    for group,y,z in [('DoorF'+suffix,.13,.89),('DoorR'+suffix,1.035,.94)]:
        cube('Handle recess',(sign*(width(y)+.016),y,z),(.010,.175,.033),'Black',group,.012)
        cube('Door handle',(sign*(width(y)+.030),y,z+.008),(.025,.142,.024),'Silver',group,.010)
    group='DoorF'+suffix
    tube('Mirror stalk',line((sign*.90,-.79,1.00),(sign*.995,-.78,1.025)),.018,'Black',group)
    cube('Mirror lower housing',(sign*1.015,-.77,1.04),(.17,.245,.10),'Black',group,.042)
    cube('Mirror cap',(sign*1.015,-.785,1.069),(.169,.225,.073),'CarPaint',group,.034)
    cube('Mirror reflective glass',(sign*1.015,-.638,1.044),(.145,.009,.072),'Silver',group,.026)

def windshield(u,v,rear=False):
    if not rear:
        y=-1.04+.64*v;w=.81*(1-v)+.662*v;x=(2*u-1)*w
        lower=1.008+.012*(1-(2*u-1)**2);upper=roof_z((2*u-1)*.662,-.40)-.018
        return (x,y,lower*(1-v)+upper*v+.009*math.sin(math.pi*v)*(1-(2*u-1)**2))
    y=1.00+.69*v;w=.665*(1-v)+.77*v;x=(2*u-1)*w
    upper=roof_z((2*u-1)*.665,1.00)-.018;lower=1.10+.016*(1-(2*u-1)**2)
    return (x,y,upper*(1-v)+lower*v+.008*math.sin(math.pi*v)*(1-(2*u-1)**2))
for rear in (False,True):
    grid('Rear windshield' if rear else 'Windshield',lambda u,v:windshield(u,v,rear),24,14,'Glass')
    for fixed,axis in [(0,0),(1,0),(0,1),(1,1)]:
        pts=[windshield(fixed,t,rear) if axis==0 else windshield(t,fixed,rear) for t in np.linspace(0,1,22)]
        tube('Windshield rubber',pts,.011,'Black')

def rear_transition(u,v):
    x=(2*u-1)*.77;y=1.69+.10*v
    target=hit_z(x,1.79) or 1.04
    return (x,y,(1.10+.016*(1-(2*u-1)**2))*(1-v)+target*v)
grid('Rear glass deck transition',rear_transition,24,5,thickness=.012)
for front in (True,False):
    y=-2.365 if front else 2.286;z=.335 if front else .748
    cube('Number plate',(0,y,z),(.43,.014,.09),'Plate',bevel=.006)
    bpy.ops.object.text_add(location=(0,y+(-.009 if front else .009),z-.020),rotation=(math.pi/2,0,0 if front else math.pi))
    o=bpy.context.object;o.name='Fictional plate lettering';o.data.body='BOR 0719';o.data.align_x='CENTER';o.data.size=.055;o.data.extrude=.0005;o.data.resolution_u=3
    bpy.ops.object.convert(target='MESH');o=bpy.context.object;o['group']='Body';o['material']='Ink';o.data.materials.append(materials['Ink'])

# Retain the actual 3D cabin and steering assembly; its window/roof geometry
# is excluded because the new outer shell now supplies those exact surfaces.
prefixes=('Undertray','Cabin floor','Interior door trim','Door armrest','Door pull','Dashboard','Display surround','Gauge glass','Navigation glass','Air vent','Dash metal trim','Center console','Console armrest','Shift selector','Cup holder','Seat base','Seat back','Headrest','Seat bolster','Seat seam','Rear bench','Rear backrest','Rear headrest','Rear view mirror','Steering column','Steering rim','Steering hub','Steering spoke','Lower spoke')
with bpy.data.libraries.load(str(OUT/'BoraSedan.blend'),link=False) as (available,loaded):loaded.objects=[n for n in available.objects if n.startswith(prefixes)]
for o in loaded.objects:
    if o:
        bpy.context.collection.objects.link(o)
        if o.name.startswith(('Interior door trim','Door armrest','Door pull')):o.location.x-=math.copysign(.065,o.location.x)
prefixes=('Pedal','Steering stalk','Climate control fascia','Climate key','Headrest support','Vent slat')
with bpy.data.libraries.load(str(OUT/'BoraTripoSedan_Polished.blend'),link=False) as (available,loaded):loaded.objects=[n for n in available.objects if n.startswith(prefixes)]
for o in loaded.objects:
    if o:bpy.context.collection.objects.link(o)
bpy.context.view_layer.update()
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'BoraS1_Retopology.blend'))
report={'source':'Tripo sedan surface sampling','roofSamples':len(roof_samples),'hoodSamples':len(hood_samples),'widthSamples':len(width_samples),'sourceDetailTriangles':sum(len(v) for v in regions.values()),'doorGapMeters':.008,'wheelArchRadiusMeters':.370,'wheelRadiusMeters':.325,'roofCenterMeters':roof_z(0,.25),'oneSharedCabinDefinition':True}
(ROOT/'dist/vehicle-retopology-validation.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print('Retopology ready:',report,flush=True)
