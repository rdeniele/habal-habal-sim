"""Render a vehicle .glb from 4 angles into one preview picture, no window.
    blender -b -P tools/blender/render_vehicle.py -- input.glb output.png [paint_hex] [object_name]
object_name: keep only that object (traffic.glb holds several vehicles)."""
import bpy
import math
import os
import sys

import numpy as np
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
src, out = args[0], args[1]
paint = args[2] if len(args) > 2 else "#2f6b3a"
only = args[3] if len(args) > 3 else ""

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
if only:
    for o in list(bpy.data.objects):
        if o.type == "MESH" and o.name != only:
            bpy.data.objects.remove(o)
meshes = [o for o in bpy.data.objects if o.type == "MESH"]
pts = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
size = max(max(p.y for p in pts) - min(p.y for p in pts), max(p.x for p in pts) - min(p.x for p in pts))
height = max(p.z for p in pts)
k = max(size, height * 1.3, 2.05) / 2.05


def lin(hexc):
    h = hexc.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    return [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c] + [1.0]


m = bpy.data.materials.get("Paint")
if m:
    m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = lin(paint)

scene = bpy.context.scene
target = bpy.data.objects.new("target", None)
scene.collection.objects.link(target)
target.location = (0, 0, height * 0.45)
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
scene.collection.objects.link(cam)
cam.data.lens = 50
con = cam.constraints.new("TRACK_TO")
con.target = target
con.track_axis = "TRACK_NEGATIVE_Z"
con.up_axis = "UP_Y"
scene.camera = cam

sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(-35))
sun.data.energy = 3.5
scene.collection.objects.link(sun)
fill = bpy.data.objects.new("fill", bpy.data.lights.new("fill", "SUN"))
fill.rotation_euler = (math.radians(60), 0, math.radians(150))
fill.data.energy = 1.0
scene.collection.objects.link(fill)
bpy.ops.mesh.primitive_plane_add(size=20)
world = bpy.data.worlds.new("w")
scene.world = world
try:
    world.use_nodes = True
except Exception:
    pass
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.55, 0.62, 0.72, 1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.9

engines = [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items]
scene.render.engine = "BLENDER_EEVEE" if "BLENDER_EEVEE" in engines else "BLENDER_EEVEE_NEXT"
scene.view_settings.view_transform = "Standard"
scene.render.resolution_x = 900
scene.render.resolution_y = 650

# (camera position) - the model faces +Y in Blender after import
views = [(2.4, 2.6, 1.4), (3.4, 0.0, 0.75), (-2.2, -2.7, 1.5), (-1.0, 0.4, 2.6)]
tiles = []
base = os.path.splitext(out)[0]
for i, pos in enumerate(views):
    cam.location = (pos[0] * k, pos[1] * k, pos[2] * k)
    path = "%s_%d.png" % (base, i)
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    img = bpy.data.images.load(path)
    w, h = img.size
    tiles.append(np.array(img.pixels[:]).reshape(h, w, 4))
    os.remove(path)
top = np.concatenate([tiles[2], tiles[3]], axis=1)      # (image rows start at the bottom)
bottom = np.concatenate([tiles[0], tiles[1]], axis=1)
grid = np.concatenate([top, bottom], axis=0)
img = bpy.data.images.new("grid", grid.shape[1], grid.shape[0], alpha=True)
img.pixels = grid.ravel()
img.filepath_raw = out
img.file_format = "PNG"
img.save()
print("Rendered:", out)
