from pathlib import Path
import bpy
r=Path(__file__).resolve().parents[1]/'assets/vehicles/local'
for filename in ['BoraTripoSedan.blend','BoraTripoSedan_Refit.blend']:
 bpy.ops.wm.open_mainfile(filepath=str(r/filename))
 o=next(o for o in bpy.context.scene.objects if o.type=='MESH' and ((not o.get('group') and len(o.data.polygons)>40000) if filename=='BoraTripoSedan.blend' else o.get('group')=='Body' and o.get('material')=='Tripo'))
 print(filename,'UV',[(u.name,u.active_render) for u in o.data.uv_layers],flush=True)
 for n in o.data.materials[0].node_tree.nodes:
  print('NODE',n.name,n.type,getattr(n,'uv_map',''),getattr(getattr(n,'image',None),'filepath',''),flush=True)
 print('UVRANGE',min(min(u.uv) for u in o.data.uv_layers.active.data),max(max(u.uv) for u in o.data.uv_layers.active.data),flush=True)
