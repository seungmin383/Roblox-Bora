"""Build BORA S3 from original Tripo proportions and new shared surface fields.

The downloaded example is a construction reference, never imported/copied.
No rejected S2 edit, Place writer, Studio/UI action or paid generation is used.
"""
import bpy,bmesh,math,json,hashlib,sys
from pathlib import Path
from mathutils import Vector,Matrix
sys.path.insert(0,str(Path(__file__).resolve().parent))
from car_surface_tools import *

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets/vehicles/BoraS3';OUT.mkdir(parents=True,exist_ok=True)
SOURCE=ROOT/'assets/vehicles/source/BoraS2_Quad_OBJ/BoraS2_Tripo_Quad_OBJ.obj'
REF=ROOT/'assets/example/Car/temp.blend'
protected=[ROOT/'Ro.rbxlx',SOURCE,REF,ROOT/'assets/vehicles/retopology/BoraS2_FitFix.blend']
hashfile=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
hashes={str(p.relative_to(ROOT)):hashfile(p) for p in protected if p.exists()}
bpy.context.preferences.filepaths.save_version=0
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
bpy.ops.wm.obj_import(filepath=str(SOURCE),forward_axis='NEGATIVE_Z',up_axis='Y')
raw=[o for o in bpy.context.scene.objects if o.type=='MESH']
points=[o.matrix_world@v.co for o in raw for v in o.data.vertices]
source_bounds=[[min(p[k] for p in points) for k in range(3)], [max(p[k] for p in points) for k in range(3)]]
for o in list(bpy.data.objects):bpy.data.objects.remove(o,do_unlink=True)
scene=bpy.context.scene;scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1

paint=material('S3 | mineral blue pearl',(.075,.18,.245),.72,.265)
bs=paint.node_tree.nodes.get('Principled BSDF');bs.inputs['Coat Weight'].default_value=.48;bs.inputs['Coat Roughness'].default_value=.20
black=material('S3 | satin graphite',(.012,.019,.024),.24,.35)
rubber=material('S3 | tyre and seals',(.012,.015,.019),0,.78)
chrome=material('S3 | brushed aluminium',(.46,.53,.57),.90,.235)
darkmetal=material('S3 | wheel graphite',(.06,.075,.087),.83,.28)
glass=material('S3 | clear smoke glass',(.70,.83,.89),0,.045,1)
lampglass=material('S3 | lamp clear cover',(.86,.93,.98),0,.025,1)
redglass=material('S3 | rear optical red',(.38,.006,.012),.12,.2)
led=material('S3 | ice white LED',(.72,.89,1),.15,.2,emission=3)
redled=material('S3 | red LED',(.72,.009,.017),.12,.22,emission=2.5)
leather=material('S3 | charcoal leather',(.045,.058,.065),0,.62)
suede=material('S3 | woven seat inserts',(.075,.091,.097),0,.90)
dashmat=material('S3 | soft touch dashboard',(.023,.031,.038),0,.75)
headliner=material('S3 | light headliner',(.28,.31,.32),0,.9)
brake=material('S3 | brake caliper',(.28,.035,.023),.45,.4)
rotormat=material('S3 | brake rotor',(.22,.24,.25),.8,.5)

# The stock sedan proportions remain related to the existing Tripo source;
# surface topology and details are newly authored, with explicit panel joins.
FRONT=-2.18;REAR=2.18;FY=-1.39;RY=1.36;WZ=.347;ARCH=.382
width_table=[(-2.3,.79),(-2.18,.855),(-1.6,.93),(-1.15,.93),(-.65,.914),(.35,.921),(1.25,.942),(1.75,.94),(2.18,.863),(2.3,.80)]
belt_table=[(-2.3,.865),(-2.18,.865),(-1.75,.955),(-1.15,1.003),(-.79,1.015),(.30,1.035),(1.43,1.045),(1.8,1.0),(2.18,.91),(2.3,.91)]
def width(y):return interp(width_table,y)
def belt(y):return interp(belt_table,y)
def side_x(y,z):
    t=max(0,min(1,(z-.22)/(belt(y)-.22)))
    contour=interp([(0,.91),(.18,.94),(.38,.945),(.60,.991),(.77,1.018),(.86,1.014),(1,1)],t)
    return width(y)*contour
def arch_bottom(y):
    z=.22
    for yc in [FY,RY]:
        d=abs(y-yc)
        if d<ARCH:
            height=WZ+math.sqrt(max(0,ARCH*ARCH-d*d))
            z=max(z,lerp(.22,height,smoothstep((ARCH-d)/.008)))
    return z
def sidefun(s,y,t,inset=0):
    z=lerp(arch_bottom(y),belt(y),t)
    return (s*(side_x(y,z)-inset),y,z)
def ystations(a,b,n):
    ys=set(seq(a,b,n))
    for yc in [FY,RY]:
        for off in [-ARCH-.001,-ARCH,-ARCH+.001,-ARCH+.004,-ARCH+.008,ARCH-.008,ARCH-.004,ARCH-.001,ARCH,ARCH+.001]:
            if a<yc+off<b:ys.add(yc+off)
    return sorted(ys)

