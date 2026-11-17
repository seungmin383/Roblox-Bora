"""Apply whitelisted signal properties, preserving every existing referent."""
from copy import deepcopy
from pathlib import Path
import hashlib
import json
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


def name(item):
    return item.findtext("Properties/string[@name='Name']")


def child(item, value):
    return next((i for i in item.findall('Item') if name(i) == value), None)


def property_replace(item, prop):
    properties = item.find('Properties')
    old = next((p for p in properties if p.get('name') == prop.get('name')), None)
    if old is not None:
        index = list(properties).index(old)
        properties.remove(old)
        properties.insert(index, deepcopy(prop))
    else:
        properties.append(deepcopy(prop))


def apply(document, staged, remapped_copy):
    workspace = document.find("Item[@class='Workspace']")
    roads = child(workspace, 'BoraRoads')
    junctions = child(roads, 'Junctions') if roads is not None else None
    original = ET.tostring(workspace)
    undo = []
    added = []
    count = 0
    # Only these props may change; no world object is replaced or removed.
    for group in staged.findall('Item'):
        junction = child(junctions, name(group)) if junctions is not None else None
        assert junction is not None, 'Saved junction changed during signal staging'
        signals = child(junction, 'Signals')
        for template in group.findall('Item'):
            signal = child(signals, name(template))
            assert signal is not None and signal.get('class') == 'Model'
            for item, prop in ((signal, template.find("Properties/BinaryString[@name='AttributesSerialize']")),
                               (child(signal, 'Red'), child(template, 'Red').find("Properties/CoordinateFrame[@name='CFrame']")),
                               (child(signal, 'Amber'), child(template, 'Amber').find("Properties/CoordinateFrame[@name='CFrame']")),
                               (child(signal, 'Green'), child(template, 'Green').find("Properties/CoordinateFrame[@name='CFrame']"))):
                assert item is not None and prop is not None
                undo.append((item, deepcopy(item.find('Properties'))))
                property_replace(item, prop)
            for part_name in ('Left', 'GreenHousing', 'LeftBacking'):
                new = child(template, part_name)
                old = child(signal, part_name)
                if new is not None and old is None:
                    copy = remapped_copy(new)
                    signal.append(copy)
                    added.append((signal, copy))
                elif old is not None:
                    assert new is not None, 'Remove left turn through the road editor to rebuild its head'
                    if part_name=='Left':
                        for segment in new.findall('Item'):
                            target=child(old,name(segment));assert target is not None
                            undo.append((target,deepcopy(target.find('Properties'))))
                            property_replace(target,segment.find("Properties/CoordinateFrame[@name='CFrame']"))
                    if part_name=='LeftBacking':
                        undo.append((old,deepcopy(old.find('Properties'))))
                        property_replace(old,new.find("Properties/CoordinateFrame[@name='CFrame']"))
                    if part_name == 'GreenHousing':
                        undo.append((old, deepcopy(old.find('Properties'))))
                        for prop_name in ('size', 'CFrame', 'Color3uint8'):
                            prop = next((p for p in new.find('Properties') if p.get('name') == prop_name), None)
                            assert prop is not None
                            property_replace(old, prop)
                        template_mesh = new.find("Item[@class='SpecialMesh']")
                        old_mesh = old.find("Item[@class='SpecialMesh']")
                        assert template_mesh is not None
                        if old_mesh is None:
                            copy = remapped_copy(template_mesh)
                            old.append(copy); added.append((old, copy))
            count += 1
    changed = ET.tostring(workspace)
    # Revert in memory, prove exact preservation, then restore the approved
    # properties. This includes terrain, roads, user attributes and references.
    after_props = [(i, deepcopy(i.find('Properties'))) for i, _ in undo]
    for item, props in reversed(undo):
        index = list(item).index(item.find('Properties'))
        item.remove(item.find('Properties')); item.insert(index, props)
    for parent, item in added:
        parent.remove(item)
    assert ET.tostring(workspace) == original, 'Signal upgrade modified protected world data'
    for item, props in after_props:
        index = list(item).index(item.find('Properties'))
        item.remove(item.find('Properties')); item.insert(index, props)
    for parent, item in added:
        parent.append(item)
    assert ET.tostring(workspace) == changed
    return count


def stage_and_apply(document, remapped_copy):
    project = ROOT / 'Ro.rbxlx'
    before = hashlib.sha256(project.read_bytes()).hexdigest()
    lune = Path.home() / 'AppData/Local/Temp/bora-lune-tool/lune.exe'
    # Stage a model fragment from the decoded document. Studio's saved Place
    # may contain damaged source text; never pass that raw XML through Lune.
    from text_encoding import xml_bytes
    input_path=ROOT/'dist/SignalInput.rbxmx'
    wrapper=ET.Element('roblox',version='4')
    workspace=document.find("Item[@class='Workspace']")
    wrapper.append(deepcopy(child(workspace,'BoraRoads')))
    input_path.write_bytes(xml_bytes(wrapper,declaration=False))
    result = subprocess.run([str(lune), 'run', 'tools/stage_signal_upgrade.luau','dist/SignalInput.rbxmx'], cwd=ROOT,
                            capture_output=True, text=True, encoding='utf-8')
    assert result.returncode == 0, result.stdout + result.stderr
    print(result.stdout.strip())
    assert hashlib.sha256(project.read_bytes()).hexdigest() == before, 'Project changed during staging; save and rebuild'
    staged = ET.parse(ROOT / 'dist/SignalUpgrade.rbxmx').getroot().find('Item')
    count = apply(document, staged, remapped_copy)
    report = json.loads((ROOT / 'dist/signal-upgrade-plan.json').read_text(encoding='utf-8'))
    report.update(InputSha256=before, PreservedWorld=True, AppliedSignals=count)
    (ROOT / 'dist/signal-upgrade-validation.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
