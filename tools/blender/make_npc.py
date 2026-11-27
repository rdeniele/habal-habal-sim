"""Habal-Habal Simulator - detailed NPCs from the NPC character sheet (original, built by code).

Each NPC is ONE smooth skinned mesh (body + clothes) on a human skeleton that uses the same
bone names as the player's rider model, so the game's existing animations drive it
(see CharacterModel._attach_skin in scenes/common/character_model.gd).

Style: anime-like proportions (big head, small chin), soft round shapes, flat colors and a
painted face (big eyes, brows, small mouth, blush).

Run without opening Blender's window (from the project folder):
    "D:\\Tools\\Blender\\blender-5.3.0-windows-x64\\blender.exe" -b -P tools/blender/make_npc.py -- vendor

Output: assets/characters/npc/<type>_m.glb and <type>_f.glb (+ .blend for editing).

Conventions: Blender Z up, the NPC faces -Y (glTF / Godot +Z; the game turns it around),
feet on z = 0, arms in an A-pose (40 degrees down from the side).
"""
import bpy
import bmesh
import math
import os
import sys

import numpy as np
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from shapes import Part, loft, se, catmull, circle, rrect, sweep, tube, rbox, srgb_to_linear, TAU   # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.normpath(os.path.join(HERE, "..", "..", "assets", "characters", "npc"))

ARM_DOWN = math.radians(40.0)   # A-pose: arm angle down from horizontal is 50, from vertical 40


# ---------------------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------------------

def ring(z, cx, cy, hw, front, back, n=2.4, count=20, shift=None):
    """Cross-section at height z. Front is -Y. shift(t) -> (dx, dy) bumps (optional)."""
    pts = []
    for i in range(count):
        t = TAU * i / count
        cs, sn = se(t, n)
        y = cy + (back if sn > 0 else front) * sn
        p = Vector((cx + hw * cs, y, z))
        if shift:
            dx, dy = shift(t)
            p.x += dx
            p.y += dy
        pts.append(p)
    return pts


def make_mats(colors):
    for name, hexc in colors.items():
        m = bpy.data.materials.new(name)
        try:
            m.use_nodes = True
        except Exception:
            pass
        b = m.node_tree.nodes.get("Principled BSDF")
        b.inputs["Base Color"].default_value = srgb_to_linear(hexc)
        b.inputs["Roughness"].default_value = 0.8
        b.inputs["Metallic"].default_value = 0.0


def panel(part, rows, thick, mat):
    """A cloth panel from a grid of points (rows top->bottom, each left->right). Thickness
    goes toward +Y (into the body), so the front face is the grid itself."""
    front = [[part.v(p) for p in row] for row in rows]
    back = [[part.v(p + Vector((0, thick, 0))) for p in row] for row in rows]
    nr, nc = len(rows), len(rows[0])
    for r in range(nr - 1):
        for c in range(nc - 1):
            part.f((front[r][c], front[r][c + 1], front[r + 1][c + 1], front[r + 1][c]), mat)
            part.f((back[r][c + 1], back[r][c], back[r + 1][c], back[r + 1][c + 1]), mat)
    for r in range(nr - 1):   # left and right edges
        part.f((front[r][0], front[r + 1][0], back[r + 1][0], back[r][0]), mat)
        part.f((front[r + 1][-1], front[r][-1], back[r][-1], back[r + 1][-1]), mat)
    for c in range(nc - 1):   # top and bottom edges
        part.f((front[0][c + 1], front[0][c], back[0][c], back[0][c + 1]), mat)
        part.f((front[-1][c], front[-1][c + 1], back[-1][c + 1], back[-1][c]), mat)


def tuft(part, base, direction, r, length, mat, sides=5):
    """A pointed clump of hair (cone)."""
    d = Vector(direction).normalized()
    base = Vector(base)
    ref = Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0))
    u = d.cross(ref).normalized()
    w = d.cross(u)
    ringv = [part.v(base + (u * math.cos(TAU * i / sides) + w * math.sin(TAU * i / sides)) * r) for i in range(sides)]
    tip = part.v(base + d * length)
    back = part.v(base - d * r * 0.6)
    for i in range(sides):
        j = (i + 1) % sides
        part.f((ringv[i], ringv[j], tip), mat)
        part.f((ringv[j], ringv[i], back), mat)


# ---------------------------------------------------------------------------------------
# The body plan (one set of numbers per gender)
# ---------------------------------------------------------------------------------------

