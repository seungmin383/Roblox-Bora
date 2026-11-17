"""Install the disaster scripts in the single saved Place."""
import os
from pathlib import Path
import sys
from uuid import uuid4

from project_xml import parse_project, read_project
from text_encoding import xml_bytes
from update_buildings import ROOT, PROJECT, digest, sha
from update_project import child, name, remapped_copy, source

mode, path = sys.argv[1:]
work = Path(path).resolve(strict=True)
allowed = (ROOT.parent / '99_Code_Work').resolve(strict=True)
assert work != allowed and work.is_relative_to(allowed)
if mode == 'check':
    sys.exit(0)
assert mode == 'apply'
bundle = read_project(work / 'BoraDisaster.rbxmx')
server = child(bundle, 'BoraDisasterRuntime')
hud = child(bundle, 'BoraDisasterHUD')
round_logic = child(server, 'DisasterRound')
for item, script_class, file in (
    (server, 'Script', 'DisasterRuntime.server.luau'),
    (hud, 'LocalScript', 'DisasterHUD.client.luau'),
    (round_logic, 'ModuleScript', 'DisasterRound.luau'),
):
    assert item.get('class') == script_class
    assert source(item).text == (ROOT / 'src' / file).read_text(encoding='utf-8')

raw = PROJECT.read_bytes()
project = parse_project(raw)
services = project.find("Item[@class='ServerScriptService']")
clients = project.find("Item[@class='StarterPlayer']/Item[@class='StarterPlayerScripts']")
world = project.find("Item[@class='Workspace']")
assert child(world, 'CenterSpawn') is not None
assert child(child(world, 'BoraNeighborhood_01'), 'Buildings') is not None
rocket = child(services, 'BoraRocketRuntime')
assert rocket is not None and child(rocket, 'BuildingDestruction') is not None

edits = ((services, server), (clients, hud))
for parent, instance in edits:
    old = child(parent, name(instance))
    if old is not None:
        assert '[BoraDisaster]' in source(old).text, 'Script name collision'
        owned = set(old.iter())
        references = {item.get('referent') for item in old.iter('Item')}
        assert not any(ref.text in references for ref in project.iter('Ref') if ref not in owned)
        parent.remove(old)
setting = rocket.find("Properties/bool[@name='Disabled']")
original_setting = setting.text
before = digest(project)
installed = []
for parent, instance in edits:
    replacement = remapped_copy(instance)
    parent.append(replacement)
    installed.append((parent, replacement))
setting.text = 'true'
payload = xml_bytes(project)
setting.text = original_setting
for parent, replacement in installed:
    parent.remove(replacement)
assert digest(project) == before

temp = work / ('disaster-' + uuid4().hex + '.tmp')
try:
    with temp.open('xb') as out:
        out.write(payload)
    assert sha(PROJECT.read_bytes()) == sha(raw), 'Studio saved a newer Place'
    os.replace(temp, PROJECT)
finally:
    temp.unlink(missing_ok=True)
assert sha(PROJECT.read_bytes()) == sha(payload)
print('Installed disaster round and HUD in Ro.rbxlx. Saved map and assets preserved.')
