"""Capture/check preservation evidence without making a Place copy."""
import sys,json,hashlib,xml.etree.ElementTree as ET,math
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from project_xml import read_project
from vehicle_project import name,child
from text_encoding import repair_document
OUT=ROOT/'dist/model-application-before.json'
def digest(item):return hashlib.sha256(ET.tostring(item)).hexdigest()
def frame(item):return item.find("Properties/CoordinateFrame[@name='CFrame']")
def point(cf):return [float(cf.findtext(k)) for k in 'XYZ']
def local(root,cf):
    r=[[float(root.findtext(f'R{i}{j}')) for j in range(3)] for i in range(3)];a=point(root);b=point(cf)
    return [sum(r[j][i]*(b[j]-a[j]) for j in range(3)) for i in range(3)]
document=read_project(ROOT/'Ro.rbxlx');repair_document(document)
workspace=document.find("Item[@class='Workspace']");roads=child(workspace,'BoraRoads');cars=child(workspace,'BoraVehicles')
car=child(cars,'BoraSedan_S1');chassis=child(car,'Chassis')
excluded=set()
for i in roads.iter('Item'):
    if name(i) in ['Signals','PedestrianSignals']:excluded.update(i.iter('Item'))
protected={i.get('referent'):digest(i.find('Properties')) for i in roads.iter('Item') if i not in excluded}
protected_heads={};counts={'vehicles':len(cars.findall('Item')),'vehicleSignals':0,'pedestrianSignals':0}
for junction in child(roads,'Junctions').findall('Item'):
    for folder_name,head_name,key in [('Signals','TripoHead','vehicleSignals'),('PedestrianSignals','TripoPedestrianHead','pedestrianSignals')]:
        folder=child(junction,folder_name)
        if folder is None:continue
        for model in folder.findall('Item'):
            counts[key]+=1
            for part in model.findall('Item'):
                if name(part) in ['Base','Pole','Arm']:protected_heads[part.get('referent')]=digest(part.find('Properties'))
                if name(part)==head_name:protected_heads[part.get('referent')+':frame']=digest(frame(part))
state={'placeSha256':hashlib.sha256((ROOT/'Ro.rbxlx').read_bytes()).hexdigest(),
 'workspace':{name(i):digest(i) for i in workspace.findall('Item') if name(i) not in ['BoraRoads','BoraVehicles']},
 'roadProperties':protected,'signalSupportsAndFrames':protected_heads,'chassisProperties':digest(chassis.find('Properties')),
 'carReferent':car.get('referent'),'counts':counts,
 'pivotLocalPositions':{name(g):local(frame(chassis),frame(child(g,'Pivot'))) for g in child(car,'Components').findall('Item')}}
if '--capture' in sys.argv:
    OUT.write_text(json.dumps(state,ensure_ascii=False,indent=2),encoding='utf-8');print('Captured model-application baseline:',counts);sys.exit(0)
before=json.loads(OUT.read_text(encoding='utf-8'))
for k in ['workspace','roadProperties','signalSupportsAndFrames','chassisProperties','carReferent','counts']:assert state[k]==before[k],k+' changed outside model scope'
manifest=json.loads((ROOT/'assets/vehicles/local/manifest.json').read_text(encoding='utf-8'))
assert child(car,'BoraVisualRevision').findtext("Properties/string[@name='Value']")==str(manifest['VisualRevision'])+':'+manifest['VisualHash']
layout=json.loads(child(car,'BoraModelLayout').findtext("Properties/string[@name='Value']"))
assert layout['Pivots']==manifest['Pivots']
for marker,pos in manifest['Markers'].items():
    cf=child(chassis,marker).find("Properties/CoordinateFrame[@name='CFrame']")
    assert cf is not None and max(abs(a-b/.28) for a,b in zip(point(cf),pos))<.001,marker
for group,pivot in manifest['Pivots'].items():
    old=manifest['LegacyLayout']['Pivots'][group]
    expected=[before['pivotLocalPositions'][group][k]+(pivot[k]-old[k])/.28 for k in range(3)]
    assert max(abs(a-b) for a,b in zip(state['pivotLocalPositions'][group],expected))<.001,group
expected={p['File'] for p in manifest['Parts']}|{p['Texture'] for p in manifest['Parts'] if p.get('Texture')}
references={p.text.removeprefix('rbxasset://BoraVehicleKit/') for p in car.iter() if p.tag in ['url','uri'] and (p.text or '').startswith('rbxasset://BoraVehicleKit/')}
assert references==expected
for n in ['TrafficSignal','PedestrianSignal']:
    assert (ROOT/f'assets/traffic/local/{n}.mesh').read_bytes()==(ROOT/f'assets/traffic/retopology/{n}_Clean.mesh').read_bytes()
    assert (ROOT/f'assets/traffic/local/{n}.png').read_bytes()==(ROOT/f'assets/traffic/retopology/{n}_Clean.png').read_bytes()
assert sorted(p for p in ROOT.rglob('*') if p.is_file() and p.suffix.lower() in ['.rbxl','.rbxlx'])==[ROOT/'Ro.rbxlx']
report={'place':'Ro.rbxlx','vehicle':'BORA S3','counts':counts,'visualParts':len(manifest['Parts']),
 'treesTerrainMapPreserved':True,'roadsSettingsAndJunctionGeometryPreserved':True,'signalPolesAndHeadPlacementPreserved':True,
 'vehicleParkedFrameAndPhysicsPreserved':True,'newMarkersAndPivotsApplied':True,'approvedSignalsApplied':True,
 'singlePlace':True,'studioPlaytestPerformed':False,'placeSha256':state['placeSha256']}
(ROOT/'dist/model-application-validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print('PASS: approved car/signals applied; world, road settings, poles, parked car and single Place preserved.',counts)