def body_plan(female):
    k = 0.95 if female else 1.0                     # overall size
    p = {"k": k, "female": female}
    # torso sections (z, half width, front depth, back depth), crotch to neck
    if female:
        p["torso"] = [(0.85, 0.15, 0.095, 0.11), (0.93, 0.175, 0.10, 0.12), (1.01, 0.14, 0.085, 0.095),
                      (1.08, 0.13, 0.085, 0.09), (1.18, 0.145, 0.12, 0.095), (1.26, 0.15, 0.115, 0.095),
                      (1.33, 0.15, 0.09, 0.09), (1.385, 0.13, 0.07, 0.075), (1.42, 0.06, 0.045, 0.045)]
    else:
        p["torso"] = [(0.86, 0.15, 0.10, 0.11), (0.95, 0.165, 0.10, 0.115), (1.03, 0.152, 0.098, 0.10),
                      (1.12, 0.158, 0.102, 0.10), (1.24, 0.172, 0.112, 0.105), (1.34, 0.176, 0.105, 0.1),
                      (1.41, 0.155, 0.085, 0.085), (1.455, 0.075, 0.05, 0.05)]
    top = p["torso"][-1][0]
    p["shoulder"] = Vector((0.165 if female else 0.18, 0.0, top - 0.035))
    p["upper_arm"] = 0.26 if female else 0.28
    p["forearm"] = 0.23 if female else 0.25
    p["hip"] = Vector((0.085 if female else 0.09, 0.0, 0.92 if female else 0.93))
    p["knee_z"] = 0.48 if female else 0.5
    p["ankle_z"] = 0.085
    p["neck"] = (top - 0.04, top + 0.06)
    p["head_c"] = Vector((0.0, -0.012, top + 0.17))
    return p


def scale_vec(v, k):
    return Vector((v.x * k, v.y * k, v.z * k))


def arm_points(p, side):
    s = Vector((side * p["shoulder"].x, p["shoulder"].y, p["shoulder"].z))
    d = Vector((side * math.sin(ARM_DOWN), 0.0, -math.cos(ARM_DOWN)))
    e = s + d * p["upper_arm"]
    w = e + d * p["forearm"]
    return s, e, w, d


def leg_points(p, side):
    h = Vector((side * p["hip"].x, 0.0, p["hip"].z))
    k = Vector((side * (p["hip"].x + 0.01), -0.005, p["knee_z"]))
    a = Vector((side * (p["hip"].x + 0.012), 0.0, p["ankle_z"]))
    return h, k, a


def bones_of(p):
    """name -> (head, tail, parent), in the same names as the rider model."""
    t = p["torso"]
    hips_z, top = t[1][0], t[-1][0]
    b = {
        "Hips": (Vector((0, 0, hips_z)), Vector((0, 0, hips_z + 0.08)), None),
        "Spine02": (Vector((0, 0, hips_z + 0.08)), Vector((0, 0, hips_z + 0.18)), "Hips"),
        "Spine01": (Vector((0, 0, hips_z + 0.18)), Vector((0, 0, hips_z + 0.3)), "Spine02"),
        "Spine": (Vector((0, 0, hips_z + 0.3)), Vector((0, 0, top - 0.03)), "Spine01"),
        "neck": (Vector((0, 0, top - 0.03)), Vector((0, 0, top + 0.06)), "Spine"),
        "Head": (Vector((0, 0, top + 0.06)), Vector((0, 0, top + 0.3)), "neck"),
    }
    for side, pre in ((1, "Left"), (-1, "Right")):
        s, e, w, d = arm_points(p, side)
        b[pre + "Shoulder"] = (Vector((side * 0.03, 0, s.z)), s, "Spine")
        b[pre + "Arm"] = (s, e, pre + "Shoulder")
        b[pre + "ForeArm"] = (e, w, pre + "Arm")
        b[pre + "Hand"] = (w, w + d * 0.09, pre + "ForeArm")
        h, k, a = leg_points(p, side)
        b[pre + "UpLeg"] = (h, k, "Hips")
        b[pre + "Leg"] = (k, a, pre + "UpLeg")
        toe = Vector((a.x, -0.12, 0.025))
        b[pre + "Foot"] = (a, toe, pre + "Leg")
        b[pre + "ToeBase"] = (toe, toe + Vector((0, -0.06, 0)), pre + "Foot")
    return b


# ---------------------------------------------------------------------------------------
# Body parts. Each returns a list of (Part, allowed bones) so every piece only bends
# with the bones it belongs to (a left leg never follows the right leg).
# ---------------------------------------------------------------------------------------

