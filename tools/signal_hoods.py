"""Measured circular sunshades with straight generators and closed wall thickness."""
import math,bpy,bmesh,numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from vehicle_mesh_ops import partition,box

def fit(source):
    mesh=source.data;mesh.calc_loop_triangles()
    tree=BVHTree.FromPolygons([v.co for v in mesh.vertices],[tuple(t.vertices) for t in mesh.loop_triangles],all_triangles=True)
    cloud=np.array([v.co[:] for v in mesh.vertices]);fits=[]
    for nominal in (-.66,0,.66):
        points=[];thickness=[];root_thickness=[]
        for z in (-.38,-.43,-.46,-.50):
            for phi in np.linspace(-math.pi*.58,math.pi*.58,45):
                direction=Vector((math.sin(phi),math.cos(phi),0));axis=Vector((nominal,-.03,z));origin=axis+direction*.36
                hit=tree.ray_cast(origin,-direction,.35)
                if hit[0] is None or abs(hit[1].z)>.55:continue
                radius=(hit[0]-axis).dot(direction)
                if not .18<radius<.29:continue
                points.append(tuple(hit[0]))
                next_hit=tree.ray_cast(hit[0]-direction*.0002,-direction,.08)
                if next_hit[0] is not None:
                    width=(hit[0]-next_hit[0]).length
                    if z<-.42 and .006<width<.025:thickness.append(width)
                    elif z==-.38 and .020<width<.055:root_thickness.append(width)
        p=np.array(points);keep=np.ones(len(p),dtype=bool)
        for _ in range(4):
            q=p[keep,:2];coeff=np.linalg.lstsq(np.column_stack((2*q[:,0],2*q[:,1],np.ones(len(q)))),np.sum(q*q,axis=1),rcond=None)[0]
            cx,cy=coeff[:2];radius=math.sqrt(coeff[2]+cx*cx+cy*cy)
            residual=np.abs(np.hypot(p[:,0]-cx,p[:,1]-cy)-radius);keep=residual<max(.005,float(np.median(residual))*2.5)
        rho=np.hypot(cloud[:,0]-cx,cloud[:,1]-cy);angle=np.arctan2(cloud[:,0]-cx,cloud[:,1]-cy)
        profile=[]
        for degrees in range(-110,111,10):
            mask=(np.abs(angle-math.radians(degrees))<math.radians(9))&(np.abs(rho-radius)<.018)&(cloud[:,2]<-.365)
            if mask.sum()>=2:profile.append((math.radians(degrees),float(np.quantile(cloud[mask,2],.10))))
        theta=np.array([a for a,z in profile]);values=np.array([z for a,z in profile])
        coeff=np.linalg.lstsq(np.column_stack((np.ones(len(theta)),np.cos(theta),np.cos(2*theta),np.sin(theta))),values,rcond=None)[0]
        radial=np.hypot(p[:,0]-cx,p[:,1]-cy)
        root_radius=float(np.median(radial[np.isclose(p[:,2],-.38)]))+.001
        front_radius=float(np.median(radial[np.isclose(p[:,2],-.50)]))
        root_radii=[]
        for z in (-.26,-.28,-.30):
            for theta in np.linspace(-math.radians(85),math.radians(85),31):
                direction=Vector((math.sin(theta),math.cos(theta),0));center=Vector((cx,cy,z))
                hit=tree.ray_cast(center+direction*.32,-direction,.20)
                if hit[0] is not None and abs(hit[1].z)<.7:
                    distance=(hit[0]-center).dot(direction)
                    if .20<distance<.285:root_radii.append(distance)
        if root_radii:root_radius=float(np.quantile(root_radii,.65))
        controls=[]
        for degrees in (0,60,90):
            nearby=[z for a,z in profile if abs(abs(a)-math.radians(degrees))<math.radians(5)]
            controls.append(float(np.mean(nearby)) if nearby else float(values.min()))
        controls[0]=float(values.min());controls.append(-.379)
        controls=np.maximum.accumulate(controls).tolist()
        item={'center':[float(cx),float(cy)],'radius':float(radius),'rootRadius':root_radius,'frontRadius':front_radius,'tipThickness':float(np.median(thickness)),
              'rootThickness':float(np.median(root_thickness)) if root_thickness else .037,'frontCoefficients':coeff.tolist(),
              'frontControls':controls,
              'minimumFrontZ':float(values.min()),'fitSamples':int(keep.sum()),'profileSamples':len(profile),'rootZ':-.235,'arcDegrees':230}
        fits.append(item)
    return fits

