"""Regression for Studio's byte entities and UTF-8 CDATA serialization."""
from pathlib import Path
import sys,xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from project_xml import parse_project
from text_encoding import xml_bytes
text='도로 · 은행나무 · 탑승 · 운전석'
doc=ET.Element('roblox',version='4');item=ET.SubElement(doc,'Item',{'class':'Model','referent':'TextFixture'});p=ET.SubElement(item,'Properties')
ET.SubElement(p,'string',name='Name').text=text
ET.SubElement(p,'string',name='Empty')
ET.SubElement(p,'ProtectedString',name='Source').text='local hint="'+text+'"\r\nlocal literal="&#51204; & < > ]]>"'
payload=xml_bytes(doc,declaration=False)
assert text.encode('utf-8') in payload and b'<![CDATA[' in payload
assert b'&#46020;' not in payload
assert ET.tostring(ET.fromstring(payload))==ET.tostring(doc)
assert ET.tostring(parse_project(payload))==ET.tostring(doc)
byte_entities=b''.join(('&#%d;'%b).encode('ascii') for b in text.encode('utf-8'))
encoded=b'<roblox><Item><Properties><string name="Name">'+byte_entities+b'</string></Properties></Item></roblox>'
assert parse_project(encoded).findtext('Item/Properties/string')==text
print('PASS: UTF-8/CDATA and escaped source text round-trip; Studio UTF-8 byte entities decode correctly.')