def torso_surface(p):
    """Front surface y at (x, z) on the torso (for laying clothes on it)."""
    secs = p["torso"]

    def at(x, z):
        for (z0, w0, f0, b0), (z1, w1, f1, b1) in zip(secs, secs[1:]):
            if z0 <= z <= z1:
                t = (z - z0) / (z1 - z0)
                w, f = w0 + (w1 - w0) * t, f0 + (f1 - f0) * t
                c = min(abs(x) / w, 0.999)
                return -f * (1 - c ** 2.4) ** (1 / 2.4)
        return -secs[0][2]
    return at


def build_torso(p, shirt_mat, pelvis_mat, shirt_bottom_z):
    part = Part("torso")
    rows = catmull(p["torso"], 3)

    def mat(c, n):
        return pelvis_mat if c.z < shirt_bottom_z else shirt_mat
    loft(part, [ring(z, 0, 0, w, f, b, n=2.4, count=22) for z, w, f, b in rows], mat)
    # the shoulder edges also follow the upper arms (no "shoulder pads" when the arms come down)
    allowed = ["Hips", "Spine02", "Spine01", "Spine", "LeftShoulder", "RightShoulder", "neck", "LeftArm", "RightArm"]
    return [(part, allowed)]


def build_arm(p, side, sleeve_mat, sleeve_len, skin_mat, long_sleeve=False):
    part = Part("arm")
    s, e, w, d = arm_points(p, side)
    path = [s - d * 0.03, s + d * 0.06, s + d * (p["upper_arm"] * 0.5), e - d * 0.02, e + d * 0.03,
            e + d * (p["forearm"] * 0.55), w - d * 0.01]
    radii = [0.058, 0.06, 0.054, 0.046, 0.045, 0.04, 0.032]
    if p["female"]:
        radii = [r * 0.88 for r in radii]
    cut = sleeve_len if not long_sleeve else 9.0

    def mat(c, n):
        along = (c - s).dot(d)
        return sleeve_mat if along < cut else skin_mat
    rings_ = []
    up = Vector((0, 0, 1))
    for i, (pt, r) in enumerate(zip(path, radii)):
        # cross-section perpendicular to the arm
        u = d.cross(Vector((0, 1, 0))).normalized()
        v = d.cross(u).normalized()
        rings_.append([pt + (u * math.cos(TAU * j / 12) + v * math.sin(TAU * j / 12)) * r for j in range(12)])
    loft(part, rings_, mat)
    if not long_sleeve:
        # a short sleeve: a looser cloth tube around the upper arm, a bit flared
        u = d.cross(Vector((0, 1, 0))).normalized()
        v = d.cross(u).normalized()
        sr = []
        for along, r in ((-0.02, 0.06), (sleeve_len * 0.5, 0.064), (sleeve_len, 0.066)):
            pt = s + d * along
            sr.append([pt + (u * math.cos(TAU * j / 12) + v * math.sin(TAU * j / 12)) * r * (0.9 if p["female"] else 1.0)
                       for j in range(12)])
        loft(part, sr, sleeve_mat, cap0=False, cap1=False)
    # hand: a soft paddle along the arm with a thumb
    hand_path = [w - d * 0.01, w + d * 0.04, w + d * 0.085]
    u = d.cross(Vector((0, 1, 0))).normalized()
    hr = []
    for k, (pt, sc) in enumerate(zip(hand_path, (0.85, 1.0, 0.7))):
        hr.append([pt + (u * math.cos(TAU * j / 10) * 0.018 + Vector((0, 1, 0)) * math.sin(TAU * j / 10) * 0.036) * sc
                   for j in range(10)])
    loft(part, hr, skin_mat)
    tuft(part, w + d * 0.025 + Vector((0, -0.03, 0)), d + Vector((0, -0.4, 0)), 0.012, 0.045, skin_mat)
    pre = "Left" if side > 0 else "Right"
    return [(part, [pre + "Shoulder", pre + "Arm", pre + "ForeArm", pre + "Hand"])]


