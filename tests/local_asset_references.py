"""Verify the local Studio asset paths used by the saved world and tree plugin."""
from collections import defaultdict
import json
from pathlib import Path
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
refs = defaultdict(set)
place = ET.parse(root / 'Ro.rbxlx').getroot()
for item in place.iter():
    if item.tag in ('uri', 'url') and (item.text or '').startswith('rbxasset://Bora'):
        group, filename = item.text.removeprefix('rbxasset://').split('/', 1)
        refs[group].add(filename)
saved_count = sum(map(len, refs.values()))
# The tree plugin preloads the legacy mesh before the first edit, even if only
# generated trees are currently saved. Include the entire supported tree pack.
refs['BoraTreeKitV3'].update(('ConnectedWood.mesh','ConnectedBark.png','GinkgoCluster.png',
                             'ProceduralBark.png','Procedural6.mesh','Procedural9.mesh','Procedural12.mesh'))
sources = {'BoraTreeKitV3': ['assets/tree/local'], 'BoraRoadKit': ['assets/maps/local','assets/traffic/local'],
           'BoraVehicleKit': ['assets/vehicles/local'],'BoraBuildingKit': ['assets/buildings/local']}
versions = Path.home() / 'AppData/Local/Roblox/Versions'
studios = list(versions.glob('*/RobloxStudioBeta.exe'))
assert studios, 'No local Studio versions found'
for studio in studios:
    for group, filenames in refs.items():
        for filename in filenames:
            originals = [root / path / filename for path in sources[group] if (root / path / filename).is_file()]
            assert len(originals) == 1, filename
            installed = studio.parent / 'content' / group / filename
            assert installed.is_file() and installed.read_bytes() == originals[0].read_bytes(), installed
groups = {group: len(files) for group, files in sorted(refs.items())}
(root / 'dist/local-asset-reference-audit.json').write_text(json.dumps({'savedReferences': saved_count,
    'installedByGroup': groups, 'studioVersions': [studio.parent.name for studio in studios]}, indent=2), encoding='utf-8')
print(f'PASS: {saved_count} saved local references and the full tree plugin pack; {sum(groups.values())} verified files per Studio version.')
