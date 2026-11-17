"""Update only tool-owned scripts in the existing, single Ro project.

Keep Studio XML properties (including session mesh payloads) intact instead of
round-tripping the world through another serializer or regenerating a scene.
"""
from copy import deepcopy
from pathlib import Path
import os
import uuid
import xml.etree.ElementTree as ET
from text_encoding import repair_document, xml_bytes
from signal_upgrade import stage_and_apply
from vehicle_project import install as install_vehicle
from project_xml import read_project
import json
import hashlib
import sys

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'Ro.rbxlx'


def name(item):
    return item.findtext("Properties/string[@name='Name']")


def child(parent, item_name):
    return next((item for item in parent.findall('Item') if name(item) == item_name), None)


def source(item):
    return next((prop for prop in item.find('Properties') if prop.get('name') == 'Source'), None)


def remapped_copy(original):
    replacement = deepcopy(original)
    references = {item.get('referent'): 'RoKit_' + uuid.uuid4().hex for item in replacement.iter('Item')}
    for item in replacement.iter('Item'):
        item.set('referent', references[item.get('referent')])
    for ref in replacement.iter('Ref'):
        if ref.text in references:
            ref.text = references[ref.text]
    return replacement


def update_document(document, kit, kit_name='BoraTreeKit'):
    storage = document.find("Item[@class='ServerStorage']")
    assert storage is not None, 'Existing project has no ServerStorage; refusing to recreate the world'
    old = child(storage, kit_name)
    if old is not None:
        required = {'BoraTreeKit':('TreeMesher','TreePlugin'),'BoraRoadKit':('RoadPath','RoadPlugin'),'BoraVehicleKit':('VehicleFactory','ServerTemplate')}[kit_name]
        assert all(child(old, item_name) is not None for item_name in required), kit_name + ' name collision'
        owned_nodes = set(old.iter())
        owned_refs = {item.get('referent') for item in old.iter('Item')}
        assert not any(ref.text in owned_refs for ref in document.iter('Ref') if ref not in owned_nodes), 'External reference to toolkit; update requires review'

    # New kit referents must not collide with Studio's numeric world referents.
    replacement = remapped_copy(kit)

    # No Workspace, camera, terrain, object attributes, or mesh data may change.
    preserved = [(item, ET.tostring(item)) for item in document.findall('Item')
                 if item.get('class') not in ('ServerStorage', 'ServerScriptService')]
    if old is not None:
        storage.remove(old)
    storage.append(replacement)

    server = document.find("Item[@class='ServerScriptService']")
    runtime = child(server, 'BoraProceduralRuntime') if server is not None and kit_name == 'BoraTreeKit' else None
    if runtime is not None:
        runtime_source = source(runtime)
        assert runtime_source is not None and '[BoraTree] runtime' in (runtime_source.text or ''), 'Runtime name collision'
        runtime_source.text = source(child(kit, 'RuntimeTemplate')).text
        for module in runtime.findall("Item[@class='ModuleScript']"):
            original = child(kit, name(module))
            if original is not None:
                source(module).text = source(original).text

    assert all(ET.tostring(item) == before for item, before in preserved), 'World layout changed'
    refs = [item.get('referent') for item in document.iter('Item')]
    assert len(refs) == len(set(refs)), 'Duplicate instance referents'
    return document


def ensure_road_reference(document, kit, reference):
    workspace = document.find("Item[@class='Workspace']")
    preserved = [(item, ET.tostring(item)) for item in workspace]
    existing = child(workspace, 'BoraMapReference')
    if existing is None:
        workspace.append(remapped_copy(reference))
    else:
        assert child(existing, 'Root') is not None and child(existing, 'Tiles') is not None, 'Map reference name collision'
    assert all(ET.tostring(item) == before for item, before in preserved), 'Existing world content changed'
    server = document.find("Item[@class='ServerScriptService']")
    assert server is not None
    runtime = child(server, 'BoraRoadGuideRuntime')
    template = child(kit, 'RoadGuideRuntime')
    if runtime is None:
        runtime = remapped_copy(template)
        runtime.find("Properties/string[@name='Name']").text = 'BoraRoadGuideRuntime'
        runtime.find("Properties/bool[@name='Disabled']").text = 'false'
        server.append(runtime)
    else:
        assert 'map is a drafting reference' in (source(runtime).text or ''), 'Road guide runtime name collision'
        source(runtime).text = source(template).text

    traffic_template = child(kit, 'RoadTrafficRuntime')
    if traffic_template is not None:
        traffic_runtime = child(server, 'BoraRoadTrafficRuntime')
        if traffic_runtime is not None:
            assert '[BoraRoad] traffic lamps' in (source(traffic_runtime).text or ''), 'Traffic runtime name collision'
            server.remove(traffic_runtime)
        traffic_runtime = remapped_copy(traffic_template)
        traffic_runtime.find("Properties/string[@name='Name']").text = 'BoraRoadTrafficRuntime'
        traffic_runtime.find("Properties/bool[@name='Disabled']").text = 'false'
        server.append(traffic_runtime)


