"""Render a .glb (e.g. the posed characters from tests/pose_export.gd) to a PNG, no window.
    blender -b -P tools/blender/render_glb.py -- input.glb output.png [--close]"""
import bpy
import math
import sys

args = sys.argv[sys.argv.index("--") + 1:]
src, out = args[0], args[1]
close = "--close" in args

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
# the game textures are pixel art: keep them sharp
for img_node in [n for m in bpy.data.materials if m.use_nodes for n in m.node_tree.nodes if n.type == "TEX_IMAGE"]:
    img_node.interpolation = "Closest"

# The game's merged meshes keep each part's color in vertex colors (Godot multiplies them in);
# Blender's importer ignores them, so multiply them in here too.
for o in [o for o in bpy.data.objects if o.type == "MESH" and len(o.data.color_attributes) > 0]:
    attr = o.data.color_attributes[0].name
    for m in o.data.materials:
        if m is None or not m.use_nodes or m.get("_vc_done"):
            continue
        nt = m.node_tree
        bsdf = nt.nodes.get("Principled BSDF")
        if bsdf is None:
            continue
        vc = nt.nodes.new("ShaderNodeVertexColor")
        vc.layer_name = attr
        mul = nt.nodes.new("ShaderNodeMix")
        mul.data_type = "RGBA"
        mul.blend_type = "MULTIPLY"
        mul.inputs["Factor"].default_value = 1.0
        base = bsdf.inputs["Base Color"]
        if base.links:
            nt.links.new(base.links[0].from_socket, mul.inputs["A"])
        else:
            mul.inputs["A"].default_value = base.default_value
        nt.links.new(vc.outputs["Color"], mul.inputs["B"])
        nt.links.new(mul.outputs["Result"], base)
        m["_vc_done"] = True

meshes = [o for o in bpy.data.objects if o.type == "MESH"]
xs = [(o.matrix_world @ v.co).x for o in meshes for v in o.data.vertices]
width = max(xs) - min(xs)
scene = bpy.context.scene
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
scene.collection.objects.link(cam)
# Godot's forward (-Z) becomes Blender's +Y after the glTF round trip. Camera in front of them.
cam.location = (0, width * 0.95 + 1.5, 1.05) if not close else (0, 3.0, 1.2)
cam.rotation_euler = (math.radians(88), 0, math.radians(180))
cam.data.lens = 35
scene.camera = cam
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
sun.rotation_euler = (math.radians(45), math.radians(-25), math.radians(-30))
sun.data.energy = 4.0
scene.collection.objects.link(sun)
world = bpy.data.worlds.new("w")
scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.5, 0.58, 0.68, 1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0
engines = [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items]
scene.render.engine = "BLENDER_EEVEE" if "BLENDER_EEVEE" in engines else ("BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in engines else "CYCLES")
if scene.render.engine == "CYCLES":
    scene.cycles.samples = 16
scene.view_settings.view_transform = "Standard"
scene.render.resolution_x = 1600
scene.render.resolution_y = 560
scene.render.filepath = out
bpy.ops.render.render(write_still=True)
print("Rendered:", out, "with", scene.render.engine)
