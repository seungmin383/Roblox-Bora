"""Small surface modelling helpers for the new BORA sedan, in metres."""
import bpy, bmesh, math
from mathutils import Vector
from mathutils.geometry import tessellate_polygon

BUILT = []

def material(name, color, metal=0, rough=.4, transmission=0, emission=0):
    m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);m.use_nodes=True
    b=m.node_tree.nodes.get('Principled BSDF')
    b.inputs['Base Color'].default_value=(*color,1)
    b.inputs['Metallic'].default_value=metal;b.inputs['Roughness'].default_value=rough
    b.inputs['Transmission Weight'].default_value=transmission
    if transmission:b.inputs['IOR'].default_value=1.46
    if emission:
        b.inputs['Emission Color'].default_value=(*color,1)
        b.inputs['Emission Strength'].default_value=emission
    return m

def mesh(name, verts, faces, mat, group='Body', smooth=True, uv=True):
    me=bpy.data.meshes.new(name);me.from_pydata(verts,[],faces);me.update()
    bm=bmesh.new();bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=1e-7)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    bm.to_mesh(me);bm.free();me.update()
    o=bpy.data.objects.new(name,me);bpy.context.scene.collection.objects.link(o)
    o.data.materials.append(mat);o['asset']='BORA S3';o['group']=group
    for p in me.polygons:p.use_smooth=smooth
    if uv:
        layer=me.uv_layers.new(name='UVMap')
        dims=[max(v.co[k] for v in me.vertices)-min(v.co[k] for v in me.vertices) for k in range(3)]
        axes=sorted(range(3),key=lambda k:dims[k],reverse=True)[:2]
        low=[min(v.co[k] for v in me.vertices) for k in axes]
        for p in me.polygons:
            for li in p.loop_indices:
                co=me.vertices[me.loops[li].vertex_index].co
                layer.data[li].uv=tuple((co[k]-low[i])/max(dims[k],1e-5) for i,k in enumerate(axes))
    BUILT.append(o)
    return o

def apply(o, modifier):
    bpy.context.view_layer.objects.active=o
    bpy.ops.object.modifier_apply(modifier=modifier.name)

def shell(o, thickness=.003):
    m=o.modifiers.new('Panel inner return','SOLIDIFY');m.thickness=thickness
    m.offset=-1;m.use_even_offset=False
    apply(o,m)
    # Keep the surface smooth; returns have a hard transition.
    bm=bmesh.new();bm.from_mesh(o.data)
    for e in bm.edges:
        if e.is_manifold and e.calc_face_angle(0)>.6:e.smooth=False
    bm.to_mesh(o.data);bm.free();o.data.update()
    return o

def bevel(o, width=.004, segments=3):
    m=o.modifiers.new('Manufactured edge radius','BEVEL')
    m.width=width;m.segments=segments;m.limit_method='ANGLE';m.angle_limit=.55
    m.harden_normals=True
    apply(o,m)
    for p in o.data.polygons:p.use_smooth=True
    m=o.modifiers.new('Weighted planar normals','WEIGHTED_NORMAL');m.keep_sharp=True;m.weight=50
    apply(o,m)
    return o