def front_z(spec,theta):
    if 'frontControls' in spec:
        x=np.radians([0,60,90,spec['arcDegrees']/2]);y=np.array(spec['frontControls']);h=np.diff(x);d=np.diff(y)/h
        slopes=[0]
        for i in (1,2):
            if d[i-1]*d[i]<=0:slopes.append(0)
            else:
                w1=2*h[i]+h[i-1];w2=h[i]+2*h[i-1];slopes.append((w1+w2)/(w1/d[i-1]+w2/d[i]))
        slopes.append(float(d[-1]));angle=min(abs(theta),x[-1]);i=min(2,int(np.searchsorted(x,angle,side='right')-1));i=max(0,i);t=(angle-x[i])/h[i]
        return float((2*t**3-3*t*t+1)*y[i]+(t**3-2*t*t+t)*h[i]*slopes[i]+(-2*t**3+3*t*t)*y[i+1]+(t**3-t*t)*h[i]*slopes[i+1])
    a,b,c,d=spec['frontCoefficients']
    return min(spec['rootZ']-.012,max(spec['minimumFrontZ']-.002,a+b*math.cos(theta)+c*math.cos(2*theta)+d*math.sin(theta)))

def trim(poly,spec):
    """Keep the lens and lower collar while removing the old upper shade wall."""
    attachment_cut=-.212
    if all(v[2]>=attachment_cut for v in poly):return [poly]
    cx,cy=spec['center'];inner=spec['rootRadius']-spec['rootThickness']+.002
    cylinder=[((math.sin(a),math.cos(a),0),inner+cx*math.sin(a)+cy*math.cos(a)) for a in np.linspace(0,2*math.pi,24,endpoint=False)]
    preserved=[];remaining=[poly]
    for x0,x1 in ((cx-.25,cx-.11),(cx+.11,cx+.25)):
        after=[]
        for part in remaining:
            lug,rest=partition(part,box(x0,x1,cy+.195,cy+.285,-.335,-.205))
            if len(lug)>=3:preserved.append(lug)
            after.extend(rest)
        remaining=after
    result=preserved;outside=[]
    outer=spec['rootRadius']+.050
    outer_planes=[((math.sin(a),math.cos(a),0),outer+cx*math.sin(a)+cy*math.cos(a)) for a in np.linspace(0,2*math.pi,24,endpoint=False)]
    for part in remaining:
        candidate,far=partition(part,outer_planes);result.extend(far)
        if len(candidate)<3:continue
        keep,rest=partition(candidate,cylinder)
        if len(keep)>=3:result.append(keep)
        outside.extend(rest)
    angle=math.radians(115)
    for side in (-1,1):
        normal=(side*math.cos(angle),-math.sin(angle),0)
        wedge=[((-side,0,0),-side*cx),(normal,normal[0]*cx+normal[1]*cy),((0,0,1),attachment_cut)]
        after=[]
        for piece in outside:_,rest=partition(piece,wedge);after.extend(rest)
        outside=after
    result.extend(outside);return result

