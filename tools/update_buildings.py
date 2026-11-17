"""Install only the building kit and adopt saved buildings without moving parts."""
from pathlib import Path
from copy import deepcopy
import hashlib,json,os,sys,xml.etree.ElementTree as ET
from collections import Counter
from uuid import uuid4
from project_xml import parse_project,read_project
from text_encoding import xml_bytes
from update_project import child,name,remapped_copy
ROOT=Path(__file__).resolve().parents[1];PROJECT=ROOT/'Ro.rbxlx';STAGE=ROOT/'dist/building-staging.json'
SOURCES=['src/BuildingParameters.luau','src/BuildingFactory.luau','src/BuildingEditorPlugin.server.luau','tools/build_buildings.luau','tools/update_buildings.py','tools/build_building_decorations.luau',
         'src/BuildingPlan.luau','src/BuildingInteriorFactory.luau','src/BuildingPlanEditor.luau','src/BuildingElevatorMotion.luau','src/BuildingElevatorActor.luau','src/BuildingRuntime.server.luau','src/BuildingClient.client.luau','src/DockPointer.luau']
FILES=['dist/BoraBuildingKit.rbxmx','dist/BuildingPatches.rbxmx','assets/buildings/local/manifest.json','assets/buildings/local/WallSconce_0.mesh','assets/buildings/local/WallSconce_1.mesh','assets/buildings/local/WallSconce_2.mesh','dist/BoraNeighborhood.rbxmx']
def sha(data):return hashlib.sha256(data).hexdigest()
def digest(item):return sha(ET.tostring(item))
def kit_work():
    work=Path(sys.argv[-1]).resolve(strict=True)
    allowed=(ROOT.parent/'99_Code_Work').resolve(strict=True)
    assert work!=allowed and work.is_relative_to(allowed),'Use a task folder in 99_Code_Work'
    return work
EDITOR_KITS=('BoraBuildingKit','BoraTreeKit','BoraRoadKit')
SCRIPT_NAMES={'BuildingPlugin':'BuildingEditorPlugin.server','BoraBuildingKit/RuntimeTemplate':'BuildingRuntime.server',
              'ClientTemplate':'BuildingClient.client','TreePlugin':'ParametricTreePlugin.server',
              'BoraTreeKit/RuntimeTemplate':'ProceduralRuntime.server','RoadPlugin':'RoadEditorPlugin.server',
              'RoadGuideRuntime':'RoadGuideRuntime.server','RoadTrafficRuntime':'RoadTrafficRuntime.server'}
def update_kit_only(work,names=EDITOR_KITS[:1]):
    """Replace editor code without changing any saved game instances or runtimes."""
    saved=PROJECT.read_bytes();doc=parse_project(saved)
    storage=doc.find("Item[@class='ServerStorage']")
    edits=[]
    for kit_name in names:
        old=child(storage,kit_name)
        kit=read_project(work/f'{kit_name}.rbxmx').find('Item')
        assert kit is not None and old is not None and name(kit)==name(old)==kit_name
        assert child(kit,'DockPointer') is not None and child(old,{'BoraBuildingKit':'BuildingPlugin','BoraRoadKit':'RoadPlugin','BoraTreeKit':'TreePlugin'}[kit_name]) is not None
        for item in kit.iter('Item'):
            code=item.find("Properties/*[@name='Source']")
            if code is not None:
                key=name(item)
                filename=SCRIPT_NAMES.get(kit_name+'/'+key,SCRIPT_NAMES.get(key,key))
                assert code.text==(ROOT/'src'/f'{filename}.luau').read_text(encoding='utf-8'),filename
        edits.append((list(storage).index(old),old,remapped_copy(kit)))
    owned={node for _,old,_ in edits for node in old.iter()}
    ids={node.get('referent') for node in owned if node.tag=='Item'}
    assert not any(r.text in ids for r in doc.iter('Ref') if r not in owned),'Existing object refers to the old toolkit'
    for _,old,_ in edits:storage.remove(old)
    baseline=digest(doc)
    for position,_,replacement in sorted(edits):storage.insert(position,replacement)
    payload=xml_bytes(doc)
    for _,_,replacement in edits:storage.remove(replacement)
    assert digest(doc)==baseline,'Saved scene changed during toolkit update'
    if sha(payload)==sha(saved):return
    tmp=work/('studio-kit-'+uuid4().hex+'.tmp')
    try:
        with tmp.open('xb') as f:f.write(payload)
        assert sha(PROJECT.read_bytes())==sha(saved),'Studio saved the Place while updating; retry after closing it'
        os.replace(tmp,PROJECT)
    finally:tmp.unlink(missing_ok=True)
    assert sha(PROJECT.read_bytes())==sha(payload)
    print(f'Updated {len(edits)} embedded editor kit(s). All world objects, plans and runtime scripts were preserved.')