def grid(name, fn, us, vs, mat, group='Body', thickness=0, normal=None):
    verts=[tuple(fn(u,v)) for v in vs for u in us];nu=len(us);faces=[]
    for j in range(len(vs)-1):
        for i in range(nu-1):
            faces.append((j*nu+i,j*nu+i+1,(j+1)*nu+i+1,(j+1)*nu+i))
    o=mesh(name,verts,faces,mat,group)
    if normal:
        center=Vector(fn(us[len(us)//2],vs[len(vs)//2]))
        average=sum((p.normal for p in o.data.polygons),Vector())
        if average.dot(Vector(normal(center)))<0:
            bm=bmesh.new();bm.from_mesh(o.data);bmesh.ops.reverse_faces(bm,faces=list(bm.faces));bm.to_mesh(o.data);bm.free()
    if thickness:shell(o,thickness)
    return o

def seq(a,b,n):return [a+(b-a)*i/n for i in range(n+1)]
def lerp(a,b,t):return a+(b-a)*t
def smoothstep(t):t=max(0,min(1,t));return t*t*(3-2*t)

def interp(table,x):
    if x<=table[0][0]:return table[0][1]
    if x>=table[-1][0]:return table[-1][1]
    for i in range(len(table)-1):
        x0,y0=table[i];x1,y1=table[i+1]
        if x0<=x<=x1:
            # Cubic Hermite with centred endpoint tangents.
            a=max(0,i-1);b=min(len(table)-1,i+2)
            m0=(y1-table[a][1])/(x1-table[a][0])
            m1=(table[b][1]-y0)/(table[b][0]-x0)
            t=(x-x0)/(x1-x0)
            return (2*t**3-3*t*t+1)*y0+(t**3-2*t*t+t)*(x1-x0)*m0+(-2*t**3+3*t*t)*y1+(t**3-t*t)*(x1-x0)*m1

def box(name,loc,size,mat,group='Body',radius=.005):
    bpy.ops.mesh.primitive_cube_add(size=1,location=loc)
    o=bpy.context.object;o.name=name;o.scale=size
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    o.data.materials.append(mat);o['asset']='BORA S3';o['group']=group;BUILT.append(o)
    if radius:bevel(o,min(radius,min(size)*.35))
    return o

def tube(name, points, radius, mat, group='Body', sides=8, closed=False):
    pts=list(map(Vector,points));vv=[];ff=[]
    for i,p in enumerate(pts):
        d=pts[(i+1)%len(pts)]-pts[i-1] if closed else pts[min(i+1,len(pts)-1)]-pts[max(0,i-1)]
        d.normalize();a=d.cross(Vector((0,0,1)))
        if a.length<.01:a=d.cross(Vector((0,1,0)))
        a.normalize();b=d.cross(a).normalized()
        vv += [tuple(p+radius*(math.cos(k*2*math.pi/sides)*a+math.sin(k*2*math.pi/sides)*b)) for k in range(sides)]
    for i in range(len(pts) if closed else len(pts)-1):
        ni=(i+1)%len(pts)
        for k in range(sides):ff.append((i*sides+k,i*sides+(k+1)%sides,ni*sides+(k+1)%sides,ni*sides+k))
    if not closed:ff += [tuple(reversed(range(sides))),tuple((len(pts)-1)*sides+k for k in range(sides))]
    return mesh(name,vv,ff,mat,group)

def cylinder(name,center,radius,depth,mat,group='Body',axis=(1,0,0),n=48):
    axis=Vector(axis).normalized();a=axis.cross(Vector((0,0,1)))
    if a.length<.01:a=axis.cross(Vector((0,1,0)))
    a.normalize();b=axis.cross(a)
    vv=[tuple(Vector(center)+axis*t+radius*(math.cos(k*2*math.pi/n)*a+math.sin(k*2*math.pi/n)*b)) for t in (-depth/2,depth/2) for k in range(n)]
    ff=[(k,(k+1)%n,n+(k+1)%n,n+k) for k in range(n)]
    ff += [tuple(reversed(range(n))),tuple(n+k for k in range(n))]
    o=mesh(name,vv,ff,mat,group)
    for p in o.data.polygons:
        if len(p.vertices)>4:p.use_smooth=False
    return o

def loop_patch(name,fn,outer,inner,mat,group='Body',depth=0):
    # Rectangular parameter-domain ring, with shared matching aperture edges.
    def border(bounds):
        a,b,c,d=bounds
        return [(u,c) for u in seq(a,b,20)[:-1]]+[(b,v) for v in seq(c,d,8)[:-1]]+[(u,d) for u in seq(b,a,20)[:-1]]+[(a,v) for v in seq(d,c,8)[:-1]]
    oo=border(outer);ii=border(inner)
    verts=[tuple(Vector(fn(u,v))+Vector((0,depth,0))) for u,v in oo+ii];n=len(oo)
    faces=[(k,(k+1)%n,(k+1)%n+n,k+n) for k in range(n)]
    o=mesh(name,verts,faces,mat,group)
    shell(o,.0015)
    return o

def pillow(name,center,width,depth,height,mat,group='Interior',lean=0):
    # Closed rounded upholstery, using regular superellipse rings.
    vv=[];ff=[];n=24
    rings=[(-.5,.18),(-.46,.72),(-.34,.96),(0,1),(.34,.96),(.46,.72),(.5,.18)]
    for z,scale in rings:
        for i in range(n):
            a=i*2*math.pi/n
            x=math.copysign(abs(math.cos(a))**.5,math.cos(a))*width*.5*scale
            y=math.copysign(abs(math.sin(a))**.5,math.sin(a))*depth*.5*scale
            vv.append((center[0]+x,center[1]+y+z*lean,center[2]+z*height))
    for j in range(len(rings)-1):
        for i in range(n):ff.append((j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i))
    ff += [tuple(reversed(range(n))),tuple((len(rings)-1)*n+i for i in range(n))]
    return mesh(name,vv,ff,mat,group)
