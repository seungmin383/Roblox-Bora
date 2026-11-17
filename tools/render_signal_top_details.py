"""Render the top fittings with an appropriate plan-view camera orientation."""
import bpy
from pathlib import Path
from mathutils import Vector,Matrix
ROOT=Path(__file__).resolve().parents[1]
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'assets/traffic/retopology/TrafficSignal_Clean.blend'))
scene=bpy.context.scene;camera=scene.camera;camera.location=(.67,1.55,.35)
direction=(Vector((.67,.341,.175))-camera.location).normalized();right=direction.cross(Vector((0,0,1))).normalized();up=right.cross(direction)
camera.rotation_euler=Matrix((right,up,-direction)).transposed().to_euler();camera.data.ortho_scale=.80
solid=bpy.data.materials.new('Top fitting solid inspection');solid.use_nodes=True
shader=solid.node_tree.nodes.get('Principled BSDF');shader.inputs['Base Color'].default_value=(.28,.32,.36,1);shader.inputs['Roughness'].default_value=.38
scene.view_layers[0].material_override=solid;scene.cycles.samples=16
scene.render.filepath=str(ROOT/'dist/preview/trafficsignal-top-ribs-solid.png');bpy.ops.render.render(write_still=True)
