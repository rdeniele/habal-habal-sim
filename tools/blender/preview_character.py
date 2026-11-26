"""Renders a quick preview of the character kit put together (no window needed).
    blender -b -P tools/blender/preview_character.py -- out.png
Opens assets/characters/character_kit.blend, places the parts like the game does
(same joint positions as character_model.gd), and renders front + side views."""
import bpy
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
KIT = os.path.normpath(os.path.join(HERE, "..", "..", "assets", "characters", "character_kit.blend"))
OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else os.path.join(HERE, "preview.png")

HIP_Y, THIGH, SHIN, UPPER_ARM, FOREARM = 0.92, 0.44, 0.42, 0.28, 0.25

bpy.ops.wm.open_mainfile(filepath=KIT)
src = {o.name: o for o in bpy.data.objects if o.type == "MESH"}
for o in src.values():
    o.hide_render = True


def mat(name, rgb):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*rgb, 1)
    m.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.8
    return m


TEX_DIR = os.path.join(os.environ.get("APPDATA", ""), "Godot", "app_userdata", "Habal-Habal Simulator", "kit_preview")


def tex_mat(name, file):
    """Material showing one of the game's painted textures (saved by tests/kit_check.gd)."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nodes = m.node_tree.nodes
    img = nodes.new("ShaderNodeTexImage")
    img.image = bpy.data.images.load(os.path.join(TEX_DIR, file))
    img.interpolation = "Closest"   # pixel look, like the game
    bsdf = nodes["Principled BSDF"]
    m.node_tree.links.new(img.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.85
    return m


def srgb(h):
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


def solid(name, hex_color):
    """Plain color as a tiny image (the texture view needs an image on every material)."""
    img = bpy.data.images.new(name, 2, 2)
    h = hex_color.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    img.pixels = [c[0], c[1], c[2], 1.0] * 4
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    node = m.node_tree.nodes.new("ShaderNodeTexImage")
    node.image = img
    m.node_tree.links.new(node.outputs["Color"], m.node_tree.nodes["Principled BSDF"].inputs["Base Color"])
    return m


SKINS = [solid("skin0", "c68c5a"), solid("skin1", "d9a06f"), solid("skin2", "a8703f"), solid("skin3", "e0b08a")]
FACES = [tex_mat("face%d" % i, "face_%d.png" % i) for i in range(4)]
TOPS = [tex_mat("tee", "tee.png"), tex_mat("dress", "dress.png"), tex_mat("polo", "polo.png"), tex_mat("jacket", "jacket.png")]
BOTTOMS = [tex_mat("jeans", "jeans.png"), tex_mat("pants", "pants.png")]
HAIR = tex_mat("hair", "hair.png")
GRAY_HAIR = solid("grayhair", "b5b5b5")
SHOE = tex_mat("shoe", "shoe.png")


def place(part, loc, material, offset_x=0.0, rot=(0, 0, 0)):
    o = src[part].copy()
    o.data = src[part].data.copy()   # own copy, so each person can have their own materials
    o.hide_render = False
    o.location = (loc[0] + offset_x, loc[1], loc[2])
    o.rotation_euler = rot
    o.data.materials.clear()
    o.data.materials.append(material)
    bpy.context.collection.objects.link(o)


def person(x, i, female=False, heavy=False, hair="hair_short", yaw=0.0, top=0, bottom=0, sleeve="sleeve_short",
           hair_mat=None, skirt=None):
    tag = ("f" if female else "m") + ("_heavy" if heavy else "")
    sh = (0.175 if female else 0.2) + (0.02 if heavy else 0.0)
    hip = (0.095 if female else 0.085) + (0.012 if heavy else 0.0)
    SKIN, SHIRT, PANTS = SKINS[i], TOPS[top], BOTTOMS[bottom]
    parts = [
        ("torso_" + tag, (0, 0, HIP_Y), SHIRT), ("pelvis_" + tag, (0, 0, HIP_Y + 0.02), SHIRT if skirt else PANTS),
        ("neck", (0, 0, HIP_Y + 0.62), SKIN), ("head", (0, 0, HIP_Y + 0.71), FACES[i]),
        (hair, (0, 0, HIP_Y + 0.71), hair_mat or HAIR),
    ]
    if skirt:
        parts.append((skirt, (0, 0, HIP_Y + 0.01), SHIRT))
    for s in (-1, 1):
        legs = SKIN if skirt else PANTS
        parts += [
            ("upper_arm", (s * sh, 0, HIP_Y + 0.5), SKIN),
            ("forearm", (s * sh, 0, HIP_Y + 0.5 - UPPER_ARM), SKIN),
            ("fist_l" if s < 0 else "fist", (s * sh, 0, HIP_Y + 0.5 - UPPER_ARM - FOREARM), SKIN),
            ("thigh", (s * hip, 0, HIP_Y), legs), ("shin", (s * hip, 0, HIP_Y - THIGH), legs),
            ("slipper" if skirt else "sneaker", (s * hip, 0, HIP_Y - THIGH - SHIN + 0.04), SHOE),
        ]
        if sleeve:
            parts.append((sleeve, (s * sh, 0, HIP_Y + 0.5), SHIRT))
    c, sn = math.cos(yaw), math.sin(yaw)
    for name, (px, py, pz), m in parts:
        rx, ry = px * c - py * sn, px * sn + py * c
        place(name, (rx, ry, pz), m, x, (0, 0, yaw))


CLOSE = "--close" in sys.argv
person(-1.6 if not CLOSE else -0.75, 0, hair="hair_short", top=0)
person(-0.55 if not CLOSE else -0.25, 1, female=True, hair="hair_long", top=1, sleeve="sleeve_cap", skirt="dress_skirt")
person(0.55 if not CLOSE else 0.25, 2, heavy=True, hair="hair_side", top=2, bottom=1, yaw=math.radians(25 if CLOSE else 60))
person(1.6 if not CLOSE else 0.75, 3, female=True, hair="hair_bun", top=3, bottom=1, sleeve=None, hair_mat=GRAY_HAIR, yaw=math.radians(-30))

scene = bpy.context.scene
cam_data = bpy.data.cameras.new("cam")
cam = bpy.data.objects.new("cam", cam_data)
scene.collection.objects.link(cam)
cam.location = (0, 6.0, 1.05) if not CLOSE else (0, 2.2, 1.62)
cam.rotation_euler = (math.radians(90), 0, math.radians(180))
cam_data.lens = 40 if not CLOSE else 70
scene.camera = cam
light = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
light.rotation_euler = (math.radians(50), math.radians(20), math.radians(150))
light.data.energy = 3.5
scene.collection.objects.link(light)
world = scene.world or bpy.data.worlds.new("w")
scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.55, 0.62, 0.7, 1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.9
scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "STUDIO"
scene.display.shading.color_type = "TEXTURE"
scene.display.shading.show_specular_highlight = False
scene.render.resolution_x = 1280
scene.render.resolution_y = 720
scene.render.filepath = OUT
bpy.ops.render.render(write_still=True)
print("Preview saved:", OUT)
