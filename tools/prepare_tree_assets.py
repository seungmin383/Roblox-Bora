"""Run with Blender: normalize Tripo parts, preserve UVs, export local preview + FBX."""
from pathlib import Path
import json
import struct
import math
import bpy
import bmesh
import numpy as np
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/tree/local"
OUT.mkdir(parents=True, exist_ok=True)
manifest = {"source": "Tripo Studio", "mode": "local-studio-preview", "parts": {}}
SOURCES = {
    "Trunk": ROOT / "assets/tripo/source/GinkgoTrunk.glb",
    "Branch": ROOT / "assets/tripo/source/GinkgoBranch.glb",
    "Twig": next((ROOT / "assets/tripo/source/GinkgoTwig").glob("*.fbx")),
}


def import_mesh(path):
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    if path.suffix.lower() == ".glb":
        bpy.ops.import_scene.gltf(filepath=str(path))
    else:
        bpy.ops.import_scene.fbx(filepath=str(path))
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    assert meshes, f"No mesh in {path}"
    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return obj


def cleanup_and_center(obj, kind):
    mesh = obj.data
    positions = np.array([vertex.co[:] for vertex in mesh.vertices])
    if kind == "Trunk":
        # The generated trunk has branch stubs. Reduce the longest protrusions
        # while retaining the original bark UVs and the roots.
        z_min, z_max = positions[:, 2].min(), positions[:, 2].max()
        span = z_max - z_min
        for vertex in mesh.vertices:
            t = (vertex.co.z - z_min) / span
            if t > .16:
                band = positions[np.abs(positions[:, 2] - vertex.co.z) < span * .07]
                if len(band) > 4:
                    cx, cy = np.median(band[:, :2], axis=0)
                    distances = np.linalg.norm(band[:, :2] - [cx, cy], axis=1)
                    limit = max(float(np.quantile(distances, .60)) * 1.05, span * .025)
                    dx, dy = vertex.co.x - cx, vertex.co.y - cy
                    radius = math.hypot(dx, dy)
                    if radius > limit:
                        vertex.co.x = cx + dx * limit / radius
                        vertex.co.y = cy + dy * limit / radius
        # A gentle extra taper prevents the adult trunk reading as a pole.
        for vertex in mesh.vertices:
            t = (vertex.co.z - z_min) / span
            vertex.co.x *= 1 - .32 * t
            vertex.co.y *= 1 - .32 * t
    else:
        # Orient the main branch axis upward. Keep the organic curvature.
        center = positions.mean(axis=0)
        _, vectors = np.linalg.eigh(np.cov((positions - center).T))
        axis = vectors[:, -1]
        values = (positions - center) @ axis
        low = positions[values < np.quantile(values, .18)]
        high = positions[values > np.quantile(values, .82)]
        def spread(points):
            centered = points - points.mean(axis=0)
            return np.linalg.norm(centered - np.outer(centered @ axis, axis), axis=1).mean()
        if spread(high) > spread(low):
            axis = -axis
        rotation = Vector(axis.tolist()).rotation_difference(Vector((0, 0, 1))).to_matrix()
        for vertex in mesh.vertices:
            vertex.co = rotation @ vertex.co
        if kind == "Branch":
            # Remove the stump at the bottom of Tripo's branch result.
            heights = [vertex.co.z for vertex in mesh.vertices]
            cut = min(heights) + (max(heights) - min(heights)) * .28
            bm = bmesh.new()
            bm.from_mesh(mesh)
            bmesh.ops.bisect_plane(bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces),
                                  plane_co=Vector((0, 0, cut)), plane_no=Vector((0, 0, 1)),
                                  dist=.00001, clear_inner=True, clear_outer=False)
            boundary = [edge for edge in bm.edges if edge.is_boundary]
            if boundary:
                bmesh.ops.holes_fill(bm, edges=boundary, sides=0)
            bm.to_mesh(mesh)
            bm.free()
            # Reduce broken side nubs to a tapered envelope, preserving UVs.
            points = np.array([vertex.co[:] for vertex in mesh.vertices])
            low_z, high_z = points[:, 2].min(), points[:, 2].max()
            span = high_z - low_z
            center_xy = np.median(points[:, :2], axis=0)
            for vertex in mesh.vertices:
                t = (vertex.co.z - low_z) / span
                band = points[np.abs(points[:, 2] - vertex.co.z) < span * .12]
                local_center = np.median(band[:, :2], axis=0)
                local_center = center_xy + np.clip(local_center-center_xy, -span*.07, span*.07)
                dx, dy = vertex.co.x-local_center[0], vertex.co.y-local_center[1]
                radius = math.hypot(dx, dy)
                limit = span * (.065-.05*t)
                if radius > limit:
                    vertex.co.x = local_center[0] + dx * limit / radius
                    vertex.co.y = local_center[1] + dy * limit / radius
    positions = np.array([vertex.co[:] for vertex in mesh.vertices])
    minimum, maximum = positions.min(axis=0), positions.max(axis=0)
    center = (minimum + maximum) / 2
    unit_length = maximum[2] - minimum[2]
    assert unit_length > 0
    for vertex in mesh.vertices:
        vertex.co = (vertex.co - Vector(center.tolist())) / unit_length
    for face in mesh.polygons:
        face.use_smooth = True
    mesh.update()


