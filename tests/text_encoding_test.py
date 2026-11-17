"""Verify repair scope and Unicode persistence using the real saved map."""
from copy import deepcopy
from pathlib import Path
import base64
import hashlib
import json
import struct
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import text_encoding as text


def corrupt(value, count):
    for _ in range(count):
        value = value.encode('utf-8').decode('latin-1')
    return value


for intended in ('\ub3c4\ub85c', '\uc740\ud589\ub098\ubb34', '\uc88c\ud68c\uc804 / \uc9c1\uc9c4'):
    for count in range(1, 7):
        assert text.recover(corrupt(intended, count)) == intended

sample = ET.fromstring('<roblox><Item class="Model" referent="test"><Properties><string name="Name" /></Properties></Item></roblox>')
item = sample.find('Item')
name = item.find("Properties/string[@name='Name']")
attrs = ET.SubElement(item.find('Properties'), 'BinaryString', name='AttributesSerialize')
kind = b'BoraGrowthTree'
attrs.text = base64.b64encode(struct.pack('<II', 1, 9) + b'AssetKind\x02' + struct.pack('<I', len(kind)) + kind).decode('ascii')
name.text = corrupt('\uc740\ud589\ub098\ubb34', 6)[:100]
assert text.repair_document(sample)[0]['after'] == '\uc740\ud589\ub098\ubb34'
name.text = '\uc0ac\uc6a9\uc790\uc758 \ub098\ubb34 / custom name'
assert text.repair_document(sample) == [], 'Valid custom names must survive'
name.text = '\ufffdunknown'
item.set('class', 'Folder')
try:
    text.repair_document(sample)
except ValueError:
    pass
else:
    raise AssertionError('Unknown damaged names must never be guessed')

document = ET.parse(ROOT / 'Ro.rbxlx').getroot()
before = ET.tostring(document)
repaired = deepcopy(document)
changes = text.repair_document(repaired)
assert not text.audit(repaired)
assert text.repair_document(repaired) == [], 'Repair must be idempotent'
payload = text.xml_bytes(repaired)
assert b'<![CDATA[' in payload and ET.tostring(ET.fromstring(payload)) == ET.tostring(repaired)
# Undo just the reported text properties. Every object, attribute, script,
# reference, mesh, placement and setting must equal the original document.
for change in changes:
    node = next(i for i in repaired.iter('Item') if i.get('referent') == change['referent'])
    prop = next(p for p in node.find('Properties') if p.get('name') == change['property'])
    prop.text = change['before']
assert ET.tostring(repaired) == before, 'Repair changed data outside the reported text properties'

# Snapshot/assert the actual Workspace across the disk build, ignoring only
# the seven explicitly repaired Name properties recorded by this turn.
baseline_path = ROOT / 'dist/text-encoding-preservation.json'
workspace = deepcopy(document.find("Item[@class='Workspace']"))
if '--snapshot' in sys.argv:
    targets = [c['referent'] for c in changes]
elif '--compare-snapshot' in sys.argv:
    targets = json.loads(baseline_path.read_text(encoding='utf-8'))['targets']
else:
    targets=[]
for i in workspace.iter('Item'):
    if i.get('referent') in targets:
        i.find("Properties/string[@name='Name']").text = 'REPAIRED_NAME'
digest = hashlib.sha256(ET.tostring(workspace)).hexdigest()
if '--snapshot' in sys.argv:
    baseline_path.write_text(json.dumps({'targets': targets, 'workspaceSha256': digest}, indent=2), encoding='utf-8')
elif '--compare-snapshot' in sys.argv:
    assert digest == json.loads(baseline_path.read_text(encoding='utf-8'))['workspaceSha256'], 'Saved world changed beyond the repaired names'
if '--snapshot' not in sys.argv:
    assert not text.audit(document), 'Saved project still contains corrupted text'
    for kit in ('BoraRoadKit', 'BoraTreeKit', 'BoraRoadReference'):
        p = ROOT / 'dist' / (kit + '.rbxmx')
        assert b'<![CDATA[' in p.read_bytes() and not text.audit(ET.parse(p).getroot())
print('PASS: text recovery, truncated names, custom names, XML Unicode round trip and world preservation;', len(changes), 'pending repairs.')
