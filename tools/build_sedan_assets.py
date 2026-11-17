"""Build a CN7-inspired original sedan with independent doors/wheels/interior.
Run in background Blender. Dimensions in meters; no additional Place files.
"""
from pathlib import Path
from collections import defaultdict
import bpy, math, struct, json
from mathutils import Vector, Matrix

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets/vehicles/local'; OUT.mkdir(parents=True,exist_ok=True)
PREVIEW=ROOT/'dist/preview';PREVIEW.mkdir(parents=True,exist_ok=True)
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
palette={
 'Paint':((.72,.77,.80),0,.65), 'Black':((.014,.020,.026),0,.25),
 'Rubber':((.020,.024,.030),0,0), 'Silver':((.40,.46,.51),0,.8),
 'Glass':((.12,.20,.26),.50,.25), 'Cabin':((.035,.045,.055),0,0),
 'Leather':((.11,.14,.16),0,0), 'Stitch':((.32,.37,.39),0,0),
 'Screen':((.018,.055,.075),0,.15),'LED':((.77,.92,1),0,.1),
 'Tail':((.8,.025,.035),0,.15), 'Amber':((1,.35,.035),0,.1)}
materials={}
for key,(color,alpha,metal) in palette.items():
 m=bpy.data.materials.new(key);m.diffuse_color=(*color,1-alpha);m.use_nodes=True
 p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*color,1)
 p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=.32 if key=='Paint' else .55
 if key=='Glass':p.inputs['Alpha'].default_value=1-alpha;m.surface_render_method='DITHERED'
 if key in ('LED','Tail','Amber'):p.inputs['Emission Color'].default_value=(*color,1);p.inputs['Emission Strength'].default_value=2
 materials[key]=m
pivots={'Body':(0,0,0),'DoorFL':(-.88,-.83,.84),'DoorFR':(.88,-.83,.84),
 'DoorRL':(-.89,.30,.83),'DoorRR':(.89,.30,.83),'Steering':(-.43,-.47,.88)}
for code,x,y in [('FL',-.795,-1.36),('FR',.795,-1.36),('RL',-.795,1.36),('RR',.795,1.36)]:pivots['Wheel'+code]=(x,y,.325)
objects=[]
def finish(obj,key,group,bevel=0):
 obj.data.materials.clear();obj.data.materials.append(materials[key]);obj['group']=group;obj['material']=key
 if bevel:
  bpy.context.view_layer.objects.active=obj;mod=obj.modifiers.new('Soft manufactured edges','BEVEL');mod.width=bevel;mod.segments=2
  bpy.ops.object.modifier_apply(modifier=mod.name)
 objects.append(obj);return obj
def mesh(name,vertices,faces,key='Paint',group='Body',bevel=0):
 data=bpy.data.meshes.new(name);data.from_pydata(vertices,[],faces);data.update()
 obj=bpy.data.objects.new(name,data);bpy.context.collection.objects.link(obj);return finish(obj,key,group,bevel)
def box(name,center,size,key='Paint',group='Body',bevel=.015):
 bpy.ops.mesh.primitive_cube_add(size=1,location=center);o=bpy.context.object;o.name=name;o.scale=size
 bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);return finish(o,key,group,bevel)
def beam(name,a,b,width,key='Black',group='Body',depth=None):
 a,b=Vector(a),Vector(b);o=box(name,(a+b)/2,(width,depth or width,(b-a).length),key,group,min(width*.18,.01))
 o.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler();return o
def panel(name,points,key='Paint',group='Body',thickness=.018):
 obj=mesh(name,points,[tuple(range(len(points)))],key,group)
 mod=obj.modifiers.new('Panel thickness','SOLIDIFY');mod.thickness=thickness
 bpy.context.view_layer.objects.active=obj;bpy.ops.object.modifier_apply(modifier=mod.name);return obj
def torus(name,center,major,minor,key,group,rotation=(0,0,0),segments=48):
 bpy.ops.mesh.primitive_torus_add(major_segments=segments,minor_segments=10,location=center,major_radius=major,minor_radius=minor,rotation=rotation)
 o=bpy.context.object;o.name=name
 for face in o.data.polygons:face.use_smooth=True
 return finish(o,key,group)
