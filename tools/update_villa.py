"""Apply only the reviewed BoraVilla conversion and building editor kit."""
from collections import Counter
from contextlib import contextmanager
from copy import deepcopy
import json
import os
from pathlib import Path
import sys
from uuid import uuid4

from project_xml import parse_project, read_project
from text_encoding import xml_bytes
from update_buildings import PROJECT, ROOT, SOURCES, buildings, digest, sha
from update_project import child, name, remapped_copy

OLD = Counter({'UpperMasonry': 1, 'GroundCeiling': 1, 'FloorBand': 2})
NEW = {'RetainedExteriorWalls', 'FloorPlanSlabs', 'FloorPlanInterior', 'VillaHallLighting'}
ATTRS = "Properties/BinaryString[@name='AttributesSerialize']"


def villa(doc):
    root = child(buildings(doc), 'BoraVilla')
    assert root is not None
    return root, child(root, 'Geometry')


def slot(doc):
    storage = doc.find("Item[@class='ServerStorage']")
    return storage, child(storage, 'BoraBuildingKit')


@contextmanager
def detach(items):
    positions = [(parent, obj, list(parent).index(obj)) for parent, obj in items]
    try:
        for parent, obj, _ in positions:
            parent.remove(obj)
        yield
    finally:
        for parent, obj, index in sorted(positions, key=lambda row: row[2]):
            parent.insert(index, obj)


def protected(doc, after=False):
    root, geo = villa(doc)
    storage, kit = slot(doc)
    exclude = NEW if after else OLD
    items = [(root.find('Properties'), root.find(ATTRS)), (geo.find('Properties'), geo.find(ATTRS)), (storage, kit)]
    items.extend((geo, i) for i in geo.findall('Item') if name(i) in exclude)
    with detach(items):
        return digest(doc)


def assert_no_external_refs(doc, removed):
    owned = set(n for i in removed for n in i.iter())
    refs = {n.get('referent') for n in owned if n.tag == 'Item'}
    assert all(r.text not in refs for r in doc.iter('Ref') if r not in owned), 'An existing object references replaced geometry'


def update(doc, patch, kit):
    root, geo = villa(doc)
    incoming = child(patch, 'Geometry')
    storage, oldkit = slot(doc)
    assert oldkit is not None and child(oldkit, 'BuildingPlanEditor') is not None
    assert child(kit, 'BuildingPlanEditor') is not None and name(kit) == name(oldkit)
    assert name(patch) == name(root)
    assert {name(i) for i in incoming.findall('Item')} == NEW
    remove = [i for i in geo.findall('Item') if name(i) in OLD]
    assert Counter(map(name, remove)) == OLD and not any(i.findall('Item') for i in remove)
    assert not any(name(i) in NEW for i in geo.findall('Item'))
    assert_no_external_refs(doc, [*remove, oldkit])
    for dst, src in ((root, patch), (geo, incoming)):
        prop = dst.find('Properties')
        prop.remove(dst.find(ATTRS))
        prop.append(deepcopy(src.find(ATTRS)))
    for i in remove:
        geo.remove(i)
    replacement = remapped_copy(incoming)
    for i in replacement.findall('Item'):
        geo.append(i)
    storage.remove(oldkit)
    storage.append(remapped_copy(kit))
    ids = [i.get('referent') for i in doc.iter('Item')]
    assert len(ids) == len(set(ids)), 'Duplicate Roblox referent'
    assert child(doc.find("Item[@class='ServerScriptService']"), 'BoraBuildingRuntime') is not None


def main():
    work = Path(sys.argv[1]).resolve(strict=True)
    assert work.is_relative_to((ROOT.parent / '99_Code_Work').resolve(strict=True))
    assert work != PROJECT.parent
    stage = work / 'villa-stage.json'
    outputs = ['villa-patch.rbxmx', 'BoraBuildingKit.rbxmx', 'villa-plan-validation.json']
    source_files = SOURCES + ['tools/build_villa.luau', 'tools/update_villa.py', 'tools/build_tree_v4.luau',
                              'tools/project_xml.py', 'tools/text_encoding.py', 'dist/BuildingDecorations.rbxmx']
    sources = {key: sha((ROOT / key).read_bytes()) for key in source_files}
    saved = PROJECT.read_bytes()
    phash = sha(saved)
    mode = sys.argv[2]
    if mode == 'capture':
        stage.write_text(json.dumps({'place': phash, 'sources': sources}, indent=2), encoding='utf-8')
        print('Captured existing Place hash before villa build.')
        return
    data = json.loads(stage.read_text(encoding='utf-8'))
    assert (data['place'], data['sources']) == (phash, sources), 'Place or sources changed since staging; re-stage.'
    hashes = {key: sha((work / key).read_bytes()) for key in outputs}
    if mode == 'seal':
        data['outputs'] = hashes
        stage.write_text(json.dumps(data, indent=2), encoding='utf-8')
        print('Sealed the villa patch and building plugin.')
        return
    assert mode == 'apply' and data['outputs'] == hashes
    doc = parse_project(saved)
    baseline = protected(doc)
    update(doc, read_project(work / outputs[0]).find('Item'), read_project(work / outputs[1]).find('Item'))
    assert protected(doc, after=True) == baseline, 'Unrelated saved geometry or services changed'
    payload = xml_bytes(doc)
    # Keep scratch files in Code Work; both directories are on the same drive.
    tmp = work / ('villa-atomic-' + uuid4().hex + '.tmp')
    try:
        with tmp.open('xb') as f:
            f.write(payload)
        assert sha(PROJECT.read_bytes()) == phash, 'Studio saved changes during staging; preserve them.'
        os.replace(tmp, PROJECT)
    finally:
        tmp.unlink(missing_ok=True)
    assert sha(PROJECT.read_bytes()) == sha(payload)
    assert sorted(p for p in ROOT.rglob('*') if p.suffix.lower() in ('.rbxl', '.rbxlx')) == [PROJECT]
    report = {'place': str(PROJECT), 'building': 'BoraVilla', 'unrelatedSavedObjectsPreserved': True,
              'facadeAndUserObjectsPreserved': True, 'stairs': 2, 'elevatorStops': 3, 'interiorDoors': 2,
              'singlePlace': True, 'studioOpened': False, 'studioPlaytestPerformed': False}
    (work / 'villa-project-validation.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print('Updated existing Ro.rbxlx; only villa interior conversion and building editor kit changed.')


if __name__ == '__main__':
    main()
