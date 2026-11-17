"""Validate staged adoption and exported meshes before touching the sole Place."""
from pathlib import Path
from copy import deepcopy
import sys,struct,math,json,hashlib,xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from update_buildings import apply,protected,buildings,digest
from project_xml import read_project
from update_project import child,name
doc=read_project(ROOT/'Ro.rbxlx');before=protected(doc)
patches=read_project(ROOT/'dist/BuildingPatches.rbxmx').find('Item');kit=read_project(ROOT/'dist/BoraBuildingKit.rbxmx').find('Item')
originals={name(b):[(i.get('referent'),digest(i)) for i in b.findall('Item')] for b in buildings(doc).findall('Item')}
if patches.findall('Item'):
    # A real user-added object must be retained byte-for-byte on adoption.
    target=buildings(doc).find('Item');custom=ET.SubElement(target,'Item',{'class':'Folder','referent':'User_Added_Keep'})
    props=ET.SubElement(custom,'Properties');ET.SubElement(props,'string',{'name':'Name'}).text='내가 만든 소품'
    custom_hash=digest(custom)
    changes=apply(doc,patches,kit);assert len(changes)==4
    assert protected(doc)==before and digest(custom)==custom_hash
    for b in buildings(doc).findall('Item'):
        geometry=child(b,'Geometry');assert geometry is not None and child(b,'BuildingOrigin') is not None
        current={i.get('referent'):digest(i) for i in geometry.findall('Item')+b.findall('Item')}
        assert all(current.get(ref)==h for ref,h in originals[name(b)])
        assert child(geometry,'CleanWallLights') is not None
    assert custom in target.findall('Item'),'User additions must stay outside regenerated Geometry'
else:
    world_hash=digest(doc.find("Item[@class='Workspace']"))
    assert not apply(doc,patches,kit)
    assert protected(doc)==before and digest(doc.find("Item[@class='Workspace']"))==world_hash
    runtime=child(doc.find("Item[@class='ServerScriptService']"),'BoraBuildingRuntime')
    client=child(doc.find("Item[@class='StarterPlayer']/Item[@class='StarterPlayerScripts']"),'BoraBuildingClient')
    assert runtime is not None and client is not None
    assert child(runtime,'BuildingElevatorMotion') is not None and child(runtime,'BuildingElevatorActor') is not None
    assert runtime.findtext("Properties/bool[@name='Disabled']")=='false' and client.findtext("Properties/bool[@name='Disabled']")=='false'
manifest=json.loads((ROOT/'assets/buildings/local/manifest.json').read_text())
assert len(manifest['Parts'])==3 and manifest['TotalTriangles']<7000
total=0
for part in manifest['Parts']:
    raw=(ROOT/'assets/buildings/local'/part['File']).read_bytes();offset=len(b'version 2.00\n')
    header,stride,face_stride,nv,nf=struct.unpack_from('<HBBII',raw,offset);offset+=12
    assert (header,stride,face_stride)==(12,40,12) and nf==part['Triangles'];total+=nf
    rows=[struct.unpack_from('<8f',raw,offset+i*stride) for i in range(nv)];offset+=nv*stride
    assert all(all(math.isfinite(v) for v in row) and abs(sum(v*v for v in row[3:6])-1)<1e-3 for row in rows)
    for i in range(nf):
        face=struct.unpack_from('<III',raw,offset+i*12);assert max(face)<nv and len(set(face))==3
        a,b,c=[rows[n][:3] for n in face];u=[b[k]-a[k] for k in range(3)];v=[c[k]-a[k] for k in range(3)]
        cross=[u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]]
        assert sum(q*q for q in cross)>1e-22
assert total==manifest['TotalTriangles']
assert hashlib.sha256((ROOT/'assets/buildings/source/WallSconce_Tripo.glb').read_bytes()).hexdigest()==manifest['SourceSha256']
for module,path in [('BuildingParameters','src/BuildingParameters.luau'),('BuildingFactory','src/BuildingFactory.luau'),('BuildingPlugin','src/BuildingEditorPlugin.server.luau'),
                    ('BuildingPlan','src/BuildingPlan.luau'),('BuildingPlanEditor','src/BuildingPlanEditor.luau'),('BuildingInteriorFactory','src/BuildingInteriorFactory.luau'),
                    ('DockPointer','src/DockPointer.luau'),
                    ('RuntimeTemplate','src/BuildingRuntime.server.luau'),('ClientTemplate','src/BuildingClient.client.luau')]:
    assert child(kit,module).findtext("Properties/*[@name='Source']")== (ROOT/path).read_text(encoding='utf-8'),module
assert sorted(p for p in ROOT.rglob('*') if p.suffix.lower() in ('.rbxl','.rbxlx'))==[ROOT/'Ro.rbxlx']
(ROOT/'dist/building-package-validation.json').write_text(json.dumps({'oldGeometryAndUserAdditionsPreserved':True,'otherMapAndServicesPreserved':True,'nativeMeshTriangles':total,'nativeNormalsUVIndicesFinite':True,'sourcePreserved':True,'singlePlace':True,'studioPlaytestPerformed':False},indent=2))
print('PASS: staged adoption preserves every original object and user additions; original Tripo preserved; native triangles/normals/UV/indices and kit sources valid.')