def cylinder(name,center,radius,depth,key,group,rotation=(0,math.pi/2,0),vertices=40):
 bpy.ops.mesh.primitive_cylinder_add(vertices=vertices,radius=radius,depth=depth,location=center,rotation=rotation)
 o=bpy.context.object;o.name=name
 for face in o.data.polygons:face.use_smooth=True
 return finish(o,key,group)
def wheel_cut(obj,x,y):
 bpy.ops.mesh.primitive_cylinder_add(vertices=48,radius=.366,depth=.7,location=(x,y,.325),rotation=(0,math.pi/2,0))
 cutter=bpy.context.object
 bpy.context.view_layer.objects.active=obj;mod=obj.modifiers.new('Wheel arch','BOOLEAN');mod.operation='DIFFERENCE';mod.object=cutter
 bpy.ops.object.modifier_apply(modifier=mod.name);bpy.data.objects.remove(cutter,do_unlink=True)

# The cabin is hollow. There is no full body block behind opening doors.
box('Undertray',(0,0,.285),(1.60,3.95,.11),'Black')
box('Cabin floor',(0,.30,.37),(1.63,2.12,.10),'Cabin')
for side in [-1,1]:
 box('Rocker panel',(side*.88,.22,.34),(.13,2.78,.18),'Paint',bevel=.025)
 for front in [True,False]:
  ys=[-2.31,-2.08,-1.6,-.83] if front else [1.17,1.7,2.12,2.31]
  widths=[.71,.84,.91,.91] if front else [.91,.90,.83,.72]
  tops=[.61,.70,.82,.88] if front else [.86,.83,.73,.64]
  vv=[]
  for y,w,z in zip(ys,widths,tops):vv.extend([(side*(w-.075),y,.34),(side*w,y,.39),(side*w,y,z),(side*(w-.075),y,z)])
  ff=[(0,3,2,1),(len(vv)-4,len(vv)-3,len(vv)-2,len(vv)-1)]
  for i in range(len(ys)-1):
   for k in range(4):ff.append((i*4+k,i*4+(k+1)%4,(i+1)*4+(k+1)%4,(i+1)*4+k))
  o=mesh('Front fender' if front else 'Rear quarter',vv,ff,'Paint',bevel=.018)
  wheel_cut(o,side*.795,-1.36 if front else 1.36)
 # Triangular creases across separately moving door skins.
 for front in [True,False]:
  code=('F' if front else 'R')+('L' if side<0 else 'R');group='Door'+code
  y0,y1=(-.815,.285) if front else (.315,1.18)
  poly=[(side*.902,y0,.39),(side*.918,y1,.39),(side*.906,y1,.84),(side*.913,(y0+y1)*.5,.77),(side*.903,y0,.87)]
  door=panel('Faceted door '+code,poly,'Paint',group,.045)
  if not front:wheel_cut(door,side*.795,1.36)
  panel('Door crease '+code,[(side*.925,y0+.025,.64),(side*.931,y1-.025,.43),(side*.932,y1-.025,.73),(side*.924,y0+.025,.78)],'Paint',group,.007)
  box('Interior door trim',(side*.862,(y0+y1)/2,.67),(.055,y1-y0-.10,.35),'Cabin',group)
  box('Door armrest',(side*.825,(y0+y1)/2,.68),(.12,.40,.055),'Leather',group)
  box('Door pull',(side*.815,y0+.25,.78),(.025,.16,.025),'Silver',group,.008)
  box('Exterior handle',(side*.95,y1-.17,.83),(.035,.16,.035),'Silver',group,.013)
  if front:
   window=[(side*.90,-.77,.90),(side*.735,-.365,1.355),(side*.745,.266,1.36),(side*.90,.266,.90)]
  else:
   window=[(side*.90,.327,.90),(side*.745,.327,1.355),(side*.75,.78,1.315),(side*.89,1.165,.90)]
  panel('Side glass '+code,window,'Glass',group,.008)
  for k in range(len(window)):beam('Window frame '+code,window[k],window[(k+1)%len(window)],.035,'Black',group)
  if front:
   beam('Mirror stem',(side*.90,-.72,.92),(side*1.00,-.77,.91),.045,'Black',group)
   box('Mirror shell',(side*1.025,-.78,.94),(.18,.25,.11),'Paint',group,.035)
   box('Mirror glass',(side*1.025,-.648,.95),(.145,.012,.075),'Silver',group,.008)
 # Structural pillars stay with the body as the doors open.
 beam('A pillar',(side*.89,-1.01,.88),(side*.72,-.40,1.385),.054,'Paint')
 beam('B pillar',(side*.89,.30,.84),(side*.74,.30,1.38),.070,'Black')
 beam('C pillar',(side*.74,.82,1.34),(side*.89,1.48,.86),.12,'Paint')