def build_leg(p, side, upper_mat, cut_z, lower_mat, baggy=0.0, cuff_mat=None):
    """upper_mat covers the leg down to cut_z (shorts / pants), below that lower_mat."""
    part = Part("leg")
    h, k, a = leg_points(p, side)
    path = [h + Vector((0, 0, 0.05)), h + (k - h) * 0.3, k + Vector((0, 0, 0.03)), k - Vector((0, 0, 0.04)),
            k + (a - k) * 0.4, a + Vector((0, 0, 0.03))]
    radii = [0.088, 0.08, 0.058, 0.055, 0.056, 0.038]
    if p["female"]:
        radii = [r * 0.94 for r in radii]
    rings_ = []
    for pt, r in zip(path, radii):
        rr = r + (baggy if pt.z > cut_z else 0.0)
        rings_.append(ring(pt.z, pt.x, pt.y, rr, rr, rr, n=2.0, count=12))
    loft(part, rings_, lambda c, n: upper_mat if c.z > cut_z else lower_mat)
    if cuff_mat:
        rings_c = [ring(cut_z + dz, path[0].x * 0 + h.x + (k.x - h.x) * 0, 0, r, r, r, n=2.0, count=12)
                   for dz, r in ((0.02, 0.062 + baggy), (-0.005, 0.064 + baggy))]
        loft(part, rings_c, cuff_mat, cap0=False, cap1=False)
    pre = "Left" if side > 0 else "Right"
    return part, [pre + "UpLeg", pre + "Leg", pre + "Foot", pre + "ToeBase", "Hips"]


def build_foot(part, p, side, skin_mat, shoe_mat, sole_mat, slipper):
    h, k, a = leg_points(p, side)
    x = a.x
    if slipper:
        # bare foot on a flat slipper with a V strap
        loft(part, [ring_x_foot(x, y, 0.02, hw, h_) for y, hw, h_ in
                    ((0.045, 0.028, 0.03), (0.02, 0.036, 0.05), (-0.05, 0.042, 0.04), (-0.13, 0.04, 0.025),
                     (-0.16, 0.025, 0.015))], skin_mat)
        rbox(part, (x, -0.055, 0.008), (0.1, 0.25, 0.016), sole_mat, bevel=0.007, segs=1)
        for s2 in (-1, 1):
            sweep(part, [(x + s2 * 0.04, -0.03, 0.02), (x + s2 * 0.02, -0.08, 0.045), (x, -0.115, 0.03)],
                  rrect(0.004, 0.008, n=6), shoe_mat)
    else:
        loft(part, [ring_x_foot(x, y, 0.0, hw, h_) for y, hw, h_ in
                    ((0.05, 0.03, 0.07), (0.03, 0.042, 0.095), (-0.04, 0.048, 0.07), (-0.13, 0.044, 0.05),
                     (-0.17, 0.028, 0.03))], shoe_mat)
        rbox(part, (x, -0.06, 0.008), (0.1, 0.24, 0.018), sole_mat, bevel=0.008, segs=1)


def ring_x_foot(x, y, z0, hw, h):
    """Foot cross-section across the foot (XZ plane) at depth y, bottom at z0."""
    pts = []
    for i in range(10):
        t = TAU * i / 10
        cs, sn = se(t, 2.6)
        pts.append(Vector((x + hw * cs, y, z0 + h / 2 + h / 2 * sn)))
    return pts


# --- head, face, hair -------------------------------------------------------------------

HEAD = [   # (dz from head center, half width, front depth, back depth, forward shift)
    (0.125, 0.004, 0.004, 0.004, 0.0), (0.112, 0.06, 0.055, 0.065, 0.0), (0.09, 0.094, 0.088, 0.1, 0.0),
    (0.05, 0.11, 0.104, 0.113, 0.0), (0.01, 0.111, 0.106, 0.11, 0.0), (-0.03, 0.104, 0.102, 0.1, 0.0),
    (-0.06, 0.094, 0.098, 0.086, -0.004), (-0.085, 0.078, 0.092, 0.066, -0.008), (-0.103, 0.058, 0.084, 0.046, -0.012),
    (-0.116, 0.034, 0.072, 0.026, -0.016), (-0.123, 0.012, 0.058, 0.01, -0.02), (-0.125, 0.002, 0.048, 0.002, -0.022),
]


def head_dims(dz):
    for a, b in zip(HEAD, HEAD[1:]):
        if b[0] <= dz <= a[0]:
            t = (a[0] - dz) / (a[0] - b[0])
            return [u + (v - u) * t for u, v in zip(a[1:], b[1:])]
    return list(HEAD[0][1:]) if dz > HEAD[0][0] else list(HEAD[-1][1:])


