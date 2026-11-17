"""Conservative planar repair and editing topology; source assets stay intact.
Produces independent asset candidates, never a Place or an in-game replacement.
"""
from pathlib import Path
import bpy,bmesh,numpy as np,math,json,struct,hashlib,sys
from mathutils import Vector,Matrix
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from signal_housing import rebuild,stitch_boundary
from signal_details import edited_source_detail
from signal_hoods import fit as fit_hoods
OUT=ROOT/'assets/traffic/retopology';OUT.mkdir(exist_ok=True)
PREVIEW=ROOT/'dist/preview';reports=[]
protected=[ROOT/'Ro.rbxlx']+[ROOT/'assets/traffic/local'/f'{name}.{extension}' for name in ('TrafficSignal','PedestrianSignal') for extension in ('blend','mesh','png')]
fingerprints={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in protected}
bpy.context.preferences.filepaths.save_version=0

def topology(mesh):
    mesh.calc_loop_triangles()
    return {'vertices':len(mesh.vertices),'faces':len(mesh.polygons),'triangles':len(mesh.loop_triangles),
            'quads':sum(len(f.vertices)==4 for f in mesh.polygons),'ngons':sum(len(f.vertices)>4 for f in mesh.polygons)}

def boundary_count(mesh):
    bm=bmesh.new();bm.from_mesh(mesh)
    answer=sum(e.is_boundary for e in bm.edges);bm.free();return answer

def samples(mesh):
    mesh.calc_loop_triangles();points=[v.co.copy() for v in mesh.vertices]
    points.extend(sum((mesh.vertices[i].co for i in t.vertices),Vector())/3 for t in mesh.loop_triangles)
    return points

def deviation(a,b,detail_test=lambda p:False):
    b.calc_loop_triangles();tree=BVHTree.FromPolygons([v.co for v in b.vertices],[tuple(t.vertices) for t in b.loop_triangles],all_triangles=True)
    points=samples(a);ranked=[];details=[]
    for p in points:
        (details if detail_test(p) else ranked).append((tree.find_nearest(p)[3],tuple(p)))
    ranked.sort(reverse=True);details.sort(reverse=True)
    print('Surface check:',ranked[:3],flush=True)
    if details:print('Simplified source detail check:',details[:3],flush=True)
    return ranked[0][0],details[0][0] if details else 0

def exposed_deviation(a,b,separate_details=False):
    """Ignore buried attachment caps and housing behind opaque lamp assemblies."""
    a.calc_loop_triangles();b.calc_loop_triangles()
    own=BVHTree.FromPolygons([v.co for v in a.vertices],[tuple(t.vertices) for t in a.loop_triangles],all_triangles=True)
    other=BVHTree.FromPolygons([v.co for v in b.vertices],[tuple(t.vertices) for t in b.loop_triangles],all_triangles=True)
    distances=[];details=[];detail_tag=a.attributes.get('DetailFace') if separate_details else None
    for tri in a.loop_triangles:
        points=[a.vertices[i].co for i in tri.vertices];normal=tri.normal
        for weights in ((1/3,1/3,1/3),(.8,.1,.1),(.1,.8,.1),(.1,.1,.8)):
            p=sum((v*w for v,w in zip(points,weights)),Vector())
            hit=own.ray_cast(p+normal*5,-normal,5.0001)
            if hit[0] is not None and (hit[0]-p).length<.00002:
                target=details if detail_tag and detail_tag.data[tri.polygon_index].value else distances
                target.append((other.find_nearest(p)[3],tuple(p)))
    distances.sort(reverse=True);print('Exposed surface check:',distances[:3],flush=True)
    details.sort(reverse=True)
    if details:print('Simplified detail exposed surface check:',details[:3],flush=True)
    return distances[0][0],details[0][0] if details else 0

