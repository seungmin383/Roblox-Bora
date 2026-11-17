"""Keep Roblox XML text Unicode-safe and repair identifiable mojibake.

UTF-8 CDATA avoids Roblox's byte-oriented interpretation of numeric entities.
Existing Studio byte entities are decoded by project_xml before repairs.
"""
from pathlib import Path
import base64
import json
import re
import struct
import xml.etree.ElementTree as ET
import html
from project_xml import MARKERS

ROOT = Path(__file__).resolve().parents[1]
BROKEN = re.compile(r'[\u0080-\u009f\ufffd\ue000-\ue0ff]|[\u00c2\u00c3][\u0080-\u00bf]')
OWNED_NAMES = {'BoraRoadPath': '\ub3c4\ub85c', 'BoraGrowthTree': '\uc740\ud589\ub098\ubb34'}
TEXT_TAGS = {'string', 'ProtectedString'}


def asset_kind(item):
    prop = item.find("Properties/BinaryString[@name='AttributesSerialize']")
    data = base64.b64decode(prop.text or '') if prop is not None else b''
    key = struct.pack('<I', 9) + b'AssetKind\x02'
    offset = data.find(key)
    if offset < 0:
        return None
    offset += len(key)
    if offset + 4 > len(data):
        return None
    size = struct.unpack_from('<I', data, offset)[0]
    return data[offset + 4:offset + 4 + size].decode('utf-8')


def recover(text):
    """Undo only reversible UTF-8-as-Latin-1 conversions, never discard bytes."""
    candidate = text
    for _ in range(16):
        if not BROKEN.search(candidate):
            return candidate
        try:
            decoded = candidate.encode('latin-1').decode('utf-8')
        except UnicodeError:
            break
        if decoded == candidate:
            break
        candidate = decoded
    return None


def audit(document):
    findings = []
    for item in document.iter('Item'):
        props = item.find('Properties')
        if props is None:
            continue
        for prop in props:
            if prop.tag in TEXT_TAGS and BROKEN.search(prop.text or ''):
                findings.append({'referent': item.get('referent'),
                                 'property': prop.get('name'), 'text': prop.text})
    return findings


def repair_document(document):
    changes = []
    for item in document.iter('Item'):
        props = item.find('Properties')
        if props is None:
            continue
        for prop in props:
            old = prop.text or ''
            if prop.tag not in TEXT_TAGS or not BROKEN.search(old):
                continue
            fixed = recover(old)
            # Instance.Name truncates long, repeatedly corrupted names. The
            # original bytes are then gone; only restore known factory defaults.
            if fixed is None and prop.get('name') == 'Name' and item.get('class') == 'Model':
                fixed = OWNED_NAMES.get(asset_kind(item))
            if fixed is None:
                raise ValueError('Cannot safely recover text: ' + str(item.get('referent')) + '/' + str(prop.get('name')))
            prop.text = fixed
            changes.append({'referent': item.get('referent'), 'property': prop.get('name'),
                            'before': old, 'after': fixed})
    assert not audit(document), 'Unresolved corrupted text'
    return changes


def xml_bytes(document, declaration=True):
    # Roblox treats numeric character entities as bytes. Keep UTF-8 text in
    # CDATA instead of writing Unicode code points as numeric entities.
    payload = ET.tostring(document, encoding='utf-8', xml_declaration=declaration)
    def cdata(match):
        tag,attrs,body=match.groups();value=html.unescape(body.decode('utf-8'))
        escaped=value.replace(']]>',']]]]><![CDATA[>').replace('\r',']]>&#13;<![CDATA[')
        return b'<'+tag+attrs+b'><![CDATA['+escaped.encode('utf-8')+b']]></'+tag+b'>'
    payload=re.sub(rb'<(string|ProtectedString)(\s[^>]*?)(?<!/)>(.*?)</\1>',cdata,payload,flags=re.S)
    parsed=ET.fromstring(payload);parsed.tail=document.tail
    assert ET.tostring(parsed) == ET.tostring(document)
    return payload


def normalize_kits():
    report = []
    for name in ('BoraTreeKit', 'BoraRoadKit', 'BoraRoadReference', 'BoraVehicleKit', 'BoraSedan'):
        path = ROOT / 'dist' / (name + '.rbxmx')
        document = ET.parse(path).getroot()
        assert not audit(document), 'Corrupted toolkit text: ' + name
        # Lune detects model XML by its opening <roblox> tag, so kit files
        # intentionally omit the optional XML declaration.
        path.write_bytes(xml_bytes(document, declaration=False))
        report.append({'file': path.name, 'corruptedStrings': 0, 'utf8Cdata': True})
    (ROOT / 'dist/text-encoding-kits.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print('Verified toolkit text; stored UTF-8 strings in CDATA.')


if __name__ == '__main__':
    normalize_kits()
