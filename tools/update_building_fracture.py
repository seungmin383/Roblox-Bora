"""Stage or add the Studio-only fracture demo to the sole saved Place."""
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
assert work != allowed and work.is_relative_to(allowed), 'Use a task folder in 99_Code_Work'
mode = sys.argv[1]
if mode == 'check':
    sys.exit(0)
package = work / 'BoraBuildingFractureDemo.rbxmx'
bundle = read_project(package)
demo = bundle.find('Item')
assert name(demo) == 'BoraBuildingFractureDemo' and demo.get('class') == 'Script'
assert demo.findtext("Properties/bool[@name='Disabled']") in (None, 'false')
module = child(demo, 'BuildingFracture')
for item, filename in [(demo, 'BuildingFractureDemo.server'), (module, 'BuildingFracture')]:
    assert item.findtext("Properties/*[@name='Source']") == (ROOT / 'src' / (filename + '.luau')).read_text(encoding='utf-8')
payload = xml_bytes(bundle, declaration=False)
if mode == 'seal':
    package.write_bytes(payload)
    print('Packaged the verified Studio-only fracture demo; Place unchanged.')
    sys.exit(0)
assert mode == 'apply', mode

original = PROJECT.read_bytes()
doc = parse_project(original)
service = doc.find("Item[@class='ServerScriptService']")
assert service is not None
old = child(service, name(demo))
position = len(service)
if old is not None:
    assert '[BoraBuildingFracture]' in (old.findtext("Properties/*[@name='Source']") or '')
    assert child(old, 'BuildingFracture') is not None
    if old.findtext("Properties/*[@name='Source']") == demo.findtext("Properties/*[@name='Source']") and +            child(old, 'BuildingFracture').findtext("Properties/*[@name='Source']") == module.findtext("Properties/*[@name='Source']"):
        print('The same fracture demo is already installed.')
        sys.exit(0)
    refs = {i.get('referent') for i in old.iter('Item')}
    owned = set(old.iter())
    assert not any(r.text in refs for r in doc.iter('Ref') if r not in owned), 'The existing demo is referenced outside its package'
    position = list(service).index(old)
    service.remove(old)
baseline = digest(doc)
new = remapped_copy(demo)
service.insert(position, new)
payload = xml_bytes(doc)
service.remove(new)
assert digest(doc) == baseline, 'Saved project changed outside the fracture demo'
tmp = work / ('fracture-' + uuid4().hex + '.tmp')
try:
    with tmp.open('xb') as handle:
        handle.write(payload)
    assert sha(PROJECT.read_bytes()) == sha(original), 'Studio saved since the disk check; retry after closing it.'
    os.replace(tmp, PROJECT)
finally:
    tmp.unlink(missing_ok=True)
assert sha(PROJECT.read_bytes()) == sha(payload)
print('Installed the Studio-only fracture demo. Existing building geometry, plans and scripts are unchanged.')
