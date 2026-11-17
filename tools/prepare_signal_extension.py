"""Reuse one optimized Tripo compartment for a matching fourth light.

Clip the original native mesh at the gap between lamps, interpolate UVs and
normals at the cut, then shift that compartment by one lamp pitch.
"""
from pathlib import Path
import hashlib
import json
import math
import struct

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/traffic/local'
source = (OUT / 'TrafficSignal.mesh').read_bytes()
layout=json.loads((OUT/'active-layout.json').read_text())['Vehicle'] if (OUT/'active-layout.json').exists() else {'Pitch':.66,'CutX':-.33,'ExtensionCenter':[-1.32,-.03,-.418]}
header = b'version 2.00\n'
size, stride, face_stride, nv, nf = struct.unpack_from('<HBBII', source, len(header))
assert (size, stride, face_stride) == (12, 40, 12)
start = len(header) + 12
vertices = [struct.unpack_from('<8f', source, start + i * stride) for i in range(nv)]
faces = [struct.unpack_from('<III', source, start + nv * stride + i * 12) for i in range(nf)]
rows, triangles, indices = [], [], {}


def vertex(row):
    normal = math.sqrt(sum(v*v for v in row[3:6]))
    values = [row[0] - layout['Pitch'], *row[1:3], *(v/normal for v in row[3:6]), *row[6:8]]
    packed = struct.pack('<8f4b4B', *values, 0, 0, 0, 127, 255, 255, 255, 255)
    if packed not in indices:
        indices[packed] = len(rows); rows.append(packed)
    return indices[packed]


for face in faces:
    polygon = [vertices[i] for i in face]
    clipped = []
    for a, b in zip(polygon, polygon[1:] + polygon[:1]):
        inside_a, inside_b = a[0] <= layout['CutX'], b[0] <= layout['CutX']
        if inside_a:
            clipped.append(a)
        if inside_a != inside_b:
            t = (layout['CutX'] - a[0]) / (b[0] - a[0])
            clipped.append(tuple(x + t*(y-x) for x, y in zip(a, b)))
    for i in range(1, len(clipped)-1):
        triangle = tuple(vertex(v) for v in (clipped[0], clipped[i], clipped[i+1]))
        if len(set(triangle)) == 3:
            triangles.append(triangle)
assert 100 < len(triangles) < 3500
payload = header + struct.pack('<HBBII', 12, 40, 12, len(rows), len(triangles))
payload += b''.join(rows) + b''.join(struct.pack('<III', *face) for face in triangles)
(OUT / 'TrafficSignalExtension.mesh').write_bytes(payload)
(OUT / 'extension-manifest.json').write_text(json.dumps({
    'source': 'Existing optimized Tripo TrafficSignal compartment',
    'sourceSha256': hashlib.sha256(source).hexdigest(),
    'triangles': len(triangles), 'vertices': len(rows), 'lampCenterMeters': layout['ExtensionCenter'],
    'cutXMeters':layout['CutX'],'pitchMeters':layout['Pitch'],
    'texture': 'TrafficSignal.png', 'uvsPreserved': True,
}, indent=2), encoding='utf-8')
print('Prepared matching Tripo signal extension:', len(triangles), 'triangles.')
