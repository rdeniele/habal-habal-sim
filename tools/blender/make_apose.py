"""A-pose character: TripoSR shape + the turnaround drawings painted on + a full skeleton
(arms too, since an A-pose keeps them apart from the body) with Blender's automatic weights.

    blender -b -P tools/blender/make_apose.py -- nanay
Needs tools/triposr_tmp/apose/<name>/ (from tools/apose_prep.py, plus TripoSR's 0/mesh.obj).
Output: assets/characters/npc/<name>.glb (+ .blend).
"""
import bpy
import bmesh
import json
import math
import os
import sys

from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import make_npc as N   # noqa: E402  (make_armature)

ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))

# Joint positions as pixels on the sheet's FRONT view. "L" is the character's left (image right).
CHARACTERS = {"nanay": {"height": 1.55, "turn": -90.0, "joints": {
    "hips": (195, 560), "chest": (195, 400), "neck": (195, 272), "head": (195, 245), "crown": (195, 125),
    "shoulder": (268, 308), "elbow": (318, 418), "wrist": (350, 520), "tip": (364, 580),
    "hip": (232, 590), "knee": (236, 745), "ankle": (240, 868), "toe": (252, 915)}}}


def load_mesh(path, height, turn):
    bpy.ops.wm.obj_import(filepath=path)
    o = [x for x in bpy.data.objects if x.type == "MESH"][0]
    o.rotation_euler = (0, 0, 0)
    o.data.transform(Matrix.Rotation(math.radians(turn), 4, "Z"))
    pts = [v.co.copy() for v in o.data.vertices]
    k = height / (max(p.z for p in pts) - min(p.z for p in pts))
    cx = (max(p.x for p in pts) + min(p.x for p in pts)) / 2
    cy = (max(p.y for p in pts) + min(p.y for p in pts)) / 2
    z0 = min(p.z for p in pts)
    for v in o.data.vertices:
        v.co = Vector(((v.co.x - cx) * k, (v.co.y - cy) * k, (v.co.z - z0) * k))
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=0.0005)
    bm.to_mesh(o.data)
    bm.free()
    tris = sum(len(p.vertices) - 2 for p in o.data.polygons)
    if tris > 16000:
        mod = o.modifiers.new("dec", "DECIMATE")
        mod.ratio = 16000 / tris
        bpy.context.view_layer.objects.active = o
        o.select_set(True)
        bpy.ops.object.modifier_apply(modifier=mod.name)
    smooth = o.modifiers.new("smooth", "SMOOTH")
    smooth.factor = 0.5
    smooth.iterations = 4
    bpy.context.view_layer.objects.active = o
    o.select_set(True)
    bpy.ops.object.modifier_apply(modifier=smooth.name)
    for p in o.data.polygons:
        p.use_smooth = True
    return o


def paint(o, atlas_path, height):
    """Project the drawings: faces looking forward get the front view, backward the back view,
    the sides of the head the side view. The atlas is front | back | side."""
    me = o.data
    pts = [v.co for v in me.vertices]
    x0, x1 = min(p.x for p in pts), max(p.x for p in pts)
    y0, y1 = min(p.y for p in pts), max(p.y for p in pts)
    while me.uv_layers:
        me.uv_layers.remove(me.uv_layers[0])
    uv = me.uv_layers.new(name="UVMap").data
    me.update()
    # averaged normals, so neighboring faces choose the same drawing (no patchwork)
    normals = [Vector(v.normal) for v in me.vertices]
    for _ in range(4):
        total = [n.copy() for n in normals]
        for e in me.edges:
            a, b = e.vertices
            total[a] += normals[b]
            total[b] += normals[a]
        normals = [n.normalized() for n in total]
    head = [p for p in pts if p.z > height * 0.84]
    head_mid = (min(p.y for p in head) + max(p.y for p in head)) / 2
    for poly in me.polygons:
        n = sum((normals[i] for i in poly.vertices), Vector()).normalized()
        c = poly.center
        # side drawing only for the sides/back of the head; the whole face stays on the front view
        if c.z > height * 0.865 and abs(n.x) > abs(n.y) * 1.2 and c.y > head_mid - 0.01:
            view = 2
        elif c.z > height * 0.865:
            view = 0 if c.y < head_mid + 0.02 else 1
        elif c.z > height * 0.8:   # jaw and neck: the back drawing shows the dark bun there
            view = 0 if n.y <= 0.6 else 1
        else:
            view = 0 if n.y <= 0.15 else 1
        for li in poly.loop_indices:
            p = me.vertices[me.loops[li].vertex_index].co
            if view == 0:
                u = (p.x - x0) / (x1 - x0)
            elif view == 1:
                u = (x1 - p.x) / (x1 - x0)
            else:   # the side drawing faces right = the character's front (-Y)
                u = (y1 - p.y) / (y1 - y0)
            # side of the jaw: the drawing's edge there is the dark bun behind it, so sample inward
            if view < 2 and height * 0.78 < c.z < height * 0.87 and abs(n.x) > 0.35:
                centre = (-x0) / (x1 - x0) if view == 0 else x1 / (x1 - x0)
                u = centre + (u - centre) * 0.6
            u = min(max(u, 0.002), 0.998)
            uv[li].uv = ((view + u) / 3.0, p.z / height)
    m = bpy.data.materials.new("Art")
    try:
        m.use_nodes = True
    except Exception:
        pass
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(atlas_path)
    tex.image.pack()
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.9
    me.materials.clear()
    me.materials.append(m)


