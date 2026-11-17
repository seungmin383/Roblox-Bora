"""Validate the saved Place and the exact assets installed for this PC."""
from pathlib import Path
import sys,json,hashlib,xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from vehicle_project import child,source
from text_encoding import audit

document=ET.parse(ROOT/'Ro.rbxlx').getroot()
workspace=document.find("Item[@class='Workspace']")
cars=child(workspace,'BoraVehicles').findall('Item')
assert len(cars)==1
car=cars[0]
assert car.findtext("Properties/string[@name='Name']")=='BoraSedan_S1'
assert child(car,'CenterDisplay') is not None
server=child(document.find("Item[@class='ServerScriptService']"),'BoraVehicleRuntime')
client=child(document.find("Item[@class='StarterPlayer']/Item[@class='StarterPlayerScripts']"),'BoraVehicleClient')
for instance,filename in [(server,'VehicleRuntime.server'),(client,'VehicleClient.client'),
                          (child(server,'VehicleDynamics'),'VehicleDynamics'),(child(server,'VehiclePhysics'),'VehiclePhysics')]:
    assert source(instance).text==(ROOT/'src'/f'{filename}.luau').read_text(encoding='utf-8')
for runtime in (server,client):
    assert runtime.findtext("Properties/bool[@name='Disabled']")=='false'
assert child(document.find("Item[@class='ReplicatedStorage']"),'BoraVehicleControl').get('class')=='RemoteEvent'
assert not audit(document)
manifest=json.loads((ROOT/'assets/vehicles/local/manifest.json').read_text(encoding='utf-8'))
assert child(car,'BoraVisualRevision').findtext("Properties/string[@name='Value']")==str(manifest['VisualRevision'])+':'+manifest['VisualHash']
expected={p['File'] for p in manifest['Parts']}|{p['Texture'] for p in manifest['Parts'] if p.get('Texture')}
references={p.text.removeprefix('rbxasset://BoraVehicleKit/') for p in car.iter() if p.tag in ('url','uri') and (p.text or '').startswith('rbxasset://BoraVehicleKit/')}
assert references==expected,(references^expected)
ids={i.get('referent') for i in document.iter('Item')}
assert all(r.text in ids or r.text in ('null',None) for r in car.iter('Ref'))
versions=Path.home()/'AppData/Local/Roblox/Versions'
installed=[]
for studio in versions.glob('*/RobloxStudioBeta.exe'):
    destination=studio.parent/'content/BoraVehicleKit'
    for filename in expected:
        original=ROOT/'assets/vehicles/local'/filename
        target=destination/filename
        assert target.is_file(),str(target)
        assert hashlib.sha256(original.read_bytes()).digest()==hashlib.sha256(target.read_bytes()).digest(),filename
    installed.append(str(destination))
assert installed
assert [p for p in ROOT.rglob('*') if p.is_file() and p.suffix.lower() in ('.rbxl','.rbxlx')]==[ROOT/'Ro.rbxlx']
report={'place':'Ro.rbxlx','vehicles':1,'brand':manifest['DisplayName'],'triangles':manifest['TotalTriangles'],
        'savedRuntimeSourcesMatch':True,'unicodeAuditPassed':True,'verifiedAssetFiles':len(expected),
        'installedAssetFolders':installed,'studioPlaytestPerformed':False}
(ROOT/'dist/vehicle-installation-validation.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print('PASS: saved single Place, one car, current enabled runtimes/remote, Unicode, and every referenced installed vehicle asset hash.')