def save_texture(obj, kind):
    for slot in obj.material_slots:
        material = slot.material
        if not material or not material.use_nodes:
            continue
        shader = next((node for node in material.node_tree.nodes if node.type == "BSDF_PRINCIPLED"), None)
        if not shader:
            continue
        links = shader.inputs["Base Color"].links
        if links and links[0].from_node.type == "TEX_IMAGE":
            image = links[0].from_node.image
            if image:
                path = OUT / f"{kind}Albedo.png"
                optimized = image.copy()
                optimized.scale(1024, 1024)
                optimized.file_format = "PNG"
                optimized.filepath_raw = str(path)
                optimized.save()
                links[0].from_node.image = optimized
                return path.name
    return None


def write_roblox_mesh(obj, path):
    mesh = obj.data
    mesh.calc_loop_triangles()
    uv_layer = mesh.uv_layers.active
    vertex_rows, triangles, indices = [], [], {}
    # Blender Z-up -> Roblox Y-up. This transform preserves handedness.
    conversion = Matrix(((1, 0, 0), (0, 0, 1), (0, -1, 0)))
    for triangle in mesh.loop_triangles:
        face = []
        for loop_id in triangle.loops:
            loop = mesh.loops[loop_id]
            point = conversion @ mesh.vertices[loop.vertex_index].co
            normal = conversion @ mesh.corner_normals[loop_id].vector
            uv = uv_layer.data[loop_id].uv if uv_layer else Vector((0, 0))
            row = tuple(float(value) for value in (*point, *normal, uv.x, 1 - uv.y))
            packed = struct.pack("<8f4b4B", *row, 0, 0, 0, 127, 255, 255, 255, 255)
            if packed not in indices:
                indices[packed] = len(vertex_rows)
                vertex_rows.append(packed)
            face.append(indices[packed])
        triangles.append(face)
    with path.open("wb") as handle:
        handle.write(b"version 2.00\n")
        handle.write(struct.pack("<HBBII", 12, 40, 12, len(vertex_rows), len(triangles)))
        for row in vertex_rows:
            handle.write(row)
        for face in triangles:
            handle.write(struct.pack("<III", *face))
    coordinates = np.array([conversion @ vertex.co for vertex in mesh.vertices])
    return {
        "vertices": len(vertex_rows), "triangles": len(triangles),
        "bounds": (coordinates.max(axis=0) - coordinates.min(axis=0)).tolist(),
        "mesh": path.name,
    }


for kind, path in SOURCES.items():
    obj = import_mesh(path)
    cleanup_and_center(obj, kind)
    obj.name = kind
    texture = save_texture(obj, kind)
    record = write_roblox_mesh(obj, OUT / f"{kind}.mesh")
    record["texture"] = texture
    manifest["parts"][kind] = record
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT / f"{kind}.blend"))
    bpy.ops.export_scene.fbx(filepath=str(OUT / f"{kind}.fbx"), use_selection=True,
                             object_types={"MESH"}, add_leaf_bones=False,
                             axis_forward="-Z", axis_up="Y", path_mode="COPY", embed_textures=True)

(OUT / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
quad = [(-.5,-.5,0,0,0,1,0,1),(.5,-.5,0,0,0,1,1,1),(.5,.5,0,0,0,1,1,0),(-.5,.5,0,0,0,1,0,0)]
with (OUT / "LeafCard.mesh").open("wb") as handle:
    handle.write(b"version 2.00\n")
    handle.write(struct.pack("<HBBII",12,40,12,8,4))
    for back in (False,True):
        for row in quad:
            values = list(row)
            if back: values[5] = -1
            handle.write(struct.pack("<8f4b4B",*values,0,0,0,127,255,255,255,255))
    for face in ((0,1,2),(0,2,3),(6,5,4),(7,6,4)):
        handle.write(struct.pack("<III",*face))
print(json.dumps(manifest, indent=2))
