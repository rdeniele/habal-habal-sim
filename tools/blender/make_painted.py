"""Sheet NPCs, "painted": the TripoSR shape with the character drawing projected back on
(front-facing faces get the drawing it was made from, back-facing faces the sheet's back view).
Keeps the shape's own head. Arms stay in their drawn pose (they're fused to the body in a
three-quarter drawing); spine, head and legs are rigged with Blender's automatic weights.

    blender -b -P tools/blender/make_painted.py -- vendor_m student_f ...
Needs tools/triposr_tmp/painted/<name>/ (tools/npc_painted_batch.py).
Output: assets/characters/npc/<name>.glb
"""
import bpy
import math
import os
import sys

from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import make_npc as N   # noqa: E402
import make_apose as A   # noqa: E402  (load_mesh)
import triposr_to_npc as T   # noqa: E402  (finding the neck and legs)

ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))


def paint(o, atlas_path, height):
    me = o.data
    pts = [v.co for v in me.vertices]
    x0, x1 = min(p.x for p in pts), max(p.x for p in pts)
    while me.uv_layers:
        me.uv_layers.remove(me.uv_layers[0])
    uv = me.uv_layers.new(name="UVMap").data
    me.update()
    normals = [Vector(v.normal) for v in me.vertices]   # averaged, so neighbors agree
    for _ in range(4):
        total = [n.copy() for n in normals]
        for e in me.edges:
            a, b = e.vertices
            total[a] += normals[b]
            total[b] += normals[a]
        normals = [n.normalized() for n in total]
    head = [p for p in pts if p.z > height * 0.86]
    head_mid = (min(p.y for p in head) + max(p.y for p in head)) / 2
    for poly in me.polygons:
        n = sum((normals[i] for i in poly.vertices), Vector()).normalized()
        if poly.center.z > height * 0.86:   # head: the back half gets the back drawing, the face never does
            view = 1 if (poly.center.y > head_mid + 0.015 and n.y > 0.1) or n.y > 0.85 else 0
        else:
            view = 0 if n.y <= 0.3 else 1
        for li in poly.loop_indices:
            p = me.vertices[me.loops[li].vertex_index].co
            u = (p.x - x0) / (x1 - x0) if view == 0 else (x1 - p.x) / (x1 - x0)
            u = min(max(u, 0.003), 0.997)
            uv[li].uv = ((view + u) / 2.0, p.z / height)
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


def build(name):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    female = name.endswith("_f")
    height = T.HEIGHT["f" if female else "m"]
    folder = os.path.join(ROOT, "tools", "triposr_tmp", "painted", name)
    o = A.load_mesh(os.path.join(folder, "0", "mesh.obj"), height, -90.0)
    o.name = name
    T.cut_above(o, height + 1.0)   # cuts nothing off the top; keeps only the main piece
    paint(o, os.path.join(folder, "atlas.png"), height)

    neck_z, _ = T.find_neck(o, height)
    mid = T.slice_width(o, neck_z - 0.12) or (0.0, 0.0, 0.0)
    cx, cy = mid[1], mid[2]
    p = N.body_plan(female)
    top = neck_z - 0.01
    p["torso"] = [(z * top / p["torso"][-1][0], w, f, b) for z, w, f, b in p["torso"]]
    p["shoulder"].z = top - 0.035
    p["hip"] = Vector((0.09, 0.0, height * 0.55))
    p["knee_z"] = height * 0.29
    bones = N.bones_of(p)
    axes = T.leg_axes(o, height, cy)
    T.fit_bones(bones, axes, cx, cy)
    head = T.slice_width(o, min(height - 0.12, neck_z + 0.1)) or (0.0, cx, cy)
    h, t, parent = bones["Head"]
    bones["Head"] = (Vector((head[1], head[2], neck_z + 0.02)), Vector((head[1], head[2], height)), parent)
    bones["neck"] = (bones["neck"][0], bones["Head"][0], bones["neck"][2])

    arm = N.make_armature(bones)
    for bone in arm.data.bones:   # fused arms must not pull on the body
        bone.use_deform = not any(k in bone.name for k in ("Shoulder", "Arm", "Hand"))
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    missing = [v.index for v in o.data.vertices if sum(g.weight for g in v.groups) < 0.01]
    if len(missing) > len(o.data.vertices) * 0.05:
        print("  %s: automatic weights failed, using distance weights" % name)
        o.vertex_groups.clear()
        T.weight_body(o, bones, axes, height * 0.5, female and name.startswith(("student", "misc")))
        head = o.vertex_groups.get("Head") or o.vertex_groups.new(name="Head")
        for v in o.data.vertices:
            if v.co.z > neck_z + 0.03:
                for g in list(v.groups):
                    o.vertex_groups[g.group].remove([v.index])
                head.add([v.index], 1.0, "REPLACE")
        missing = []
    if missing:
        (o.vertex_groups.get("Spine") or o.vertex_groups.new(name="Spine")).add(missing, 1.0, "REPLACE")
    os.makedirs(N.OUT_DIR, exist_ok=True)
    staging = os.path.join(folder, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=staging, export_format="GLB")
    os.replace(staging, os.path.join(N.OUT_DIR, name + ".glb"))
    print("  %s: %d triangles, %d points unweighted" % (name, sum(len(q.vertices) - 2 for q in o.data.polygons), len(missing)))


for n in sys.argv[sys.argv.index("--") + 1:]:
    build(n)
