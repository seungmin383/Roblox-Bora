"""Export the approved S3 to existing native-asset slots, preserving the blend."""
import bpy,json,hashlib,struct,math,shutil
from pathlib import Path
from collections import defaultdict
from mathutils import Matrix,Vector
ROOT=Path(__file__).resolve().parents[1];SRC=ROOT/'assets/vehicles/BoraS3';OUT=ROOT/'assets/vehicles/local'
old=json.loads((OUT/'manifest.json').read_text(encoding='utf-8'))
legacy=old.get('LegacyLayout',{'Pivots':old['Pivots'],'Markers':{'Eye':[-.43,.58,.08],'SeatedRoot':[-.43,.25,.22],'OutsideDriver':[-1.35,.33,-.02],'DriverHandle':[-1.0,.21,.10],
 'SuspensionFL':[-.795,-.02,-1.36],'SuspensionFR':[.795,-.02,-1.36],'SuspensionRL':[-.795,-.02,1.36],'SuspensionRR':[.795,-.02,1.36]},'SeatPosition':[-.43,.43,.24]})
source=SRC/'BoraS3.blend';digest=hashlib.sha256(source.read_bytes()).hexdigest()
bpy.ops.wm.open_mainfile(filepath=str(source),load_ui=False)
# Proper rotation: -Y front in Blender becomes -Z in Roblox; driver's +X
# side becomes Roblox -X. Determinant +1 preserves face/UV handedness.
convert=Matrix(((-1,0,0),(0,0,1),(0,1,0)))
prov=json.loads((SRC/'provenance.json').read_text(encoding='utf-8'))
pivots={g:list(convert@Vector(p)) for g,p in prov['pivots'].items() if g!='Interior'}
pivots['Body']=[0,0,0]
markers={'Eye':[-.405,1.25-.62,.065],'SeatedRoot':[-.405,.87-.62,.11],'OutsideDriver':[-1.36,.95-.62,-.02],'DriverHandle':[-1.0,.83-.62,-.18]}
for code in ['FL','FR','RL','RR']:
    p=pivots['Wheel'+code];markers['Suspension'+code]=[p[0],.347+.275-.62,p[2]]
layout={'Pivots':pivots,'Markers':markers,'SeatPosition':[-.405,.45,.11]}
catalog={'Version':3,'Design':'BORA S3 approved independent sedan','Units':'meters','Dimensions':[2.194,1.508,4.628],
 'Wheelbase':2.75,'WheelRadius':.344,'Parts':[],'Pivots':pivots,'Markers':markers,'SeatPosition':layout['SeatPosition'],
 'LegacyLayout':legacy,'LayoutJson':json.dumps(layout,separators=(',',':')),'VisualRevision':5,'VisualHash':digest[:16],
 'VirtualBrand':'BORA','DisplayName':'BORA S3','Source':'Independently authored BORA S3 / Tripo proportion study',
 'ApprovedBlend':'assets/vehicles/BoraS3/BoraS3.blend','ApprovedBlendSha256':digest,'RobloxConversion':[list(r) for r in convert],
 'SteeringAxis':[0,.5,math.cos(math.radians(30))],
 'Screens':{'DashboardDisplay':{'Position':[-.405,1.025,-.598],'Size':[.315,.122],'Tilt':12},'CenterDisplay':{'Position':[.12,1.008,-.479],'Size':[.32,.168],'Tilt':12}}}
semantic={'mineral blue pearl':('CarPaint','SmoothPlastic',0),'satin graphite':('Black','SmoothPlastic',0),'tyre and seals':('Rubber','SmoothPlastic',0),
 'brushed aluminium':('Silver','Metal',0),'wheel graphite':('Metal','Metal',0),'clear smoke glass':('Glass','Glass',.70),
 'lamp clear cover':('Lens','Glass',.48),'rear optical red':('TailLens','SmoothPlastic',0),'ice white LED':('LED','Neon',0),
 'red LED':('Tail','Neon',0),'charcoal leather':('Leather','SmoothPlastic',0),'woven seat inserts':('Cloth','Fabric',0),
 'soft touch dashboard':('Cabin','SmoothPlastic',0),'light headliner':('Headliner','Fabric',0),'brake caliper':('Brake','Metal',0),'brake rotor':('Rotor','Metal',0)}
