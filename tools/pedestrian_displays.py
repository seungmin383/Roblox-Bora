"""Closed rounded-rectangle pedestrian display plates, shades and screens."""
import bpy,bmesh,math
from mathutils import Vector
from signal_details import finish

def outline(w,h,r,segments=5):
    points=[]
    for cx,cy,start in ((w-r,h-r,0),(-w+r,h-r,90),(-w+r,-h+r,180),(w-r,-h+r,270)):
        for i in range(segments+1):
            a=math.radians(start+i*90/segments)
            points.append((cx+r*math.cos(a),cy+r*math.sin(a)))
    return points

def part(name,verts,faces,kind,section_size):
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(verts,[],faces);mesh.update()
    bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    assert all(len(e.link_faces)==2 for e in bm.edges),name+' is open'
    assert bm.calc_volume(signed=True)>0,name+' has inverted faces'
    bm.to_mesh(mesh);bm.free();mesh.update()
    sharp=mesh.attributes.new('sharp_edge','BOOLEAN','EDGE')
    for edge in mesh.edges:
        # A full perimeter is a crisp step. Long wall edges stay smooth around
        # the corner arcs, while each straight side remains a single plane.
        sharp.data[edge.index].value=edge.vertices[0]//section_size==edge.vertices[1]//section_size
    for f in mesh.polygons:f.use_smooth=len(f.vertices)==4
    tag=mesh.attributes.new('DisplayFace','INT','FACE');category=mesh.attributes.new('DisplayKind','INT','FACE')
    normals=mesh.attributes.new('DisplayNormal','FLOAT_VECTOR','CORNER')
    for f in mesh.polygons:tag.data[f.index].value=1;category.data[f.index].value=kind
    for d,n in zip(normals.data,mesh.corner_normals):d.vector=n.vector
    obj=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(obj);return obj

def loft_normals(obj,sections,n,closed=False):
    mesh=obj.data;values=[item.vector.copy() for item in mesh.corner_normals]
    for face in mesh.polygons:
        if len(face.vertices)!=4:continue
        station=min(mesh.loops[lid].vertex_index//n for lid in face.loop_indices)
        if closed and {mesh.loops[lid].vertex_index//n for lid in face.loop_indices}=={0,len(sections)-1}:station=len(sections)-1
        following=(station+1)%len(sections)
        for lid in face.loop_indices:
            vid=mesh.loops[lid].vertex_index;section=vid//n;i=vid%n;corner=i//6;step=i%6
            angle=math.radians(corner*90+step*18);radius,slope=sections[section]
            tangent=Vector((-radius*math.sin(angle),radius*math.cos(angle),-slope*radius*math.cos(angle)))
            generator=mesh.vertices[following*n+i].co-mesh.vertices[station*n+i].co
            normal=tangent.cross(generator).normalized()
            if normal.dot(face.normal)<0:normal=-normal
            values[lid]=normal
    mesh.normals_split_custom_set(values)
    for datum,normal in zip(mesh.attributes['DisplayNormal'].data,values):datum.vector=normal

def solid(name,cy,w,h,r,back,front,kind):
    verts=[];faces=[];bevel=.0015
    sections=[(w-bevel,h-bevel,r-bevel,back),(w,h,r,back-bevel),
              (w,h,r,front+bevel),(w-bevel,h-bevel,r-bevel,front)]
    n=len(outline(w,h,r))
    for sw,sh,sr,z in sections:
        verts.extend((x,y+cy,z) for x,y in outline(sw,sh,sr))
    faces.append(tuple(reversed(range(n))))
    for k in range(3):
        for i in range(n):j=(i+1)%n;faces.append((k*n+i,k*n+j,(k+1)*n+j,(k+1)*n+i))
    faces.append(tuple(3*n+i for i in range(n)))
    obj=part(name,verts,faces,kind,n);loft_normals(obj,[(sr,0) for sw,sh,sr,z in sections],n)
    return obj

def shade(cy,index):
    w,h,r=.151,.159,.035;tip=.007;root=.027;bevel=.001;verts=[];faces=[]
    def mouth(y):return -.094-.038*y/h
    profiles=[(w,h,r,'root'),(w,h,r,'mouthBevel'),(w-bevel,h-bevel,r-bevel,'mouth'),
              (w-tip+bevel,h-tip+bevel,.044,'mouth'),(w-tip,h-tip,.045,'mouthBevel'),
              (w-tip,h-tip,.060,'neck'),(.133,.140,.040,'funnel'),(.124,.132,.028,'screen'),(.124,.132,.028,'root')]
    n=len(outline(w,h,r))
    for sw,sh,sr,station in profiles:
        for x,y in outline(sw,sh,sr):
            z=mouth(y)+(bevel if station=='mouthBevel' else 0) if station.startswith('mouth') else {'root':-.006,'neck':-.048,'funnel':-.043,'screen':-.0185}[station]
            verts.append((x,y+cy,z))
    for k in range(len(profiles)):
        for i in range(n):j=(i+1)%n;faces.append((k*n+i,k*n+j,((k+1)%len(profiles))*n+j,((k+1)%len(profiles))*n+i))
    obj=part('Clean rectangular thick shade '+str(index+1),verts,faces,2,n)
    loft_normals(obj,[(sr,.038/h if station.startswith('mouth') else 0) for sw,sh,sr,station in profiles],n,True)
    return obj,{'centerMeters':[0,cy],'outerHalfWidthMeters':w,'outerHalfHeightMeters':h,
                'cornerRadiusMeters':r,'frontThicknessMm':tip*1000,'rootThicknessMm':root*1000,
                'perimeterVertices':n,'wallQuads':n*len(profiles),'closedThickness':True,'planarStraightWalls':True,
                'frontTopZ':mouth(h),'frontBottomZ':mouth(-h)}

def bolt(x,y,z,name,back=False):
    sides=6;verts=[];faces=[]
    # Flat hex head with a small edge chamfer, axis along the case normal.
    for radius,depth in ((.006,.006),(.007,.004),(.007,-.003),(.0055,-.005)):
        for i in range(sides):
            a=2*math.pi*i/sides;verts.append((x+radius*math.cos(a),y+radius*math.sin(a),z+(-depth if back else depth)))
    faces=[tuple(reversed(range(sides)))]
    for k in range(3):
        for i in range(sides):j=(i+1)%sides;faces.append((k*sides+i,k*sides+j,(k+1)*sides+j,(k+1)*sides+i))
    faces.append(tuple(3*sides+i for i in range(sides)))
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(verts,[],faces);mesh.update()
    obj=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(obj);return finish(obj,40,0)

def make_displays():
    parts=[];reports=[]
    for index,cy in enumerate((.1815,-.2075)):
        parts.append(solid('Clean display attachment plate '+str(index+1),cy,.160,.170,.009,.015,-.006,1))
        hood,report=shade(cy,index);parts.append(hood)
        parts.append(solid('Flat pedestrian display panel '+str(index+1),cy,.1255,.1335,.028,-.003,-.0185,3))
        for sx in (-1,1):
            for sy in (-1,1):parts.append(bolt(sx*.148,cy+sy*.157,-.010,'Clean display plate bolt'))
        report.update({'plateHalfWidthMeters':.160,'plateHalfHeightMeters':.170,'screenFrontZ':-.0185,
                       'screenFlat':True,'plateClosed':True,'screenClosed':True,'plateBolts':4})
        reports.append(report)
    for x,y in ((-.179,.363),(.179,.363),(0,.374)):
        parts.append(bolt(x,y,.006,'Clean case front bolt'))
    return parts,reports
