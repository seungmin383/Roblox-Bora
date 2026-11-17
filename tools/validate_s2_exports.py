"""Validate native binary assets and exported GLB, without launching Studio."""
from pathlib import Path
import json,struct,math,hashlib,sys
import numpy as np
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'assets/vehicles/retopology'
FIT_FIX='--fit-fix' in sys.argv
NATIVE=OUT/('native-fit' if FIT_FIX else 'native')
manifest=json.loads((NATIVE/'manifest.json').read_text());native=[]
for p in manifest['Parts']:
 data=(NATIVE/p['File']).read_bytes();header=b'version 2.00\n';assert data.startswith(header)
 size,stride,face_stride,nv,nf=struct.unpack_from('<HBBII',data,len(header));base=len(header)+12
 assert size==12 and stride==40 and face_stride==12 and nf<=8000 and len(data)==base+40*nv+12*nf
 rows=np.ndarray((nv,8),dtype='<f4',buffer=data,offset=base,strides=(40,4));idx=np.frombuffer(data,dtype='<u4',count=3*nf,offset=base+nv*40).reshape(-1,3)
 assert np.isfinite(rows).all() and idx.max()<nv
 norm=np.linalg.norm(rows[:,3:6],axis=1);assert np.max(abs(norm-1))<.001
 tris=rows[idx,:3];areas=np.linalg.norm(np.cross(tris[:,1]-tris[:,0],tris[:,2]-tris[:,0]),axis=1)/2
 assert (areas>5e-12).all(),(p['File'],float(areas.min()))
 if p.get('Texture'):assert (NATIVE/p['Texture']).is_file()
 native.append({'file':p['File'],'vertices':nv,'triangles':nf,'normalMaxError':float(max(abs(norm-1))),'minTriangleArea':float(areas.min())})
data=(OUT/('BoraS2_FitFix.glb' if FIT_FIX else 'BoraS2_Clean.glb')).read_bytes();magic,version,size=struct.unpack_from('<III',data);assert magic==0x46546c67 and version==2 and size==len(data)
offset=12;chunks={}
while offset<len(data):
 n,t=struct.unpack_from('<II',data,offset);offset+=8;chunks[t]=data[offset:offset+n];offset+=n
g=json.loads(chunks[0x4e4f534a]);binary=chunks[0x004e4942]
def accessor(i):
 a=g['accessors'][i];view=g['bufferViews'][a['bufferView']];dims={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']];dtype={5126:'<f4',5125:'<u4',5123:'<u2',5121:'u1'}[a['componentType']]
 item=np.dtype(dtype).itemsize;start=view.get('byteOffset',0)+a.get('byteOffset',0)
 return np.ndarray((a['count'],dims),dtype=dtype,buffer=binary,offset=start,strides=(view.get('byteStride',dims*item),item))
glb_count=0;extensions=g.get('extensionsUsed',[])
for mesh in g['meshes']:
 for p in mesh['primitives']:
  pos=accessor(p['attributes']['POSITION']);normal=accessor(p['attributes']['NORMAL']);ids=accessor(p['indices']).ravel().reshape(-1,3)
  assert np.isfinite(pos).all() and np.isfinite(normal).all() and ids.max()<len(pos)
  assert np.max(abs(np.linalg.norm(normal,axis=1)-1))<.001
  vv=pos[ids];areas=np.linalg.norm(np.cross(vv[:,1]-vv[:,0],vv[:,2]-vv[:,0]),axis=1)/2;assert (areas>5e-12).all()
  glb_count+=len(ids)
assert glb_count==manifest['TotalTriangles']==sum(r['triangles'] for r in native)
old=json.loads((OUT/'preserved-files.json').read_text());changed=[p for p,h in old.items() if hashlib.sha256((ROOT/p).read_bytes()).hexdigest()!=h]
assert not changed
places=[str(p.relative_to(ROOT)) for ext in ['*.rbxl','*.rbxlx'] for p in ROOT.rglob(ext)];assert places==['Ro.rbxlx']
report={'status':'pass','totalTriangles':glb_count,'nativePartCount':len(native),'nativeParts':native,'glbExtensions':extensions,'preservedFilesChanged':changed,'placeFiles':places,'installedInPlace':False}
(OUT/('BoraS2_FitFix_ExportValidation.json' if FIT_FIX else 'BoraS2_ExportValidation.json')).write_text(json.dumps(report,indent=2))
print(json.dumps({k:v for k,v in report.items() if k!='nativeParts'}),flush=True)