def make(spec,index):
    cx,cy=spec['center'];radius=spec['frontRadius'];root_radius=spec['rootRadius'];root=spec['rootZ'];segments=24;bevel=.002
    width=spec['tipThickness'];root_width=spec['rootThickness'];verts=[];faces=[];angles=np.linspace(-math.radians(spec['arcDegrees']/2),math.radians(spec['arcDegrees']/2),segments+1)
    # Each station is a closed cross-section from exterior to interior.
    for theta in angles:
        z=front_z(spec,float(theta))
        profile=[(root_radius,root),(radius,z+bevel),(radius-bevel,z),
                 (radius-width+bevel,z),(radius-width,z+bevel),(root_radius-root_width,root)]
        for r,depth in profile:verts.append((cx+r*math.sin(theta),cy+r*math.cos(theta),depth))
    for i in range(segments):
        for j in range(6):k=(j+1)%6;faces.append((i*6+j,(i+1)*6+j,(i+1)*6+k,i*6+k))
    faces.append(tuple(reversed(range(6))));faces.append(tuple(segments*6+j for j in range(6)))
    mesh=bpy.data.meshes.new('Smooth thick visor');mesh.from_pydata(verts,[],faces);mesh.update()
    bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    assert all(len(e.link_faces)==2 for e in bm.edges),'Shade has an open thickness boundary'
    assert len(bm.verts)-len(bm.edges)+len(bm.faces)==2,'Shade thickness is not a closed shell'
    bm.to_mesh(mesh);bm.free();mesh.update()
    for f in mesh.polygons:f.use_smooth=len(f.vertices)==4
    mark=mesh.attributes.new('HoodFace','INT','FACE')
    for d in mark.data:d.value=1
    normals=[n.vector.copy() for n in mesh.corner_normals]
    # Analytic ruled-surface normals keep each long wall straight and smooth.
    for face in mesh.polygons:
        if face.index<segments*6 and face.index%6==0:
            for lid in face.loop_indices:
                vertex=mesh.loops[lid].vertex_index;station=vertex//6;theta=float(angles[station]);at_front=vertex%6==1
                radial=Vector((math.sin(theta),math.cos(theta),0));tangent=Vector((math.cos(theta),-math.sin(theta),0))*(radius if at_front else root_radius)
                if at_front:tangent.z=(front_z(spec,theta+.0001)-front_z(spec,theta-.0001))/.0002
                generator=radial*(radius-root_radius)+Vector((0,0,front_z(spec,theta)+bevel-root))
                normals[lid]=tangent.cross(generator).normalized()
    mesh.normals_split_custom_set(normals)
    attr=mesh.attributes.new('HoodNormal','FLOAT_VECTOR','CORNER')
    for d,n in zip(attr.data,normals):d.vector=n
    obj=bpy.data.objects.new('Rebuilt shade '+str(index+1),mesh);bpy.context.collection.objects.link(obj)
    root_measured=(mesh.vertices[0].co-mesh.vertices[5].co).length
    front_measured=(mesh.vertices[1].co-mesh.vertices[4].co).length
    lateral=max(math.hypot(mesh.vertices[i*6+1].co.x-mesh.vertices[i*6].co.x,mesh.vertices[i*6+1].co.y-mesh.vertices[i*6].co.y) for i in range(segments+1))
    return obj,{'centerMeters':spec['center'],'outerRadiusMeters':radius,'rootRadiusMeters':root_radius,'rootThicknessMm':root_width*1000,
                'frontThicknessMm':width*1000,'projectionMeters':root-min(front_z(spec,float(a)) for a in angles),
                'arcSegments':segments,'faces':len(mesh.polygons),'closedThickness':True,'sourceFitSamples':spec['fitSamples'],
                'measuredRootThicknessMm':root_measured*1000,'measuredFrontThicknessMm':front_measured*1000,
                'maximumTaperMm':lateral*1000,'straightWallGenerators':True,'quadWallFaces':segments*6}

def make_flange(spec,index):
    cx,cy=spec['center'];outer=spec['rootRadius']+.023;inner=spec['rootRadius']-spec['rootThickness'];segments=32
    profile=[(outer,-.211),(outer,-.245),(inner,-.245),(inner,-.211)]
    verts=[];faces=[]
    for i in range(segments):
        phi=2*math.pi*i/segments
        for radius,z in profile:verts.append((cx+radius*math.sin(phi),cy+radius*math.cos(phi),z))
    for i in range(segments):
        for j in range(4):faces.append((i*4+j,((i+1)%segments)*4+j,((i+1)%segments)*4+(j+1)%4,i*4+(j+1)%4))
    mesh=bpy.data.meshes.new('Clean circular attachment flange');mesh.from_pydata(verts,[],faces);mesh.update()
    bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    assert all(len(e.link_faces)==2 for e in bm.edges),'Root flange is open'
    bm.to_mesh(mesh);bm.free();mesh.update()
    for face in mesh.polygons:face.use_smooth=face.index%4 in (0,2)
    mark=mesh.attributes.new('HoodFace','INT','FACE')
    for datum in mark.data:datum.value=1
    normals=mesh.attributes.new('HoodNormal','FLOAT_VECTOR','CORNER')
    for datum,normal in zip(normals.data,mesh.corner_normals):datum.vector=normal.vector
    obj=bpy.data.objects.new('Smooth shade flange '+str(index+1),mesh);bpy.context.collection.objects.link(obj);return obj
