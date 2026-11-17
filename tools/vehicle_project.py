"""Install vehicle-owned instances into the one existing project in memory."""
from pathlib import Path
import xml.etree.ElementTree as ET
from copy import deepcopy
import base64,struct

ROOT=Path(__file__).resolve().parents[1]


def name(item):
    return item.findtext("Properties/string[@name='Name']")


def child(parent, value):
    return next((i for i in parent.findall('Item') if name(i)==value), None)


def source(item):
    return next(p for p in item.find('Properties') if p.get('name')=='Source')


def service(document, class_name):
    existing=document.find("Item[@class='%s']" % class_name)
    if existing is not None:
        return existing
    item=ET.SubElement(document,'Item',{'class':class_name,'referent':'RoVehicleService_'+class_name})
    props=ET.SubElement(item,'Properties');ET.SubElement(props,'string',name='Name').text=class_name
    return item


def update_visuals(existing,template,remapped_copy):
    for fresh in child(template,'Components').findall('Item'):
        old=child(child(existing,'Components'),name(fresh))
        if old is None:continue
        old_prompts=old.findall(".//Item[@class='ProximityPrompt']")
        new_prompts=fresh.findall(".//Item[@class='ProximityPrompt']")
        for target,original in zip(old_prompts,new_prompts):
            for key in ('ActionText','ObjectText'):
                prop=target.find(f"Properties/string[@name='{key}']")
                if prop is not None:prop.text=original.findtext(f"Properties/string[@name='{key}']")
    revision=child(template,'BoraVisualRevision')
    current=child(existing,'BoraVisualRevision')
    if revision is None or (current is not None and current.findtext("Properties/string[@name='Value']")==revision.findtext("Properties/string[@name='Value']")):
        return False
    from vehicle_layout import migrate
    migrate(existing,template,remapped_copy)
    chassis=child(existing,'Chassis');preserved_chassis=ET.tostring(chassis)
    mechanics=ET.tostring(child(existing,'Mechanics'))
    template_root=child(template,'Chassis')
    def render_part(item):
        return item.get('class')=='Part' and any((n.text or '').startswith('rbxasset://BoraVehicleKit/') for n in item.iter() if n.tag in ('url','uri'))
    def copy_part(part,pivot,source_pivot):
        new=remapped_copy(part)
        for ref in new.iter('Ref'):
            if ref.text==source_pivot.get('referent'):ref.text=pivot.get('referent')
        frame=new.find("Properties/CoordinateFrame[@name='CFrame']")
        parent_frame=pivot.find("Properties/CoordinateFrame[@name='CFrame']")
        frame.clear();frame.attrib['name']='CFrame'
        for value in parent_frame:frame.append(deepcopy(value))
        return new
    groups=child(existing,'Components')
    for fresh in child(template,'Components').findall('Item'):
        old=child(groups,name(fresh));assert old is not None,'Missing vehicle component'
        pivot,source_pivot=child(old,'Pivot'),child(fresh,'Pivot')
        for part in list(old.findall('Item')):
            if render_part(part):old.remove(part)
        for part in fresh.findall('Item'):
            if render_part(part):old.append(copy_part(part,pivot,source_pivot))
    # Screens have their own position relative to the existing chassis. Keep
    # the user's parked position/rotation and articulated pivot edits intact.
    def frame_values(item):
        p=item.find("Properties/CoordinateFrame[@name='CFrame']")
        return [float(p.findtext(k)) for k in ('X','Y','Z')],[[float(p.findtext(f'R{i}{j}')) for j in range(3)] for i in range(3)]
    actual_pos,actual_rot=frame_values(chassis);base_pos,base_rot=frame_values(template_root)
    for key in ('DashboardDisplay','CenterDisplay'):
        original=child(template,key)
        if original is None:continue
        old=child(existing,key)
        if old is not None:existing.remove(old)
        new=remapped_copy(original)
        for ref in new.iter('Ref'):
            if ref.text==template_root.get('referent'):ref.text=chassis.get('referent')
        pos,rot=frame_values(original)
        local=[sum(base_rot[j][i]*(pos[j]-base_pos[j]) for j in range(3)) for i in range(3)]
        local_rot=[[sum(base_rot[k][i]*rot[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
        frame=new.find("Properties/CoordinateFrame[@name='CFrame']")
        for i,k in enumerate(('X','Y','Z')):frame.find(k).text=str(actual_pos[i]+sum(actual_rot[i][j]*local[j] for j in range(3)))
        for i in range(3):
            for j in range(3):frame.find(f'R{i}{j}').text=str(sum(actual_rot[i][k]*local_rot[k][j] for k in range(3)))
        existing.append(new)
    if current is not None:existing.remove(current)
    existing.append(remapped_copy(revision))
    # Replace one numeric attribute without overwriting custom user attributes.
    old_attr=existing.find("Properties/BinaryString[@name='AttributesSerialize']")
    new_attr=template.find("Properties/BinaryString[@name='AttributesSerialize']")
    data=bytearray(base64.b64decode(old_attr.text));fresh=base64.b64decode(new_attr.text)
    needle=struct.pack('<I',13)+b'MeshTriangles';a=data.find(needle)+len(needle);b=fresh.find(needle)+len(needle)
    assert a>=len(needle) and b>=len(needle) and data[a]==fresh[b] and data[a] in (5,6)
    size={5:4,6:8}[data[a]]
    data[a:a+1+size]=fresh[b:b+1+size];old_attr.text=base64.b64encode(data).decode('ascii')
    assert ET.tostring(chassis)==preserved_chassis and ET.tostring(child(existing,'Mechanics'))==mechanics
    return True


def install(document, kit, car, remapped_copy, update_document):
    workspace=document.find("Item[@class='Workspace']")
    assert workspace is not None
    preserved=[(i,ET.tostring(i)) for i in workspace if name(i)!='BoraVehicles']
    update_document(document,kit,'BoraVehicleKit')
    vehicles=child(workspace,'BoraVehicles')
    if vehicles is None:
        vehicles=ET.SubElement(workspace,'Item',{'class':'Folder','referent':'RoVehicleFolder'})
        props=ET.SubElement(vehicles,'Properties');ET.SubElement(props,'string',name='Name').text='BoraVehicles'
    existing=child(vehicles,'BoraSedan_S1')
    if existing is None:
        vehicles.append(remapped_copy(car))
    else:
        assert child(existing,'Chassis') is not None and child(existing,'Mechanics') is not None,'Vehicle model name collision'
        update_visuals(existing,car,remapped_copy)
    for template_name,target_name,parent in (
        ('ServerTemplate','BoraVehicleRuntime',service(document,'ServerScriptService')),
        ('ClientTemplate','BoraVehicleClient',None),
    ):
        if parent is None:
            starter=service(document,'StarterPlayer')
            parent=starter.find("Item[@class='StarterPlayerScripts']")
            if parent is None:
                parent=ET.SubElement(starter,'Item',{'class':'StarterPlayerScripts','referent':'RoVehicleStarterScripts'})
                props=ET.SubElement(parent,'Properties');ET.SubElement(props,'string',name='Name').text='StarterPlayerScripts'
        old=child(parent,target_name)
        if old is not None:
            assert '[BoraVehicle]' in (source(old).text or ''),'Vehicle runtime name collision'
            # Update owned sources in place so existing instance refs survive.
            template=child(kit,template_name)
            source(old).text=source(template).text
            for module in template.findall("Item[@class='ModuleScript']"):
                installed=child(old,name(module))
                if installed is None:old.append(remapped_copy(module))
                else:source(installed).text=source(module).text
        else:
            new=remapped_copy(child(kit,template_name))
            new.find("Properties/string[@name='Name']").text=target_name
            new.find("Properties/bool[@name='Disabled']").text='false'
            parent.append(new)
    replicated=service(document,'ReplicatedStorage')
    remote=child(replicated,'BoraVehicleControl')
    if remote is None:
        remote=ET.SubElement(replicated,'Item',{'class':'RemoteEvent','referent':'RoVehicleControlRemote'})
        props=ET.SubElement(remote,'Properties');ET.SubElement(props,'string',name='Name').text='BoraVehicleControl'
    assert remote.get('class')=='RemoteEvent','Vehicle remote name collision'
    assert all(ET.tostring(item)==before for item,before in preserved),'Existing world changed during install'
    refs=[i.get('referent') for i in document.iter('Item')]
    assert len(refs)==len(set(refs)),'Vehicle instance ID collision'
    return document