for s,side in [(1,'L'),(-1,'R')]:
    grid('Body | recessed door and arch backing '+side,lambda y,t:sidefun(s,y,t,.010),ystations(FRONT,REAR,84),seq(0,1,7),black,thickness=.004,normal=lambda p:(s,0,0))
    panels=[('Front fender',FRONT,-.812,'Body'),('Front door',-.808,.296,'DoorF'+side),('Rear door',.304,1.266,'DoorR'+side),('Rear quarter',1.270,REAR,'Body')]
    for label,a,b,group in panels:
        grid(label+' | skin '+side,lambda y,t:sidefun(s,y,t),ystations(a,b,max(12,round((b-a)*25))),[0,.04,.12,.26,.4,.55,.69,.80,.89,.96,1],paint,group,.004,lambda p:(s,0,0))
    # Rolled arch returns follow the same analytic opening as the fender skin.
    for yc,which in [(FY,'Front'),(RY,'Rear')]:
        def lip(a,t):
            y=yc-ARCH*math.cos(a);z=WZ+ARCH*math.sin(a)
            return (s*(side_x(y,z)-.030*t),y,z)
        grid(which+' wheel arch | inward lip '+side,lip,seq(0,math.pi,56),[0,.3,1],black,thickness=.002)
        tube(which+' wheel arch | painted rolled edge '+side,
             [(s*(side_x(yc-ARCH*math.cos(a),WZ+ARCH*math.sin(a))+.0008),yc-ARCH*math.cos(a),WZ+ARCH*math.sin(a)) for a in seq(.015,math.pi-.015,56)],.0032,paint,sides=6)
    # Sills have a clean straight extrusion and a narrow aluminium upper strip.
    box('Sill | graphite extrusion '+side,(s*.871,.02,.225),(.075,2.00,.065),black,radius=.018)
    tube('Sill | aluminium blade '+side,[(s*.911,y,.254) for y in seq(-.94,.93,40)],.004,chrome,sides=6)
    for y,group in [(-.18,'DoorF'+side),(.96,'DoorR'+side)]:
        x=side_x(y,.946)
        o=box('Flush door handle | '+group,(s*(x+.004),y,.947),(.019,.157,.028),black,group,radius=.008)
        box('Handle | aluminium touch surface '+group,(s*(x+.015),y-.003,.951),(.006,.112,.012),chrome,group,radius=.003)

def corner_u(u):
    a=abs(u)
    if a<=.82:return u
    t=(a-.82)/.18
    return math.copysign(.82+.18*(t+.83*t*t-.83*t*t*t),u)
def front(u,v):
    top=belt(FRONT)+.035*(1-u*u)
    z=lerp(.22,top,v)
    return (corner_u(u)*side_x(FRONT,z),-2.30+.12*u**4+(.10*(1-v)**4+.055*v**4)*(1-u**4),z)
def rear(u,v):
    top=belt(REAR)+.030*(1-u*u)
    z=lerp(.22,top,v)
    return (corner_u(u)*side_x(REAR,z),2.30-.12*u**4-(.10*(1-v)**4+.030*v**4)*(1-u**4),z)
def hood(u,v):
    y0=front(u,1)[1];cross=min(1,(u*.914/.78)**2);y1=-.84+.05*cross;y=lerp(y0,y1,v)
    z=belt(y)+lerp(.035,.025,v)*(1-u*u)
    start=belt(FRONT)+.035*(1-u*u)
    end=1.04-.025*cross
    z += (start-(belt(y0)+.035*(1-u*u)))*(1-v)**4
    z += (end-(belt(y1)+.025*(1-u*u)))*v**4
    z += .009*math.exp(-((abs(u)-.65)/.095)**2)*math.sin(math.pi*v)
    x=u*width(y)+(front(u,1)[0]-u*width(y0))*(1-v)**4
    return (x,y,z)
def deck(u,v):
    cross=min(1,(u*.94/.78)**2);y0=1.46-.03*cross;y1=rear(u,1)[1];y=lerp(y0,y1,v)
    z=belt(y)+.030*(1-u*u)
    z+=(1.075-.030*cross-(belt(y0)+.03*(1-u*u)))*(1-v)**4
    z+=(belt(REAR)+.03*(1-u*u)-(belt(y1)+.03*(1-u*u)))*v**4
    x=u*width(y)+(rear(u,1)[0]-u*width(y1))*v**4
    return (x,y,z)

# The hood and adjacent fender crowns share the SAME analytic surface.
grid('Hood | inner gap backing',lambda u,v:Vector(hood(u,v))-Vector((0,0,.007)),seq(-1,1,32),seq(0,1,20),black,thickness=.004,normal=lambda p:(0,0,1))
for name,a,b in [('Hood | centre panel',-.785,.785),('Fender crown | L',-1,-.790),('Fender crown | R',.790,1)]:
    grid(name,hood,seq(a,b,26 if 'centre' in name else 8),seq(.003,.997,26),paint,thickness=.004,normal=lambda p:(0,0,1))
grid('Trunk | inner gap backing',lambda u,v:Vector(deck(u,v))-Vector((0,0,.007)),seq(-1,1,32),seq(0,1,16),black,thickness=.004,normal=lambda p:(0,0,1))
for name,a,b in [('Trunk lid',-.86,.86),('Rear fender crown L',-1,-.865),('Rear fender crown R',.865,1)]:
    grid(name,deck,seq(a,b,30 if 'lid' in name else 7),seq(.002,.998,21),paint,thickness=.004,normal=lambda p:(0,0,1))