# Long low hood, sloping roof and angular rear deck.
panel('Hood',[(-.79,-2.14,.71),(.79,-2.14,.71),(.86,-.99,.89),(-.86,-.99,.89)],'Paint',thickness=.035)
for side in [-1,1]:beam('Hood sculpt line',(side*.55,-2.03,.735),(side*.48,-1.06,.90),.014,'Paint')
panel('Roof',[(-.72,-.40,1.39),(.72,-.40,1.39),(.74,.25,1.435),(.73,.83,1.345),(-.73,.83,1.345),(-.74,.25,1.435)],'Paint',thickness=.03)
panel('Windshield',[(-.86,-1.005,.91),(.86,-1.005,.91),(.715,-.408,1.365),(-.715,-.408,1.365)],'Glass',thickness=.009)
panel('Rear windshield',[(-.73,.845,1.32),(.73,.845,1.32),(.84,1.47,.875),(-.84,1.47,.875)],'Glass',thickness=.009)
panel('Trunk',[(-.85,1.49,.865),(.85,1.49,.865),(.75,2.19,.73),(-.75,2.19,.73)],'Paint',thickness=.035)
beam('Rear lip',(-.76,2.15,.755),(.76,2.15,.755),.040,'Paint')
# Wide parametric grille and sharp swept DRLs.
panel('Front bumper',[(-.72,-2.335,.32),(.72,-2.335,.32),(.83,-2.28,.62),(.72,-2.32,.71),(-.72,-2.32,.71),(-.83,-2.28,.62)],'Paint',thickness=.07)
panel('Grille',[(-.68,-2.375,.37),(.68,-2.375,.37),(.76,-2.355,.57),(.57,-2.35,.64),(-.57,-2.35,.64),(-.76,-2.355,.57)],'Black')
for i in range(15):
 x=-.66+i*.094
 beam('Grille diamond',(x,-2.389,.39),(min(.72,x+.14),-2.388,.60),.014,'Silver')
 beam('Grille diamond',(x,-2.389,.60),(min(.72,x+.14),-2.388,.39),.012,'Black')
for side in [-1,1]:
 panel('Headlamp bed',[(side*.60,-2.315,.645),(side*.81,-2.20,.70),(side*.88,-1.98,.745),(side*.67,-2.15,.71)],'Black')
 beam('Sharp LED',(side*.61,-2.332,.665),(side*.80,-2.22,.727),.026,'LED')
 beam('Swept LED',(side*.80,-2.22,.727),(side*.872,-2.00,.763),.019,'LED')
 box('Lower intake',(side*.72,-2.305,.38),(.16,.055,.16),'Black',bevel=.024)
panel('Rear bumper',[(-.73,2.32,.32),(.73,2.32,.32),(.81,2.25,.64),(.72,2.26,.73),(-.72,2.26,.73),(-.81,2.25,.64)],'Paint',thickness=.07)
beam('H tail bridge',(-.72,2.305,.665),(.72,2.305,.665),.024,'Tail')
for side in [-1,1]:
 beam('Tail top',(side*.38,2.29,.725),(side*.76,2.26,.725),.035,'Tail')
 beam('Tail drop',(side*.72,2.28,.725),(side*.72,2.31,.59),.033,'Tail')
 beam('Tail lower',(side*.72,2.31,.59),(side*.52,2.33,.59),.023,'Tail')
box('Rear diffuser',(0,2.29,.305),(1.38,.10,.14),'Black')
box('Front plate',(0,-2.414,.45),(.48,.016,.11),'Silver',bevel=.008)
box('Rear plate',(0,2.382,.47),(.48,.018,.11),'Silver',bevel=.008)

