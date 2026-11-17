"""Read-only Blender reference inventory. Never saves or exports the source asset."""
import bpy
import bmesh
import hashlib
import json
from pathlib import Path
from collections import Counter
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'assets/example/Car/temp.blend'
OUT = ROOT / 'assets/vehicles/reference-study'
OUT.mkdir(parents=True, exist_ok=True)
digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
before = digest(SOURCE)
bpy.ops.wm.open_mainfile(filepath=str(SOURCE), load_ui=False)
report = {
    'source': str(SOURCE.relative_to(ROOT)), 'sha256': before,
    'blenderVersion': bpy.app.version_string,
    'unitSystem': bpy.context.scene.unit_settings.system,
    'unitScale': bpy.context.scene.unit_settings.scale_length,
    'objects': [], 'materials': [], 'images': [],
    'collections': [{'name': c.name, 'objects': [o.name for o in c.objects]}
                    for c in bpy.data.collections],
    'scenes': [{'name': s.name, 'camera': s.camera.name if s.camera else None}
               for s in bpy.data.scenes],
}
for o in bpy.data.objects:
    row = {'name': o.name, 'type': o.type,
           'parent': o.parent.name if o.parent else None,
           'location': list(o.location), 'scale': list(o.scale),
           'hideRender': o.hide_render, 'hideViewport': o.hide_viewport,
           'collections': [c.name for c in o.users_collection],
           'modifiers': [{'name': m.name, 'type': m.type,
                          'viewport': m.show_viewport, 'render': m.show_render,
                          **({'levels': m.levels, 'renderLevels': m.render_levels}
                             if m.type == 'SUBSURF' else {})}
                         for m in o.modifiers]}
    if o.type == 'MESH':
        me = o.data
        me.calc_loop_triangles()
        bm = bmesh.new(); bm.from_mesh(me)
        world = [o.matrix_world @ Vector(c) for c in o.bound_box]
        lo = [min(v[i] for v in world) for i in range(3)]
        hi = [max(v[i] for v in world) for i in range(3)]
        row.update(vertices=len(me.vertices), edges=len(me.edges),
                   faces=len(me.polygons), triangles=len(me.loop_triangles),
                   faceSides=dict(Counter(len(p.vertices) for p in me.polygons)),
                   bounds=[lo, hi], dimensions=[hi[i]-lo[i] for i in range(3)],
                   materials=[m.name if m else None for m in me.materials],
                   materialFaces=dict(Counter(p.material_index for p in me.polygons)),
                   uvLayers=[uv.name for uv in me.uv_layers],
                   boundaryEdges=sum(e.is_boundary for e in bm.edges),
                   wireEdges=sum(e.is_wire for e in bm.edges),
                   edgesOverTwoFaces=sum(len(e.link_faces)>2 for e in bm.edges),
                   zeroAreaFaces=sum(f.calc_area()<1e-12 for f in bm.faces),
                   customNormals=me.has_custom_normals)
        bm.free()
    report['objects'].append(row)
    if o.type == 'MESH' and o.name == 'st-003':
        parents = list(range(len(o.data.vertices)))
        def find(i):
            while parents[i] != i:
                parents[i] = parents[parents[i]]
                i = parents[i]
            return i
        for e in o.data.edges:
            a,b = map(find, e.vertices)
            parents[a] = b
        groups = {}
        for v in o.data.vertices:
            groups.setdefault(find(v.index), []).append(o.matrix_world @ v.co)
        report['interiorComponents'] = []
        for verts in sorted(groups.values(), key=len, reverse=True):
            report['interiorComponents'].append({'vertices':len(verts),
                'bounds': [[min(v[k] for v in verts) for k in range(3)],
                           [max(v[k] for v in verts) for k in range(3)]]})
for m in bpy.data.materials:
    nodes = m.node_tree.nodes if m.use_nodes else []
    bsdf = next((n for n in nodes if n.type == 'BSDF_PRINCIPLED'), None)
    params = {}
    if bsdf:
        for name in ['Base Color', 'Metallic', 'Roughness', 'Alpha',
                     'Transmission Weight', 'IOR']:
            socket = bsdf.inputs.get(name)
            if socket:
                val = socket.default_value
                params[name] = {'linked': socket.is_linked,
                                'value': list(val) if hasattr(val, '__len__') else val}
    report['materials'].append({'name': m.name, 'useNodes': m.use_nodes,
        'parameters': params, 'nodes': [{'type': n.type, 'name': n.name,
            **({'image': n.image.name if n.image else None} if n.type=='TEX_IMAGE' else {})}
            for n in nodes]})
for im in bpy.data.images:
    resolved = Path(bpy.path.abspath(im.filepath)) if im.filepath else None
    report['images'].append({'name': im.name, 'filepath': im.filepath,
        'size': list(im.size), 'packed': bool(im.packed_file),
        'externalExists': bool(resolved and resolved.exists())})
meshes = [r for r in report['objects'] if r['type']=='MESH']
report['totals'] = {k: sum(r[k] for r in meshes)
    for k in ['vertices', 'faces', 'triangles', 'boundaryEdges',
              'edgesOverTwoFaces', 'zeroAreaFaces']}
report['totals']['meshObjects'] = len(meshes)
report['sourceUnchanged'] = digest(SOURCE) == before
(OUT / 'car-reference-inventory.json').write_text(
    json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
print('REFERENCE_TOTALS', json.dumps(report['totals']))
for r in meshes:
    print('MESH', r['name'], 'faces', r['faces'], 'triangles', r['triangles'],
          'bounds', r['bounds'], 'materials', r['materials'])
print('SOURCE_UNCHANGED', report['sourceUnchanged'])
