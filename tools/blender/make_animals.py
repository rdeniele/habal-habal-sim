"""Street dog (aspin) and cat (puspin), built in code: clean low-poly, in separate parts the
game moves (see scenes/npc/animal.gd).

    blender -b -P tools/blender/make_animals.py     -> assets/animals/dog.glb, cat.glb

Parts (each object's origin is its joint): Body, Head (neck), Tail (base), LegFL, LegFR,
LegBL, LegBR (shoulder / hip). Blender Z up, faces +Y (Godot -Z), paws on z = 0.
Materials the game recolors: Coat, Patch, Muzzle.
"""
import bpy
import math
import os
import sys

from mathutils import Vector, Matrix

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from shapes import Part, loft, sweep, se, circle, srgb_to_linear, TAU   # noqa: E402

OUT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "animals"))
COLORS = {"Coat": "#c08a52", "Patch": "#e9dcc4", "Muzzle": "#e3cfae", "Nose": "#2a2220", "Eye": "#1c1512",
          "Shine": "#f6f2ea", "Inner": "#c88a80", "Tongue": "#d4686a", "Whisker": "#f3efe6"}


def materials():
    for name, hexc in COLORS.items():
        m = bpy.data.materials.new(name)
        try:
            m.use_nodes = True
        except Exception:
            pass
        b = m.node_tree.nodes.get("Principled BSDF")
        b.inputs["Base Color"].default_value = srgb_to_linear(hexc)
        b.inputs["Roughness"].default_value = 0.3 if name in ("Eye", "Nose") else 0.9


def ring_y(y, z, w, up, down, count=14, n=2.3):
    """Cross-section across the body (XZ plane) at depth y."""
    pts = []
    for i in range(count):
        cs, sn = se(TAU * i / count, n)
        pts.append(Vector((w * cs, y, z + (up if sn > 0 else down) * sn)))
    return pts


def blob(part, c, rx, ry, rz, mat, rows=5, count=12):
    c = Vector(c)
    rings = []
    for i in range(rows + 1):
        t = math.pi * (i + 0.3) / (rows + 0.6)
        y = c.y + ry * math.cos(t)
        rings.append([Vector((c.x + rx * math.sin(t) * math.cos(TAU * j / count), y,
                              c.z + rz * math.sin(t) * math.sin(TAU * j / count))) for j in range(count)])
    loft(part, rings, mat)


def cone(part, base, tip, r, mat, sides=6, flat=1.0):
    base, tip = Vector(base), Vector(tip)
    d = (tip - base).normalized()
    u = d.cross(Vector((0, 1, 0))).normalized()
    v = d.cross(u).normalized()
    ring = [part.v(base + (u * math.cos(TAU * i / sides) + v * math.sin(TAU * i / sides) * flat) * r) for i in range(sides)]
    top = part.v(tip)
    mid = part.v(base)
    for i in range(sides):
        j = (i + 1) % sides
        part.f((ring[i], ring[j], top), mat, False)
        part.f((ring[j], ring[i], mid), mat, False)


def leg(name, s, top, paw_y, thick, mat_top, hind):
    """One leg from the joint down to the paw; hind legs have the backward bend."""
    part = Part(name)
    x, y, z = top
    bend = -0.05 * s if hind else 0.008 * s
    path = [(x, y, z + 0.02 * s), (x, y + (0.01 if hind else 0.0) * s, z - z * 0.28),
            (x, y + bend, z * 0.4), (x, y + bend * 0.45, z * 0.16), (x, paw_y, 0.035 * s)]
    radii = [thick * 1.5, thick * 1.15, thick * 0.78, thick * 0.66, thick * 0.74]
    rings = []
    for (px, py, pz), r in zip(path, radii):
        rings.append([Vector((px + r * math.cos(TAU * i / 8), py + r * math.sin(TAU * i / 8), pz)) for i in range(8)])
    loft(part, rings, lambda c, n: "Patch" if c.z < z * 0.2 else mat_top)
    blob(part, (x, paw_y + 0.016 * s, 0.024 * s), thick * 1.05, thick * 1.35, 0.026 * s, "Patch", rows=4, count=8)
    return part