front_holes=[('Upper grille',-.61,.61,.32,.69),('Lower intake',-.56,.56,.075,.235),('Headlamp L',-.965,-.66,.755,.925),('Headlamp R',.66,.965,.755,.925)]
rear_holes=[('Rear light band',-.96,.96,.73,.87),('Registration recess',-.29,.29,.34,.61),('Rear diffuser',-.68,.68,.06,.23)]
def fascia(name,fn,holes,facing):
    us=set(seq(-1,1,44));vs=set(seq(0,1,20))
    for _,a,b,c,d in holes:us.update([a,b]);vs.update([c,d])
    us=sorted(us);vs=sorted(vs);nu=len(us)
    vv=[fn(u,v) for v in vs for u in us];ff=[]
    for j in range(len(vs)-1):
        for i in range(len(us)-1):
            u=(us[i]+us[i+1])/2;v=(vs[j]+vs[j+1])/2
            if any(a<u<b and c<v<d for _,a,b,c,d in holes):continue
            face=(j*nu+i,j*nu+i+1,(j+1)*nu+i+1,(j+1)*nu+i)
            ff.append(face)
    o=mesh(name,vv,ff,paint)
    avg=sum((p.normal for p in o.data.polygons),Vector())
    if avg.y*facing<0:
        bm=bmesh.new();bm.from_mesh(o.data);bmesh.ops.reverse_faces(bm,faces=list(bm.faces));bm.to_mesh(o.data);bm.free()
    shell(o,.005)
    for label,a,b,c,d in holes:
        def recessed(u,v,fn=fn):
            p=Vector(fn(u,v));p.y-=facing*.025;return p
        grid(label+' | recessed backing',recessed,seq(a,b,24),seq(c,d,5),black,thickness=.004,normal=lambda p:(0,facing,0))
        # Actual return from the cut opening to the recessed backing.
        loop_patch(label+' | inset frame',fn,(a,b,c,d),(a+.008,b-.008,c+.009,d-.009),black,depth=-facing*.001)
        border=[(a,c),(b,c),(b,d),(a,d),(a,c)]
        for k in range(4):
            p0,p1=border[k],border[k+1]
            grid(label+' | aperture wall '+str(k),lambda t,w:Vector(fn(lerp(p0[0],p1[0],t),lerp(p0[1],p1[1],t)))+Vector((0,-facing*.025*w,0)),seq(0,1,24),[0,1],black,thickness=.001)
fascia('Front | continuous bumper and lamp apertures',front,front_holes,-1)
fascia('Rear | continuous bumper and lamp apertures',rear,rear_holes,1)

for label,a,b,c,d in front_holes:
    if 'grille' in label or 'intake' in label:
        for k,v in enumerate(seq(c+.025,d-.025,5 if 'grille' in label else 2)):
            tube(label+' | horizontal aero blade '+str(k),[Vector(front(u,v))+Vector((0,.011,0)) for u in seq(a+.016,b-.016,38)],.0065 if 'grille' in label else .004,chrome if k==0 else darkmetal,sides=6)
        for u in seq(a+.025,b-.025,16):
            tube(label+' | vertical support '+str(round(u,3)),[Vector(front(u,v))+Vector((0,.019,0)) for v in [c+.015,d-.015]],.0025,black,sides=5)
    if 'Headlamp' in label:
        for k,v in enumerate([d-.025,c+.025]):
            tube(label+' | LED signature '+str(k),[Vector(front(u,v))+Vector((0,.006,0)) for u in seq(a+.018,b-.018,28)],.006,led,sides=8)
        for k,u in enumerate(seq(a+.055,b-.055,2)):
            p=Vector(front(u,(c+d)/2));p.y+=.011
            cylinder(label+' | projector bezel '+str(k),p,.024,.012,chrome,axis=(0,1,0),n=24)
            p.y-=.007;cylinder(label+' | projector optic '+str(k),p,.018,.004,lampglass,axis=(0,1,0),n=24)
        grid(label+' | clear lens',lambda u,v:Vector(front(u,v))+Vector((0,.0015,0)),seq(a+.012,b-.012,22),seq(c+.013,d-.013,6),lampglass,thickness=.002,normal=lambda p:(0,-1,0))
for v in [.768,.825]:
    tube('Rear | full width LED '+str(v),[Vector(rear(u,v))+Vector((0,-.006,0)) for u in seq(-.94,.94,80)],.0065,redled,sides=8)
grid('Rear | smoked red lamp lens',lambda u,v:Vector(rear(u,v))+Vector((0,-.002,0)),seq(-.95,.95,60),seq(.742,.858,6),redglass,thickness=.002,normal=lambda p:(0,1,0))
for s in [-1,1]:
    for u in seq(s*.76,s*.92,4):
        tube('Rear | optical vertical bars '+str(u),[Vector(rear(u,v))+Vector((0,-.008,0)) for v in [.748,.85]],.003,redled,sides=6)
    tube('Front | lower bumper blade '+str(s),[Vector(front(u,.015))+Vector((0,-.004,-.004)) for u in seq(0,s*.97,40)],.012,black,sides=8)
    tube('Rear | lower bumper blade '+str(s),[Vector(rear(u,.014))+Vector((0,.004,-.004)) for u in seq(0,s*.97,40)],.012,black,sides=8)
    for u in [s*.31,s*.54]:
        box('Rear | diffuser vertical fin '+str(u),(u,2.273,.287),(.014,.09,.08),black,radius=.004)

