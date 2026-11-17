"""Remove generated real-brand badge geometry; add original BORA markings.
Edits mesh geometry and replaces hub centers, not the source GLB or its atlas.
"""
from pathlib import Path
import json,struct,math,hashlib
import numpy as np
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'assets/vehicles/local'
m=json.loads((OUT/'manifest.json').read_text(encoding='utf-8'))
if m.get('VirtualBrand')=='BORA':
 print('BORA brand already applied.')
 raise SystemExit(0)
header=b'version 2.00\n'
def read(path):
 binary=path.read_bytes();_,stride,_,nv,nf=struct.unpack_from('<HBBII',binary,len(header));start=len(header)+12
 rows=[binary[start+i*stride:start+(i+1)*stride] for i in range(nv)]
 faces=[struct.unpack_from('<III',binary,start+nv*stride+i*12) for i in range(nf)]
 return rows,faces
def write(path,rows,faces):
 path.write_bytes(header+struct.pack('<HBBII',12,40,12,len(rows),len(faces))+b''.join(rows)+b''.join(struct.pack('<III',*f) for f in faces))
def bounds(rows):
 points=[struct.unpack_from('<3f',r) for r in rows]
 return [max(.001,max(p[i] for p in points)-min(p[i] for p in points)) for i in range(3)]
removed=0
for part in list(m['Parts']):
 if part['Material']!='Tripo':continue
 rows,faces=read(OUT/part['File']);kept=[];repaint={'front':[],'rear':[],'wheel':[]}
 paint_uv=None
 if part['Group']=='Body':
  values=np.array([struct.unpack_from('<8f',row) for row in rows])
  target=np.array([.25,.94,2.23]);nearest=np.argmin(np.sum((values[:,:3]-target)**2,axis=1));paint_uv=values[nearest,6:8]
  # Change shared positions before splitting faces so patch edges stay welded.
  for i,row in enumerate(rows):
   data=list(struct.unpack_from('<8f',row));x,y,z=data[:3]
   if abs(x)<.15 and .49<y<.71 and z< -2.24:
    blend=max(0,1-(abs(x)/.15)**6)*max(0,1-(abs(y-.60)/.11)**6)
    data[2]=z+(-2.322-z)*blend
    rows[i]=struct.pack('<8f',*data)+row[32:]
 for face in faces:
  p=[sum(struct.unpack_from('<3f',rows[i])[axis] for i in face)/3 for axis in range(3)]
  x,y,z=p;region=None
  if part['Group']=='Body':
   if abs(x)<.14 and .50<y<.70 and z< -2.24:region='front'
   elif (abs(x)<.18 and .79<y<1.09 and z>1.95) or (abs(x)<.57 and .68<y<.84 and z>2.10):region='rear'
  elif part['Group'].startswith('Wheel'):
   if y*y+z*z<.060**2 and abs(x)>.04:region='wheel'
  if region:removed+=1;repaint[region].append(face)
  else:kept.append(face)
 for region,patch in repaint.items():
  if not patch:continue
  used=sorted({i for face in patch for i in face});mapping={old:new for new,old in enumerate(used)}
  patch_rows=[]
  for i in used:
   original=rows[i];values=list(struct.unpack_from('<8f',original));x,y,z=values[:3]
   if region=='rear':values[6:8]=paint_uv
   patch_rows.append(struct.pack('<8f',*values)+original[32:])
  patch_faces=[tuple(mapping[i] for i in f) for f in patch]
  filename=part['Group']+'_Debadged_'+region+'.mesh';write(OUT/filename,patch_rows,patch_faces)
  entry={'Group':part['Group'],'Material':'Debadged','File':filename,'Color':([20,25,29] if region=='front' else [255,255,255]) if part['Group']=='Body' else [155,163,170],
   'Transparency':0,'Bounds':bounds(patch_rows),'Triangles':len(patch_faces)}
  if region=='rear':entry['Texture']='TripoSedan.png'
  m['Parts'].append(entry)
 used=sorted({i for face in kept for i in face});mapping={old:new for new,old in enumerate(used)}
 rows=[rows[i] for i in used];kept=[tuple(mapping[i] for i in f) for f in kept]
 write(OUT/part['File'],rows,kept);part['Triangles']=len(kept);part['Bounds']=bounds(rows)

