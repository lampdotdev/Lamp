"""Render the welcome's three holds and two camera moves with Blender Cycles.

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
parser.add_argument('--frames', default='0,48,96', help='Comma-separated holds, or all')
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
scene.render.resolution_y = round(args.width * 760 / 1080)
scene.render.resolution_percentage = 100
scene.render.fps = 30
scene.render.image_settings.file_format = 'PNG'
scene.render.image_settings.color_mode = 'RGBA'
scene.render.image_settings.color_depth = '8'
scene.render.film_transparent = True
scene.view_settings.view_transform = 'AgX'
scene.view_settings.look = 'AgX - Medium High Contrast'
scene.view_settings.exposure = 1.45
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
camera_data.dof.aperture_fstop = 1.6
camera_data.dof.aperture_blades = 9


def framing(eye, subject, screen, fov):
    eye, subject = Vector(eye), Vector(subject)
    d = subject - eye
    yaw, pitch = math.atan2(d.x, -d.z), math.atan2(d.y, math.hypot(d.x, d.z))
    half = math.radians(fov) / 2
    yaw -= math.atan(screen[0] * math.tan(half) * 1080 / 760)
    pitch -= math.atan(screen[1] * math.tan(half))
    forward = Vector((math.sin(yaw) * math.cos(pitch), math.sin(pitch), -math.cos(yaw) * math.cos(pitch)))
    return eye, eye + forward * d.length, fov


poses = [
    (Vector((0.55, 1.5, 5.6)), Vector((0.75, 2.05, 0)), 30),
    framing((2.6, 2.2, 3.0), (0, 1.5, 0), (0.93, 0.05), 30),
    framing((-4.2, 1.7, -0.4), (-1.46, 1.25, -0.53), (-0.88, 0.05), 26),
]
focus = [Vector((0, 1.52, 0)), Vector((0, 1.55, 0)), Vector((-1.46, 1.25, -0.53))]
# The last composition is close enough that focusing inside the handle leaves its
# visible glaze blurred. Focus on the near surface of the actual imported mesh.
handle_centre = Vector((-1.4225 * math.cos(-0.35), 1.28375, 1.4225 * math.sin(-0.35)))
origin = point(poses[2][0])
direction = (point(handle_centre) - origin).normalized()
depsgraph = bpy.context.evaluated_depsgraph_get()
depsgraph.update()
hit, location, _, _, hit_object, _ = scene.ray_cast(depsgraph, origin, direction)
if not hit or hit_object.name == 'Seamless ground':
    raise RuntimeError('The final focus ray missed the handle')
focus[2] = Vector((location.x, location.z, -location.y)) / scale
print('Handle surface focus:', tuple(focus[2]))


def pose_at(frame):
    leg = min(frame // 48, 1)
    t = (frame - leg * 48) / 48
    e = t * t * (3 - 2 * t)
    a, b = poses[leg], poses[leg + 1]
    centre = Vector((0, 1, 0))
    def polar(p):
        d = p - centre
        return math.atan2(d.x, d.z), math.asin(d.y / d.length), d.length
    az, el, r = polar(a[0])
    bz, bl, br = polar(b[0])
    delta = (bz - az + math.pi) % (2 * math.pi) - math.pi
    az, el, r = az + delta * e, el + (bl - el) * e, r + (br - r) * e
    eye = centre + r * Vector((math.cos(el) * math.sin(az), math.sin(el), math.cos(el) * math.cos(az)))
    target = a[1].lerp(b[1], e)
    fov = a[2] + (b[2] - a[2]) * e
    return eye, target, fov, focus[leg].lerp(focus[leg + 1], e)


scene.frame_start = 0
scene.frame_end = 96
for frame in range(97):
    eye, target, fov, subject = pose_at(frame)
    camera.location = point(eye)
    camera.rotation_euler = (point(target) - camera.location).to_track_quat('-Z', 'Y').to_euler()
    camera_data.lens = 12 / math.tan(math.radians(fov) / 2)
    forward = (point(target) - camera.location).normalized()
    camera_data.dof.focus_distance = (point(subject) - camera.location).dot(forward)
    camera.keyframe_insert('location', frame=frame)
    camera.keyframe_insert('rotation_euler', frame=frame)
    camera_data.keyframe_insert('lens', frame=frame)
    camera_data.dof.keyframe_insert('focus_distance', frame=frame)

scene.frame_set(0)
bpy.ops.wm.save_as_mainfile(filepath=str(output / 'onboarding.blend'))
frames = range(97) if args.frames == 'all' else [int(f) for f in args.frames.split(',')]
for frame in frames:
    if args.resume and (output / f'{frame:04d}.png').exists():
        continue
    scene.frame_set(frame)
    scene.render.filepath = str(output / f'{frame:04d}.png')
    bpy.ops.render.render(write_still=True)
