"""Fitted case, shades and optics, preserving the separate Tripo attachments."""
import bpy,bmesh,sys,math
from pathlib import Path
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).resolve().parent))
from vehicle_mesh_ops import partition,box
from signal_hoods import fit as fit_hoods,make as make_hood,make_flange
from signal_optics import fit_optics,make_optics
from signal_details import keep_front_fasteners,make_clips,make_top_ribs,report as detail_report
from pedestrian_displays import make_displays

def stitch_boundary(bm,tolerance=.000002):
    """Split collinear T-junctions left by clipped polygon partitions."""
    edges=[e for e in bm.edges if e.is_boundary]
    vertices={v for e in edges for v in e.verts};splits=0
    for edge in edges:
        if not edge.is_valid:continue
        a,b=edge.verts;origin=a.co.copy();direction=b.co-origin;length2=direction.length_squared
        if length2<tolerance*tolerance:continue
        candidates=[]
        for vertex in vertices:
            if vertex in (a,b):continue
            t=(vertex.co-origin).dot(direction)/length2
            if .000001<t<.999999 and (vertex.co-(origin+direction*t)).length<tolerance:candidates.append((t,vertex.co.copy()))
        previous=0;current=edge;start=a
        for t,position in sorted(candidates,key=lambda p:p[0]):
            if t-previous<.000001:continue
            extra,new_vertex=bmesh.utils.edge_split(current,start,(t-previous)/(1-previous));new_vertex.co=position
            current=next(e for e in (current,extra) if b in e.verts);start=new_vertex;previous=t;splits+=1
    if splits:bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=tolerance)
    return splits

def pedestrian_case():
    # Large upper XY corner rounds and a small front/back bevel are separate.
    # A uniform cube bevel would incorrectly change the thin case's silhouette.
    profiles=[(.014,.007),(.016,.002),(.021,0),(.116,0),(.121,.002),(.123,.007)]
    vertices=[];faces=[]
    for z,inset in profiles:
        x=.212-inset;y0=-.410+inset;y1=.409-inset
        for cx,cy,start,r in [(x-max(.001,.006-inset),y0+max(.001,.006-inset),-90,max(.001,.006-inset)),
                              (x-(.055-inset),y1-(.055-inset),0,.055-inset),
                              (-x+(.055-inset),y1-(.055-inset),90,.055-inset),
                              (-x+max(.001,.006-inset),y0+max(.001,.006-inset),180,max(.001,.006-inset))]:
            for i in range(4):
                a=math.radians(start+i*30);vertices.append((cx+r*math.cos(a),cy+r*math.sin(a),z))
    n=16;faces.append(tuple(reversed(range(n))))
    for k in range(len(profiles)-1):
        for i in range(n):j=(i+1)%n;faces.append((k*n+i,k*n+j,(k+1)*n+j,(k+1)*n+i))
    faces.append(tuple((len(profiles)-1)*n+i for i in range(n)))
    mesh=bpy.data.meshes.new('Connected rectangular case with rounded top corners');mesh.from_pydata(vertices,[],faces);mesh.update()
    obj=bpy.data.objects.new('PedestrianSignal_Housing',mesh);bpy.context.collection.objects.link(obj);return obj

