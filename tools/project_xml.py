"""Read Roblox byte-entity XML while retaining evidence of damaged text."""
from pathlib import Path
import re,xml.etree.ElementTree as ET

MARKERS=re.compile('[\ue000-\ue0ff]')
def read_project(path):
    return parse_project(Path(path).read_bytes())

def parse_project(data):
    chunks=re.split(rb'(<!\[CDATA\[.*?\]\]>)',data,flags=re.S)
    def entity(match):
        value=match.group(1);number=int(value[1:],16) if value.startswith(b'x') else int(value)
        if 128<=number<=255:return bytes([number])
        if number<32 and number not in (9,10,13):return chr(0xe000+number).encode('utf-8')
        return match.group()
    for i in range(0,len(chunks),2):chunks[i]=re.sub(rb'&#(x[0-9a-fA-F]+|[0-9]+);',entity,chunks[i])
    text=b''.join(chunks).decode('utf-8','surrogateescape')
    text=''.join(chr(0xe000+(ord(c)-0xdc00)) if 0xdc80<=ord(c)<=0xdcff else (chr(0xe000+ord(c)) if ord(c)<32 and c not in '\t\r\n' else c) for c in text)
    return ET.fromstring(text.encode('utf-8'))
