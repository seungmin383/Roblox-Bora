"""Read-only Blender mesh audit. Run with Blender --python-exit-code 1.

Coordinates and areas are object-local units. A closed component is not proof
of correct silhouette, lack of self-intersection, or visual quality.
"""
import argparse
import json
import math
import sys
from pathlib import Path

import bpy
import bmesh


def arguments():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('blend', type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--object', action='append', default=[], dest='objects')
    parser.add_argument('--face-tag', action='append', default=[], dest='tags')
    parser.add_argument('--require-closed', action='store_true')
    parser.add_argument('--area-epsilon', type=float, default=1e-12)
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    result = parser.parse_args(argv)
    if not result.blend.is_file():
        parser.error('Input .blend does not exist')
    if result.blend.resolve() == result.output.resolve():
        parser.error('Audit output must not overwrite the input .blend')
    if result.output.suffix.lower() != '.json':
        parser.error('Audit output must be a .json file')
    if result.area_epsilon < 0:
        parser.error('Area epsilon must be nonnegative')
    return result


def finite(values):
    return all(math.isfinite(float(value)) for value in values)


def inspect(obj, tags, area_epsilon):
    mesh = obj.data
    mesh.calc_loop_triangles()
    if tags:
        present = [mesh.attributes.get(name) for name in tags]
        present = [tag for tag in present if tag is not None]
        if any(tag.domain != 'FACE' or tag.data_type != 'INT' for tag in present):
            raise ValueError('Face tags must be FACE/INT attributes: ' + obj.name)
        selected = {face.index for face in mesh.polygons
                    if any(tag.data[face.index].value != 0 for tag in present)}
    else:
        selected = {face.index for face in mesh.polygons}
    if not selected:
        return None

    vertices = {i for face in mesh.polygons if face.index in selected for i in face.vertices}
    loops = {lid for face in mesh.polygons if face.index in selected for lid in face.loop_indices}
    positions_finite = all(finite(mesh.vertices[i].co) for i in vertices)
    normals = [mesh.corner_normals[lid].vector for lid in loops]
    normals_finite = all(finite(normal) for normal in normals)
    bad_normals = sum(not finite(normal) or abs(normal.length - 1) > .001 for normal in normals)
    uv = mesh.uv_layers.active
    uv_finite = all(finite(uv.data[lid].uv) for lid in loops) if uv else None

    bm = bmesh.new()
    try:
        bm.from_mesh(mesh)
        bm.faces.ensure_lookup_table()
        bm.faces.index_update()
        remaining = {bm.faces[i] for i in selected}
        components = []
        while remaining:
            seed = remaining.pop()
            faces = {seed}
            stack = [seed]
            while stack:
                face = stack.pop()
                for edge in face.edges:
                    for other in edge.link_faces:
                        if other in remaining:
                            remaining.remove(other)
                            faces.add(other)
                            stack.append(other)
            edges = {edge for face in faces for edge in face.edges}
            verts = {vertex for face in faces for vertex in face.verts}
            incidences = [sum(face in faces for face in edge.link_faces) for edge in edges]
            open_edges = sum(count == 1 for count in incidences)
            nonmanifold = sum(count > 2 for count in incidences)
            components.append({
                'faces': len(faces), 'vertices': len(verts), 'edges': len(edges),
                'open_edges': open_edges, 'nonmanifold_edges': nonmanifold,
                'euler': len(verts) - len(edges) + len(faces),
                'degenerate_faces': sum(face.calc_area() <= area_epsilon for face in faces),
                'closed': not open_edges and not nonmanifold,
            })
    finally:
        bm.free()

    return {
        'object': obj.name,
        'coordinate_space': 'object-local',
        'object_scale': list(obj.scale),
        'selected_faces': len(selected),
        'selected_vertices': len(vertices),
        'selected_triangles': sum(tri.polygon_index in selected for tri in mesh.loop_triangles),
        'quads': sum(len(face.vertices) == 4 for face in mesh.polygons if face.index in selected),
        'ngons': sum(len(face.vertices) > 4 for face in mesh.polygons if face.index in selected),
        'positions_finite': positions_finite,
        'normals_finite': normals_finite,
        'nonunit_or_invalid_corner_normals': bad_normals,
        'active_uv_layer': uv.name if uv else None,
        'uv_finite': uv_finite,
        'components': sorted(components, key=lambda item: item['faces'], reverse=True),
    }


def main():
    args = arguments()
    bpy.ops.wm.open_mainfile(filepath=str(args.blend.resolve()))
    # Files may have been saved in Edit Mode. Flush the edit mesh only in this
    # background process; otherwise face/UV attribute arrays can appear empty.
    # Never save the source file from this inspector.
    if bpy.context.object and bpy.context.object.mode != 'OBJECT':
        bpy.ops.object.mode_set(mode='OBJECT')
    if args.objects:
        objects = []
        for name in args.objects:
            obj = bpy.context.scene.objects.get(name)
            if obj is None or obj.type != 'MESH':
                raise ValueError('Mesh object not found in the scene: ' + name)
            if obj not in objects:
                objects.append(obj)
    else:
        objects = [obj for obj in bpy.context.scene.objects if obj.type == 'MESH' and not obj.hide_get()]
    missing_tags = [name for name in args.tags if not any(name in obj.data.attributes for obj in objects)]
    if missing_tags:
        raise ValueError('Face tags not found in the selected meshes: ' + ', '.join(missing_tags))
    rows = [inspect(obj, args.tags, args.area_epsilon) for obj in objects]
    rows = [row for row in rows if row is not None]
    if not rows:
        raise ValueError('No matching mesh faces; check visibility, object names and face tags')
    report = {
        'input': str(args.blend.resolve()),
        'blender_version': bpy.app.version_string,
        'scene_unit_scale_length': bpy.context.scene.unit_settings.scale_length,
        'face_tags': args.tags,
        'area_epsilon_object_units_squared': args.area_epsilon,
        'objects': rows,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2, allow_nan=False), encoding='utf-8')
    problems = []
    if args.require_closed:
        for row in rows:
            if not row['positions_finite'] or not row['normals_finite'] or row['uv_finite'] is False:
                problems.append(row['object'] + ': non-finite mesh data')
            if row['nonunit_or_invalid_corner_normals']:
                problems.append(row['object'] + ': invalid corner normals')
            if any(not part['closed'] or part['degenerate_faces'] for part in row['components']):
                problems.append(row['object'] + ': open, nonmanifold or degenerate component')
    print('Mesh audit: ' + str(args.output.resolve()), flush=True)
    if problems:
        raise RuntimeError('; '.join(problems))


if __name__ == '__main__':
    main()