def buildings(doc):
    town=child(doc.find("Item[@class='Workspace']"),'BoraNeighborhood_01')
    assert town is not None
    return child(town,'Buildings')
def protected(doc):
    """Hash everything except building roots and the newly owned editor kit."""
    d=deepcopy(doc);bs=buildings(d)
    for b in bs.findall('Item'):bs.remove(b)
    storage=d.find("Item[@class='ServerStorage']");kit=child(storage,'BoraBuildingKit')
    if kit is not None:storage.remove(kit)
    server=d.find("Item[@class='ServerScriptService']");runtime=child(server,'BoraBuildingRuntime')
    if runtime is not None:server.remove(runtime)
    starter=d.find("Item[@class='StarterPlayer']");scripts=starter.find("Item[@class='StarterPlayerScripts']");client=child(scripts,'BoraBuildingClient')
    if client is not None:scripts.remove(client)
    return digest(d)
def install_runtime(doc,kit):
    server=doc.find("Item[@class='ServerScriptService']")
    scripts=doc.find("Item[@class='StarterPlayer']/Item[@class='StarterPlayerScripts']")
    assert server is not None and scripts is not None,'Preserve existing services; StarterPlayerScripts must exist'
    for parent,target,template,marker in [(server,'BoraBuildingRuntime','RuntimeTemplate','[BoraBuilding] elevator runtime'),
                                         (scripts,'BoraBuildingClient','ClientTemplate','BoraElevatorFloors')]:
        old=child(parent,target)
        if old is not None:
            assert marker in (old.findtext("Properties/*[@name='Source']") or ''),'Building runtime name collision'
            old_refs={i.get('referent') for i in old.iter('Item')};owned=set(old.iter())
            assert not any(r.text in old_refs for r in doc.iter('Ref') if r not in owned),'External reference to building runtime'
            parent.remove(old)
        replacement=remapped_copy(child(kit,template));assert replacement is not None
        replacement.find("Properties/string[@name='Name']").text=target
        disabled=replacement.find("Properties/bool[@name='Disabled']");assert disabled is not None;disabled.text='false'
        parent.append(replacement)
def apply(doc,patches,kit):
    before=protected(doc);world_before=digest(doc.find("Item[@class='Workspace']"));updated=[]
    legacy=child(read_project(ROOT/'dist/BoraNeighborhood.rbxmx').find('Item'),'Buildings')
    for patch in patches.findall('Item'):
        b=child(buildings(doc),name(patch));assert b is not None
        assert child(b,'BuildingOrigin') is None and child(b,'Geometry') is None,'Building already adopted; restage'
        original=[(i,digest(i)) for i in b.findall('Item')]
        # Ownership wrapper changes no existing Part/Gui/property/referent.
        geometry=deepcopy(child(patch,'Geometry'))
        for i in geometry.findall('Item'):geometry.remove(i)
        geometry=remapped_copy(geometry)
        baseline=child(legacy,name(b));assert baseline is not None,'Unknown legacy building'
        owned=Counter((i.get('class'),name(i)) for i in baseline.findall('Item'))
        for item,_ in original:
            key=(item.get('class'),name(item))
            if owned[key]>0:
                owned[key]-=1;b.remove(item);geometry.append(item)
        details=child(child(patch,'Geometry'),'Details')
        if details is not None:
            lamps=[i for i in details.findall('Item') if name(i)=='WallSconce']
            if lamps:
                lighting=deepcopy(details)
                lighting.find("Properties/string[@name='Name']").text='CleanWallLights'
                for item in lighting.findall('Item'):
                    if name(item)!='WallSconce':lighting.remove(item)
                geometry.append(remapped_copy(lighting))
        attrs=patch.find("Properties/BinaryString[@name='AttributesSerialize']");assert attrs is not None
        props=b.find('Properties');old=props.find("BinaryString[@name='AttributesSerialize']")
        if old is not None:props.remove(old)
        props.append(deepcopy(attrs));b.append(geometry)
        origin=remapped_copy(child(patch,'BuildingOrigin'));b.append(origin)
        assert all(digest(i)==old_hash for i,old_hash in original),'Existing geometry edited'
        updated.append({'name':name(b),'preservedOriginalChildren':len(original)})
    storage=doc.find("Item[@class='ServerStorage']");old=child(storage,'BoraBuildingKit')
    if old is not None:
        assert child(old,'BuildingParameters') is not None,'Kit name collision'
        storage.remove(old)
    storage.append(remapped_copy(kit))
    install_runtime(doc,kit)
    if not updated:assert digest(doc.find("Item[@class='Workspace']"))==world_before,'Code-only update changed the saved world'
    assert protected(doc)==before,'Car, roads, trees, furniture, services or building parents changed'
    ids=[i.get('referent') for i in doc.iter('Item')];assert len(ids)==len(set(ids))
    return updated