# Greenhouse: windshield/roof/rear window and side frame use shared endpoints.
def wind(u,v):
    return (u*lerp(.78,.67,v),lerp(-.84+.05*u*u,-.25+.04*u*u,v),lerp(1.04-.025*u*u,1.475-.05*u*u,v)+.009*math.sin(math.pi*v)*(1-u*u))
def roof(u,v):
    return (u*(.67+.018*math.sin(math.pi*v)),lerp(-.25+.04*u*u,.82-.04*u*u,v),lerp(1.475-.05*u*u,1.471-.05*u*u,v)+.035*math.sin(math.pi*v)*(1-.3*u*u))
def backwindow(u,v):
    return (u*lerp(.67,.78,v),lerp(.82-.04*u*u,1.46-.03*u*u,v),lerp(1.471-.05*u*u,1.075-.030*u*u,v)+.008*math.sin(math.pi*v)*(1-u*u))
for label,fn in [('Windshield',wind),('Rear window',backwindow)]:
    inset=Vector((0,.0015 if label=='Windshield' else -.0015,-.002))
    grid(label+' | clear curved glass',lambda u,v:Vector(fn(u,v))+inset,seq(-.962,.962,28),seq(.032,.968,18),glass,thickness=.003,normal=lambda p:(0,-1 if label=='Windshield' else 1,1))
    loop_patch(label+' | painted frame',fn,(-1,1,0,1),(-.977,.977,.020,.980),paint)
    loop_patch(label+' | rubber ceramic border',fn,(-.977,.977,.020,.980),(-.951,.951,.041,.959),rubber)
grid('Roof | continuous crown',roof,seq(-1,1,28),seq(0,1,26),paint,thickness=.007,normal=lambda p:(0,0,1))
grid('Roof | inner headliner',lambda u,v:Vector(roof(u,v))-Vector((0,0,.028)),seq(-.97,.97,20),seq(.025,.975,20),headliner,'Interior',.003,lambda p:(0,0,-1))
for s,side in [(1,'L'),(-1,'R')]:
    for a,b,group in [(-.79,.296,'DoorF'+side),(.304,1.266,'DoorR'+side),(1.270,1.43,'Body')]:
        grid('Shoulder | window to body bridge '+group,lambda y,t:(s*lerp(width(y),.78,t),y,belt(y)+.004*math.sin(math.pi*t)),seq(a,b,max(6,round((b-a)*24))),seq(0,1,5),paint,group,thickness=.004,normal=lambda p:(0,0,1))
    cornersF=[(-.79,1.015),(.30,1.035),(.30,1.448),(-.21,1.425)]
    cornersR=[(.30,1.035),(1.43,1.045),(.78,1.421),(.30,1.448)]
    def sidegreen(corners,u,v):
        y=lerp(lerp(corners[0][0],corners[1][0],u),lerp(corners[3][0],corners[2][0],u),v)
        z=lerp(lerp(corners[0][1],corners[1][1],u),lerp(corners[3][1],corners[2][1],u),v)
        t=(y+.21)/.99;upperx=.67+.018*math.sin(math.pi*max(0,min(1,t)))
        x=lerp(.78,upperx,v)+.007*math.sin(math.pi*u)*math.sin(math.pi*v)
        return Vector((s*x,y,z))
    for letter,corners in [('F',cornersF),('R',cornersR)]:
        group='Door'+letter+side
        fn=lambda u,v,corners=corners:sidegreen(corners,u,v)
        loop_patch(group+' | structural window frame',fn,(0,1,0,1),(.032,.968,.065,.932),paint,group)
        loop_patch(group+' | window gasket',fn,(.030,.970,.062,.935),(.046,.954,.084,.914),rubber,group)
        grid(group+' | clear curved window',lambda u,v:fn(u,v)-Vector((s*.002,0,0)),seq(.044,.956,18),seq(.081,.917,10),glass,group,.003,lambda p:(s,0,.2))
        tube(group+' | belt brightwork',[fn(u,.045)+Vector((s*.003,0,0)) for u in seq(.01,.99,35)],.0038,chrome,group,sides=6)
    # Interior lower door card aligned inward from the skin.
    for a,b,group in [(-.75,.28,'DoorF'+side),(.33,1.19,'DoorR'+side)]:
        grid(group+' | contoured inner door card',lambda y,t:(s*(side_x(y,lerp(.31,.99,t))-.075),y,lerp(.31,.99,t)),seq(a,b,20),seq(0,1,10),leather,group,.009,lambda p:(-s,0,0))
        tube(group+' | interior armrest',[(s*.767,y,.635) for y in seq(a+.10,b-.07,20)],.025,dashmat,group,sides=8)
        box(group+' | interior release',(s*.785,a+.21,.84),(.022,.10,.025),chrome,group,radius=.006)
    # Mirror stem and sculpted cap, outside the cabin envelope.
    tube('Mirror | mounting stalk '+side,[(s*.82,-.65,1.04),(s*.96,-.70,1.01)],.025,black,sides=12)
    cap=pillow('Mirror | painted cap '+side,(s*1.002,-.69,1.045),.19,.18,.103,paint,'Body')
    mirror=box('Mirror | reflective insert '+side,(s*1.005,-.607,1.043),(.151,.006,.061),chrome,radius=.012)
    tube('Mirror | signal '+side,[(s*x,-.765,1.025) for x in seq(.94,1.07,12)],.0028,led,sides=6)