def make_builder(group,key):
 return {'Group':group,'Material':key,'Rows':[],'Faces':[]}
def triangle(builder,a,b,c):
 u=[b[i]-a[i] for i in range(3)];v=[c[i]-a[i] for i in range(3)]
 n=[u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]];length=math.sqrt(sum(x*x for x in n));n=[x/length for x in n]
 start=len(builder['Rows'])
 for point in (a,b,c):builder['Rows'].append(struct.pack('<8f4b4B',*point,*n,0,0,0,0,0,127,255,255,255,255))
 builder['Faces'].append((start,start+1,start+2))
def quad(builder,points):
 triangle(builder,*points[:3]);triangle(builder,points[0],points[2],points[3])
def box(builder,center,size):
 vertices=[tuple(center[i]+size[i]*p[i] for i in range(3)) for p in [(-.5,-.5,-.5),(.5,-.5,-.5),(.5,.5,-.5),(-.5,.5,-.5),(-.5,-.5,.5),(.5,-.5,.5),(.5,.5,.5),(-.5,.5,.5)]]
 for face in [(0,3,2,1),(4,5,6,7),(0,1,5,4),(3,7,6,2),(0,4,7,3),(1,2,6,5)]:quad(builder,[vertices[i] for i in face])
silver=make_builder('Body','BrandSilver')
for z,sign,y,slope in [(-2.335,-1,.60,.0),(2.286,1,.96,.1)]:
 # Original slanted double-chevron emblem, unrelated to the Hyundai oval H.
 for shift in [-.05,.035]:
  points=[(shift-.028,y-.032,z-.032*slope),(shift+.010,y,z),(shift-.028,y+.032,z+.032*slope),(shift-.010,y+.032,z+.032*slope),(shift+.028,y,z),(shift-.010,y-.032,z-.032*slope)]
  if sign<0:points.reverse()
  for i in range(1,len(points)-1):triangle(silver,points[0],points[i],points[i+1])
builders=[silver]
for code in ['FL','FR','RL','RR']:
 group='Wheel'+code;b=make_builder(group,'BrandSilver');side=-1 if code.endswith('L') else 1;x=side*.142
 center=(x,0,0)
 for i in range(32):
  a=i*2*math.pi/32;c=(i+1)*2*math.pi/32
  p=(x,.042*math.cos(a),.042*math.sin(a));q=(x,.042*math.cos(c),.042*math.sin(c))
  triangle(b,center,p,q) if side>0 else triangle(b,center,q,p)
 builders.append(b)
for index,b in enumerate(builders):
 filename=b['Group']+'_'+b['Material']+'.mesh';write(OUT/filename,b['Rows'],b['Faces'])
 m['Parts'].append({'Group':b['Group'],'Material':b['Material'],'File':filename,'Color':[15,21,26] if b['Material']=='BrandBlack' else [188,206,216],
 'Transparency':0,'Bounds':bounds(b['Rows']),'Triangles':len(b['Faces'])})
m['VirtualBrand']='BORA';m['DisplayName']='BORA S1';m['RemovedBadgeTriangles']=removed;m['DebrandedSurfaceTriangles']=removed
m['Design']='BORA S1 original virtual-brand compact sedan / Tripo base'
m['TotalTriangles']=sum(p['Triangles'] for p in m['Parts'])
digest=hashlib.sha256()
digest.update(json.dumps(m['Parts'],sort_keys=True).encode('utf-8'))
for filename in sorted({p['File'] for p in m['Parts']}|{p['Texture'] for p in m['Parts'] if p.get('Texture')}):digest.update((OUT/filename).read_bytes())
m['VisualHash']=digest.hexdigest()[:16]
(OUT/'manifest.json').write_text(json.dumps(m,indent=2),encoding='utf-8')
print('BORA S1:',removed,'surface triangles debranded;',m['TotalTriangles'],'final triangles.')