def skeleton(o, spec, box, height):
    scale = height / (box[3] - box[1])
    mid = (box[0] + box[2]) / 2.0
    pts = [v.co for v in o.data.vertices]

    def depth(x, z):
        """Middle (front to back) of the body near (x, z)."""
        near = [p.y for p in pts if abs(p.x - x) < 0.045 and abs(p.z - z) < 0.03]
        return (min(near) + max(near)) / 2 if near else 0.0

    def at(joint, side=1):
        px, py = spec["joints"][joint]
        x = (px - mid) * scale * side
        z = (box[3] - py) * scale
        return Vector((x, depth(x, z), z))

    hips, chest, neck, head, crown = (at(j) for j in ("hips", "chest", "neck", "head", "crown"))
    for v in (chest, neck, head, crown):
        v.x = 0.0
    hips.x = 0.0
    s1 = hips.lerp(chest, 0.34)
    s2 = hips.lerp(chest, 0.67)
    bones = {
        "Hips": (hips, s1, None), "Spine02": (s1, s2, "Hips"), "Spine01": (s2, chest, "Spine02"),
        "Spine": (chest, neck, "Spine01"), "neck": (neck, head, "Spine"), "Head": (head, crown, "neck"),
    }
    for side, pre in ((1, "Left"), (-1, "Right")):
        sh, el, wr, tip = (at(j, side) for j in ("shoulder", "elbow", "wrist", "tip"))
        hip, knee, ankle, toe = (at(j, side) for j in ("hip", "knee", "ankle", "toe"))
        hip.y = (hips.y + knee.y) / 2
        toe.y = ankle.y - 0.11
        bones[pre + "Shoulder"] = (Vector((side * 0.03, chest.y, sh.z)), sh, "Spine")
        bones[pre + "Arm"] = (sh, el, pre + "Shoulder")
        bones[pre + "ForeArm"] = (el, wr, pre + "Arm")
        bones[pre + "Hand"] = (wr, tip, pre + "ForeArm")
        bones[pre + "UpLeg"] = (hip, knee, "Hips")
        bones[pre + "Leg"] = (knee, ankle, pre + "UpLeg")
        bones[pre + "Foot"] = (ankle, toe, pre + "Leg")
        bones[pre + "ToeBase"] = (toe, toe + Vector((0, -0.05, 0)), pre + "Foot")
    return bones


def main():
    name = sys.argv[sys.argv.index("--") + 1]
    spec = CHARACTERS[name]
    folder = os.path.join(ROOT, "tools", "triposr_tmp", "apose", name)
    box = json.load(open(os.path.join(folder, "info.json")))["box"]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    o = load_mesh(os.path.join(folder, "0", "mesh.obj"), spec["height"], spec["turn"])
    o.name = name
    paint(o, os.path.join(folder, "atlas.png"), spec["height"])
    bones = skeleton(o, spec, box, spec["height"])
    arm = N.make_armature(bones)
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    missing = [v.index for v in o.data.vertices if sum(g.weight for g in v.groups) < 0.01]
    print("  automatic weights: %d of %d points unweighted" % (len(missing), len(o.data.vertices)))
    if len(missing) > len(o.data.vertices) * 0.05:
        raise RuntimeError("Blender could not weight this mesh")
    if missing:
        (o.vertex_groups.get("Spine") or o.vertex_groups.new(name="Spine")).add(missing, 1.0, "REPLACE")
    print("  %s: %d triangles" % (name, sum(len(p.vertices) - 2 for p in o.data.polygons)))
    os.makedirs(N.OUT_DIR, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(N.OUT_DIR, name + ".blend"))
    bpy.ops.export_scene.gltf(filepath=os.path.join(N.OUT_DIR, name + ".glb"), export_format="GLB")


if __name__ == "__main__":
    main()
