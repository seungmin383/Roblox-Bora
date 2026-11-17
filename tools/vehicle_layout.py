"""Merge a new visual layout while retaining user offsets and instance refs."""
from pathlib import Path
from copy import deepcopy
import json,subprocess,xml.etree.ElementTree as ET
from text_encoding import xml_bytes
ROOT=Path(__file__).resolve().parents[1]
def child(parent,name):return next((x for x in parent.findall('Item') if x.findtext("Properties/string[@name='Name']")==name),None)
def migrate(existing,template,remapped_copy):
    fresh=child(template,'BoraModelLayout')
    if fresh is None:return False
    current=child(existing,'BoraModelLayout')
    new=json.loads(fresh.findtext("Properties/string[@name='Value']"))
    manifest=json.loads((ROOT/'assets/vehicles/local/manifest.json').read_text(encoding='utf-8'))
    old=json.loads(current.findtext("Properties/string[@name='Value']")) if current is not None else manifest['LegacyLayout']
    if old==new:return False
    wrapper=ET.Element('roblox',version='4');model=ET.SubElement(wrapper,'Item',{'class':'Model','referent':'LayoutInput'})
    props=ET.SubElement(model,'Properties');ET.SubElement(props,'string',name='Name').text='VehicleLayoutInput'
    copy=deepcopy(existing);copy.find("Properties/string[@name='Name']").text='Existing';model.append(copy)
    plan=ET.SubElement(model,'Item',{'class':'StringValue','referent':'LayoutPlan'});p=ET.SubElement(plan,'Properties')
    ET.SubElement(p,'string',name='Name').text='Plan';ET.SubElement(p,'string',name='Value').text=json.dumps({'Old':old,'New':new,'Design':manifest['Design']})
    (ROOT/'dist/VehicleLayoutInput.rbxmx').write_bytes(xml_bytes(wrapper,declaration=False))
    lune=Path.home()/'AppData/Local/Temp/bora-lune-tool/lune.exe'
    result=subprocess.run([str(lune),'run','tools/stage_vehicle_layout.luau'],cwd=ROOT,capture_output=True,text=True,encoding='utf-8')
    assert result.returncode==0,result.stdout+result.stderr
    staged=ET.parse(ROOT/'dist/VehicleLayoutUpgrade.rbxmx').getroot().find('Item')
    def prop(target,source,key):
        a=target.find('Properties');b=next((x for x in source.find('Properties') if x.get('name')==key),None)
        assert b is not None,(target.get('class'),key)
        previous=next((x for x in a if x.get('name')==key),None)
        index=list(a).index(previous) if previous is not None else len(a)
        if previous is not None:a.remove(previous)
        a.insert(index,deepcopy(b))
    for group in new['Pivots']:
        prop(child(child(child(existing,'Components'),group),'Pivot'),child(child(child(staged,'Components'),group),'Pivot'),'CFrame')
        motor=child(child(existing,'Mechanics'),group);source=child(child(staged,'Mechanics'),group)
        for key in ['C0','AttributesSerialize']:prop(motor,source,key)
    for key in new['Markers']:
        prop(child(child(existing,'Chassis'),key),child(child(staged,'Chassis'),key),'CFrame')
    # Old packages wrote Attachment.Position, a virtual property ignored by
    # Studio's XML loader. Repair the known zeroed grip/prompt frames only.
    for group in new['Pivots']:
        a=child(child(child(existing,'Components'),group),'Pivot')
        b=child(child(child(template,'Components'),group),'Pivot')
        for marker in a.findall("Item[@class='Attachment']"):
            fresh_marker=child(b,marker.findtext("Properties/string[@name='Name']"))
            cf=marker.find("Properties/CoordinateFrame[@name='CFrame']")
            if fresh_marker is not None and cf is not None and all(abs(float(cf.findtext(k)))<1e-8 for k in 'XYZ'):
                prop(marker,fresh_marker,'CFrame')
    prop(child(existing,'DriverSeat'),child(staged,'DriverSeat'),'CFrame')
    prop(existing,staged,'AttributesSerialize')
    if current is not None:existing.remove(current)
    existing.append(remapped_copy(fresh))
    print(result.stdout.strip())
    return True
