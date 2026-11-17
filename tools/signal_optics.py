"""Measured concentric bezels and convex lenses, with closed section thickness."""
import math,bpy,bmesh,numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from vehicle_mesh_ops import partition,box

def fit_optics(source,spec):
    mesh=source.data;mesh.calc_loop_triangles()
    tree=BVHTree.FromPolygons([v.co for v in mesh.vertices],[tuple(t.vertices) for t in mesh.loop_triangles],all_triangles=True)
    cx,cy=spec['center'];cloud=[]
    for r in np.linspace(0,.145,16):
        for a in np.linspace(0,2*math.pi,32,endpoint=False):
            p,_,_,_=tree.ray_cast(Vector((cx+r*math.sin(a),cy+r*math.cos(a),-1)),Vector((0,0,1)),1)
            if p is not None:cloud.append(tuple(p))
    cloud=np.array(cloud)
    sphere=np.linalg.lstsq(np.column_stack((2*cloud,np.ones(len(cloud)))),np.sum(cloud*cloud,axis=1),rcond=None)[0]
    cx,cy=map(float,sphere[:2]);rows=[]
    # Sample the glass inside the hood opening, avoiding its side wall.
    for r in np.linspace(0,.171,16):
        for a in np.linspace(0,2*math.pi,32,endpoint=False):
            p,_,_,_=tree.ray_cast(Vector((cx+r*math.sin(a),cy+r*math.cos(a),-1)),Vector((0,0,1)),1)
            if p is not None and -.43<p.z<-.31:rows.append((r,p.z))
    r,z=np.array(rows).T
    coefficients=np.linalg.lstsq(np.column_stack((np.ones(len(r)),r*r,r**4)),z,rcond=None)[0]
    # The lower exposed arc gives the rim cross-section without the sunshade.
    rim=[]
    for radius in np.arange(.180,.225,.001):
        values=[]
        for a in np.radians(np.linspace(168,192,17)):
            p,_,_,_=tree.ray_cast(Vector((cx+radius*math.sin(a),cy+radius*math.cos(a),-1)),Vector((0,0,1)),1)
            if p is not None and p.z<-.30:values.append(p.z)
        if values:rim.append((radius,float(np.median(values))))
    peak_r,peak_z=min(rim,key=lambda p:p[1]);shift=peak_r-.200
    inner=.172+shift;outer=.220+shift
    lens_radius=inner+.001
    def lens_z(r):return float(coefficients@[1,r*r,r**4])
    # Small bevels separate the lens seat, front lip, outer wall and rear flange.
    profile=[(inner,lens_z(inner)+.003),
             (peak_r-.009,peak_z+.006),(peak_r-.003,peak_z),
             (peak_r+.003,peak_z),(outer-.005,peak_z+.009),
             (outer,peak_z+.023),(outer,-.276),
             (outer+.027,-.257),
             (outer+.026,-.246),(outer+.026,-.211),(inner,-.211)]
    return {'center':[cx,cy],'lensPolynomial':coefficients.tolist(),'lensRadius':lens_radius,
            'profile':profile,'glassSamples':len(rows),'rimSamples':len(rim)*17,
            'peakRadius':peak_r,'peakZ':peak_z,'segments':32}

def retain_mounts(poly,spec):
    """Remove the old optical body, retaining separate Tripo retaining clips."""
    cx,cy=spec['center'];result=[];remaining=[poly]
    regions=[]
    for side in (-1,1):
        x0,x1=sorted((cx+side*.11,cx+side*.25))
        regions.append(box(x0,x1,cy+.195,cy+.285,-.335,-.205))
        x0,x1=sorted((cx+side*.135,cx+side*.232))
        regions.append(box(x0,x1,cy-.282,cy-.120,-.410,-.225))
    # Keep only the protruding portion of the lower clips; their attachment is
    # buried inside the regular replacement ring, not left as a jagged seam.
    for index,planes in enumerate(regions):
        after=[]
        for part in remaining:
            inside,outside=partition(part,planes);after.extend(outside)
            if len(inside)<3:continue
            if index%2==1:
                radius=.211
                cylinder=[((math.sin(a),math.cos(a),0),radius+cx*math.sin(a)+cy*math.cos(a)) for a in np.linspace(0,2*math.pi,32,endpoint=False)]
                _,protrusion=partition(inside,cylinder);result.extend(protrusion)
            else:result.append(inside)
        remaining=after
    radius=.305
    cylinder=[((math.sin(a),math.cos(a),0),radius+cx*math.sin(a)+cy*math.cos(a)) for a in np.linspace(0,2*math.pi,32,endpoint=False)]
    for part in remaining:
        _,outside=partition(part,cylinder);result.extend(outside)
    return result

