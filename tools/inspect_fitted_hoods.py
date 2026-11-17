from pathlib import Path
import bpy,sys,json
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from signal_hoods import fit
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'assets/traffic/local/TrafficSignal.blend'))
source=next(o for o in bpy.context.scene.objects if o.type=='MESH')
print(json.dumps(fit(source),indent=2),flush=True)
