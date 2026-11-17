"""Run a normal test so that its reports are kept alongside the staged kits."""
from pathlib import Path
import os
import re
import runpy
import sys
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
work = Path(os.environ['BORA_BUILDINGS_WORK']).resolve(strict=True)
assert work.is_relative_to((root.parent / '99_Code_Work').resolve(strict=True))
script = sys.argv[1]
assert re.fullmatch('[a-z][a-z_0-9]*', script) and script != 'run_local_audit'
reports = work / 'results' / script
reports.mkdir(parents=True, exist_ok=True)
staged = {'BoraRoadKit.rbxmx', 'BoraTreeKit.rbxmx', 'BoraBuildingKit.rbxmx'}


def resolve_input(file):
    if isinstance(file, (str, Path)):
        path = Path(file).resolve()
        if path.parent == root / 'dist' and path.name in staged and (work / path.name).is_file():
            return work / path.name
    return file


def resolve_output(file):
    path = file.resolve()
    assert path.parent == root / 'dist' and path.suffix.lower() not in ('.rbxl', '.rbxlx'), path
    return reports / path.name


read_bytes, write_text, write_bytes, parse = Path.read_bytes, Path.write_text, Path.write_bytes, ET.parse
Path.read_bytes = lambda self: read_bytes(resolve_input(self))
Path.write_text = lambda self, *a, **kw: write_text(resolve_output(self), *a, **kw)
Path.write_bytes = lambda self, *a, **kw: write_bytes(resolve_output(self), *a, **kw)
ET.parse = lambda source, *a, **kw: parse(resolve_input(source), *a, **kw)
sys.argv = [script, *sys.argv[2:]]
runpy.run_path(str(root / 'tests' / (script + '.py')), run_name='__main__')