def build_head(p, skin_mat):
    part = Part("head")
    c = p["head_c"]
    rows = catmull([tuple(r) for r in HEAD], 2)
    loft(part, [ring(c.z + dz, 0, c.y + sh, w, f, b, n=2.15, count=32) for dz, w, f, b, sh in rows], "Face")
    for side in (-1, 1):   # ears
        e = c + Vector((side * 0.108, 0.005, -0.012))
        loft(part, [ring(e.z + dz, e.x, e.y, 0.012, r, r * 0.7, n=2.0, count=6) for dz, r in
                    ((0.025, 0.006), (0.012, 0.02), (-0.012, 0.018), (-0.03, 0.006))], skin_mat)
    # neck
    n0, n1 = p["neck"]
    loft(part, [ring(z, 0, c.y + 0.017, r, r, r, n=2.0, count=12) for z, r in ((n0, 0.056), (n1, 0.05), (n1 + 0.05, 0.046))],
         skin_mat)
    return part


def uv_head(obj, p):
    """Wrap the face texture around the head like a label: u = around (0.5 = front), v = top->chin."""
    c = p["head_c"]
    me = obj.data
    if not me.uv_layers:
        me.uv_layers.new(name="UVMap")
    uv = me.uv_layers[0].data
    top, bot = c.z + 0.125, c.z - 0.125
    for poly in me.polygons:
        mat = me.materials[poly.material_index].name if me.materials else ""
        us = []
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            us.append(math.atan2(co.x - c.x, -(co.y - c.y)) / TAU + 0.5)
        if max(us) - min(us) > 0.5:
            us = [u + 1.0 if u < 0.5 else u for u in us]
        for li, u in zip(poly.loop_indices, us):
            co = me.vertices[me.loops[li].vertex_index].co
            uv[li].uv = (u if mat == "Face" else 0.02, 1.0 - (top - co.z) / (top - bot))


def paint_face(name, skin_hex, hair_hex, female, blush=True):
    """Anime face, 512 x 256 (x = 256 is the middle of the face, y = 0 the top of the head).
    Rows: brows ~112, eyes ~118-146, nose ~165, mouth ~190, chin ~245."""
    W, H = 512, 256
    sh = skin_hex.lstrip("#")
    skin = np.array([int(sh[i:i + 2], 16) / 255.0 for i in (0, 2, 4)])
    img = np.ones((H, W, 4), dtype=np.float32)
    img[:, :, :3] = skin
    cx = W // 2

    def lin(h):   # (image pixels are stored as sRGB, so plain 0..1 values)
        h = h.lstrip("#")
        return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)])
    hair = lin(hair_hex)
    # soft shade toward the back and under the jaw
    xs = np.abs(np.arange(W) - cx) / cx
    img[:, :, :3] *= (1.0 - 0.12 * xs[None, :, None])
    img[226:, :, :3] *= 0.85
    # hair painted on the scalp (hair meshes sit on top)
    for x in range(W):
        f = 1.0 - abs(x - cx) / cx
        line = int(96 - 60 * f ** 1.4)   # low at the back, high at the forehead
        img[:max(line, 40) if f > 0.3 else 150, x, :3] = hair

    def ellipse(cx_, cy_, rx, ry, color, alpha=1.0):
        yy, xx = np.ogrid[:H, :W]
        m = ((xx - cx_) / rx) ** 2 + ((yy - cy_) / ry) ** 2 <= 1.0
        img[m, :3] = img[m, :3] * (1 - alpha) + color * alpha
        return m
    dark = lin("#1b1414")
    iris = lin("#4a2d1e")
    iris2 = lin("#8a5a3a")
    white = lin("#fbf8f2")
    for side in (-1, 1):
        ex = cx + side * 26
        ellipse(ex, 133, 10, 14, white)                     # eye white
        ellipse(ex, 135, 8, 12, iris)                       # iris
        ellipse(ex, 140, 6, 6, iris2)                       # lighter bottom
        ellipse(ex, 134, 4, 6, dark)                        # pupil
        ellipse(ex - side * 3, 129, 2.5, 3.5, white)        # big shine
        ellipse(ex + side * 3, 141, 1.2, 1.6, white)        # small shine
        # upper lash: thick dark arc, a flick at the outer corner (women: longer)
        for x in range(ex - 12, ex + 13):
            t = (x - ex) / 12.0
            y = int(122 + 4 * t * t)
            img[y:y + 4, x, :3] = dark
        for k in range(5 if female else 3):
            img[124 - k, ex + side * (12 + k), :3] = dark
        img[146:148, ex - 7:ex + 8, :3] = img[146:148, ex - 7:ex + 8, :3] * 0.7   # lower lid
        # brow
        for x in range(ex - 11, ex + 12):
            t = (x - ex) / 11.0
            y = int(110 - 4 * (1 - t * t) + (1 if side * t > 0.3 else 0))
            img[y:y + (2 if female else 3), x, :3] = hair * 0.85
    # nose: a soft shadow tick
    img[160:166, cx - 1:cx + 1, :3] *= 0.8
    img[166:168, cx - 2:cx + 3, :3] *= 0.75
    # mouth: small smile
    for x in range(cx - 9, cx + 10):
        t = (x - cx) / 9.0
        y = int(190 + 2.5 * (1 - t * t) - 2.5)
        img[y:y + 2, x, :3] = lin("#7a3a35")
    # blush
    if blush:
        for side in (-1, 1):
            ellipse(cx + side * 38, 166, 12, 6, lin("#e88a7a"), 0.35)
    image = bpy.data.images.new(name, W, H)
    image.pixels.foreach_set(np.flipud(img).ravel())
    image.pack()
    return image