def make_part(name,vertices,faces,kinds):
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(vertices,[],faces);mesh.update()
    bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    assert all(len(e.link_faces)==2 for e in bm.edges),name+' is not closed'
    bm.to_mesh(mesh);bm.free();mesh.update()
    for f in mesh.polygons:f.use_smooth=True
    tag=mesh.attributes.new('OpticFace','INT','FACE')
    kind=mesh.attributes.new('OpticKind','INT','FACE')
    for f,value in zip(mesh.polygons,kinds):tag.data[f.index].value=1;kind.data[f.index].value=value
    obj=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(obj)
    return obj

def make_optics(spec,index):
    cx,cy=spec['center'];n=spec['segments'];profile=spec['profile'];m=len(profile);vertices=[];faces=[]
    for i in range(n):
        a=2*math.pi*i/n
        for r,z in profile:vertices.append((cx+r*math.sin(a),cy+r*math.cos(a),z))
    for i in range(n):
        for j in range(m):faces.append((i*m+j,((i+1)%n)*m+j,((i+1)%n)*m+(j+1)%m,i*m+(j+1)%m))
    bezel=make_part('Concentric optical bezel '+str(index+1),vertices,faces,[1]*len(faces))
    sharp=bezel.data.attributes.new('sharp_edge','BOOLEAN','EDGE')
    for edge in bezel.data.edges:
        sharp.data[edge.index].value=edge.vertices[0]%m==edge.vertices[1]%m
    # Split normals at the manufactured steps; interpolate only around a ring.
    normals=[Vector() for _ in bezel.data.loops]
    for f in bezel.data.polygons:
        section=f.index%m
        r0,z0=profile[section];r1,z1=profile[(section+1)%m]
        for lid in f.loop_indices:
            i=bezel.data.loops[lid].vertex_index//m;a=2*math.pi*i/n
            normal=Vector(((z1-z0)*math.sin(a),(z1-z0)*math.cos(a),-(r1-r0))).normalized()
            if normal.dot(f.normal)<0:normal=-normal
            normals[lid]=normal
    bezel.data.normals_split_custom_set(normals)
    normal_attr=bezel.data.attributes.new('OpticNormal','FLOAT_VECTOR','CORNER')
    for d,v in zip(normal_attr.data,normals):d.vector=v
    coeff=spec['lensPolynomial'];radius=spec['lensRadius'];rings=5
    def z(r):return coeff[0]+coeff[1]*r*r+coeff[2]*r**4
    vertices=[(cx,cy,z(0))];faces=[]
    for ring in range(1,rings+1):
        r=radius*ring/rings
        for i in range(n):
            a=2*math.pi*i/n;vertices.append((cx+r*math.sin(a),cy+r*math.cos(a),z(r)))
    for i in range(n):faces.append((0,1+i,1+(i+1)%n))
    for ring in range(rings-1):
        for i in range(n):
            a=1+ring*n+i;b=1+ring*n+(i+1)%n;faces.append((a,b,b+n,a+n))
    # A separate back face closes the lens volume and stays inside the bezel.
    base=len(vertices)
    for i in range(n):
        a=2*math.pi*i/n;vertices.append((cx+radius*math.sin(a),cy+radius*math.cos(a),z(radius)+.010))
    front=1+(rings-1)*n
    for i in range(n):faces.append((front+i,front+(i+1)%n,base+(i+1)%n,base+i))
    faces.append(tuple(base+i for i in reversed(range(n))))
    lens=make_part('Smooth convex signal lens '+str(index+1),vertices,faces,[2]*len(faces))
    sharp=lens.data.attributes.new('sharp_edge','BOOLEAN','EDGE')
    for edge in lens.data.edges:
        a,b=edge.vertices
        sharp.data[edge.index].value=(front<=a<base and front<=b<base) or (a>=base and b>=base)
    normals=[normal.vector.copy() for normal in lens.data.corner_normals]
    front_faces=n*rings
    for face in lens.data.polygons:
        if face.index>=front_faces:continue
        for lid in face.loop_indices:
            p=lens.data.vertices[lens.data.loops[lid].vertex_index].co;x=p.x-cx;y=p.y-cy;r2=x*x+y*y
            k=2*coeff[1]+4*coeff[2]*r2;normals[lid]=Vector((k*x,k*y,-1)).normalized()
    lens.data.normals_split_custom_set(normals)
    normal_attr=lens.data.attributes.new('OpticNormal','FLOAT_VECTOR','CORNER')
    for d,v in zip(normal_attr.data,normals):d.vector=v
    report={'centerMeters':spec['center'],'radialSegments':n,'bezelProfile':profile,'lensPolynomial':coeff,
            'lensRadiusMeters':radius,'lensRings':rings,'glassFitSamples':spec['glassSamples'],
            'rimFitSamples':spec['rimSamples'],'closedBezel':True,'closedLens':True,
            'bezelQuads':len(bezel.data.polygons),'lensQuads':n*rings,
            'minimumLensThicknessMm':10,'concentricLoops':True}
    return [bezel,lens],report
