"""Validate saved GLB buffers and scene hierarchy with the Python stdlib."""
import json,struct,math
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'assets/vehicles/BoraS3'
raw=(OUT/'BoraS3.glb').read_bytes()
magic,version,size=struct.unpack_from('<III',raw)
assert magic==0x46546c67 and version==2 and size==len(raw)
chunks={};offset=12
while offset<len(raw):
    length,kind=struct.unpack_from('<II',raw,offset);offset+=8
    chunks[kind]=raw[offset:offset+length];offset+=length
doc=json.loads(chunks[0x4e4f534a]);blob=chunks[0x004e4942]
components={5120:('b',1),5121:('B',1),5122:('h',2),5123:('H',2),5125:('I',4),5126:('f',4)}
widths={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}
def accessor(i):
    a=doc['accessors'][i];v=doc['bufferViews'][a['bufferView']]
    fmt,size=components[a['componentType']];n=widths[a['type']]
    stride=v.get('byteStride',n*size);start=v.get('byteOffset',0)+a.get('byteOffset',0)
    assert a['count']==0 or start+(a['count']-1)*stride+n*size<=v.get('byteOffset',0)+v['byteLength']
    return [struct.unpack_from('<'+fmt*n,blob,start+k*stride) for k in range(a['count'])]
errors=[];triangles=0;primitives=0
for me in doc['meshes']:
    for p in me['primitives']:
        primitives+=1
        assert p.get('mode',4)==4
        vertices=accessor(p['attributes']['POSITION']);normals=accessor(p['attributes']['NORMAL'])
        texcoords=accessor(p['attributes']['TEXCOORD_0'])
        indices=[r[0] for r in accessor(p['indices'])]
        assert len(indices)%3==0 and len(normals)==len(vertices)==len(texcoords)
        assert all(0<=i<len(vertices) for i in indices)
        assert all(math.isfinite(v) for rows in [vertices,normals,texcoords] for row in rows for v in row)
        assert all(sum(c*c for c in n)>.9 for n in normals)
        triangles+=len(indices)//3
audit=json.loads((OUT/'audit.json').read_text(encoding='utf-8'))
assert triangles==audit['totals']['triangles'],(triangles,audit['totals']['triangles'])
assert all('camera' not in n for n in doc['nodes'])
assert all('Studio ground' not in n.get('name','') and 'Studio softbox' not in n.get('name','') for n in doc['nodes'])
for im in doc.get('images',[]):
    assert 'bufferView' in im,'GLB texture must be embedded'
groups={n.get('extras',{}).get('group') for n in doc['nodes']}
assert {'Body','Interior','Steering','DoorFL','DoorFR','DoorRL','DoorRR','WheelFL','WheelFR','WheelRL','WheelRR'}<=groups
report={'status':'PASS','triangles':triangles,'primitives':primitives,'embeddedImages':len(doc.get('images',[])),
        'groups':sorted(g for g in groups if g),'presentationExcluded':True,'errors':errors}
(OUT/'glb-validation.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print(json.dumps(report))
