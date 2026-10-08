"""Render the website hero's lamp: one still of the welcome's porcelain lamp, with its own size and camera.

The model, glaze and studio light are the welcome's (render-onboarding.py, which this started as); --button adds
the orange of the page's Download button as a small light the glaze reflects. See RELEASING.md.

Originally: render the welcome's three holds and two camera moves with Blender Cycles.

Run after export-model.swift; see README.md. Coordinates below match the original
SceneKit compositions, converted from Y-up to Blender's Z-up at the boundary.
"""
import argparse
import math
from pathlib import Path
import sys

import bpy
import bmesh
from mathutils import Vector


parser = argparse.ArgumentParser()
parser.add_argument('--model', required=True)
parser.add_argument('--output', required=True)
parser.add_argument('--width', type=int, default=2160)
parser.add_argument('--samples', type=int, default=256)
parser.add_argument('--height', type=int, default=800)
parser.add_argument('--eye', default='0.55,1.5,5.6')
parser.add_argument('--target', default='0.75,2.05,0')
parser.add_argument('--fov', type=float, default=30)
parser.add_argument('--focus', default='0,1.52,0')
parser.add_argument('--name', default='hero')
parser.add_argument('--exposure', type=float, default=1.45)
parser.add_argument('--fstop', type=float, default=1.6)
parser.add_argument('--sky', default='', help='r,g,b,strength of the surrounding light, for the page tint')
parser.add_argument('--button', type=float, default=0, help='watts of an orange light where the page button is')
parser.add_argument('--resume', action='store_true', help='Skip existing frames; only use when their settings are unchanged')
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
output = Path(args.output).resolve()
output.mkdir(parents=True, exist_ok=True)

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
prefs = bpy.context.preferences.addons['cycles'].preferences
prefs.compute_device_type = 'METAL'
prefs.get_devices()
for device in prefs.devices:
    device.use = device.type == 'METAL'
scene.cycles.device = 'GPU'
scene.cycles.samples = args.samples
scene.cycles.use_denoising = True
scene.cycles.adaptive_threshold = 0.008
scene.cycles.max_bounces = 12
scene.cycles.diffuse_bounces = 8
scene.cycles.glossy_bounces = 6
scene.render.resolution_x = args.width
scene.render.resolution_y = args.height
scene.render.resolution_percentage = 100
scene.render.fps = 30
scene.render.image_settings.file_format = 'PNG'
scene.render.image_settings.color_mode = 'RGBA'
scene.render.image_settings.color_depth = '8'
scene.render.film_transparent = True
scene.view_settings.view_transform = 'AgX'
scene.view_settings.look = 'AgX - Medium High Contrast'
scene.view_settings.exposure = args.exposure
scene.render.use_persistent_data = True

# A tabletop-sized object makes photographic aperture values meaningful.
scale = 0.12
def point(p):
    return Vector((p[0], -p[2], p[1])) * scale


def material(name, color, roughness):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    shader = m.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Base Color'].default_value = (*color, 1)
    shader.inputs['Roughness'].default_value = roughness
    return m, shader


porcelain, shader = material('Glazed white ceramic', (0.95, 0.95, 0.95), 0.22)
shader.inputs['IOR'].default_value = 1.50
shader.inputs['Metallic'].default_value = 0.0
shader.inputs['Coat Weight'].default_value = 0.40
shader.inputs['Coat Roughness'].default_value = 0.12
shader.inputs['Coat IOR'].default_value = 1.50
shader.inputs['Subsurface Weight'].default_value = 0.01
shader.inputs['Subsurface Radius'].default_value = (0.004, 0.002, 0.001)

bpy.ops.wm.obj_import(filepath=str(Path(args.model).resolve()), forward_axis='NEGATIVE_Z', up_axis='Y')
for obj in list(bpy.context.selected_objects):
    obj.scale *= scale
    if obj.type == 'MESH':
        mesh = bmesh.new()
        mesh.from_mesh(obj.data)
        bmesh.ops.recalc_face_normals(mesh, faces=list(mesh.faces))
        mesh.to_mesh(obj.data)
        mesh.free()
        obj.data.materials.clear()
        obj.data.materials.append(porcelain)
        for poly in obj.data.polygons:
            poly.use_smooth = True

ground, _ = material('Warm white cyclorama', (0.87, 0.862, 0.847), 0.65)
bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -0.0005))
bpy.context.object.name = 'Seamless ground'
bpy.context.object.data.materials.append(ground)
# The crop never shows the foot. Keep the ground's bounced light while allowing
# the native warm-white page to remain perfectly uniform behind the silhouette.
bpy.context.object.visible_camera = False
scene.world.use_nodes = True
scene.world.node_tree.nodes['Background'].inputs['Color'].default_value = (1.0, 0.98, 0.95, 1)
scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value = 0.2


def softbox(name, location, watts, size, color, height=None):
    data = bpy.data.lights.new(name, 'AREA')
    data.energy = watts
    data.shape = 'RECTANGLE' if height else 'DISK'
    data.size = size
    if height:
        data.size_y = height
    data.color = color
    obj = bpy.data.objects.new(name, data)
    scene.collection.objects.link(obj)
    obj.location = location
    obj.rotation_euler = (point((0, 0.8, 0)) - obj.location).to_track_quat('-Z', 'Y').to_euler()


softbox('Large window / key', (-0.55, -0.45, 0.9), 6.5, 0.85, (1.0, 0.975, 0.93))
softbox('White card / fill', (0.65, -0.2, 0.5), 1.8, 0.7, (0.95, 0.975, 1.0))
softbox('Top silk', (0.1, 0.45, 0.95), 3.5, 0.7, (1.0, 0.99, 0.97))
# A narrow studio reflection gives the glaze a readable highlight that travels
# across the curves as the camera moves, without changing the ceramic body.
softbox('Glaze reflection strip', (-0.42, -0.38, 0.46), 2.8, 0.12, (1.0, 0.985, 0.96), height=0.65)

camera_data = bpy.data.cameras.new('Welcome camera')
camera = bpy.data.objects.new('Welcome camera', camera_data)
scene.collection.objects.link(camera)
scene.camera = camera
camera_data.sensor_fit = 'VERTICAL'
camera_data.sensor_height = 24
camera_data.clip_start = 0.005
camera_data.clip_end = 100
camera_data.dof.use_dof = True
camera_data.dof.aperture_fstop = args.fstop
camera_data.dof.aperture_blades = 9



vec = lambda s: Vector(tuple(float(v) for v in s.split(',')))
# The page around the lamp: its tinted sky as the surrounding light, and the orange button above it, which the
# glaze reflects.
if args.sky:
    r, g, b, strength = (float(v) for v in args.sky.split(','))
    scene.world.node_tree.nodes['Background'].inputs['Color'].default_value = (r, g, b, 1)
    scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value = strength
if args.button:
    softbox('Download button', (0.1, -0.5, 0.5), args.button, 0.035, (1.0, 0.42, 0.08), height=0.012)
eye, target, subject = vec(args.eye), vec(args.target), vec(args.focus)
camera.location = point(eye)
camera.rotation_euler = (point(target) - camera.location).to_track_quat('-Z', 'Y').to_euler()
camera_data.lens = 12 / math.tan(math.radians(args.fov) / 2)
forward = (point(target) - camera.location).normalized()
camera_data.dof.focus_distance = (point(subject) - camera.location).dot(forward)
scene.render.filepath = str(output / f'{args.name}.png')
bpy.ops.render.render(write_still=True)
