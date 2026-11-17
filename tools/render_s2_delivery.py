"""Render the final saved car without modifying the blend or opening an app."""
import bpy
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'assets/vehicles/retopology'
bpy.ops.wm.open_mainfile(filepath=str(OUT/'BoraS2_Clean.blend'))
scene=bpy.context.scene;cam=scene.camera
for name,loc,target in [('s2-clean-front.png',(5.3,-6.2,2.7),(0,0,.65)),('s2-clean-rear.png',(-5,6,2.8),(0,0,.7))]:
 cam.location=loc;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.lens=52
 scene.render.filepath=str(OUT/name);bpy.ops.render.render(write_still=True)
