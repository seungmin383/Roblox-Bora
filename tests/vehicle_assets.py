"""Audit the delivered Tripo meshes, real glazing and hollow-cabin components."""
from pathlib import Path
import hashlib,json,math,struct
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[1];folder=ROOT/'assets/vehicles/local'
m=json.loads((folder/'manifest.json').read_text(encoding='utf-8'))
if m.get('DisplayName')=='BORA S3':
    import runpy
    runpy.run_path(str(ROOT/'tests/s3_project_assets.py'),run_name='__main__')
    raise SystemExit(0)
assert m['Source']=='Tripo Studio' and m['TaskId']=='e52b36bb-be6a-4653-9036-5b1143b2a826'
assert m['SourceTriangles']==1903375 and m['TotalTriangles']<80000
assert m['VirtualBrand']=='BORA' and m['DisplayName']=='BORA S1' and m['RemovedBadgeTriangles']>0
groups={};total=0;eye=np.array([-.43,1.20,.08]);ray=np.array([0,0,-1]);opaque_sight_hits=[]
for part in m['Parts']:
    binary=(folder/part['File']).read_bytes();header=b'version 2.00\n'
    assert binary.startswith(header)
    size,stride,face_stride,nv,nf=struct.unpack_from('<HBBII',binary,len(header))
    assert (size,stride,face_stride)==(12,40,12) and nf==part['Triangles']
    assert len(binary)==len(header)+12+nv*stride+nf*12
    rows=np.array([struct.unpack_from('<8f',binary,len(header)+12+i*stride) for i in range(nv)])
    indices=np.frombuffer(binary,dtype='<u4',offset=len(header)+12+nv*stride).reshape(-1,3)
    assert indices.max()<nv and np.isfinite(rows).all()
    assert np.all(np.abs(np.linalg.norm(rows[:,3:6],axis=1)-1)<.01)
    assert np.allclose(np.maximum(.001,np.ptp(rows[:,:3],axis=0)),part['Bounds'],atol=.001)
    assert rows[:,6:8].min()>=-.001 and rows[:,6:8].max()<=1.001
    if part['Material']=='Glass':assert part['Transparency']>=.6 and 'Texture' not in part,'Window must be real transparent geometry without a baked interior picture'
    world=rows[:,:3]+m['Pivots'][part['Group']]
    if part['Group'].startswith('Door') and part['Material']=='Glass':
        assert world[:,1].max()>1.25 and world[:,1].min()>.95,'Door glazing no longer reaches the cabin roof'
    if part['Group'].startswith('Door') and part['Material']=='Cabin':
        assert np.abs(world[:,0]).max()<.85,'Interior door trim protrudes through the outer skin'
    if part['Group'].startswith('Door') and part['Material'] in ('Tripo','CarPaint'):
        # The front door also carries its painted mirror cap ahead of the hinge.
        lo,hi=(-.91,.30) if part['Group'].startswith('DoorF') else (.30,1.22)
        assert world[:,2].min()>=lo-.001 and world[:,2].max()<=hi+.001,'Door cut has protruding source triangles'
    if part['Material']!='Glass':
        a=world[indices[:,0]];e=world[indices[:,1]]-a;f=world[indices[:,2]]-a;h=np.cross(ray,f)
        det=np.einsum('ij,ij->i',e,h);valid=np.abs(det)>1e-8;inv=np.divide(1,det,out=np.zeros_like(det),where=valid)
        delta=eye-a;u=inv*np.einsum('ij,ij->i',delta,h);q=np.cross(delta,e);v=inv*np.einsum('j,ij->i',ray,q);distance=inv*np.einsum('ij,ij->i',f,q)
        hits=valid&(u>=0)&(v>=0)&(u+v<=1)&(distance>0)&(distance<1.8)
        if hits.any():opaque_sight_hits.append(part['File'])
    groups.setdefault(part['Group'],set()).add(part['Material']);total+=nf
for group in ['Body','DoorFL','DoorFR','DoorRL','DoorRR','Steering','WheelFL','WheelFR','WheelRL','WheelRR']:
    assert group in groups,'Missing functional component '+group
for group in ['DoorFL','DoorFR','DoorRL','DoorRR']:
    assert {'Glass','Cabin','CarPaint'}.issubset(groups[group])
assert m.get('Retopology') is True
retopo=json.loads((ROOT/'dist/vehicle-retopology-validation.json').read_text(encoding='utf-8'))
assert retopo['roofSamples']>400 and retopo['hoodSamples']>400 and retopo['widthSamples']>=30
assert retopo['sourceDetailTriangles']>20000 and retopo['oneSharedCabinDefinition']
assert {'Cabin','Leather','Screen','Glass','Tripo'}.issubset(groups['Body'])
assert 'Debadged' in groups['Body'] and 'BrandSilver' in groups['Body']
for group in ['WheelFL','WheelFR','WheelRL','WheelRR']:assert 'BrandSilver' in groups[group]
assert total==m['TotalTriangles']
assert not opaque_sight_hits,'Opaque source geometry blocks cockpit view: '+str(opaque_sight_hits)
image=Image.open(folder/'TripoSedan.png');assert image.size==(2048,2048)
(ROOT/'dist/vehicle-asset-validation.json').write_text(json.dumps({'source':m['Source'],'taskId':m['TaskId'],
    'rawTriangles':m['SourceTriangles'],'finalTriangles':total,'groups':{k:sorted(v) for k,v in groups.items()},
    'realGlazing':True,'textureSize':list(image.size),'sourceSha256':hashlib.sha256((ROOT/'assets/vehicles/source/BoraCN7_Tripo_Source.glb').read_bytes()).hexdigest()},indent=2),encoding='utf-8')
print('PASS: Tripo source, game mesh budget, normals/UVs/indices, independent doors/wheels/steering, transparent untextured windows and 3D cabin.')
