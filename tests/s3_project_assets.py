"""Validate the exact approved S3 geometry exported to native runtime groups."""
from pathlib import Path
import json,struct,math,hashlib
import numpy as np
ROOT=Path(__file__).resolve().parents[1];folder=ROOT/'assets/vehicles/local'
m=json.loads((folder/'manifest.json').read_text(encoding='utf-8'))
assert m['DisplayName']=='BORA S3' and m['VisualRevision']==5
assert hashlib.sha256((ROOT/m['ApprovedBlend']).read_bytes()).hexdigest()==m['ApprovedBlendSha256']
approved=json.loads((ROOT/'assets/vehicles/BoraS3/audit.json').read_text(encoding='utf-8'))
assert m['TotalTriangles']==approved['totals']['triangles']
assert np.linalg.det(np.array(m['RobloxConversion']))>.99999
groups={};total=0;hits=[];eye=np.array(m['Markers']['Eye'])+np.array([0,.62,0]);ray=np.array([0,0,-1])
for p in m['Parts']:
    binary=(folder/p['File']).read_bytes();size,stride,fs,nv,nf=struct.unpack_from('<HBBII',binary,13)
    assert (size,stride,fs)==(12,40,12) and 0<nf<=7600 and nf==p['Triangles']
    assert len(binary)==25+nv*40+nf*12
    vertices=np.array([struct.unpack_from('<8f',binary,25+i*40) for i in range(nv)])
    indices=np.frombuffer(binary,dtype='<u4',offset=25+nv*40).reshape(-1,3)
    assert indices.min()>=0 and indices.max()<nv and np.isfinite(vertices).all()
    assert np.allclose(np.linalg.norm(vertices[:,3:6],axis=1),1,atol=.001)
    assert np.allclose(np.maximum(.001,np.ptp(vertices[:,:3],axis=0)),p['Bounds'],atol=.00001)
    world=vertices[:,:3]+np.array(m['Pivots'][p['Group']])
    if p.get('Texture'):
        assert (folder/p['Texture']).is_file()
        assert vertices[:,6:].min()>=-.0001 and vertices[:,6:].max()<=1.0001
    if p['Material']=='Glass':assert p['Transparency']>=.6 and not p.get('Texture')
    if p['RobloxMaterial']!='Glass':
        a=world[indices[:,0]];e=world[indices[:,1]]-a;f=world[indices[:,2]]-a;h=np.cross(ray,f)
        det=np.einsum('ij,ij->i',e,h);valid=np.abs(det)>1e-9;inv=np.divide(1,det,out=np.zeros_like(det),where=valid)
        d=eye-a;u=inv*np.einsum('ij,ij->i',d,h);q=np.cross(d,e);v=inv*np.einsum('j,ij->i',ray,q);distance=inv*np.einsum('ij,ij->i',f,q)
        hit=valid&(u>=0)&(v>=0)&(u+v<=1)&(distance>0)&(distance<2.3)
        if hit.any():hits.append(p['File'])
    groups.setdefault(p['Group'],set()).add(p['Material']);total+=nf
assert total==m['TotalTriangles'] and not hits,hits
assert set(groups)=={'Body','DoorFL','DoorFR','DoorRL','DoorRR','Steering','WheelFL','WheelFR','WheelRL','WheelRR'}
for g in ['DoorFL','DoorFR','DoorRL','DoorRR']:assert {'CarPaint','Glass','Leather'}<=groups[g]
for g in ['WheelFL','WheelFR','WheelRL','WheelRR']:assert m['Pivots'][g][0]<0 if g.endswith('L') else m['Pivots'][g][0]>0
normal=np.array(m['SteeringAxis']);to_driver=eye-np.array(m['Pivots']['Steering']);to_driver/=np.linalg.norm(to_driver)
assert np.dot(normal,to_driver)>.99
assert m['Markers']['Eye'][0]<0 and m['Pivots']['Steering'][0]<0
(ROOT/'dist/vehicle-asset-validation.json').write_text(json.dumps({'DisplayName':m['DisplayName'],'triangles':total,'parts':len(m['Parts']),
 'maxPartTriangles':max(p['Triangles'] for p in m['Parts']),'properAxisConversion':True,'clearForwardEyeRay':True,'driverFacingSteering':True,'approvedSourceUnchanged':True},indent=2),encoding='utf-8')
print('PASS: exact approved S3 triangles, native buffers/UVs/normals, <=7600 triangles per part, transparent glazing, left-hand driver, cockpit sightline and steering direction.')