groups=defaultdict(list)
for o in bpy.context.scene.objects:
    if o.type=='MESH' and o.get('asset')=='BORA S3':
        group='Body' if o['group']=='Interior' else o['group']
        for mi,mat in enumerate(o.data.materials):groups[(group,mat.name)].append((o,mi))
def rgb(linear):return round(255*(12.92*linear if linear<=.0031308 else 1.055*linear**(1/2.4)-.055))
for (group,matname),objects in sorted(groups.items()):
    mat=bpy.data.materials[matname];bs=mat.node_tree.nodes.get('Principled BSDF');suffix=matname.split(' | ')[-1]
    key,material,alpha=semantic.get(suffix,('Screen' if 'display' in matname.lower() else 'Plate','SmoothPlastic',0))
    color=[rgb(c) for c in bs.inputs['Base Color'].default_value[:3]]
    texture=None
    for n in mat.node_tree.nodes:
        if n.type=='TEX_IMAGE' and n.image:
            filename=Path(bpy.path.abspath(n.image.filepath)).name
            if (SRC/filename).is_file():shutil.copyfile(SRC/filename,OUT/filename);texture=filename;color=[255,255,255]
    chunks=[];triangles=[]
    for o,mi in objects:
        o.data.calc_loop_triangles();uv=o.data.uv_layers.active
        transform=o.matrix_world;normals=convert@transform.to_3x3().inverted().transposed()
        for tri in o.data.loop_triangles:
            if tri.material_index!=mi:continue
            tri_rows=[]
            for li in tri.loops:
                loop=o.data.loops[li];p=convert@(transform@o.data.vertices[loop.vertex_index].co)-Vector(pivots[group])
                normal=(normals@o.data.corner_normals[li].vector).normalized();tex=uv.data[li].uv
                tri_rows.append(struct.pack('<8f4b4B',*p,*normal,tex.x,1-tex.y,0,0,0,127,255,255,255,255))
            triangles.append(tri_rows)
    for ci,start in enumerate(range(0,len(triangles),7600)):
        rows=[];faces=[];lookup={};lo=Vector((math.inf,)*3);hi=-lo
        for tri in triangles[start:start+7600]:
            face=[]
            for packed in tri:
                if packed not in lookup:
                    lookup[packed]=len(rows);rows.append(packed)
                    p=struct.unpack_from('<3f',packed)
                    for k in range(3):lo[k]=min(lo[k],p[k]);hi[k]=max(hi[k],p[k])
                face.append(lookup[packed])
            faces.append(face)
        number=len(catalog['Parts']);filename=f'S3_{group}_{number:03d}_{ci:02d}.mesh'
        payload=b'version 2.00\n'+struct.pack('<HBBII',12,40,12,len(rows),len(faces))+b''.join(rows)+b''.join(struct.pack('<III',*f) for f in faces)
        (OUT/filename).write_bytes(payload)
        part={'Group':group,'Material':key,'RobloxMaterial':material,'File':filename,'Color':color,'Transparency':alpha,
              'Bounds':[max(.001,hi[k]-lo[k]) for k in range(3)],'Triangles':len(faces)}
        if texture:part['Texture']=texture
        catalog['Parts'].append(part)
catalog['TotalTriangles']=sum(p['Triangles'] for p in catalog['Parts'])
assert catalog['TotalTriangles']==176384
assert hashlib.sha256(source.read_bytes()).hexdigest()==digest
(OUT/'manifest.json').write_text(json.dumps(catalog,ensure_ascii=False,indent=2),encoding='utf-8')
print('S3 native export:',catalog['TotalTriangles'],'triangles;',len(catalog['Parts']),'parts; source unchanged.',flush=True)
