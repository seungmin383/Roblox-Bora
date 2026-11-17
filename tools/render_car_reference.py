"""Diagnostic solid/wire renders in memory; never writes a blend file."""
import bpy
import hashlib
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'assets/example/Car/temp.blend'
OUT = ROOT / 'assets/vehicles/reference-study'
OUT.mkdir(parents=True, exist_ok=True)
before = hashlib.sha256(SOURCE.read_bytes()).hexdigest()
bpy.ops.wm.open_mainfile(filepath=str(SOURCE), load_ui=False)
scene = bpy.context.scene
scene.render.engine = 'BLENDER_WORKBENCH'
scene.render.resolution_x = 1400
scene.render.resolution_y = 950
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
display = scene.display.shading
display.light = 'STUDIO'
display.studiolight_rotate_z = 0.5
display.color_type = 'MATERIAL'
display.show_shadows = True
display.show_cavity = True
display.cavity_type = 'BOTH'
display.curvature_ridge_factor = 1.3
display.curvature_valley_factor = 1.1
display.show_specular_highlight = True
display.background_type = 'WORLD'
scene.world.color = (.13, .13, .13)
scene.view_settings.view_transform = 'Standard'
scene.display.render_aa = '16'
camera_data = bpy.data.cameras.new('Reference diagnostic camera')
camera = bpy.data.objects.new('Reference diagnostic camera', camera_data)
scene.collection.objects.link(camera)
scene.camera = camera
camera_data.clip_end = 1000
camera_data.clip_start = .02
camera_data.lens = 52
colors = {
 'mat_st-003': (.48,.57,.66,1), 'mat_st-007': (.36,.38,.40,1),
 'mat_st-024': (.30,.51,.61,1), 'mat_st-030': (.30,.51,.61,1),
 'mat_st-010': (.065,.065,.065,1), 'mat_st-011': (.065,.065,.065,1),
 'mat_st-013': (.48,.48,.50,1), 'mat_st-017': (.48,.48,.50,1),
 'mat_st-018': (.61,.29,.25,1), 'mat_st-022': (.60,.65,.68,1),
}
for mat in bpy.data.materials:
    mat.diffuse_color = colors.get(mat.name, (.20,.23,.26,1))
meshes = [o for o in scene.objects if o.type == 'MESH']
for obj in meshes:
    obj.hide_render = False
    obj.hide_set(False)

def render(name, location, target, lens=52):
    camera.location = location
    camera.rotation_euler = (Vector(target)-camera.location).to_track_quat('-Z','Y').to_euler()
    camera_data.lens = lens
    scene.render.filepath = str(OUT/name)
    bpy.ops.render.render(write_still=True)
    print('REFERENCE_RENDER', name, flush=True)

render('reference-front-solid.png', (-69,-66,37), (-5,0,7))
render('reference-rear-solid.png', (58,64,33), (-4,0,7))

# Full interior object and adjacent structure, without opaque diagnostic glass.
for obj in meshes:
    obj.hide_render = obj.name != 'st-003'
render('reference-interior-solid.png', (-28,-28,27), (-3,0,7), 48)
render('reference-cockpit-solid.png', (-5,-4,13.2), (-14,-2,8.8), 18)

# Render real source edges; no decimation or triangulation is used.
for obj in meshes:
    obj.hide_render = obj.name not in {'st-001','st-007','st-033','st-038','st-040','st-041','st-059'}
gray = bpy.data.materials.new('Reference diagnostic gray')
gray.diffuse_color = (.65,.68,.72,1)
black = bpy.data.materials.new('Reference diagnostic edge')
black.diffuse_color = (.025,.028,.035,1)
for obj in meshes:
    if obj.hide_render:
        continue
    obj.data.materials.clear()
    obj.data.materials.append(gray)
    obj.data.materials.append(black)
    for poly in obj.data.polygons:
        poly.material_index = 0
    wire = obj.modifiers.new('Reference real mesh edges', 'WIREFRAME')
    wire.thickness = .026 / max(abs(s) for s in obj.scale)
    wire.offset = 1.0
    wire.use_replace = False
    wire.use_even_offset = False
    wire.material_offset = 1
render('reference-front-wire.png', (-47,-39,24), (-20,0,8), 58)
assert hashlib.sha256(SOURCE.read_bytes()).hexdigest() == before
print('SOURCE_UNCHANGED True', flush=True)