# Windshield cowl and two physically separate wipers.
grid('Cowl | curved sealed tray',lambda u,v:(.78*u,lerp(-.885+.05*u*u,-.838+.05*u*u,v),1.032-.025*u*u-.004*(1-v)),seq(-1,1,40),seq(0,1,5),black,thickness=.004,normal=lambda p:(0,0,1))
for x in [-.40,.23]:
    tube('Wiper | arm '+str(x),[(x,-.819,1.055),(x+.10,-.785,1.069),(x+.19,-.759,1.085)],.004,black,sides=6)
    tube('Wiper | blade '+str(x),[(x-.20,-.780,1.075),(x+.25,-.752,1.09)],.006,rubber,sides=8)

# Wheels are rotational solids with controlled profiles, not AI wheel lumps.
pivots={}
for s,side in [(1,'L'),(-1,'R')]:
  for yc,which in [(FY,'F'),(RY,'R')]:
    group='Wheel'+which+side;xc=s*.825;pivots[group]=[xc,yc,WZ]
    profile=[(-.112,.261),(-.115,.286),(-.105,.318),(-.085,.337),(-.061,.344),(.061,.344),(.085,.337),(.105,.318),(.115,.286),(.112,.261)]
    vv=[];ff=[];n=64
    for a,r in profile:
        vv += [(xc+s*a,yc+r*math.sin(t),WZ+r*math.cos(t)) for t in seq(0,2*math.pi,n)[:-1]]
    for j in range(len(profile)):
        nj=(j+1)%len(profile)
        for k in range(n):ff.append((j*n+k,j*n+(k+1)%n,nj*n+(k+1)%n,nj*n+k))
    mesh(group+' | profiled tyre',vv,ff,rubber,group)
    for off in [-.042,0,.042]:
        tube(group+' | tread channel '+str(off),[(xc+s*off,yc+.3445*math.sin(t),WZ+.3445*math.cos(t)) for t in seq(0,2*math.pi,64)[:-1]],.0014,black,group,sides=5,closed=True)
    for a in seq(0,2*math.pi,40)[:-1]:
        for sg in [-1,1]:
            pts=[]
            for t in seq(0,1,3):
                ang=a+.08*t;off=sg*lerp(.055,.093,t);r=lerp(.344,.334,t)
                pts.append((xc+s*off,yc+r*math.sin(ang),WZ+r*math.cos(ang)))
            tube(group+' | shoulder tread '+str(round(a,3))+' '+str(sg),pts,.0013,black,group,sides=4)
    outerx=xc+s*.107
    for radius in [.254,.266]:
        tube(group+' | machined rim lip '+str(radius),[(outerx,yc+radius*math.sin(t),WZ+radius*math.cos(t)) for t in seq(0,2*math.pi,64)[:-1]],.007,chrome,group,sides=8,closed=True)
    barrel_profile=[(-.08,.247),(.08,.247),(.08,.239),(-.08,.239)]
    bv=[(xc+s*ax,yc+r*math.sin(t),WZ+r*math.cos(t)) for ax,r in barrel_profile for t in seq(0,2*math.pi,64)[:-1]]
    bf=[]
    for j in range(4):
        for k in range(64):bf.append((j*64+k,j*64+(k+1)%64,((j+1)%4)*64+(k+1)%64,((j+1)%4)*64+k))
    mesh(group+' | open rim barrel',bv,bf,darkmetal,group)
    # Rotor is forward of the barrel end and behind the spoke plane.
    cylinder(group+' | brake rotor',(outerx-s*.035,yc,WZ),.206,.009,rotormat,group,n=64)
    for a in seq(0,2*math.pi,28)[:-1]:
        cylinder(group+' | rotor perforation '+str(round(a,3)),(outerx-s*.029,yc+.174*math.sin(a),WZ+.174*math.cos(a)),.004,.0008,black,group,n=8)
    box(group+' | red brake caliper',(outerx-s*.012,yc+.16,WZ+.015),(.036,.064,.135),brake,group,radius=.015)
    for k in range(5):
      for split in [-1,1]:
        angle=2*math.pi*k/5+split*.085
        vv=[]
        for xoff in [-.016,.004]:
            for r,da in [(.055,-.18),(.245,-.048),(.245,.048),(.07,.18)]:
                a=angle+da;vv.append((outerx+s*xoff,yc+r*math.sin(a),WZ+r*math.cos(a)))
        o=mesh(group+' | split spoke '+str(k)+' '+str(split),vv,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],chrome,group,False)
        bevel(o,.003,2)
    cylinder(group+' | centre cap',(outerx+s*.006,yc,WZ),.062,.018,darkmetal,group,n=40)
    for a in seq(0,2*math.pi,5)[:-1]:
        cylinder(group+' | lug '+str(round(a,3)),(outerx+s*.017,yc+.043*math.sin(a),WZ+.043*math.cos(a)),.008,.006,chrome,group,n=8)

