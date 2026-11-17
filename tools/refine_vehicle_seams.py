"""Straighten shared Tripo panel borders without adding faces or changing pivots."""
from pathlib import Path
from collections import defaultdict
import json,struct

ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'assets/vehicles/local'
manifest=json.loads((OUT/'manifest.json').read_text(encoding='utf-8'))
if manifest.get('PanelSeamsRefined'):
    print('Panel seams already refined.');raise SystemExit(0)
entries=[];membership=defaultdict(set)
def point_key(point):return tuple(round(v,5) for v in point)
for part in manifest['Parts']:
    if part['Material'] not in ('Tripo','CarPaint') or part['Group'].startswith('Wheel'):continue
    data=bytearray((OUT/part['File']).read_bytes())
    _,stride,_,nv,_=struct.unpack_from('<HBBII',data,13)
    rows=[];pivot=manifest['Pivots'][part['Group']]
    for i in range(nv):
        local=struct.unpack_from('<3f',data,25+i*stride)
        world=[local[j]+pivot[j] for j in range(3)]
        key=point_key(world);membership[key].add(part['Group']);rows.append((world,key))
    entries.append((part,data,stride,rows,pivot))

snapped={}
def clamp(value,lo,hi):return min(hi,max(lo,value))
for point,groups in membership.items():
    doors=sorted(g for g in groups if g.startswith('Door'))
    if not doors:continue
    x,y,z=point
    front=any(g.startswith('DoorF') for g in doors)
    rear=any(g.startswith('DoorR') for g in doors)
    if front and rear:z=.30
    elif 'Body' in groups:
        lo,hi=(-.84,.30) if front else (.30,1.22)
        # Move the shared border to its nearest intended cut plane. Both sides
        # receive the same position, keeping the closed car surface connected.
        candidates=[(abs(z-lo),2,lo),(abs(z-hi),2,hi),(abs(y-.37),1,.37),(abs(y-.87),1,.87)]
        _,axis,value=min(candidates)
        if axis==2:z=value
        else:y=value
    snapped[point]=[x,y,z]

changed=0
for part,data,stride,rows,pivot in entries:
    points=[]
    for i,(original,key) in enumerate(rows):
        world=list(snapped.get(key,original));x,y,z=world
        if part['Group'].startswith('Door'):
            lo,hi=(-.84,.30) if part['Group'].startswith('DoorF') else (.30,1.22)
            world[1]=clamp(y,.37,.87);world[2]=clamp(z,lo,hi)
        elif -1.04<z<1.50 and .87<y<1.30:
            world[1]=.87
        local=[world[j]-pivot[j] for j in range(3)]
        old=struct.unpack_from('<3f',data,25+i*stride)
        if any(abs(local[j]-old[j])>1e-6 for j in range(3)):changed+=1
        struct.pack_into('<3f',data,25+i*stride,*local);points.append(local)
    (OUT/part['File']).write_bytes(data)
    part['Bounds']=[max(.001,max(p[j] for p in points)-min(p[j] for p in points)) for j in range(3)]
manifest['PanelSeamsRefined']=True
(OUT/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
print('Straightened panel borders:',changed,'vertex records; triangle budget and functional pivots unchanged.')
