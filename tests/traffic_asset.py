from pathlib import Path
import hashlib,json,struct
import numpy as np
from PIL import Image
root=Path(__file__).resolve().parents[1]
folder=root/'assets/traffic/local'
for filename,metadata,task in [('TrafficSignal','manifest.json','ce30b66d-2fca-4301-81d8-824268179ce4'),('PedestrianSignal','pedestrian-manifest.json','18113186-2d02-4423-8ea5-c805f7780b75')]:
 manifest=json.loads((folder/metadata).read_text())
 assert manifest['source']=='Tripo Studio' and manifest['taskId']==task
 binary=(folder/f'{filename}.mesh').read_bytes();header=b'version 2.00\n'
 assert binary.startswith(header)
 size,stride,face_stride,nv,nf=struct.unpack_from('<HBBII',binary,len(header))
 assert (size,stride,face_stride)==(12,40,12) and 1000<=nf<=10000
 assert nf==manifest['triangles'] and len(binary)==len(header)+12+nv*stride+nf*12
 values=np.array([struct.unpack_from('<8f',binary,len(header)+12+i*stride) for i in range(nv)])
 faces=np.frombuffer(binary,dtype='<u4',offset=len(header)+12+nv*stride).reshape(-1,3)
 assert np.isfinite(values).all() and faces.max()<nv and faces.min()>=0
 assert np.all(np.abs(np.linalg.norm(values[:,3:6],axis=1)-1)<.01)
 assert np.allclose(values[:,:3].max(axis=0)-values[:,:3].min(axis=0),manifest['boundsMeters'],atol=.001)
 assert np.isfinite(manifest['lampCentersMeters']).all()
 image=Image.open(folder/f'{filename}.png');assert image.width==image.height==1024
 if filename=='PedestrianSignal':
  assert len(manifest['lampCentersMeters'])==2 and manifest['boundsMeters'][1]>.8
  layout=json.loads((root/'dist/pedestrian-display-calibration.json').read_text())
  assert np.allclose(layout['CentersMeters'],manifest['lampCentersMeters'],atol=.015),'Pedestrian icons do not match the generated displays'
 print(f'PASS: {filename}, Tripo provenance, {nf} triangles, positions/normals/UVs, indices, mesh length/bounds, calibrated displays, 1024px albedo.')
manifest=json.loads((folder/'extension-manifest.json').read_text())
assert manifest['sourceSha256']==hashlib.sha256((folder/'TrafficSignal.mesh').read_bytes()).hexdigest()
binary=(folder/'TrafficSignalExtension.mesh').read_bytes()
size,stride,face_stride,nv,nf=struct.unpack_from('<HBBII',binary,len(header))
assert (size,stride,face_stride)==(12,40,12) and 100<nf<3500
assert nf==manifest['triangles'] and len(binary)==len(header)+12+nv*stride+nf*12
values=np.array([struct.unpack_from('<8f',binary,len(header)+12+i*stride) for i in range(nv)])
indices=np.frombuffer(binary,dtype='<u4',offset=len(header)+12+nv*stride)
assert np.isfinite(values).all() and indices.max()<nv
assert np.all(np.abs(np.linalg.norm(values[:,3:6],axis=1)-1)<.01)
assert values[:,0].max()<=manifest['cutXMeters']-manifest['pitchMeters']+.001 and values[:,0].min()<manifest['lampCenterMeters'][0]-.25
assert values[:,6:8].min()>=0 and values[:,6:8].max()<=1
assert manifest['uvsPreserved'] and manifest['texture']=='TrafficSignal.png'
print(f'PASS: fourth Tripo compartment, {nf} triangles, source fingerprint, clipped bounds, normals, indices and UVs.')