# Interior, designed inside the same glazing envelope.
box('Cabin | floor pan',(0,.19,.305),(1.59,2.18,.035),dashmat,'Interior',radius=.03)
box('Cabin | lower undertray',(0,.02,.195),(1.64,3.60,.04),black,radius=.04)
for s in [-1,1]:
    x=s*.405
    pillow('Front seat | cushion '+str(s),(x,.04,.50),.48,.55,.17,leather)
    pillow('Front seat | cushion insert '+str(s),(x,.005,.577),.325,.40,.035,suede)
    pillow('Front seat | sculpted back '+str(s),(x,.315,.86),.47,.17,.62,leather,lean=.12)
    pillow('Front seat | back insert '+str(s),(x,.226,.86),.31,.025,.46,suede,lean=.09)
    for sign in [-1,1]:
        pillow('Front seat | side bolster '+str(s)+' '+str(sign),(x+sign*.196,.05,.572),.09,.49,.13,leather)
        tube('Front seat | headrest post '+str(s)+' '+str(sign),[(x+sign*.067,.365,1.08),(x+sign*.067,.365,1.185)],.008,chrome,'Interior',sides=8)
    pillow('Front seat | head restraint '+str(s),(x,.37,1.23),.26,.13,.185,leather)
    for dx in [-.14,.14]:
        tube('Front seat | cushion stitch '+str(s)+' '+str(dx),[(x+dx,y,.595) for y in seq(-.15,.16,18)],.0008,chrome,'Interior',sides=4)
    box('Front seat | rail '+str(s),(x,.09,.377),(.36,.43,.035),black,'Interior',radius=.008)
    box('Front seat | belt buckle '+str(s),(x-s*.255,.21,.54),(.033,.055,.08),black,'Interior',radius=.009)
    box('Front seat | belt release '+str(s),(x-s*.255,.20,.582),(.025,.033,.009),brake,'Interior',radius=.002)
pillow('Rear bench | full cushion',(0,.98,.52),1.43,.48,.19,leather)
pillow('Rear bench | sculpted back',(0,1.10,.85),1.43,.17,.58,leather,lean=.10)
for x in [-.46,0,.46]:
    pillow('Rear bench | headrest '+str(x),(x,1.055,1.15),.255,.12,.16,leather)
    for dx in [-.065,.065]:
        tube('Rear headrest | post '+str(x)+' '+str(dx),[(x+dx,1.10,1.095),(x+dx,1.10,1.145)],.006,chrome,'Interior',sides=8)
    pillow('Rear bench | seat insert '+str(x),(x,.97,.61),.34,.36,.027,suede)
box('Rear parcel shelf',(0,1.37,1.005),(1.48,.25,.025),dashmat,'Interior',radius=.02)

def dash(u,v):
    x=.724*u
    fronty=-.772+.075*u*u;backy=-.415+.025*u*u
    return (x,lerp(fronty,backy,v),.875+.052*(1-u*u)+.020*math.sin(math.pi*v)-.035*v)
grid('Dashboard | full width sculpted upper',dash,seq(-1,1,32),seq(0,1,12),dashmat,'Interior',.035,lambda p:(0,0,1))
grid('Dashboard | front fascia',lambda u,t:(.724*u,-.415+.025*u*u+.010*t,lerp(.84,.69,t)+.05*(1-u*u)),seq(-1,1,40),seq(0,1,8),leather,'Interior',.009,lambda p:(0,1,0))
tube('Dashboard | aluminium sweep',[(.715*u,-.402+.025*u*u,.845+.024*(1-u*u)) for u in seq(-1,1,60)],.004,chrome,'Interior',sides=6)
for x in [-.61,-.10,.15,.61]:
    box('Dashboard | vent surround '+str(x),(x,-.39,.824),(.15,.021,.047),black,'Interior',radius=.009)
    for z in [.812,.826,.840]:box('Dashboard | vent vane '+str(x)+' '+str(z),(x,-.377,z),(.126,.005,.0025),chrome,'Interior',radius=.0006)
box('Dashboard | glovebox',(-.405,-.389,.735),(.43,.012,.10),dashmat,'Interior',radius=.01)
box('Centre console | sculpted tunnel',(0,.05,.503),(.245,.98,.26),leather,'Interior',radius=.055)
box('Centre console | satin top',(0,-.06,.641),(.216,.53,.018),darkmetal,'Interior',radius=.018)
pillow('Centre console | armrest',(0,.34,.682),.22,.32,.12,leather)
cylinder('Centre console | drive selector',(0,-.10,.669),.035,.025,chrome,'Interior',axis=(0,0,1),n=32)
cylinder('Centre console | selector top',(0,-.10,.684),.028,.004,black,'Interior',axis=(0,0,1),n=32)
for y in [.04,.155]:
    cylinder('Centre console | cup recess '+str(y),(0,y,.654),.039,.006,black,'Interior',axis=(0,0,1),n=32)
    tube('Centre console | cup rim '+str(y),[(.042*math.cos(t),y+.042*math.sin(t),.658) for t in seq(0,2*math.pi,32)[:-1]],.0025,chrome,'Interior',sides=6,closed=True)

# Tilted three-spoke steering wheel and isolated pivot.
steering=Vector((.405,-.37,.963));pivots['Steering']=list(steering)
axis=Vector((0,-math.cos(math.radians(30)),-math.sin(math.radians(30))));a=Vector((1,0,0));b=axis.cross(a)
driver_normal=-axis
wheelpts=[steering+.166*(math.cos(t)*a+math.sin(t)*b) for t in seq(0,2*math.pi,64)[:-1]]
tube('Steering | stitched leather rim',wheelpts,.019,leather,'Steering',sides=16,closed=True)
for ang in [0,math.pi,math.pi*1.5]:
    p=steering+.137*(math.cos(ang)*a+math.sin(ang)*b)
    tube('Steering | metal spoke '+str(ang),[steering,p],.021,darkmetal,'Steering',sides=8)
