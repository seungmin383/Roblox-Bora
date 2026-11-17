"""Add only the reviewed neighborhood to the existing sole Place."""
from pathlib import Path
import hashlib,json,os,sys,xml.etree.ElementTree as ET
from project_xml import read_project
from text_encoding import xml_bytes
from update_project import child,name,remapped_copy
ROOT=Path(__file__).resolve().parents[1]
PROJECT=ROOT/'Ro.rbxlx'
CAPTURE=ROOT/'dist/neighborhood-staging.json'
SOURCES=['src/NeighborhoodFactory.luau','tools/build_neighborhood.luau']
def sha(data):return hashlib.sha256(data).hexdigest()
def digest(item):return sha(ET.tostring(item))
def protected(document):
    world=document.find("Item[@class='Workspace']")
    return {
        'services':{i.get('referent'):digest(i) for i in document.findall('Item') if i is not world},
        'workspaceProperties':digest(world.find('Properties')),
        'existingWorld':{i.get('referent'):digest(i) for i in world.findall('Item') if name(i)!='BoraNeighborhood_01'},
    }
def apply(document,model):
    world=document.find("Item[@class='Workspace']");assert world is not None
    existing=child(world,'BoraNeighborhood_01')
    if existing is not None:
        assert child(existing,'BoraNeighborhoodRevision') is not None,'User model name collision'
        return False
    before=protected(document)
    world.append(remapped_copy(model))
    assert protected(document)==before,'Existing map or services changed'
    ids=[i.get('referent') for i in document.iter('Item')]
    assert len(ids)==len(set(ids)),'Duplicate referents'
    return True
def main():
    assert PROJECT.is_file()
    if '--capture' in sys.argv:
        data={'projectSha256':sha(PROJECT.read_bytes()),'protected':protected(read_project(PROJECT)),
              'sources':{p:sha((ROOT/p).read_bytes()) for p in SOURCES}}
        CAPTURE.write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')
        print('Captured existing single project and source hashes; no Place copy created.');return
    data=json.loads(CAPTURE.read_text(encoding='utf-8'))
    assert sha(PROJECT.read_bytes())==data['projectSha256'],'Project changed since staging; preserve newer saved edits and stage again'
    assert all(sha((ROOT/p).read_bytes())==v for p,v in data['sources'].items()),'Neighborhood source changed since staging'
    files=['dist/BoraNeighborhood.rbxmx','dist/neighborhood-plan.json']
    if '--seal' in sys.argv:
        data['staged']={p:sha((ROOT/p).read_bytes()) for p in files}
        CAPTURE.write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8');print('Sealed neighborhood model and layout.');return
    assert all(sha((ROOT/p).read_bytes())==v for p,v in data['staged'].items()),'Staged model changed'
    document=read_project(PROJECT)
    assert protected(document)==data['protected']
    model=ET.parse(ROOT/'dist/BoraNeighborhood.rbxmx').getroot().find('Item')
    assert name(model)=='BoraNeighborhood_01'
    added=apply(document,model)
    if added:
        payload=xml_bytes(document);ET.fromstring(payload)
        temporary=ROOT/'.Ro.neighborhood.tmp'
        try:
            temporary.write_bytes(payload)
            assert sha(PROJECT.read_bytes())==data['projectSha256'],'Project changed during update'
            os.replace(temporary,PROJECT)
        finally:temporary.unlink(missing_ok=True)
    saved=read_project(PROJECT)
    assert protected(saved)==data['protected']
    assert len([i for i in saved.find("Item[@class='Workspace']").findall('Item') if name(i)=='BoraNeighborhood_01'])==1
    assert sorted(p for p in ROOT.rglob('*') if p.is_file() and p.suffix.lower() in ('.rbxl','.rbxlx'))==[PROJECT]
    report={'place':'Ro.rbxlx','added':added,'existingWorldAndServicesExactlyPreserved':True,
        'singleNeighborhood':True,'singlePlace':True,'studioOpened':False,'studioPlaytestPerformed':False,
        'layout':json.loads((ROOT/'dist/neighborhood-plan.json').read_text(encoding='utf-8'))}
    (ROOT/'dist/neighborhood-project-validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print('Applied neighborhood only; all existing roads, signals, trees, car, camera and services preserved.' if added else 'Existing neighborhood/user edits preserved; no duplicate added.')
if __name__=='__main__':main()
