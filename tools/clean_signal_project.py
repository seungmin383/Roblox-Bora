"""Calibrate saved pedestrian icons and mesh bounds without rebuilding roads."""
import json,uuid
from pathlib import Path
import xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[1]
def child(parent,name):return next((x for x in parent.findall('Item') if x.findtext("Properties/string[@name='Name']")==name),None)
def apply(document):
    layout=json.loads((ROOT/'assets/traffic/local/active-layout.json').read_text())
    workspace=document.find("Item[@class='Workspace']");roads=child(workspace,'BoraRoads')
    junctions=child(roads,'Junctions');count=0
    for junction in junctions.findall('Item'):
        for group,headname,key in [('Signals','TripoHead','Vehicle'),('PedestrianSignals','TripoPedestrianHead','Pedestrian')]:
            folder=child(junction,group)
            if folder is None:continue
            for signal in folder.findall('Item'):
                head=child(signal,headname)
                if head is None:continue
                mesh=head.find("Item[@class='SpecialMesh']");scale=mesh.find("Properties/Vector3[@name='Scale']")
                factors=[float(scale.findtext(k)) for k in 'XYZ']
                size=next(p for p in head.find('Properties') if p.get('name') in ('size','Size'))
                for k,value in zip('XYZ',layout[key]['Bounds']):size.find(k).text=str(value*factors['XYZ'.index(k)])
                if key!='Pedestrian':continue
                current=child(signal,'BoraDisplayLayout')
                previous=json.loads(current.findtext("Properties/string[@name='Value']")) if current is not None else [[0,.205,-.031],[0,-.205,-.031]]
                target=layout['Pedestrian']['Centers']
                if previous==target:continue
                frame=head.find("Properties/CoordinateFrame[@name='CFrame']")
                rotation=[[float(frame.findtext(f'R{i}{j}')) for j in range(3)] for i in range(3)]
                for index,name in enumerate(['StopIcon','WalkIcon']):
                    icon=child(signal,name);assert icon is not None
                    delta=[(target[index][i]-previous[index][i])*factors[i] for i in range(3)]
                    world=[sum(rotation[i][j]*delta[j] for j in range(3)) for i in range(3)]
                    for part in icon.findall("Item[@class='Part']"):
                        cf=part.find("Properties/CoordinateFrame[@name='CFrame']")
                        for i,k in enumerate('XYZ'):cf.find(k).text=str(float(cf.findtext(k))+world[i])
                if current is None:
                    current=ET.SubElement(signal,'Item',{'class':'StringValue','referent':'RoSignalLayout_'+uuid.uuid4().hex})
                    props=ET.SubElement(current,'Properties');ET.SubElement(props,'string',name='Name').text='BoraDisplayLayout';ET.SubElement(props,'string',name='Value')
                current.find("Properties/string[@name='Value']").text=json.dumps(target,separators=(',',':'))
                count+=1
    return count