o=box('Steering | airbag pad',steering,(.145,.058,.103),leather,'Steering',radius=.025)
o.rotation_euler.x=math.radians(30)
for s in [-1,1]:
    p=steering+Vector((s*.097,0,0))+driver_normal*.024
    o=box('Steering | control pad '+str(s),p,(.043,.025,.035),black,'Steering',radius=.007);o.rotation_euler.x=math.radians(30)
    for z in [-.007,.007]:
        o=box('Steering | button '+str(s)+' '+str(z),p+driver_normal*.014+b*z,(.022,.004,.003),chrome,'Steering',radius=.001);o.rotation_euler.x=math.radians(30)
tube('Steering | column',[(.405,-.404,.736),(.405,-.376,.779),tuple(steering-driver_normal*.02)],.016,dashmat,'Interior',sides=16)
box('Steering | lower dashboard mount',(.405,-.389,.744),(.085,.026,.058),dashmat,'Interior',radius=.012)
for x in [.55,.48]:
    box('Driver | pedal '+str(x),(x,-.68,.40),(.055,.025,.09),darkmetal,'Interior',radius=.006)
box('Cabin | interior mirror',(0,-.345,1.325),(.20,.035,.062),black,'Interior',radius=.015)
box('Cabin | mirror reflective face',(0,-.323,1.325),(.177,.004,.046),chrome,'Interior',radius=.008)
tube('Cabin | mirror mount',[(0,-.36,1.352),(0,-.33,1.402)],.009,black,'Interior',sides=8)

# Screens use newly authored flat UI graphics with explicit, unmirrored UVs.
def screen(name,center,w,h,filename):
    tilt=math.radians(12);center=Vector(center);right=Vector((-1,0,0));up=Vector((0,-math.sin(tilt),math.cos(tilt)))
    normal=right.cross(up).normalized()
    o=box(name+' | housing',center-normal*.017,(w+.022,.025,h+.019),black,'Interior',radius=.012)
    o.rotation_euler.x=tilt
    mat=material(name+' | display',(.015,.02,.025),0,.3)
    im=bpy.data.images.load(str(OUT/filename),check_existing=True);im.pack()
    bs=mat.node_tree.nodes.get('Principled BSDF');tex=mat.node_tree.nodes.new('ShaderNodeTexImage');tex.image=im
    mat.node_tree.links.new(tex.outputs['Color'],bs.inputs['Base Color'])
    mat.node_tree.links.new(tex.outputs['Color'],bs.inputs['Emission Color']);bs.inputs['Emission Strength'].default_value=.6
    vv=[center+right*x+up*z for x,z in [(-w/2,-h/2),(w/2,-h/2),(w/2,h/2),(-w/2,h/2)]]
    o=mesh(name+' | display panel',vv,[(0,1,2,3)],mat,'Interior',False)
    uv=o.data.uv_layers.active
    for loop in o.data.loops:
        delta=o.data.vertices[loop.vertex_index].co-center
        uv.data[loop.index].uv=(delta.dot(right)/w+.5,delta.dot(up)/h+.5)
    shell(o,.001)
screen('Instrument cluster',(.405,-.598,1.025),.315,.122,'S3_Instruments.png')
screen('Centre navigation',(-.12,-.479,1.008),.32,.168,'S3_Navigation.png')

# Registration plates are small flat graphic surfaces, with no borrowed badges.
def plate(name,fn,u0,u1,v0,v1,facing):
    center=Vector(fn((u0+u1)/2,(v0+v1)/2));center.y+=facing*.016
    box(name+' | mount',center,(.39,.016,.084),black,radius=.006)
    mat=material(name+' | printed plate',(.7,.7,.7),0,.45)
    im=bpy.data.images.load(str(OUT/'S3_Plate.png'),check_existing=True);im.pack()
    tex=mat.node_tree.nodes.new('ShaderNodeTexImage');tex.image=im
    mat.node_tree.links.new(tex.outputs['Color'],mat.node_tree.nodes.get('Principled BSDF').inputs['Base Color'])
    y=center.y+facing*.009;x=.184;z=.035
    # UV order faces the plate on each end, preserving text orientation.
    vv=[(-x,y,center.z-z),(x,y,center.z-z),(x,y,center.z+z),(-x,y,center.z+z)]
    ff=[(0,1,2,3)] if facing==-1 else [(1,0,3,2)]
    o=mesh(name+' | printed face',vv,ff,mat,smooth=False)
    for loop in o.data.loops:
        co=o.data.vertices[loop.vertex_index].co
        o.data.uv_layers.active.data[loop.index].uv=(-facing*co.x/(2*x)+.5,(co.z-center.z)/(2*z)+.5)
    shell(o,.001)
plate('Front plate',front,-.24,.24,.29,.46,-1)
plate('Rear plate',rear,-.24,.24,.37,.57,1)

# Function groups/pivots are provided for later chassis integration.
for side,s in [('L',1),('R',-1)]:
    pivots['DoorF'+side]=[s*.88,-.79,.73]
    pivots['DoorR'+side]=[s*.90,.305,.75]
pivots['Body']=[0,0,.60];pivots['Interior']=[0,0,.60]
for group,pivot in pivots.items():
    collection=bpy.data.collections.new(group);scene.collection.children.link(collection)
    root=bpy.data.objects.new(group+' | pivot',None);collection.objects.link(root);root.location=pivot
    root['group']=group;root['pivotMetres']=pivot
    if group=='Steering':root['DriverFacingCorrected']=True;root['DriverFacingNormal']=list(driver_normal)
    bpy.context.view_layer.update()
    for o in [o for o in BUILT if o.get('group')==group]:
        world=o.matrix_world.copy()
        for c in list(o.users_collection):c.objects.unlink(o)
        collection.objects.link(o);o.parent=root;o.matrix_world=world

