"""Install the rocket system without saving or regenerating any world geometry."""
import os
from pathlib import Path
import sys
from uuid import uuid4

from project_xml import parse_project, read_project
from text_encoding import xml_bytes
from update_buildings import ROOT, PROJECT, digest, sha
from update_project import child, name, remapped_copy

work = Path(sys.argv[2]).resolve(strict=True)
allowed = (ROOT.parent / '99_Code_Work').resolve(strict=True)
assert work != allowed and work.is_relative_to(allowed)
mode = sys.argv[1]
if mode == 'check':
    sys.exit(0)
path = work / 'BoraRocketRuntime.rbxmx'
bundle = read_project(path)
script = bundle.find('Item')
assert name(script) == 'BoraRocketRuntime' and script.get('class') == 'Script'
assert script.findtext("Properties/bool[@name='Disabled']") == 'false'
expected = {'BuildingFracture', 'BuildingDestruction', 'RocketFlight', 'RocketLauncherFactory', 'RocketLauncherClient'}
assert {name(i) for i in script.findall('Item')} == expected
for item in script.iter('Item'):
    label = name(item)
    filename = {'BoraRocketRuntime': 'RocketRuntime.server', 'RocketLauncherClient': 'RocketLauncherClient.client'}.get(label, label)
    assert item.findtext("Properties/*[@name='Source']") == (ROOT / 'src' / f'{filename}.luau').read_text(encoding='utf-8'), filename
if mode == 'seal':
    path.write_bytes(xml_bytes(bundle, declaration=False))
    print('Staged the rocket and destruction runtime; Ro.rbxlx was not edited.')
    sys.exit(0)
assert mode == 'apply'
raw = PROJECT.read_bytes()
doc = parse_project(raw)
server = doc.find("Item[@class='ServerScriptService']")
assert server is not None
removed = []
for label, marker in [('BoraRocketRuntime', '[BoraRocketRuntime]'), ('BoraBuildingFractureDemo', '[BoraBuildingFracture]')]:
    item = child(server, label)
    if item is not None:
        assert marker in (item.findtext("Properties/*[@name='Source']") or ''), label + ' name collision'
        removed.append(item)
owned = {node for item in removed for node in item.iter()}
ids = {node.get('referent') for node in owned if node.tag == 'Item'}
assert not any(ref.text in ids for ref in doc.iter('Ref') if ref not in owned)
for item in removed:
    server.remove(item)
before = digest(doc)
replacement = remapped_copy(script)
if child(server, 'BoraDisasterRuntime') is not None:
    replacement.find("Properties/bool[@name='Disabled']").text = 'true'
server.append(replacement)
payload = xml_bytes(doc)
server.remove(replacement)
assert digest(doc) == before, 'Unrelated project data changed'
temp = work / ('rocket-' + uuid4().hex + '.tmp')
try:
    with temp.open('xb') as out:
        out.write(payload)
    assert sha(PROJECT.read_bytes()) == sha(raw), 'Studio saved a newer Place; close it and try again'
    os.replace(temp, PROJECT)
finally:
    temp.unlink(missing_ok=True)
assert sha(PROJECT.read_bytes()) == sha(payload)
print('Installed the rocket system and replaced its old E-key demo. Saved geometry and unrelated scripts are unchanged.')
