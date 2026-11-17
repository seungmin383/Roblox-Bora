"""Check staged geometry against the user's actual roads; no Place writes."""
from pathlib import Path
from copy import deepcopy
import sys,json,math,xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from project_xml import read_project
from update_project import child,name
from update_neighborhood import apply,protected
doc=ET.parse(ROOT/'dist/BoraNeighborhood.rbxmx').getroot();model=doc.find('Item')
plan=json.loads((ROOT/'dist/neighborhood-plan.json').read_text(encoding='utf-8'))
parts=[i for i in model.iter('Item') if i.get('class') in ('Part','WedgePart')]
assert len(parts)==plan['Parts'] and len(parts)<1600
assert len(child(model,'Buildings').findall('Item'))==4
assert len(child(model,'StreetFurniture').findall('Item'))==8
assert len(child(model,'CrosswalkApproaches').findall('Item'))==8
assert len(model.findall(".//Item[@class='PointLight']"))==8
labels=[i.findtext("Properties/string[@name='Text']") for i in model.findall(".//Item[@class='TextLabel']")]
assert all(title in labels for title in ['느린 커피','보라 약국','보라 마트','보라빌라  101'])
def xyz(p):return [float(p.findtext(k)) for k in 'XYZ']
def polygon(item):
    props=item.find('Properties');s=xyz(props.find("Vector3[@name='size']"));cf=props.find("CoordinateFrame[@name='CFrame']")
    p=xyz(cf);r=[[float(cf.findtext(f'R{i}{j}')) for j in range(3)] for i in range(3)]
    vertices=[];ys=[]
    raw=[(x,y,z) for x in (-.5,.5) for y in (-.5,.5) for z in (-.5,.5)]
    if item.get('class')=='WedgePart':raw=[(-.5,-.5,-.5),(.5,-.5,-.5),(-.5,-.5,.5),(.5,-.5,.5),(-.5,.5,.5),(.5,.5,.5)]
    for v in raw:
        point=[p[i]+sum(r[i][j]*s[j]*v[j] for j in range(3)) for i in range(3)]
        vertices.append((point[0],point[2]));ys.append(point[1])
    vertices=sorted(set(vertices))
    def cross(a,b,c):return (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])
    lower=[];upper=[]
    for point in vertices:
        while len(lower)>=2 and cross(lower[-2],lower[-1],point)<=1e-7:lower.pop()
        lower.append(point)
    for point in reversed(vertices):
        while len(upper)>=2 and cross(upper[-2],upper[-1],point)<=1e-7:upper.pop()
        upper.append(point)
    return lower[:-1]+upper[:-1],min(ys),max(ys)
def overlap(a,b,tolerance=.025):
    for poly in (a,b):
        for i,p in enumerate(poly):
            q=poly[(i+1)%len(poly)];dx,dz=q[0]-p[0],q[1]-p[1];length=math.hypot(dx,dz)
            if length<1e-8:continue
            axis=(-dz/length,dx/length)
            aa=[x*axis[0]+z*axis[1] for x,z in a];bb=[x*axis[0]+z*axis[1] for x,z in b]
            if min(max(aa),max(bb))-max(min(aa),min(bb))<=tolerance:return False
    return True
scene=read_project(ROOT/'Ro.rbxlx');world=scene.find("Item[@class='Workspace']");roads=child(world,'BoraRoads')
existing=child(world,'BoraNeighborhood_01')
live_parts=[i for i in existing.iter('Item') if i.get('class') in ('Part','WedgePart')] if existing is not None else []
parents={c:p for p in roads.iter() for c in p};grid={};cell=16
def cells(poly):
    for x in range(math.floor(min(p[0] for p in poly)/cell),math.floor(max(p[0] for p in poly)/cell)+1):
        for z in range(math.floor(min(p[1] for p in poly)/cell),math.floor(max(p[1] for p in poly)/cell)+1):yield x,z
for i in roads.iter('Item'):
    if i.get('class') not in ('Part','WedgePart'):continue
    ancestor=parents.get(i);asphalt=False
    while ancestor is not None:
        if name(ancestor)=='Asphalt':asphalt=True;break
        ancestor=parents.get(ancestor)
    if not asphalt:continue
    poly,lo,hi=polygon(i)
    for c in cells(poly):grid.setdefault(c,[]).append((poly,lo,hi))
checked=0
for p in parts+live_parts:
    props=p.find('Properties');assert props.findtext("bool[@name='Anchored']")=='true'
    size=xyz(props.find("Vector3[@name='size']"));assert all(math.isfinite(v) and 0<v<300 for v in size)
    if props.findtext("bool[@name='CanCollide']")!='true':continue
    poly,lo,hi=polygon(p);seen=set()
    for c in cells(poly):
        for other,y0,y1 in grid.get(c,[]):
            key=id(other)
            if key in seen:continue
            seen.add(key)
            # Driving corridor stays clear throughout the car's height.
            if lo>y1+2.5/.28 or hi<y0-.1:continue
            assert not overlap(poly,other),f'{name(p)} intrudes on saved asphalt'
    checked+=1
before=protected(scene)
if existing is not None:
    original=ET.tostring(scene)
    assert not apply(scene,model) and ET.tostring(scene)==original,'Existing neighborhood changed on repeat build'
    # Test the first-install path in memory, after proving it preserves the saved town.
    world.remove(existing)
assert apply(scene,model)
assert protected(scene)==before
saved=ET.tostring(scene)
assert not apply(scene,model) and ET.tostring(scene)==saved,'Repeat build changed the neighborhood'
town=child(world,'BoraNeighborhood_01')
custom=town.find(".//Item[@class='Part']/Properties/Color3uint8[@name='Color3uint8']")
assert custom is not None;custom.text='16711935'
saved=ET.tostring(scene)
assert not apply(scene,model) and ET.tostring(scene)==saved,'User-edited neighborhood was overwritten'
report={'newParts':len(parts),'savedParts':len(live_parts),'collidersCheckedAgainstActualRoads':checked,'buildings':4,'streetlights':8,'tactileLandings':8,
    'asphaltClear':True,'existingWorldAndServicesPreserved':True,'repeatBuildPreservesUserEdits':True,'studioPlaytestPerformed':False}
(ROOT/'dist/neighborhood-geometry-validation.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print('PASS: four buildings, native glass/signs, anchored geometry, actual road clearance, original map/services, repeat build and user edits.')
