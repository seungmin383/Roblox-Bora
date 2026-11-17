"""Simple closed replacement clips and straight shallow case ribs."""
import bpy,bmesh,math
from mathutils import Vector
from vehicle_mesh_ops import partition,box

def finish(obj,kind,bevel=.002):
    bpy.context.view_layer.objects.active=obj
    if bevel:
        modifier=obj.modifiers.new('Small manufactured edge chamfer','BEVEL');modifier.width=bevel;modifier.segments=1
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    mesh=obj.data;bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    assert all(len(e.link_faces)==2 for e in bm.edges),'Replacement detail has an open edge'
    assert len(bm.verts)-len(bm.edges)+len(bm.faces)==2,'Replacement detail is not one solid'
    assert bm.calc_volume(signed=True)>0,'Replacement detail is inverted'
    bm.to_mesh(mesh);bm.free();mesh.update()
    for f in mesh.polygons:f.use_smooth=False
    tag=mesh.attributes.new('DetailFace','INT','FACE');category=mesh.attributes.new('DetailKind','INT','FACE')
    normals=mesh.attributes.new('DetailNormal','FLOAT_VECTOR','CORNER')
    for face in mesh.polygons:
        tag.data[face.index].value=1;category.data[face.index].value=kind
        for lid in face.loop_indices:normals.data[lid].vector=face.normal
    return obj

def block(name,center,dimensions,kind,bevel=.002):
    bpy.ops.object.select_all(action='DESELECT');bpy.ops.mesh.primitive_cube_add(size=1,location=center)
    obj=bpy.context.object;obj.name=name;obj.scale=dimensions
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    return finish(obj,kind,bevel)

def prism(name,profile,origin,u,v,w,width,kind,bevel=.002):
    origin,u,v,w=map(Vector,(origin,u,v,w));vertices=[];n=len(profile)
    for side in (-1,1):
        for a,b in profile:vertices.append(origin+u*a+v*b+w*(side*width/2))
    faces=[tuple(reversed(range(n))),tuple(n+i for i in range(n))]
    for i in range(n):j=(i+1)%n;faces.append((i,j,n+j,n+i))
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(vertices,[],faces);mesh.update()
    obj=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(obj)
    return finish(obj,kind,bevel)

def keep_front_fasteners(poly):
    remaining=[poly];result=[]
    for sx in (-1,1):
        for sy in (-1,1):
            x0,x1=(.88,.98) if sx>0 else (-.98,-.88)
            y0,y1=(.23,.32) if sy>0 else (-.34,-.24)
            after=[]
            for part in remaining:
                inside,outside=partition(part,box(x0,x1,y0,y1,-.27,-.209));after.extend(outside)
                if len(inside)>=3:result.append(inside)
            remaining=after
    return result

def edited_source_detail(point,hoods):
    """Regions intentionally simplified, rather than fitted to Tripo dents."""
    x,y,z=point
    if .337<y<.405 and .42<abs(x)<.94 and -.065<z<.415:return True
    for spec in hoods:
        cx,cy=spec['center'];dx=abs(x-cx);dy=y-cy
        if .095<dx<.27 and -.425<z<-.203 and (-.300<dy<-.100 or .180<dy<.300):return True
    return False

def make_clips(hood,optical,index):
    parts=[];cx,cy=hood['center']
    # The short rear shoe meets the case, and the front tongue sits above it.
    upper=[(-.018,-.207),(.018,-.207),(.018,-.304),(-.023,-.304),(-.023,-.250),(-.018,-.250)]
    for side in (-1,1):
        parts.append(prism('Clean upper mounting shoe %d %d'%(index+1,side),upper,
                           (cx+side*.163,cy+.215,0),(0,1,0),(0,0,1),(1,0,0),.066,1,.0025))
    cx,cy=optical['center']
    lower=[(.195,-.367),(.195,-.390),(.234,-.390),(.248,-.371),
           (.248,-.300),(.282,-.300),(.282,-.267),(.230,-.267),(.230,-.358),(.217,-.367)]
    for side in (-1,1):
        angle=side*math.radians(135);radial=(math.sin(angle),math.cos(angle),0);tangent=(math.cos(angle),-math.sin(angle),0)
        parts.append(prism('Clean lower retaining latch %d %d'%(index+1,side),lower,
                           (cx,cy,0),radial,(0,0,1),tangent,.035,2,.002))
    return parts

def make_top_ribs():
    parts=[]
    # A shallow carrier with four straight ribs keeps the source silhouette.
    outline=[(.790,.008),(.892,.008),(.899,-.038),(.909,-.038),(.892,.078),
             (.914,.120),(.914,.228),(.892,.271),(.909,.388),(.895,.388),(.790,.342)]
    for side in (-1,1):
        parts.append(prism('Clean top rib carrier '+str(side),outline,(0,.344,0),(side,0,0),(0,0,1),(0,1,0),.014,3,.0015))
        parts.append(block('Clean raised carrier pad '+str(side),(side*.852,.356,.174),(.086,.018,.076),3,.002))
        for z in (.022,.106,.241,.326):
            parts.append(block('Straight top rib %.3f %d'%(z,side),(side*.617,.3415,z),(.358,.009,.009),3,.001))
    return parts

def report(parts):
    result=[]
    for obj in parts:
        mesh=obj.data;kind=mesh.attributes['DetailKind'].data[0].value
        result.append({'name':obj.name,'kind':kind,'faces':len(mesh.polygons),'closed':True,
                       'lowMeters':[min(v.co[i] for v in mesh.vertices) for i in range(3)],
                       'highMeters':[max(v.co[i] for v in mesh.vertices) for i in range(3)]})
    return result