def rebuild(source,name):
    traffic=name=='TrafficSignal'
    low=Vector((-1.009,-.363,-.200) if traffic else (-.212,-.410,.014))
    high=Vector((1.009,.338,.552) if traffic else (.212,.409,.123))
    radius=.020 if traffic else .007
    bpy.ops.object.select_all(action='DESELECT')
    if traffic:
        bpy.ops.mesh.primitive_cube_add(size=1,location=(low+high)*.5)
        case=bpy.context.object;case.name=name+'_Housing';case.scale=high-low
        bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
        bevel=case.modifiers.new('Uniform three-step corner bevel','BEVEL');bevel.width=radius;bevel.segments=3
        bpy.ops.object.modifier_apply(modifier=bevel.name)
    else:
        case=pedestrian_case();bpy.context.view_layer.objects.active=case
    if traffic:
        bm=bmesh.new();bm.from_mesh(case.data);bm.normal_update()
        front=max((f for f in bm.faces if f.normal.z<-.99),key=lambda f:f.calc_area())
        bmesh.ops.inset_region(bm,faces=[front],thickness=.025,depth=.009,use_even_offset=True)
        bm.normal_update()
        back=max((f for f in bm.faces if f.normal.z>.99),key=lambda f:f.calc_area())
        bmesh.ops.inset_region(bm,faces=[back],thickness=.008,depth=-.015,use_even_offset=True)
        bm.normal_update()
        center=max((f for f in bm.faces if f.normal.z>.99),key=lambda f:f.calc_area())
        bmesh.ops.inset_region(bm,faces=[center],thickness=.005,depth=.017,use_even_offset=True)
        bm.to_mesh(case.data);bm.free();case.data.update()
    for f in case.data.polygons:f.use_smooth=len(f.vertices)<=4 and max(abs(a) for a in f.normal)<.999
    # A closed shell and axis-aligned long runs are the point of this rebuild.
    bm=bmesh.new();bm.from_mesh(case.data)
    assert all(len(e.link_faces)==2 for e in bm.edges),'Housing has an open edge'
    long_edges=[e for e in bm.edges if e.calc_length()>.15]
    vectors=[tuple(e.verts[1].co-e.verts[0].co) for e in long_edges]
    deviations=[math.degrees(math.acos(min(1,max(abs(v) for v in d)/math.sqrt(sum(v*v for v in d))))) for d in vectors]
    assert max(deviations,default=0)<.01,'A long housing edge is not straight along its axis'
    assert len(bm.verts)-len(bm.edges)+len(bm.faces)==2,'Housing is not a single closed shell'
    bm.free()
    # Preserve these clean corner normals through later source-normal transfer.
    marker=case.data.attributes.new('HousingFace','INT','FACE')
    for datum in marker.data:datum.value=1
    normal=case.data.attributes.new('HousingNormal','FLOAT_VECTOR','CORNER')
    for datum,n in zip(normal.data,case.data.corner_normals):datum.vector=n.vector
    case_faces=len(case.data.polygons);case_verts=len(case.data.vertices)
    source.data.calc_loop_triangles()
    triangles=[[tuple(source.data.vertices[i].co) for i in tri.vertices] for tri in source.data.loop_triangles]
    hood_specs=fit_hoods(source) if traffic else []
    if traffic:
        regions=[('Lamps',[((0,0,1),-.213)],2,-.209),
                 ('Right vents',box(1.012,1.10,-.32,.30,-.18,.51),0,1.009),
                 ('Left vents',box(-1.10,-1.012,-.32,.30,-.18,.51),0,-1.009)]
        for sx in (-1,1):
            for sy in (-1,1):
                x0,x1=(.88,.98) if sx>0 else (-.98,-.88)
                y0,y1=(.24,.315) if sy>0 else (-.338,-.24)
                regions.append(('Rear fastener',box(x0,x1,y0,y1,.558,.62),2,.554))
    else:
        regions=[('Rear fasteners',[((0,0,-1),-.126)],2,.123)]
    pieces=[];region_stats=[]
    for label,planes,axis,attachment in regions:
        vertices=[];faces=[]
        for tri in triangles:
            inside,_=partition(tri,planes)
            if len(inside)<3:continue
            parts=[inside]
            if label=='Lamps':
                center_x=sum(v[0] for v in inside)/len(inside)
                spec=min(hood_specs,key=lambda s:abs(center_x-s['center'][0]))
                parts=keep_front_fasteners(inside)
            for part in parts:
                for i in range(1,len(part)-1):
                    a,b,c=[Vector(p) for p in (part[0],part[i],part[i+1])]
                    if (b-a).cross(c-a).length<1e-10:continue
                    start=len(vertices);vertices.extend((a,b,c));faces.append((start,start+1,start+2))
        if not faces:continue
        mesh=bpy.data.meshes.new(label);mesh.from_pydata(vertices,[],faces);mesh.update()
        bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.000001)
        # Sink the clipped attachment boundary into its new flat housing wall.
        for v in bm.verts:
            if any(e.is_boundary for e in v.link_edges):
                if label!='Lamps' or abs(v.co.z+.213)<.00001:v.co[axis]=attachment
        stitch_boundary(bm)
        boundary=[e for e in bm.edges if e.is_boundary]
        if label=='Lamps' and boundary:
            old_vertices=set(bm.verts)
            extruded=bmesh.ops.extrude_edge_only(bm,edges=boundary)
            for element in extruded['geom']:
                if isinstance(element,bmesh.types.BMVert) and element not in old_vertices:
                    near=min(hood_specs,key=lambda s:abs(element.co.x-s['center'][0]))
                    cx,cy=near['center']
                    element.co.z=-.250 if math.hypot(element.co.x-cx,element.co.y-cy)<.305 else attachment
            bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.000001)
            bmesh.ops.dissolve_degenerate(bm,dist=.0000001,edges=list(bm.edges))
            boundary=[e for e in bm.edges if e.is_boundary]
        if boundary:bmesh.ops.holes_fill(bm,edges=boundary,sides=0)
        bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(mesh);bm.free();mesh.update()
        for f in mesh.polygons:f.use_smooth=True
        obj=bpy.data.objects.new(label,mesh);bpy.context.collection.objects.link(obj);pieces.append(obj)
        region_stats.append({'detail':label,'faces':len(mesh.polygons)})
    hood_reports=[];optic_reports=[];detail_parts=[]
    for index,spec in enumerate(hood_specs):
        obj,report=make_hood(spec,index);pieces.append(obj);hood_reports.append(report)
        flange=make_flange(spec,index);pieces.append(flange);report['cleanRootFlange']=True
        optical=fit_optics(source,spec)
        optics,optic_report=make_optics(optical,index);pieces.extend(optics);optic_reports.append(optic_report)
        detail_parts.extend(make_clips(spec,optical,index))
    if traffic:detail_parts.extend(make_top_ribs())
    details=detail_report(detail_parts);pieces.extend(detail_parts)
    display_reports=[]
    if not traffic:
        display_parts,display_reports=make_displays();pieces.extend(display_parts)
    bpy.ops.object.select_all(action='DESELECT');case.select_set(True)
    for o in pieces:o.select_set(True)
    bpy.context.view_layer.objects.active=case;bpy.ops.object.join()
    case.name=name+'_Clean'
    return case,{'method':'Fitted housing with connected uniform bevel strips; original clipped Tripo details',
                 'housingFaces':case_faces,'housingVertices':case_verts,'bevelRadiusMeters':radius,'bevelSegments':3,
                 'upperCornerRadiusMeters':(.020 if traffic else .055),'housingClosed':True,
                 'longStraightEdges':len(long_edges),'maxLongEdgeDeviationDegrees':max(deviations,default=0),
                 'fittedLowMeters':list(low),'fittedHighMeters':list(high),'details':region_stats,
                 'rebuiltHoods':hood_reports,
                 'rebuiltOptics':optic_reports,
                 'rebuiltDetails':details,
                 'rebuiltDisplays':display_reports,
                 'straightEdgeRuns':True,'continuousHousing':True}