# Keep the wheel subassemblies editable without hundreds of tiny tread objects.
for group in [g for g in pivots if g.startswith('Wheel')]:
    mats={o.data.materials[0] for o in BUILT if o.get('group')==group}
    for mat in mats:
        objects=[o for o in BUILT if o.get('group')==group and o.data.materials[0]==mat]
        if len(objects)<2:continue
        for o in bpy.context.selected_objects:o.select_set(False)
        for o in objects:o.select_set(True)
        bpy.context.view_layer.objects.active=objects[0]
        source_names=[o.name for o in objects]
        for o in objects:BUILT.remove(o)
        bpy.ops.object.join();joined=bpy.context.object
        joined.name=group+' | '+mat.name.split(' | ')[-1]
        joined['sourcePartNames']=source_names
        BUILT.append(joined)

# UVs for the few primitive detail meshes; no pixel art is baked into the body.
for o in BUILT:
    if not o.data.uv_layers:
        layer=o.data.uv_layers.new(name='UVMap')
        for p in o.data.polygons:
            axis=max(range(3),key=lambda k:abs(p.normal[k]));axes=[k for k in range(3) if k!=axis]
            for li in p.loop_indices:
                co=o.data.vertices[o.data.loops[li].vertex_index].co
                layer.data[li].uv=(co[axes[0]],co[axes[1]])
    for p in o.data.polygons:
        if p.area<1e-13:print('TINY_FACE',o.name,p.index,p.area)

scene.render.engine='CYCLES';scene.cycles.samples=32;scene.cycles.use_denoising=True
scene.render.resolution_x=1440;scene.render.resolution_y=1000;scene.render.resolution_percentage=100
scene.view_settings.view_transform='AgX';scene.world.use_nodes=True
scene.world.node_tree.nodes['Background'].inputs['Color'].default_value=(.24,.30,.38,1)
scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value=.35
presentation=bpy.data.collections.new('Presentation | excluded from export');scene.collection.children.link(presentation)
for i,(loc,power,size,target) in enumerate([((-3,-3,5),1600,5,(0,0,.6)),((4,-1,4),1800,4,(0,0,.7)),((1,5,5),2100,4,(0,.4,.8)),((-4,2,2.5),500,3,(0,0,.6))]):
    bpy.ops.object.light_add(type='AREA',location=loc);o=bpy.context.object;o.name='Studio softbox '+str(i);o.data.energy=power;o.data.shape='DISK';o.data.size=size
    o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler()
    for c in list(o.users_collection):c.objects.unlink(o)
    presentation.objects.link(o)
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.003));o=bpy.context.object;o.name='Studio ground';o.data.materials.append(material('Studio ground',(.045,.057,.072),.10,.5))
for c in list(o.users_collection):c.objects.unlink(o)
presentation.objects.link(o)
bpy.ops.object.camera_add(location=(-5.4,-6.4,2.9));cam=bpy.context.object;cam.name='Presentation camera';cam.data.lens=52;cam.rotation_euler=(Vector((0,0,.72))-cam.location).to_track_quat('-Z','Y').to_euler();scene.camera=cam
for c in list(cam.users_collection):c.objects.unlink(cam)
presentation.objects.link(cam)
bpy.context.view_layer.update()
for o in bpy.context.selected_objects:o.select_set(False)
for o in BUILT:o.select_set(True)
bpy.context.view_layer.objects.active=BUILT[0]
# Save an immediately usable editing view, with camera and lights hidden in viewport.
for o in presentation.objects:
    if o.type in {'LIGHT','CAMERA'}:o.hide_set(True)
for screen_data in bpy.data.screens:
    for area in screen_data.areas:
        if area.type=='VIEW_3D':
            area.spaces.active.clip_end=1000
            area.spaces.active.region_3d.view_distance=7
            area.spaces.active.region_3d.view_location=(0,0,.7)
            area.spaces.active.region_3d.view_rotation=cam.rotation_euler.to_quaternion()
            area.spaces.active.shading.type='MATERIAL'
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'BoraS3.blend'))
bpy.ops.export_scene.gltf(filepath=str(OUT/'BoraS3.glb'),export_format='GLB',use_selection=True,export_yup=True,export_apply=True,export_extras=True,export_cameras=False,export_lights=False)
for path,digest in hashes.items():assert hashfile(ROOT/path)==digest,'Protected file changed: '+path
provenance={'name':'BORA S3','stage':'new complete editable candidate, not user-approved','sourceProportions':str(SOURCE.relative_to(ROOT)),
 'sourceBounds':source_bounds,'reference':str(REF.relative_to(ROOT)),'referenceGeometryCopied':False,'rejectedS2Used':False,
 'description':'New matched parametric panels, greenhouse and independently authored interior; based on existing Tripo sedan proportions.',
 'protectedFiles':hashes,'protectedUnchanged':True,'pivots':pivots,'installedInPlace':False}
(OUT/'provenance.json').write_text(json.dumps(provenance,ensure_ascii=False,indent=2),encoding='utf-8')
print('BUILT_S3',len(BUILT),'objects',flush=True)