def make_face_material(image):
    m = bpy.data.materials.new("Face")
    try:
        m.use_nodes = True
    except Exception:
        pass
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = image
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.8


def hair_shell(part, p, scale, front_z, back_z, mat, bumpy=0.0, steps=6):
    """A cap of hair over the skull, down to a hairline (dz) that is lower at the back."""
    c = p["head_c"]
    rings_ = []
    for k in range(steps):
        pts = []
        for i in range(24):
            t = TAU * i / 24
            cs, sn = se(t, 2.2)
            frontness = max(0.0, -sn)               # 1 at the front, 0 at the sides/back
            low = back_z + (front_z - back_z) * frontness ** 1.5
            dz = 0.128 + (low - 0.128) * (k / (steps - 1))
            w, f, b, sh = head_dims(dz)
            bump = 1.0 + bumpy * (0.5 + 0.5 * math.sin(t * 7 + k * 1.3))
            y = c.y + sh + (b if sn > 0 else f) * sn
            pts.append(Vector((w * cs * scale * bump, (y - c.y) * scale * bump + c.y, c.z + dz)))
        rings_.append(pts)
    loft(part, rings_, mat, cap0=True, cap1=False)


def on_head(p, angle, dz, s=1.05):
    """A point on the head surface. angle 0 = front, + toward the left (+X)."""
    c = p["head_c"]
    w, f, b, sh = head_dims(dz)
    x = math.sin(angle) * w * s
    y = c.y + sh + (-f if math.cos(angle) > 0 else b) * abs(math.cos(angle)) * s
    return Vector((x, y, c.z + dz))


# ---------------------------------------------------------------------------------------
# Skinning: every vertex follows its nearest allowed bones (smooth falloff)
# ---------------------------------------------------------------------------------------

def seg_dist(pnt, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (pnt - a).dot(ab) / max(ab.length_squared, 1e-9)))
    return (a + ab * t - pnt).length


def weight_object(obj, bones, allowed):
    me = obj.data
    groups = {name: obj.vertex_groups.new(name=name) for name in allowed}
    for v in me.vertices:
        ws = []
        for name in allowed:
            h, t, _ = bones[name]
            d = seg_dist(v.co, h, t)
            ws.append((1.0 / (d * d + 1e-4) ** 2, name))
        ws.sort(reverse=True)
        ws = ws[:3]
        total = sum(w for w, _ in ws)
        for w, name in ws:
            if w / total > 0.02:
                groups[name].add([v.index], w / total, "REPLACE")


def make_armature(bones):
    data = bpy.data.armatures.new("Armature")
    arm = bpy.data.objects.new("Armature", data)
    bpy.context.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    arm.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    for name, (h, t, parent) in bones.items():
        eb = data.edit_bones.new(name)
        eb.head, eb.tail = h, t
    for name, (h, t, parent) in bones.items():
        if parent:
            data.edit_bones[name].parent = data.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm


def finish(name, pieces, bones, p):
    """Build every Part, weight it, join into one skinned mesh, export."""
    objs = []
    for part, allowed in pieces:
        obj = part.build(sharp_deg=80.0)
        obj.data.uv_layers.new(name="UVMap")
        if part.name == "head":
            uv_head(obj, p)
        weight_object(obj, bones, allowed)
        objs.append(obj)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    body = objs[0]
    body.name = name
    body.data.name = name
    arm = make_armature(bones)
    body.parent = arm
    mod = body.modifiers.new("Armature", "ARMATURE")
    mod.object = arm
    tris = sum(len(pl.vertices) - 2 for pl in body.data.polygons)
    print("  %s: %d triangles" % (name, tris))
    os.makedirs(OUT_DIR, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT_DIR, name + ".blend"))
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT_DIR, name + ".glb"), export_format="GLB")


