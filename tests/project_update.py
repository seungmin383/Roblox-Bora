"""Verify project updates in memory; never create another Place file."""
from copy import deepcopy
import importlib.util
from pathlib import Path
import xml.etree.ElementTree as ET
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
places = sorted(path for path in ROOT.rglob('*') if path.is_file() and path.suffix.lower() in ('.rbxl', '.rbxlx'))
assert places == [ROOT / 'Ro.rbxlx'], 'Only the root Ro.rbxlx project may exist'
spec = importlib.util.spec_from_file_location('update_project', ROOT / 'tools/update_project.py')
update = importlib.util.module_from_spec(spec)
spec.loader.exec_module(update)
document = ET.parse(ROOT / 'Ro.rbxlx').getroot()
kit = ET.parse(ROOT / 'dist/BoraTreeKit.rbxmx').getroot().find('Item')
workspace = document.find("Item[@class='Workspace']")
before = ET.tostring(workspace)
trees = update.child(workspace, 'BoraTrees')
assert trees is not None
update.update_document(document, kit)
assert ET.tostring(workspace) == before, 'World/mesh/attributes were changed'
runtime = update.child(document.find("Item[@class='ServerScriptService']"), 'BoraProceduralRuntime')
assert runtime is not None
assert update.source(update.child(runtime, 'TreeMesher')).text == update.source(update.child(kit, 'TreeMesher')).text
update.update_document(document, kit)
assert ET.tostring(workspace) == before, 'Repeated update changed the world'
road_kit = ET.parse(ROOT / 'dist/BoraRoadKit.rbxmx').getroot().find('Item')
reference = ET.parse(ROOT / 'dist/BoraRoadReference.rbxmx').getroot().find('Item')
update.update_document(document, road_kit, 'BoraRoadKit')
update.ensure_road_reference(document, road_kit, reference)
assert ET.tostring(workspace) == before, 'Existing map or roads were replaced during a rebuild'
assert update.child(workspace, 'BoraMapReference') is not None
road_runtime = update.child(document.find("Item[@class='ServerScriptService']"), 'BoraRoadGuideRuntime')
assert road_runtime is not None and road_runtime.find("Properties/bool[@name='Disabled']").text == 'false'
traffic_runtime = update.child(document.find("Item[@class='ServerScriptService']"), 'BoraRoadTrafficRuntime')
assert traffic_runtime is not None and traffic_runtime.find("Properties/bool[@name='Disabled']").text == 'false'
assert update.source(update.child(traffic_runtime, 'TrafficTiming')).text == (ROOT / 'src/TrafficTiming.luau').read_text(encoding='utf-8')
update.ensure_road_reference(document, road_kit, reference)
assert ET.tostring(workspace) == before, 'Traffic runtime installation changed the map'
assert len([x for x in document.find("Item[@class='ServerScriptService']").findall('Item') if update.name(x)=='BoraRoadTrafficRuntime']) == 1

collision = deepcopy(document)
old = update.child(collision.find("Item[@class='ServerStorage']"), 'BoraTreeKit')
external = ET.SubElement(collision.find("Item[@class='Workspace']/Properties"), 'Ref', name='TestExternalReference')
external.text = old.get('referent')
try:
    update.update_document(collision, kit)
except AssertionError as error:
    assert 'External reference' in str(error)
else:
    raise AssertionError('An external toolkit reference was silently broken')
print('PASS: only toolkit/runtime sources updated, world/mesh/recipes preserved, repeat update safe, reference collision rejected.')