def main():
    if '--check-kit-work' in sys.argv:kit_work();return
    if '--normalize-editor-kits' in sys.argv:
        work=kit_work()
        for kit_name in EDITOR_KITS:
            path=work/f'{kit_name}.rbxmx';path.write_bytes(xml_bytes(read_project(path),declaration=False))
        return
    if '--editor-kits-only' in sys.argv:update_kit_only(kit_work(),EDITOR_KITS);return
    if '--kit-only' in sys.argv:update_kit_only(kit_work());return
    if '--capture' in sys.argv:
        doc=read_project(PROJECT);titles={}
        for b in buildings(doc).findall('Item'):
            board=child(b,'ShopSign')
            if board is not None:titles[name(b)]=board.findtext("Item[@class='SurfaceGui']/Item[@class='TextLabel']/Properties/string[@name='Text']")
        data={'projectHash':sha(PROJECT.read_bytes()),'protected':protected(doc),'titles':titles,
              'sources':{p:sha((ROOT/p).read_bytes()) for p in SOURCES}}
        STAGE.write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')
        print('Captured sole Place and existing sign text; no Place copy.');return
    data=json.loads(STAGE.read_text(encoding='utf-8'))
    assert sha(PROJECT.read_bytes())==data['projectHash'],'Place was saved after staging; preserve newer edits and restage'
    assert all(sha((ROOT/p).read_bytes())==h for p,h in data['sources'].items()),'Building sources changed; restage'
    if '--seal' in sys.argv:
        data['files']={p:sha((ROOT/p).read_bytes()) for p in FILES};STAGE.write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')
        print('Sealed building kit and recipe patches.');return
    assert all(sha((ROOT/p).read_bytes())==h for p,h in data['files'].items()),'Staged building package changed'
    doc=read_project(PROJECT);assert protected(doc)==data['protected']
    patches=read_project(ROOT/FILES[1]).find('Item');kit=read_project(ROOT/FILES[0]).find('Item')
    originals={name(b):[digest(i) for i in b.findall('Item')] for b in buildings(doc).findall('Item')}
    updated=apply(doc,patches,kit);payload=xml_bytes(doc);ET.fromstring(payload)
    temp=ROOT/'.Ro.buildings.tmp'
    try:
        temp.write_bytes(payload);assert sha(PROJECT.read_bytes())==data['projectHash'],'Concurrent save; abort'
        os.replace(temp,PROJECT)
    finally:temp.unlink(missing_ok=True)
    saved=read_project(PROJECT);assert protected(saved)==data['protected']
    for change in updated:
        b=child(buildings(saved),change['name'])
        hashes=[digest(i) for i in b.findall('Item')]+[digest(i) for i in child(b,'Geometry').findall('Item')]
        assert all(h in hashes for h in originals[change['name']])
    assert sorted(p for p in ROOT.rglob('*') if p.suffix.lower() in ('.rbxl','.rbxlx'))==[PROJECT]
    report={'place':'Ro.rbxlx','buildingsConnected':updated,'allExistingGeometryAndPlacementPreserved':True,
            'roadsCarTreesAndOtherServicesPreserved':True,'floorPlanAndElevatorRuntimeInstalled':True,'entireWorkspacePreserved':not updated,
            'singlePlace':True,'studioOpened':False,'studioPlaytestPerformed':False}
    (ROOT/'dist/building-project-validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print('Building editor installed; existing building geometry, placements and the rest of the map preserved.')
if __name__=='__main__':main()
