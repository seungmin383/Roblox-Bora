"""Signal migration preserves the saved map, object IDs and reference graph."""
from pathlib import Path
from copy import deepcopy
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from signal_upgrade import apply, child, name
from update_project import remapped_copy
from text_encoding import audit, xml_bytes

document = ET.parse(ROOT / 'Ro.rbxlx').getroot()
stage = ET.parse(ROOT / 'dist/SignalUpgrade.rbxmx').getroot().find('Item')
before = ET.tostring(document)
refs = {i.get('referent') for i in document.iter('Item')}
references = [p.text for p in document.iter('Ref')]
count = apply(document, stage, remapped_copy)
assert refs.issubset({i.get('referent') for i in document.iter('Item')}), 'Original instance ID was removed'
assert references == [p.text for p in document.iter('Ref')], 'Existing object references changed'
after = ET.tostring(document)
apply(document, stage, remapped_copy)
assert ET.tostring(document) == after, 'Repeated signal migration adds or changes objects'
assert not audit(document)
assert ET.tostring(ET.fromstring(xml_bytes(document))) == after
all_ids = [i.get('referent') for i in document.iter('Item')]
assert len(all_ids) == len(set(all_ids)), 'Duplicate added referents'
roads = child(document.find("Item[@class='Workspace']"), 'BoraRoads')
for junction in child(roads, 'Junctions').findall('Item'):
    staged = child(stage, name(junction))
    signals = child(junction, 'Signals')
    for signal in signals.findall('Item'):
        template = child(staged, name(signal))
        assert signal.find("Properties/BinaryString[@name='AttributesSerialize']").text == template.find("Properties/BinaryString[@name='AttributesSerialize']").text
        assert child(signal, 'Left') is not None if child(template, 'Left') is not None else child(signal, 'Left') is None
if '--applied' in sys.argv:
    assert before == after, 'Saved project has not received the signal upgrade'
print('PASS: signal-only migration, original world/IDs/references, repeat safety and Unicode preservation;', count, 'heads.')
