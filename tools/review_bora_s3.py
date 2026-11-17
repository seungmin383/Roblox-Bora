"""Reload and inspect S3. All review edits are transient and never saved."""
import bpy,bmesh,math,json,sys,hashlib
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'assets/vehicles/BoraS3'
bpy.ops.wm.open_mainfile(filepath=str(OUT/'BoraS3.blend'),load_ui=False)
scene=bpy.context.scene;cam=scene.camera;cam.hide_set(False)
assets=[o for o in scene.objects if o.type=='MESH' and o.get('asset')=='BORA S3']
rows=[];errors=[]
for o in assets:
    me=o.data;me.calc_loop_triangles();bm=bmesh.new();bm.from_mesh(me)
    bad_uv=sum(not all(math.isfinite(x) for x in v.uv) for layer in me.uv_layers for v in layer.data)
    bad_tris=0
    for tri in me.loop_triangles:
        a,b,c=[me.vertices[i].co for i in tri.vertices]
        if (b-a).cross(c-a).length/2<1e-12:bad_tris+=1
    row={'name':o.name,'group':o.get('group'),'vertices':len(me.vertices),'faces':len(me.polygons),'triangles':len(me.loop_triangles),
        'boundaryEdges':sum(e.is_boundary for e in bm.edges),'overusedEdges':sum(len(e.link_faces)>2 for e in bm.edges),
        'wireEdges':sum(not e.link_faces for e in bm.edges),'badTriangles':bad_tris,'badUVs':bad_uv,
        'badNormals':sum(not all(math.isfinite(x) for x in n.vector) or n.vector.length<.5 for n in me.corner_normals),
        'bounds':[[min((o.matrix_world@v.co)[k] for v in me.vertices) for k in range(3)],
                  [max((o.matrix_world@v.co)[k] for v in me.vertices) for k in range(3)]]}
    bm.free();rows.append(row)
    if any(row[k] for k in ['overusedEdges','wireEdges','badTriangles','badUVs','badNormals']):errors.append(o.name)
low=[min(r['bounds'][0][k] for r in rows) for k in range(3)]
high=[max(r['bounds'][1][k] for r in rows) for k in range(3)]
prov=json.loads((OUT/'provenance.json').read_text(encoding='utf-8'))
protected={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest()==h for p,h in prov['protectedFiles'].items()}
report={'objects':rows,'totals':{k:sum(r[k] for r in rows) for k in ['vertices','faces','triangles','boundaryEdges','overusedEdges','wireEdges','badTriangles','badUVs','badNormals']},
 'bounds':[low,high],'dimensions':[high[k]-low[k] for k in range(3)],'protectedUnchanged':protected,'errors':errors,
 'note':'Structural audit only; visual approval and Roblox runtime validation are separate.'}
def tree(o):
    o.data.calc_loop_triangles()
    return BVHTree.FromPolygons([o.matrix_world@v.co for v in o.data.vertices],[t.vertices[:] for t in o.data.loop_triangles],all_triangles=True,epsilon=1e-7)
glazing=[o for o in assets if 'clear curved' in o.name]
interior=[o for o in assets if (o.get('group') in {'Interior','Steering'} or 'inner door card' in o.name) and 'headliner' not in o.name]
glass_trees={o.name:tree(o) for o in glazing}
intersections=[]
for o in interior:
    ot=tree(o)
    for g in glazing:
        hits=ot.overlap(glass_trees[g.name])
        if hits:intersections.append({'interior':o.name,'glass':g.name,'trianglePairs':len(hits)})
report['interiorGlassIntersections']=intersections
report['intersectionCheckScope']='All Interior/Steering surfaces and inner door cards against all six glazing objects; headliner excluded as roof lining.'
(OUT/'audit.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print('S3_AUDIT',json.dumps({k:v for k,v in report.items() if k!='objects'}),flush=True)
if '--audit-only' in sys.argv:sys.exit(0)

def render(name,loc,target,lens=52):
    cam.location=loc;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.lens=lens
    scene.render.filepath=str(OUT/name);bpy.ops.render.render(write_still=True);print('S3_RENDER',name,flush=True)

if '--beauty' in sys.argv:
    scene.render.engine='CYCLES';scene.cycles.samples=24;scene.cycles.use_denoising=True
    scene.render.resolution_x=1440;scene.render.resolution_y=1000
    if '--quick' in sys.argv:
        scene.cycles.samples=12;scene.render.resolution_x=1100;scene.render.resolution_y=760
    for o in scene.objects:
        if o.type=='LIGHT':o.hide_set(False)
    if '--cockpit-only' not in sys.argv:
        render('S3_Front.png',(-5.0,-6.1,2.9),(0,0,.74),55)
        if '--quick' in sys.argv:sys.exit(0)
        render('S3_Rear.png',(5.1,6.1,2.7),(0,0,.72),55)
    render('S3_Cockpit.png',(.405,.065,1.25),(.12,-.90,.93),21)
else:
    scene.render.engine='BLENDER_WORKBENCH';scene.render.resolution_x=1440;scene.render.resolution_y=1000
    shade=scene.display.shading;shade.light='STUDIO';shade.color_type='MATERIAL';shade.show_shadows=True;shade.show_cavity=True;shade.cavity_type='BOTH'
    shade.background_type='WORLD';scene.world.color=(.11,.13,.16);scene.view_settings.view_transform='Standard'
    scene.display.render_aa='16'
    for o in scene.objects:
        if o.type=='MESH' and o not in assets:o.hide_render=True
    render('S3_SolidFront.png',(-5.0,-6.1,2.9),(0,0,.74),55)
    render('S3_SolidRear.png',(5.1,6.1,2.7),(0,0,.72),55)
    render('S3_Side.png',(-8.8,0,2.15),(0,0,.74),52)
    for o in assets:
        o.hide_render=(o.get('group') not in {'Interior','Steering'} and 'inner door card' not in o.name) or 'headliner' in o.name
    render('S3_CabinCutaway.png',(-2.65,-3.1,2.8),(0,.05,.73),53)
    for o in assets:o.hide_render=False
    gray=bpy.data.materials.new('Review grey');gray.diffuse_color=(.55,.60,.64,1)
    wire=bpy.data.materials.new('Review actual mesh edges');wire.diffuse_color=(.015,.019,.023,1)
    for o in assets:
        if o.get('group')!='Body' or any(k in o.name.lower() for k in ['glass','lens','grille','blade','intake','backing','wiper','mirror','plate']):o.hide_render=True;continue
        o.data.materials.clear();o.data.materials.append(gray);o.data.materials.append(wire)
        for p in o.data.polygons:p.material_index=0
        m=o.modifiers.new('Review real edges','WIREFRAME');m.thickness=.0008;m.offset=1;m.use_replace=False;m.use_even_offset=False;m.material_offset=1
    render('S3_WireFront.png',(-3.7,-4.3,2.3),(0,-.7,.75),60)
print('REVIEW_FINISHED',flush=True)