# ---------------------------------------------------------------------------------------
# NPC types
# ---------------------------------------------------------------------------------------

def vendor_head(p, female):
    """The vendor's head, face and headwear: (head Part, hair Part). Also used by
    triposr_to_npc.py to put a clean anime head on a TripoSR body."""
    c = p["head_c"]
    head = build_head(p, "Skin")
    hair = Part("hair")
    if female:
        hair_shell(hair, p, 1.05, 0.07, -0.07, "Hair")
        for a in (-0.35, 0.0, 0.35):   # bangs under the kerchief
            tuft(hair, on_head(p, a, 0.078, 1.0), (math.sin(a) * 0.3, -0.5, -0.85), 0.024, 0.045, "Hair", sides=6)
        for side in (-1, 1):           # side locks
            tuft(hair, on_head(p, side * 1.2, 0.035, 1.0), (side * 0.05, -0.1, -1.0), 0.013, 0.085, "Hair", sides=6)
        loft(hair, [ring(c.z + dz, 0, c.y + 0.11, r, r, r, n=2.0, count=10) for dz, r in
                    ((-0.0, 0.01), (-0.015, 0.045), (-0.05, 0.05), (-0.08, 0.03), (-0.09, 0.008))], "Hair")   # low bun
        # kerchief over the top and back, knot at the back
        hair_shell(hair, p, 1.1, 0.085, -0.03, "Cloth", steps=5)
        loft(hair, [ring(c.z - 0.02 + dz, 0, c.y + 0.125, r, r, r, n=2.0, count=8) for dz, r in
                    ((0.02, 0.008), (0.0, 0.025), (-0.025, 0.02), (-0.035, 0.006))], "Cloth")
        for side in (-1, 1):
            tuft(hair, (side * 0.015, c.y + 0.13, c.z - 0.03), (side * 0.3, 0.4, -1.0), 0.018, 0.08, "Cloth")
    else:
        hair_shell(hair, p, 1.06, 0.075, -0.05, "Hair", bumpy=0.03)
        for a in (-0.55, -0.27, 0.0, 0.27, 0.55):   # fringe falling over the forehead
            tuft(hair, on_head(p, a, 0.088, 1.0), (math.sin(a) * 0.3, -0.55, -0.85), 0.03, 0.05, "Hair", sides=6)
        for a in (0.4, 1.2, 2.0, 2.8, -0.4, -1.2, -2.0, -2.8):   # soft clumps lying back on the head
            tuft(hair, on_head(p, a, 0.098, 0.97), (math.sin(a) * 0.5, 0.6 - math.cos(a) * 0.2, 0.35), 0.034, 0.042, "Hair", sides=6)
        for a in (1.5, -1.5, 2.4, -2.4):
            tuft(hair, on_head(p, a, 0.035), (math.sin(a) * 0.4, 0.2, -1.0), 0.026, 0.035, "Hair", sides=6)
        # white headband with the knot tails at the back
        band = [on_head(p, TAU * i / 24, 0.065, 1.075) for i in range(25)]
        sweep(hair, band, rrect(0.006, 0.016, n=8), "Cloth", caps=False)
        for side in (-1, 1):
            tuft(hair, (side * 0.012, c.y + 0.118, c.z + 0.06), (side * 0.25, 0.5, -1.0), 0.014, 0.075, "Cloth")
    return head, hair


