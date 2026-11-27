"""Render a character .glb (made by make_npc.py, facing -Y) from the front, 3/4, side and back,
plus a face close-up, into one picture. No window.
    blender -b -P tools/blender/render_character.py -- input.glb output.png"""
import bpy
import math
import os
import sys

import numpy as np

args = sys.argv[sys.argv.index("--") + 1:]
src, out = os.path.abspath(args[0]), os.path.abspath(args[1])

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
for img_node in [n for m in bpy.data.materials if m.use_nodes for n in m.node_tree.nodes if n.type == "TEX_IMAGE"]:
    img_node.interpolation = "Linear"

scene = bpy.context.scene
target = bpy.data.objects.new("target", None)
scene.collection.objects.link(target)
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
scene.collection.objects.link(cam)
con = cam.constraints.new("TRACK_TO")
con.target = target
con.track_axis = "TRACK_NEGATIVE_Z"
con.up_axis = "UP_Y"
scene.camera = cam
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
sun.rotation_euler = (math.radians(55), 0, math.radians(-25))
sun.data.energy = 3.0
scene.collection.objects.link(sun)
fill = bpy.data.objects.new("fill", bpy.data.lights.new("fill", "SUN"))
fill.rotation_euler = (math.radians(60), 0, math.radians(160))
fill.data.energy = 1.2
scene.collection.objects.link(fill)
world = bpy.data.worlds.new("w")
scene.world = world
try:
    world.use_nodes = True
except Exception:
    pass
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.82, 0.78, 0.72, 1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0
engines = [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items]
scene.render.engine = "BLENDER_EEVEE" if "BLENDER_EEVEE" in engines else "BLENDER_EEVEE_NEXT"
scene.view_settings.view_transform = "Standard"
scene.render.resolution_x = 420
scene.render.resolution_y = 760

# (camera position, look-at point, lens)
views = [((0, -4.2, 1.0), (0, 0, 0.85), 50), ((2.9, -3.0, 1.1), (0, 0, 0.85), 50), ((4.2, 0, 1.0), (0, 0, 0.85), 50),
         ((0, 4.2, 1.0), (0, 0, 0.85), 50), ((0, -1.2, 1.6), (0, 0, 1.58), 85)]
tiles = []
base = os.path.splitext(out)[0]
for i, (pos, look, lens) in enumerate(views):
    cam.location = pos
    target.location = look
    cam.data.lens = lens
    path = "%s_%d.png" % (base, i)
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    img = bpy.data.images.load(path)
    w, h = img.size
    tiles.append(np.array(img.pixels[:]).reshape(h, w, 4))
    os.remove(path)
grid = np.concatenate(tiles, axis=1)
img = bpy.data.images.new("grid", grid.shape[1], grid.shape[0], alpha=True)
img.pixels = grid.ravel()
img.filepath_raw = out
img.file_format = "PNG"
img.save()
print("Rendered:", out)