def update_vehicle_code(document):
    """Change existing driving script sources only; never recalibrate models."""
    kit=child(document.find("Item[@class='ServerStorage']"),'BoraVehicleKit')
    server=child(document.find("Item[@class='ServerScriptService']"),'BoraVehicleRuntime')
    client=child(document.find("Item[@class='StarterPlayer']/Item[@class='StarterPlayerScripts']"),'BoraVehicleClient')
    fresh=ET.parse(ROOT/'dist/BoraVehicleKit.rbxmx').getroot().find('Item')
    assert kit is not None and server is not None and client is not None
    assert '[BoraVehicle]' in source(server).text and '[BoraVehicle]' in source(client).text
    before=ET.tostring(document);changes=[]
    def sync(target,template):
        assert target is not None and template is not None and target.get('class')==template.get('class')
        prop=source(target);new=source(template)
        assert prop is not None and new is not None
        changes.append((prop,prop.text,new.text));prop.text=new.text
        for module in template.findall("Item[@class='ModuleScript']"):
            sync(child(target,name(module)),module)
    for key in ('VehicleDynamics','VehiclePhysics','ServerTemplate','ClientTemplate'):
        sync(child(kit,key),child(fresh,key))
    sync(server,child(fresh,'ServerTemplate'));sync(client,child(fresh,'ClientTemplate'))
    for prop,old,new in changes:prop.text=old
    assert ET.tostring(document)==before,'Vehicle code update changed non-source data'
    for prop,old,new in changes:prop.text=new


def main():
    assert PROJECT.is_file(), 'Ro.rbxlx must already exist; no new project will be created'
    input_hash=hashlib.sha256(PROJECT.read_bytes()).hexdigest()
    document = read_project(PROJECT)
    code_only='--vehicle-code-only' in sys.argv
    world_before=ET.tostring(document.find("Item[@class='Workspace']")) if code_only else None
    if code_only:
        update_vehicle_code(document)
    else:
        kit = ET.parse(ROOT / 'dist/BoraTreeKit.rbxmx').getroot().find('Item')
        assert kit is not None and name(kit) == 'BoraTreeKit'
        update_document(document, kit)
        road_kit = ET.parse(ROOT / 'dist/BoraRoadKit.rbxmx').getroot().find('Item')
        reference = ET.parse(ROOT / 'dist/BoraRoadReference.rbxmx').getroot().find('Item')
        assert name(road_kit) == 'BoraRoadKit' and name(reference) == 'BoraMapReference'
        update_document(document, road_kit, 'BoraRoadKit')
        ensure_road_reference(document, road_kit, reference)
        stage_and_apply(document, remapped_copy)
        from clean_signal_project import apply as apply_clean_signals
        print('Recalibrated saved pedestrian heads:',apply_clean_signals(document))
        vehicle_kit=ET.parse(ROOT / 'dist/BoraVehicleKit.rbxmx').getroot().find('Item')
        vehicle=ET.parse(ROOT / 'dist/BoraSedan.rbxmx').getroot().find('Item')
        install_vehicle(document,vehicle_kit,vehicle,remapped_copy,update_document)
    text_repairs = repair_document(document)
    if code_only:assert ET.tostring(document.find("Item[@class='Workspace']"))==world_before,'Vehicle code update changed the saved world'
    payload = xml_bytes(document)
    ET.fromstring(payload)
    temporary = ROOT / '.Ro.update.tmp'
    try:
        temporary.write_bytes(payload)
        assert hashlib.sha256(PROJECT.read_bytes()).hexdigest()==input_hash,'Ro.rbxlx changed while building; refusing to overwrite newer saved edits'
        os.replace(temporary, PROJECT)
    finally:
        temporary.unlink(missing_ok=True)
    (ROOT / 'dist/text-encoding-repairs.json').write_text(
        json.dumps({'repairs': text_repairs, 'remainingCorruptedStrings': 0}, ensure_ascii=True, indent=2), encoding='utf-8')
    print('Updated Ro.rbxlx toolkit/runtime sources; world and tree data preserved. Repaired text properties:', len(text_repairs))


if __name__ == '__main__':
    main()