# First-person cabin: open footwell, split screens, console, four seats.
box('Dashboard',(0,-.74,.84),(1.64,.40,.20),'Cabin',bevel=.065)
box('Display surround',(-.20,-.578,.965),(.92,.06,.20),'Black',bevel=.025)
box('Gauge glass',(-.45,-.539,.97),(.34,.018,.145),'Screen',bevel=.015)
box('Navigation glass',(.02,-.539,.97),(.43,.018,.145),'Screen',bevel=.015)
for side in [-1,1]:box('Air vent',(side*.69,-.535,.84),(.19,.025,.04),'Black',bevel=.006)
beam('Dash metal trim',(-.77,-.524,.81),(.77,-.524,.81),.015,'Silver')
box('Center console',(0,.12,.52),(.25,1.02,.24),'Cabin',bevel=.045)
box('Console armrest',(0,.50,.67),(.23,.32,.08),'Leather',bevel=.035)
box('Shift selector',(0,-.15,.68),(.075,.10,.10),'Silver',bevel=.020)
for y in [.12,.29]:torus('Cup holder',(0,y,.655),.057,.010,'Black','Body',segments=24)
for x in [-.43,.43]:
 box('Seat base',(x,.30,.49),(.45,.49,.12),'Leather',bevel=.055)
 back=box('Seat back',(x,.57,.77),(.45,.13,.50),'Leather',bevel=.05);back.rotation_euler.x=math.radians(10)
 box('Headrest',(x,.64,1.085),(.26,.11,.17),'Leather',bevel=.045)
 for sx in [-1,1]:box('Seat bolster',(x+sx*.19,.30,.56),(.055,.40,.065),'Cabin',bevel=.022)
 box('Seat seam',(x,.24,.555),(.012,.27,.006),'Stitch',bevel=.002)
box('Rear bench',(0,1.03,.49),(1.35,.42,.12),'Leather',bevel=.045)
box('Rear backrest',(0,1.25,.72),(1.35,.13,.42),'Leather',bevel=.045)
for x in [-.43,0,.43]:box('Rear headrest',(x,1.30,.99),(.22,.11,.16),'Leather',bevel=.035)
box('Roof liner',(0,.22,1.38),(1.38,1.13,.015),'Cabin',bevel=.005)
box('Rear view mirror',(0,-.56,1.26),(.24,.045,.09),'Silver',bevel=.02)
beam('Steering column',(-.43,-.66,.80),(-.43,-.47,.88),.075,'Black')
torus('Steering rim',pivots['Steering'],.169,.020,'Cabin','Steering',(math.radians(70),0,0),48)
steer=box('Steering hub',pivots['Steering'],(.13,.05,.095),'Cabin','Steering',.025);steer.rotation_euler.x=math.radians(70)
for sx in [-1,1]:beam('Steering spoke',(-.43+sx*.04,-.47,.88),(-.43+sx*.15,-.47,.88),.035,'Silver','Steering')
beam('Lower spoke',(-.43,-.47,.85),(-.43,-.42,.727),.034,'Cabin','Steering')

for code in ['FL','FR','RL','RR']:
 group='Wheel'+code;x,y,z=pivots[group];side=-1 if x<0 else 1
 torus('Tire '+code,(x,y,z),.258,.067,'Rubber',group,(0,math.pi/2,0),48)
 for offset in [-.041,.041]:torus('Tire shoulder '+code,(x+offset,y,z),.259,.035,'Rubber',group,(0,math.pi/2,0),48)
 outer=x+side*.083
 cylinder('Brake disc '+code,(x+side*.048,y,z),.204,.014,'Silver',group)
 cylinder('Rim well '+code,(outer,y,z),.225,.022,'Black',group)
 torus('Rim lip '+code,(outer+side*.012,y,z),.213,.012,'Silver',group,(0,math.pi/2,0),40)
 cylinder('Hub '+code,(outer+side*.025,y,z),.052,.028,'Silver',group)
 for i in range(5):
  angle=2*math.pi*i/5
  for spread in [-.08,.08]:
   a=(outer+side*.024,y+math.sin(angle)*.05,z+math.cos(angle)*.05)
   b=(outer+side*.024,y+math.sin(angle+spread)*.205,z+math.cos(angle+spread)*.205)
   beam('Split spoke '+code,a,b,.021,'Silver',group)
  cylinder('Wheel bolt',(outer+side*.042,y+math.sin(angle)*.036,z+math.cos(angle)*.036),.007,.009,'Black',group,vertices=8)

# Export each moving group/material as native meshes with shared group pivots.
groups=defaultdict(list)
for obj in objects:
 bpy.context.view_layer.objects.active=obj
 for mod in list(obj.modifiers):bpy.ops.object.modifier_apply(modifier=mod.name)
 obj.data.calc_loop_triangles();groups[(obj['group'],obj['material'])].append(obj)