def animal(kind):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    materials()
    dog = kind == "dog"
    s = 1.0 if dog else 0.6
    # --- body: chest deeper than the belly, rump rounded -------------------------------
    body = Part("Body")
    if dog:
        rows = [(-0.31, 0.42, 0.035, 0.04, 0.04), (-0.27, 0.425, 0.09, 0.08, 0.085), (-0.16, 0.415, 0.105, 0.09, 0.095),
                (-0.03, 0.41, 0.098, 0.09, 0.09), (0.1, 0.41, 0.115, 0.1, 0.13), (0.2, 0.425, 0.11, 0.095, 0.13),
                (0.27, 0.45, 0.075, 0.08, 0.095), (0.31, 0.47, 0.03, 0.035, 0.04)]
    else:
        rows = [(-0.2, 0.24, 0.025, 0.03, 0.03), (-0.17, 0.245, 0.062, 0.06, 0.062), (-0.08, 0.24, 0.07, 0.062, 0.062),
                (0.03, 0.235, 0.062, 0.058, 0.058), (0.11, 0.24, 0.068, 0.062, 0.072), (0.16, 0.255, 0.05, 0.052, 0.058),
                (0.19, 0.27, 0.02, 0.025, 0.028)]

    def coat(c, n):
        if n.z < -0.55 or (c.y > (0.16 if dog else 0.1) and c.z < (0.38 if dog else 0.22)):
            return "Patch"     # pale belly and chest
        return "Coat"
    loft(body, [ring_y(*r) for r in rows], coat)
    if not dog:   # tabby stripes along the back
        for y in (-0.11, -0.05, 0.01, 0.07):
            sweep(body, [Vector((-0.055, y, 0.275)), Vector((0, y, 0.303)), Vector((0.055, y, 0.275))], circle(0.008, 5), "Patch",
                  scales=[0.3, 1.0, 0.3])
    neck_base = Vector((0, 0.24, 0.47)) if dog else Vector((0, 0.145, 0.265))
    neck_top = Vector((0, 0.32, 0.575)) if dog else Vector((0, 0.19, 0.325))
    sweep(body, [neck_base, neck_base.lerp(neck_top, 0.5), neck_top], circle(0.062 if dog else 0.044, 10), "Coat",
          scales=[1.15, 0.95, 0.85])

    # --- head (origin = top of the neck) ------------------------------------------------
    head = Part("Head")
    h = neck_top
    if dog:
        blob(head, h + Vector((0, 0.035, 0.035)), 0.082, 0.092, 0.08, "Coat", rows=6, count=14)
        muzzle = [(0.09, 0.012, 0.048, 0.042, 0.045), (0.15, 0.002, 0.038, 0.032, 0.036), (0.2, -0.002, 0.028, 0.025, 0.026)]
        loft(head, [ring_y(h.y + y, h.z + z, w, u, d, 10) for y, z, w, u, d in muzzle], "Muzzle")
        blob(head, h + Vector((0, 0.208, 0.012)), 0.021, 0.016, 0.018, "Nose", rows=4, count=8)
        blob(head, h + Vector((0, 0.165, -0.03)), 0.016, 0.03, 0.007, "Tongue", rows=4, count=8)
        for side in (-1, 1):
            cone(head, h + Vector((side * 0.055, 0.012, 0.095)), h + Vector((side * 0.095, 0.0, 0.178)), 0.037, "Coat", flat=0.55)
            cone(head, h + Vector((side * 0.057, 0.027, 0.1)), h + Vector((side * 0.089, 0.018, 0.158)), 0.022, "Inner", flat=0.35)
            eye = h + Vector((side * 0.04, 0.116, 0.056))
            blob(head, eye, 0.014, 0.009, 0.015, "Eye", rows=4, count=8)
            blob(head, eye + Vector((-side * 0.004, 0.009, 0.005)), 0.004, 0.003, 0.004, "Shine", rows=3, count=6)
            blob(head, eye + Vector((0, 0.0, 0.026)), 0.016, 0.01, 0.007, "Patch", rows=3, count=8)   # brow dots
    else:
        blob(head, h + Vector((0, 0.022, 0.028)), 0.062, 0.056, 0.052, "Coat", rows=6, count=14)
        for side in (-1, 1):
            blob(head, h + Vector((side * 0.017, 0.07, 0.01)), 0.022, 0.016, 0.017, "Muzzle", rows=4, count=8)
            cone(head, h + Vector((side * 0.038, 0.016, 0.065)), h + Vector((side * 0.057, 0.012, 0.125)), 0.027, "Coat", flat=0.6)
            cone(head, h + Vector((side * 0.039, 0.027, 0.069)), h + Vector((side * 0.053, 0.023, 0.11)), 0.016, "Inner", flat=0.35)
            eye = h + Vector((side * 0.026, 0.071, 0.04))
            blob(head, eye, 0.013, 0.006, 0.013, "Shine", rows=4, count=8)
            blob(head, eye + Vector((0, 0.005, 0)), 0.005, 0.003, 0.012, "Eye", rows=4, count=8)
            for k in (-1, 0, 1):
                a = h + Vector((side * 0.027, 0.078, 0.01 + k * 0.006))
                sweep(head, [a, a + Vector((side * 0.055, -0.004, k * 0.012))], circle(0.0013, 4), "Whisker")
        blob(head, h + Vector((0, 0.083, 0.022)), 0.009, 0.007, 0.006, "Nose", rows=3, count=8)

    # --- tail (origin = base) ------------------------------------------------------------
    tail = Part("Tail")
    if dog:   # aspin tail curled up over the back
        base = Vector((0, -0.29, 0.46))
        path = [base, base + Vector((0, -0.07, 0.07)), base + Vector((0, -0.075, 0.17)), base + Vector((0, -0.02, 0.22)),
                base + Vector((0, 0.045, 0.19))]
        sweep(tail, path, circle(0.03, 8), "Coat", scales=[1.1, 1.0, 0.9, 0.75, 0.3])
    else:
        base = Vector((0, -0.19, 0.27))
        path = [base, base + Vector((0, -0.08, 0.02)), base + Vector((0, -0.12, 0.1)), base + Vector((0, -0.105, 0.2)),
                base + Vector((0, -0.07, 0.235))]
        sweep(tail, path, circle(0.019, 8), "Coat", scales=[1.1, 1.0, 0.95, 0.9, 0.5])

    parts = [(body, Vector((0, 0, 0))), (head, neck_top.copy()), (tail, base.copy())]
    if dog:
        joints = {"LegFL": (-0.072, 0.185, 0.37), "LegFR": (0.072, 0.185, 0.37), "LegBL": (-0.072, -0.2, 0.39), "LegBR": (0.072, -0.2, 0.39)}
        thick = 0.034
    else:
        joints = {"LegFL": (-0.042, 0.105, 0.205), "LegFR": (0.042, 0.105, 0.205), "LegBL": (-0.044, -0.13, 0.22), "LegBR": (0.044, -0.13, 0.22)}
        thick = 0.022
    for name, j in joints.items():
        hind = name[3] == "B"
        parts.append((leg(name, s, j, j[1] + (0.0 if hind else 0.012 * s), thick, "Coat", hind), Vector(j)))

    for part, origin in parts:
        obj = part.build(sharp_deg=55.0)
        # move the geometry so the object's origin is the joint
        obj.data.transform(Matrix.Translation(-origin))
        obj.location = origin
    os.makedirs(OUT, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, kind + ".glb"), export_format="GLB")
    print("  %s: %d triangles" % (kind, sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in bpy.data.objects)))


for k in ("dog", "cat"):
    animal(k)