def plane_repair(mesh,tolerance):
    points=np.array([v.co[:] for v in mesh.vertices],dtype=float)
    faces=[list(f.vertices) for f in mesh.polygons]
    normals=np.array([f.normal[:] for f in mesh.polygons]);centers=np.array([points[f].mean(axis=0) for f in faces]);areas=np.array([f.area for f in mesh.polygons])
    diagonal=float(np.linalg.norm(np.ptp(points,axis=0)));min_area=diagonal**2*.008
    used=set();patches=[]
    for axis in range(3):
        for sign in (-1,1):
            candidates=np.where(normals[:,axis]*sign>math.cos(math.radians(18)))[0]
            if not len(candidates):continue
            step=tolerance*2
            bins=np.round(centers[candidates,axis]/step).astype(int)
            for bucket in sorted(set(bins),key=lambda k:-areas[candidates[bins==k]].sum()):
                cluster=[int(i) for i in candidates[np.abs(bins-bucket)<=1] if int(i) not in used]
                if len(cluster)<8 or areas[cluster].sum()<min_area:continue
                ids=np.unique(np.concatenate([faces[i] for i in cluster]));cloud=points[ids]
                center=cloud.mean(axis=0);_,_,basis=np.linalg.svd(cloud-center,full_matrices=False);normal=basis[-1]
                if abs(normal[axis])<math.cos(math.radians(8)):continue
                accepted=[i for i in cluster if np.max(np.abs((points[faces[i]]-center)@normal))<tolerance]
                if len(accepted)<8 or areas[accepted].sum()<min_area:continue
                ids=np.unique(np.concatenate([faces[i] for i in accepted]));cloud=points[ids]
                center=cloud.mean(axis=0);_,_,basis=np.linalg.svd(cloud-center,full_matrices=False);normal=basis[-1]
                offsets=(cloud-center)@normal
                if np.max(np.abs(offsets))>tolerance:continue
                points[ids]-=offsets[:,None]*normal;used.update(accepted)
                patches.append({'axis':'XYZ'[axis],'faces':len(accepted),'areaM2':float(areas[accepted].sum()),'maxMoveMm':float(np.max(np.abs(offsets))*1000)})
    for v,p in zip(mesh.vertices,points):v.co=p
    mesh.update();return patches

def aim(item,target):
    direction=(Vector(target)-item.location).normalized();right=direction.cross(Vector((0,1,0))).normalized();up=right.cross(direction)
    item.rotation_euler=Matrix((right,up,-direction)).transposed().to_euler()

def bake_clean_hood_paint(clean,image,tag_name='HoodFace',tag_value=1,color=(.035,.041,.047,1)):
    """Use clean paint on the remade shade, not baked dents from the old wall."""
    if not clean.data.attributes.get(tag_name):return
    mesh=clean.data.copy();bm=bmesh.new();bm.from_mesh(mesh);tag=bm.faces.layers.int.get(tag_name)
    bmesh.ops.delete(bm,geom=[f for f in bm.faces if f[tag]!=tag_value],context='FACES');bm.to_mesh(mesh);bm.free()
    target=bpy.data.objects.new('Temporary visor paint bake',mesh);bpy.context.collection.objects.link(target)
    mat=bpy.data.materials.new('Uniform charcoal visor paint');mat.use_nodes=True
    nodes=mat.node_tree.nodes;emission=nodes.new('ShaderNodeEmission');emission.inputs['Color'].default_value=color
    mat.node_tree.links.new(emission.outputs[0],nodes.get('Material Output').inputs['Surface'])
    tex=nodes.new('ShaderNodeTexImage');tex.image=image;nodes.active=tex
    mesh.materials.clear();mesh.materials.append(mat)
    for f in mesh.polygons:f.material_index=0
    bpy.ops.object.select_all(action='DESELECT');target.select_set(True);bpy.context.view_layer.objects.active=target
    bake=bpy.context.scene.render.bake;bake.use_selected_to_active=False;bake.use_clear=False
    bpy.ops.object.bake(type='EMIT');image.save()
    bpy.data.objects.remove(target,do_unlink=True)
    clean.select_set(True);bpy.context.view_layer.objects.active=clean;bake.use_selected_to_active=True;bake.use_clear=True