manifest={'Version':1,'Design':'Original CN7-inspired compact sedan','Units':'meters',
 'Dimensions':[1.83,1.435,4.68],'Wheelbase':2.72,'WheelRadius':.325,'Parts':[],
 'Pivots':{k:[v[0],v[2],v[1]] for k,v in pivots.items()},'TotalTriangles':0}
conversion=Matrix(((1,0,0),(0,0,1),(0,1,0)))
for (group,key),items in sorted(groups.items()):
 pivot=Vector(pivots[group]);rows=[];faces=[];lookup={};lo=Vector((math.inf,)*3);hi=-lo
 for obj in items:
  rotation=obj.matrix_world.to_3x3()
  for tri in obj.data.loop_triangles:
   face=[]
   for lid in tri.loops:
    loop=obj.data.loops[lid];p=conversion@(obj.matrix_world@obj.data.vertices[loop.vertex_index].co-pivot)
    normal=(conversion@rotation@obj.data.corner_normals[lid].vector).normalized()
    lo=Vector(tuple(min(lo[i],p[i]) for i in range(3)));hi=Vector(tuple(max(hi[i],p[i]) for i in range(3)))
    packed=struct.pack('<8f4b4B',*p,*normal,0,0,0,0,0,127,255,255,255,255)
    if packed not in lookup:lookup[packed]=len(rows);rows.append(packed)
    face.append(lookup[packed])
   faces.append(tuple(reversed(face))) # conversion reverses handedness
 filename=group+'_'+key+'.mesh'
 data=b'version 2.00\n'+struct.pack('<HBBII',12,40,12,len(rows),len(faces))+b''.join(rows)+b''.join(struct.pack('<III',*f) for f in faces)
 (OUT/filename).write_bytes(data)
 color,alpha,_=palette[key]
 # Convert linear render colors to display RGB used by Roblox Color3.
 rgb=[round((12.92*c if c<=.0031308 else 1.055*c**(1/2.4)-.055)*255) for c in color]
 manifest['Parts'].append({'Group':group,'Material':key,'File':filename,'Color':rgb,'Transparency':alpha,'Bounds':[max(.001,hi[i]-lo[i]) for i in range(3)],'Triangles':len(faces)})
 manifest['TotalTriangles']+=len(faces)
(OUT/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
assert manifest['TotalTriangles']<55000,manifest['TotalTriangles']
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'BoraSedan.blend'))
# Evidence renders of the actual modeled components, not concept art.
floor=bpy.data.materials.new('Studio floor');floor.diffuse_color=(.09,.11,.13,1)
bpy.ops.mesh.primitive_plane_add(size=200);bpy.context.object.data.materials.append(floor)
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=24;scene.cycles.use_denoising=True
scene.world.color=(.30,.30,.30)
for location,energy,size in [((1,-4,6),1400,6),((-4,1,4),1100,5),((3,4,4),1600,5)]:
 bpy.ops.object.light_add(type='AREA',location=location);bpy.context.object.data.energy=energy;bpy.context.object.data.shape='DISK';bpy.context.object.data.size=size
 bpy.context.object.rotation_euler=(Vector((0,0,.5))-bpy.context.object.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add(location=(-5,-7,3.6));cam=bpy.context.object;scene.camera=cam;cam.data.lens=53
def render(name,location,target,res=(1300,850)):
 cam.location=location;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler()
 scene.render.resolution_x,scene.render.resolution_y=res;scene.render.resolution_percentage=100
 scene.render.image_settings.file_format='PNG';scene.render.filepath=str(PREVIEW/name);bpy.ops.render.render(write_still=True)
render('sedan-exterior.png',(-5.1,-6.6,3.05),(0,-.05,.60))
render('sedan-interior.png',(-.43,.29,1.19),(-.18,-1.1,.93),(1250,800))
# Driver's door open; rotate the actual separate component around its hinge.
pivot=Vector(pivots['DoorFL']);rotation=Matrix.Rotation(math.radians(65),4,'Z')
for obj in objects:
 if obj['group']=='DoorFL':obj.matrix_world=Matrix.Translation(pivot)@rotation@Matrix.Translation(-pivot)@obj.matrix_world
render('sedan-door-open.png',(-4,-4,2.8),(-.20,0,.72))
print('SEDAN_ASSETS',manifest['TotalTriangles'],'triangles',len(manifest['Parts']),'mesh components',flush=True)
