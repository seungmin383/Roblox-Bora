"""Dry-run vehicle installation; keep the only Place and all existing edits."""
from pathlib import Path
import sys,xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from update_project import remapped_copy,update_document
from vehicle_project import install,child
from text_encoding import audit
from project_xml import read_project
document=read_project(ROOT/'Ro.rbxlx')
workspace=document.find("Item[@class='Workspace']")
before=[(i,ET.tostring(i)) for i in workspace if i.findtext("Properties/string[@name='Name']")!='BoraVehicles']
old_vehicles=child(workspace,'BoraVehicles')
old_car=child(old_vehicles,'BoraSedan_S1') if old_vehicles is not None else None
before_chassis=ET.tostring(child(old_car,'Chassis').find('Properties')) if old_car is not None else None
kit=ET.parse(ROOT/'dist/BoraVehicleKit.rbxmx').getroot().find('Item')
car=ET.parse(ROOT/'dist/BoraSedan.rbxmx').getroot().find('Item')
install(document,kit,car,remapped_copy,update_document)
assert all(ET.tostring(i)==data for i,data in before),'Existing world changed'
vehicles=child(workspace,'BoraVehicles');assert len(vehicles.findall('Item'))==1
stored=child(vehicles,'BoraSedan_S1');assert stored is not None
chassis=child(stored,'Chassis');before_car=ET.tostring(stored)
if before_chassis is not None:assert ET.tostring(chassis.find('Properties'))==before_chassis,'Visual upgrade moved or reset chassis physics/parked frame'
assert child(stored,'BoraVisualRevision').findtext("Properties/string[@name='Value']")==child(car,'BoraVisualRevision').findtext("Properties/string[@name='Value']")
chassis.find("Properties/CoordinateFrame[@name='CFrame']/X").text='123.25'
modified_car=ET.tostring(stored)
install(document,kit,car,remapped_copy,update_document)
assert len(vehicles.findall('Item'))==1 and ET.tostring(stored)==modified_car,'Repeat build reset/duplicated edited vehicle'
# Force the visual migration path on an edited car, preserving physical state.
pivot=child(child(child(stored,'Components'),'DoorFL'),'Pivot')
pivot.find("Properties/CoordinateFrame[@name='CFrame']/Y").text='9.25'
saved_pivot=ET.tostring(pivot);saved_chassis=ET.tostring(chassis);saved_mechanics=ET.tostring(child(stored,'Mechanics'))
stored.remove(child(stored,'BoraVisualRevision'))
install(document,kit,car,remapped_copy,update_document)
assert ET.tostring(chassis)==saved_chassis and ET.tostring(pivot)==saved_pivot
assert ET.tostring(child(stored,'Mechanics'))==saved_mechanics
ids={i.get('referent') for i in document.iter('Item')}
assert all(r.text in ids or r.text in ('null',None) for r in stored.iter('Ref')),'Visual upgrade left a dangling pivot/weld reference'
for service,name in [('ServerScriptService','BoraVehicleRuntime'),('ReplicatedStorage','BoraVehicleControl')]:
    assert child(document.find("Item[@class='%s']"%service),name) is not None
starter=document.find("Item[@class='StarterPlayer']/Item[@class='StarterPlayerScripts']")
assert child(starter,'BoraVehicleClient') is not None
# The normal build also repairs pre-existing damaged road/tree names.
from text_encoding import repair_document
repair_document(document)
assert not audit(document)
places=[p for p in ROOT.rglob('*') if p.suffix.lower() in ('.rbxl','.rbxlx')]
assert places==[ROOT/'Ro.rbxlx']
print('PASS: vehicle/server/client/remote install, single Place, original world preservation, repeat build and edited-car preservation.')