def vendor(female):
    """Street / food / market vendor: tee, long apron, towel on the shoulder (men) or a
    kerchief (women), headband, shorts or capri pants, slippers / flats."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    p = body_plan(female)
    if female:
        colors = {"Skin": "#d39b6e", "Hair": "#2a1f1a", "Shirt": "#e7a6a3", "Apron": "#6e4632", "ApronDark": "#58372a",
                  "Pants": "#3e3f45", "Shoe": "#4a3b34", "Sole": "#2c2622", "Cloth": "#d98c8a", "Tie": "#5a3a2b"}
    else:
        colors = {"Skin": "#c98d61", "Hair": "#1d1a19", "Shirt": "#4b5059", "Apron": "#6b4430", "ApronDark": "#55351f",
                  "Pants": "#7d6c55", "Shoe": "#2a2a2a", "Sole": "#3a3330", "Cloth": "#efe9dc", "Tie": "#5a3a2b"}
    make_mats(colors)
    make_face_material(paint_face("face", colors["Skin"], colors["Hair"], female))
    bones = bones_of(p)
    pieces = []
    pieces += build_torso(p, "Shirt", "Pants", 0.97 if female else 0.99)
    for side in (1, -1):
        pieces += build_arm(p, side, "Shirt", 0.12, "Skin")
        if female:
            leg, allowed = build_leg(p, side, "Pants", 0.24, "Skin", baggy=0.008)
            build_foot(leg, p, side, "Skin", "Shoe", "Sole", slipper=False)
        else:
            leg, allowed = build_leg(p, side, "Pants", p["knee_z"] - 0.02, "Skin", baggy=0.02)
            build_foot(leg, p, side, "Skin", "Shoe", "Sole", slipper=True)
        pieces.append((leg, allowed))

    # head, hair, headwear
    head, hair = vendor_head(p, female)
    pieces.append((head, ["Head", "neck"]))
    pieces.append((hair, ["Head"]))

    # Apron: bib + long skirt panel laid over the front, neck strap and waist ties
    front = torso_surface(p)
    apron = Part("apron")
    bib_top = p["torso"][-2][0] - 0.06
    waist = p["torso"][2][0]
    hem = 0.42 if female else 0.5
    rows = []
    for z in [bib_top - (bib_top - hem) * i / 9 for i in range(10)]:
        if z > waist:
            w = 0.1 if female else 0.11
        else:
            w = 0.2 if z > 0.86 else 0.21 + (0.86 - z) * 0.05
        row = []
        for j in range(7):
            x = -w + 2 * w * j / 6
            if z > 0.86:
                y = front(x, z) - 0.012
            else:
                y = -0.12 + 0.05 * (x / w) ** 2     # hangs in front of the legs
            row.append(Vector((x, y, z)))
        rows.append(row)
    panel(apron, rows, 0.006, "Apron")
    rbox(apron, (0.06, -0.15, 0.78 if not female else 0.74), (0.12, 0.006, 0.1), "ApronDark", bevel=0.004, segs=1)
    rbox(apron, (-0.06, -0.15, 0.78 if not female else 0.74), (0.12, 0.006, 0.1), "ApronDark", bevel=0.004, segs=1)
    nz = p["neck"][0]
    strap = [(-0.08, front(-0.08, bib_top) - 0.012, bib_top), (-0.07, -0.04, nz + 0.01), (0.0, 0.06, nz + 0.02),
             (0.07, -0.04, nz + 0.01), (0.08, front(0.08, bib_top) - 0.012, bib_top)]
    sweep(apron, catmull([tuple(s) for s in strap], 3), rrect(0.004, 0.01, n=6), "Tie")
    secs = p["torso"]
    wz = waist
    ww, wf, wb = secs[2][1] + 0.008, secs[2][2] + 0.008, secs[2][3] + 0.008
    tie = []
    for i in range(13):
        t = math.radians(-90 + 180 * i / 12)   # from the left side, around the back, to the right
        tie.append(Vector((math.sin(t) * ww, math.cos(t) * wb, wz)))
    sweep(apron, tie, rrect(0.004, 0.012, n=6), "Tie", caps=False)
    for side in (-1, 1):
        tuft(apron, (side * 0.02, wb, wz), (side * 0.4, 0.3, -1.0), 0.012, 0.12, "Tie")
    pieces.append((apron, ["Hips", "Spine02", "Spine01", "Spine"]))

    if not female:
        # towel over the left shoulder, hanging in front and behind
        towel = Part("towel")
        sx = 0.11
        path = [(sx, front(sx, 1.12) - 0.02, 1.12), (sx, front(sx, 1.3) - 0.025, 1.3), (sx + 0.005, -0.06, p["torso"][-2][0] + 0.035),
                (sx + 0.005, 0.04, p["torso"][-2][0] + 0.04), (sx, 0.115, 1.3), (sx, 0.12, 1.1)]
        sweep(towel, catmull(path, 3), rrect(0.009, 0.06, n=10), "Cloth")
        pieces.append((towel, ["Spine01", "Spine", "LeftShoulder"]))

    finish("vendor_" + ("f" if female else "m"), pieces, bones, p)


TYPES = {"vendor": vendor}


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else ["vendor"]
    for t in args:
        print("NPC:", t)
        for female in (False, True):
            TYPES[t](female)


if __name__ == "__main__":
    main()