names=('TrafficSignal',) if '--traffic' in sys.argv else (('PedestrianSignal',) if '--pedestrian' in sys.argv else ('TrafficSignal','PedestrianSignal'))
for name in names:
    bpy.ops.wm.open_mainfile(filepath=str(ROOT/'assets/traffic/local'/f'{name}.blend'))
    bpy.context.preferences.filepaths.save_version=0
    source=next(o for o in bpy.context.scene.objects if o.type=='MESH');source.name=name+'_Reference'
    clean,housing=rebuild(source,name)
    before=topology(source.data);boundaries=boundary_count(source.data)
    tolerance=.0025 if name=='TrafficSignal' else .0012
    patches=[]
    # The color is rebaked below, so old UV cuts must not block planar merges.
    while clean.data.uv_layers:clean.data.uv_layers.remove(clean.data.uv_layers[0])
    bm=bmesh.new();bm.from_mesh(clean.data);bm.normal_update()
    bmesh.ops.dissolve_degenerate(bm,dist=.0000001,edges=list(bm.edges))
    owned=bm.faces.layers.int.get('HousingFace')
    hood_layer=bm.faces.layers.int.get('HoodFace')
    optic_layer=bm.faces.layers.int.get('OpticFace')
    detail_layer=bm.faces.layers.int.get('DetailFace')
    display_layer=bm.faces.layers.int.get('DisplayFace')
    protected_face=lambda f:bool(f[owned] or (hood_layer and f[hood_layer]) or (optic_layer and f[optic_layer]) or (detail_layer and f[detail_layer]) or (display_layer and f[display_layer]))
    detail_edges=[e for e in bm.edges if all(not protected_face(f) for f in e.link_faces)]
    detail_verts=[v for v in bm.verts if all(not protected_face(f) for f in v.link_faces)]
    bmesh.ops.dissolve_limit(bm,angle_limit=math.radians(.5),use_dissolve_boundaries=False,verts=detail_verts,edges=detail_edges,delimit={'MATERIAL','SHARP'})
    bmesh.ops.join_triangles(bm,faces=[f for f in bm.faces if not protected_face(f)],angle_face_threshold=math.radians(12),angle_shape_threshold=math.radians(40),cmp_uvs=False,cmp_materials=True,cmp_seam=False,cmp_sharp=True)
    bm.to_mesh(clean.data);bm.free();clean.data.update()
    # Measure both directions; merging a nonplanar pair can otherwise go unseen.
    hoods=fit_hoods(source) if housing.get('rebuiltDetails') else []
    original_distance,source_detail_distance=deviation(source.data,clean.data,lambda p:edited_source_detail(p,hoods) if hoods else False)
    exposed_distance,exposed_detail_distance=exposed_deviation(clean.data,source.data,bool(housing.get('rebuiltDetails')))
    error=max(original_distance,exposed_distance,source_detail_distance,exposed_detail_distance)
    print('Original/exposed candidate surface distances:',original_distance,exposed_distance,flush=True)
    source_error_limit=.020 if name=='TrafficSignal' or housing.get('rebuiltDisplays') else .006
    exposed_error_limit=.030 if housing.get('rebuiltHoods') else source_error_limit
    error_limit=max(source_error_limit,exposed_error_limit,.050 if housing.get('rebuiltDetails') else 0)
    assert original_distance<source_error_limit and exposed_distance<exposed_error_limit,('Remodeled surface differs too much',name,error)
    assert max(source_detail_distance,exposed_detail_distance)<.050,'Simplified detail exceeds its 50 mm silhouette envelope'
    if '--validate-only' in sys.argv:continue
    if boundary_count(clean.data)>boundaries:
        bm=bmesh.new();bm.from_mesh(clean.data);edges=[e for e in bm.edges if e.is_boundary]
        print('Remaining detail boundary edges',len(edges),[tuple(e.verts[0].co) for e in edges[:12]],flush=True)
        print('Stitched detail T-junctions',stitch_boundary(bm),flush=True)
        edges=[e for e in bm.edges if e.is_boundary]
        if len(edges)<16:
            bmesh.ops.remove_doubles(bm,verts=list({v for e in edges for v in e.verts}),dist=.001)
            bmesh.ops.dissolve_degenerate(bm,edges=[e for e in bm.edges if e.is_boundary],dist=.000001)
            edges=[e for e in bm.edges if e.is_boundary]
        repaired=bmesh.ops.holes_fill(bm,edges=edges,sides=0)
        print('Filled remaining detail gaps',len(repaired.get('faces',[])),flush=True)
        bm.to_mesh(clean.data);bm.free();clean.data.update()
    bm=bmesh.new();bm.from_mesh(clean.data);body_tag=bm.faces.layers.int.get('HousingFace');hood_tag=bm.faces.layers.int.get('HoodFace');optic_tag=bm.faces.layers.int.get('OpticFace')
    detail_tag=bm.faces.layers.int.get('DetailFace')
    display_tag=bm.faces.layers.int.get('DisplayFace')
    manufactured_boundaries=sum(e.is_boundary and any(f[body_tag] or (hood_tag and f[hood_tag]) or (optic_tag and f[optic_tag]) or (detail_tag and f[detail_tag]) or (display_tag and f[display_tag]) for f in e.link_faces) for e in bm.edges)
    bm.free();assert manufactured_boundaries==0,'Rebuilt wall thickness has an open edge'
    after=topology(clean.data)
    print('Mesh counts',before,after,flush=True)
    # Rebuilt shades now include real inner walls and capped thickness.
    # Complete thick optics have their own loops and lens back faces, in
    # addition to the existing closed shades. Budget the full assembly.
    triangle_budget=9000 if housing.get('rebuiltOptics') else (8000 if housing.get('rebuiltHoods') else before['triangles'])
    assert after['faces']<before['faces'] and after['triangles']<=triangle_budget
    # Preserve the original smooth shading independently of new internal edges.
    bpy.ops.object.select_all(action='DESELECT');clean.select_set(True);bpy.context.view_layer.objects.active=clean
    transfer=clean.modifiers.new('Preserve source shading','DATA_TRANSFER');transfer.object=source;transfer.use_loop_data=True;transfer.data_types_loops={'CUSTOM_NORMAL'};transfer.loop_mapping='POLYINTERP_NEAREST'
    bpy.ops.object.modifier_apply(modifier=transfer.name)
    # A broad repaired plane needs a flat normal. Transferring the old noisy
    # normals there would leave dents in the shading despite the flat geometry.
    mesh=clean.data;loop_normals=[n.vector.copy() for n in mesh.corner_normals]
    diagonal=(Vector(tuple(max(v.co[i] for v in mesh.vertices) for i in range(3)))-Vector(tuple(min(v.co[i] for v in mesh.vertices) for i in range(3)))).length
    for face in mesh.polygons:
        if mesh.attributes['HousingFace'].data[face.index].value:
            for lid in face.loop_indices:loop_normals[lid]=mesh.attributes['HousingNormal'].data[lid].vector.copy()
        elif mesh.attributes.get('HoodFace') and mesh.attributes['HoodFace'].data[face.index].value:
            for lid in face.loop_indices:loop_normals[lid]=mesh.attributes['HoodNormal'].data[lid].vector.copy()
        elif mesh.attributes.get('OpticFace') and mesh.attributes['OpticFace'].data[face.index].value:
            for lid in face.loop_indices:loop_normals[lid]=mesh.attributes['OpticNormal'].data[lid].vector.copy()
        elif face.area>diagonal**2*.002:
            for lid in face.loop_indices:loop_normals[lid]=face.normal.copy()
    mesh.normals_split_custom_set(loop_normals)
    # Repack and bake the source color, rather than stretch the old UV mapping.
    bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.uv.smart_project(angle_limit=math.radians(66),island_margin=.015);bpy.ops.object.mode_set(mode='OBJECT')
    for slot in source.material_slots:
        if not slot.material:continue
        material=slot.material.copy();slot.material=material;nodes=material.node_tree.nodes;shader=next(n for n in nodes if n.type=='BSDF_PRINCIPLED');output=next(n for n in nodes if n.type=='OUTPUT_MATERIAL');emission=nodes.new('ShaderNodeEmission')
        links=shader.inputs['Base Color'].links
        if links:material.node_tree.links.new(links[0].from_socket,emission.inputs['Color'])
        else:emission.inputs['Color'].default_value=shader.inputs['Base Color'].default_value
        material.node_tree.links.new(emission.outputs[0],output.inputs['Surface'])
    material=bpy.data.materials.new(name+'_Rebaked');material.use_nodes=True
    shader=material.node_tree.nodes.get('Principled BSDF');shader.inputs['Roughness'].default_value=.75;shader.inputs['Metallic'].default_value=.10
    image=bpy.data.images.new(name+'_Clean_Albedo',width=1024,height=1024,alpha=False);image.filepath_raw=str(OUT/f'{name}_Clean.png');image.file_format='PNG'
    tex=material.node_tree.nodes.new('ShaderNodeTexImage');tex.image=image;material.node_tree.nodes.active=tex
    clean.data.materials.clear();clean.data.materials.append(material)
    for face in clean.data.polygons:face.material_index=0
    source.hide_set(False);source.hide_render=False;source.select_set(True);clean.select_set(True);bpy.context.view_layer.objects.active=clean
    scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=1
    scene.render.bake.use_selected_to_active=True;scene.render.bake.cage_extrusion=error_limit*1.2;scene.render.bake.max_ray_distance=error_limit*2;scene.render.bake.margin=12
    bpy.ops.object.bake(type='EMIT');image.save();material.node_tree.links.new(tex.outputs['Color'],shader.inputs['Base Color'])
    source.hide_render=True;source.hide_set(True);source.select_set(False)
    bake_clean_hood_paint(clean,image)
    bake_clean_hood_paint(clean,image,'OpticKind',1)
    bake_clean_hood_paint(clean,image,'OpticKind',2,(.008,.012,.016,1))
    bake_clean_hood_paint(clean,image,'DetailFace')
    for kind in (1,2):bake_clean_hood_paint(clean,image,'DisplayKind',kind)
    bake_clean_hood_paint(clean,image,'DisplayKind',3,(.008,.012,.016,1))
    clean['TopologyCleanup']='Connected housing, thick sunshades, concentric optics; closed simple retaining clips and straight top ribs'
    if housing.get('rebuiltDisplays'):clean['TopologyCleanup']='Preserved case; closed rectangular thick sunshades, flat display panels and attachment plates; simple hex fasteners'
    clean['MaximumSurfaceDeviationMm']=error*1000
    # Edit-mode UV packing can re-encode split normals at sharp optical steps.
    # Restore the manufactured normals on the final mesh, after all edit-mode
    # operations, so the exported and saved surfaces use the same values.
    normals=[item.vector.copy() for item in clean.data.corner_normals]
    for face in clean.data.polygons:
        for prefix in ('Housing','Hood','Optic','Detail','Display'):
            marker=clean.data.attributes.get(prefix+'Face')
            if marker and marker.data[face.index].value:
                expected=clean.data.attributes[prefix+'Normal']
                for lid in face.loop_indices:normals[lid]=expected.data[lid].vector.copy()
                break
    clean.data.normals_split_custom_set(normals)
    # Native candidate has its own filename and is not installed into Studio.
    mesh=clean.data;mesh.calc_loop_triangles();uv=mesh.uv_layers.active;rows=[];indices=[];lookup={}
    for tri in mesh.loop_triangles:
        points=[mesh.vertices[i].co for i in tri.vertices];geometric=(points[1]-points[0]).cross(points[2]-points[0])
        if geometric.length<.000000000001:continue
        geometric.normalize()
        face=[]
        for lid in tri.loops:
            loop=mesh.loops[lid];p=mesh.vertices[loop.vertex_index].co;n=mesh.corner_normals[lid].vector.normalized();t=uv.data[lid].uv
            if n.length<.5:n=geometric
            packed=struct.pack('<8f4b4B',*p,*n,t.x,1-t.y,0,0,0,127,255,255,255,255)
            if packed not in lookup:lookup[packed]=len(rows);rows.append(packed)
            face.append(lookup[packed])
        indices.append(face)
    after['editingTriangles']=after['triangles'];after['degenerateExportTrianglesRemoved']=after['triangles']-len(indices);after['triangles']=len(indices)
    (OUT/f'{name}_Clean.mesh').write_bytes(b'version 2.00\n'+struct.pack('<HBBII',12,40,12,len(rows),len(indices))+b''.join(rows)+b''.join(struct.pack('<III',*f) for f in indices))
    scene.cycles.samples=16;scene.render.resolution_x=1100;scene.render.resolution_y=750;scene.render.resolution_percentage=100
    if name=='PedestrianSignal':scene.camera.data.ortho_scale=1.6
    scene.render.filepath=str(PREVIEW/f'{name.lower()}-clean-shaded.png');bpy.ops.render.render(write_still=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/f'{name}_Clean.blend'))
    if name=='PedestrianSignal':
        camera=scene.camera;saved=(camera.location.copy(),camera.rotation_euler.copy(),camera.data.ortho_scale)
        camera.location=(.54,.26,-1.8);aim(camera,(0,0,-.025));camera.data.ortho_scale=.94
        scene.render.resolution_x=900;scene.render.resolution_y=1000
        solid=bpy.data.materials.new('Pedestrian solid inspection');solid.use_nodes=True
        shader=solid.node_tree.nodes.get('Principled BSDF');shader.inputs['Base Color'].default_value=(.28,.32,.36,1);shader.inputs['Roughness'].default_value=.40
        scene.view_layers[0].material_override=solid
        scene.render.filepath=str(PREVIEW/'pedestriansignal-displays-solid.png');bpy.ops.render.render(write_still=True)
        scene.view_layers[0].material_override=None
        black=bpy.data.materials.new('Pedestrian editing edges');black.use_nodes=True
        black.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value=(.002,.003,.004,1)
        edges=clean.copy();edges.data=clean.data.copy();bpy.context.collection.objects.link(edges)
        edges.data.materials.clear();edges.data.materials.append(black)
        for face in edges.data.polygons:face.material_index=0
        wire=edges.modifiers.new('Rectangular editing loops','WIREFRAME');wire.thickness=.0007;wire.offset=1;wire.use_even_offset=False
        saved_materials=list(clean.data.materials);clean.data.materials.clear();clean.data.materials.append(solid)
        scene.render.filepath=str(PREVIEW/'pedestriansignal-displays-wire.png');bpy.ops.render.render(write_still=True)
        clean.data.materials.clear()
        for material in saved_materials:clean.data.materials.append(material)
        bpy.data.objects.remove(edges,do_unlink=True)
        camera.location,camera.rotation_euler,camera.data.ortho_scale=saved
        scene.render.resolution_x=1100;scene.render.resolution_y=750
    if name=='TrafficSignal':
        camera=scene.camera;saved=(camera.location.copy(),camera.rotation_euler.copy(),camera.data.ortho_scale)
        camera.location=(1.05,.45,-2.15);aim(camera,(0,-.015,-.37));camera.data.ortho_scale=1.45
        solid=bpy.data.materials.new('Solid surface inspection');solid.use_nodes=True
        solid.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value=(.28,.32,.36,1)
        solid.node_tree.nodes.get('Principled BSDF').inputs['Roughness'].default_value=.38
        scene.view_layers[0].material_override=solid
        scene.render.filepath=str(PREVIEW/'trafficsignal-hood-solid.png');bpy.ops.render.render(write_still=True)
        camera.location=(.60,-.85,-2.70);aim(camera,(0,-.02,-.33));camera.data.ortho_scale=2.22
        scene.render.filepath=str(PREVIEW/'trafficsignal-optics-solid.png');bpy.ops.render.render(write_still=True)
        # Show the actual editing loops rather than export triangulation.
        black=bpy.data.materials.new('Optical inspection edges');black.use_nodes=True
        black.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value=(.002,.003,.004,1)
        edge_obj=clean.copy();edge_obj.data=clean.data.copy();bpy.context.collection.objects.link(edge_obj)
        edge_obj.data.materials.clear();edge_obj.data.materials.append(black)
        for face in edge_obj.data.polygons:face.material_index=0
        wire=edge_obj.modifiers.new('Concentric editing loops','WIREFRAME');wire.thickness=.0013;wire.use_replace=True;wire.offset=1;wire.use_even_offset=False
        # Per-object materials let the wire stay black under the gray surface.
        scene.view_layers[0].material_override=None
        saved_materials=list(clean.data.materials);clean.data.materials.clear();clean.data.materials.append(solid)
        scene.render.filepath=str(PREVIEW/'trafficsignal-optics-wire.png');bpy.ops.render.render(write_still=True)
        clean.data.materials.clear()
        for item in saved_materials:clean.data.materials.append(item)
        bpy.data.objects.remove(edge_obj,do_unlink=True)
        scene.view_layers[0].material_override=solid
        camera.location=(1.10,.75,-2.10);aim(camera,(0,.05,-.09));camera.data.ortho_scale=2.30
        scene.render.filepath=str(PREVIEW/'trafficsignal-details-solid.png');bpy.ops.render.render(write_still=True)
        camera.location=(.67,1.55,.35);direction=(Vector((.67,.341,.175))-camera.location).normalized()
        right=direction.cross(Vector((0,0,1))).normalized();up=right.cross(direction)
        camera.rotation_euler=Matrix((right,up,-direction)).transposed().to_euler();camera.data.ortho_scale=.80
        scene.render.filepath=str(PREVIEW/'trafficsignal-top-ribs-solid.png');bpy.ops.render.render(write_still=True)
        scene.view_layers[0].material_override=None
        camera.location,camera.rotation_euler,camera.data.ortho_scale=saved
    # Back-side edge views reveal the large housing planes clearly.
    scene.camera.location=(1.5,.8,3) if name=='TrafficSignal' else (.65,.4,1.6);aim(scene.camera,(0,0,0))
    gray=bpy.data.materials.new('Topology gray');gray.use_nodes=True;gray.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value=(.42,.46,.50,1)
    black=bpy.data.materials.new('Topology edges');black.use_nodes=True;black.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value=(.005,.008,.010,1)
    for original,label in ((source,'before'),(clean,'after')):
        source.hide_render=True;clean.hide_render=True
        display=original.copy();display.data=original.data.copy();bpy.context.collection.objects.link(display);display.hide_render=False;display.hide_set(False)
        display.data.materials.clear();display.data.materials.append(gray)
        for f in display.data.polygons:f.material_index=0
        edges=display.copy();edges.data=display.data.copy();bpy.context.collection.objects.link(edges);edges.data.materials.clear();edges.data.materials.append(black)
        wire=edges.modifiers.new('Actual editing edges','WIREFRAME');wire.thickness=.0025 if name=='TrafficSignal' else .0012;wire.use_replace=True;wire.offset=1;wire.use_even_offset=False
        scene.render.filepath=str(PREVIEW/f'{name.lower()}-topology-{label}.png');bpy.ops.render.render(write_still=True)
        bpy.data.objects.remove(edges,do_unlink=True);bpy.data.objects.remove(display,do_unlink=True)
    report={'asset':name,'before':before,'after':after,'planePatches':patches,'housing':housing,'maxSurfaceDeviationMm':error*1000,'sourceSurfaceDistanceMm':original_distance*1000,'exposedCandidateDistanceMm':exposed_distance*1000,'sourceSurfaceDistanceLimitMm':source_error_limit*1000,'exposedCandidateDistanceLimitMm':exposed_error_limit*1000,'surfaceDeviationLimitMm':error_limit*1000,'surfaceDistanceMethod':'Original vertices/triangle centers to candidate, and externally visible candidate triangle samples to original; buried attachment caps excluded','originalBoundaryEdges':boundaries,'cleanBoundaryEdges':boundary_count(clean.data),'manufacturedBoundaryEdges':manufactured_boundaries,'albedoRebaked':True,'sourceAssetUnchanged':True,'gameAssetReplaced':False}
    report.update({'simplifiedSourceDetailDistanceMm':source_detail_distance*1000,
                   'simplifiedExposedDetailDistanceMm':exposed_detail_distance*1000,
                   'simplifiedDetailDistanceLimitMm':50 if housing.get('rebuiltDetails') else 0,
                   'sourceSurfaceDistanceMethod':'Vertices and triangle centers outside intentionally simplified clip and top-rib regions',
                   'surfaceDistanceMethod':'Preserved body/shade/optic regions retain strict distances; deliberately simplified clips and top ribs have a separate bounded silhouette envelope; exposed samples exclude buried attachment caps'})
    if housing.get('rebuiltDisplays'):
        report['sourceSurfaceDistanceMethod']='All original vertices and triangle centers to the reconstructed pedestrian signal'
        report['surfaceDistanceMethod']='Bidirectional original-to-candidate samples and externally visible candidate triangle samples to original, including all new pedestrian parts; buried attachment caps excluded'
    reports.append(report);print(json.dumps(report),flush=True)
if '--validate-only' in sys.argv:raise SystemExit(0)
if len(names)==1 and (OUT/'cleanup-report.json').exists():
    updated={r['asset']:r for r in reports}
    reports=[updated.get(r['asset'],r) for r in json.loads((OUT/'cleanup-report.json').read_text(encoding='utf-8'))]
(OUT/'cleanup-report.json').write_text(json.dumps(reports,indent=2),encoding='utf-8')
assert fingerprints=={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in protected},'Original source or Place changed'
(OUT/'preserved-files.json').write_text(json.dumps(fingerprints,indent=2),encoding='utf-8')
print('Signal cleanup candidates complete; original assets and Ro.rbxlx untouched.',flush=True)
