"""All street NPCs, built entirely in code (original, no AI models): clean stylized low-poly
people with solid colors, crisp edges, simple faces and one skinned mesh on the same bone names
as the game's rider, so every animation and the ragdoll work.

    blender -b -P tools/blender/make_people.py                 (all 20)
    blender -b -P tools/blender/make_people.py -- vendor_m     (just some)

Output: assets/characters/npc/<type>_<m|f>.glb
Types and outfits follow the NPC sheet: see LOOKS below to change colors or accessories.
Conventions: Blender Z up, faces -Y, feet on z = 0, arms in an A-pose.
"""
import bpy
import bmesh
import math
import os
import sys

import numpy as np
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from shapes import Part, loft, sweep, catmull, rrect, circle, rbox, tube, se, srgb_to_linear, TAU   # noqa: E402
from make_npc import make_armature, seg_dist, OUT_DIR   # noqa: E402

ARM_OUT = math.radians(34.0)   # A-pose: arms this far from hanging straight down


# =======================================================================================
# Who everyone is
# =======================================================================================

SKIN = ["#c68b5e", "#b97d4f", "#d29a6c", "#a96f45"]
BLACK, BROWN, GREY = "#1f1b19", "#3a2a1f", "#8f8c89"

# keys: top, top2 (trim), sleeve ("short"|"long"|"none"), bottom, legwear ("pants"|"shorts"|
# "skirt"|"capri"), shoes, shoe, sole, hair (style), haircol, skin, hat, hatcol, extras [...]
LOOKS = {
    "vendor_m": dict(top="#4a4f58", sleeve="short", bottom="#77664f", legwear="shorts", shoes="slippers", shoe="#34302c",
                     hair="short", skin=0, hat="headband", hatcol="#f1ece0", extras=["apron", "towel"], accent="#6e4630"),
    "vendor_f": dict(top="#dc9795", sleeve="short", bottom="#45464d", legwear="capri", shoes="flats", shoe="#4b3a33",
                     hair="bun", skin=2, hat="kerchief", hatcol="#c97f80", extras=["apron"], accent="#6e4630"),
    "enforcer_m": dict(top="#9db4d6", sleeve="short", bottom="#2c3450", legwear="pants", shoes="boots", shoe="#1c1c1f",
                       hair="short", skin=1, hat="cap", hatcol="#2c3450", extras=["collar", "tie", "belt", "pouches", "badge"], accent="#2c3450"),
    "enforcer_f": dict(top="#9db4d6", sleeve="short", bottom="#2c3450", legwear="pants", shoes="boots", shoe="#1c1c1f",
                       hair="ponytail", skin=0, hat="cap", hatcol="#2c3450", extras=["collar", "vest", "belt", "pouches", "badge"], accent="#2f3036"),
    "customer_m": dict(top="#ece6da", sleeve="short", bottom="#3b3c41", legwear="shorts", shoes="sneakers", shoe="#e9e6df",
                       hair="side", skin=2, extras=["backpack"], accent="#34353b"),
    "customer_f": dict(top="#e8ddcc", sleeve="short", bottom="#55759c", legwear="pants", shoes="sneakers", shoe="#ece9e2",
                       hair="bun", skin=1, extras=["tote", "belt"], accent="#9a6b43"),
    "pedestrian_m": dict(top="#45464e", sleeve="long", bottom="#34343a", legwear="pants", shoes="sneakers", shoe="#d9d6d0",
                         hair="short", skin=0, hat="cap_back", hatcol="#363c52", extras=["hood", "headphones", "pocket", "cargo"], accent="#d8d2c8"),
    "pedestrian_f": dict(top="#c7a582", sleeve="long", bottom="#4a6488", legwear="shorts", shoes="sneakers", shoe="#cfccc6",
                         hair="long", haircol=BROWN, skin=2, hat="cap", hatcol="#c9a47c", extras=["hood", "pocket", "backpack", "socks"], accent="#3b3b42"),
    "fellow_rider_m": dict(top="#4c683c", sleeve="long", bottom="#36373d", legwear="pants", shoes="sneakers", shoe="#e1ded7",
                           hair="messy", skin=1, extras=["hood", "stripe", "flag", "backpack", "gloves", "cargo"], accent="#3d5031"),
    "fellow_rider_f": dict(top="#4c683c", sleeve="long", bottom="#36373d", legwear="pants", shoes="sneakers", shoe="#e1ded7",
                           hair="ponytail", skin=0, extras=["hood", "stripe", "flag", "backpack", "gloves", "cargo"], accent="#3d5031"),
    "office_worker_m": dict(top="#c9c0d6", sleeve="short", bottom="#4a4c55", legwear="pants", shoes="leather", shoe="#2a2422",
                            hair="side", skin=2, extras=["collar", "lanyard", "belt", "glasses", "sling"], accent="#2f2b2a"),
    "office_worker_f": dict(top="#ece8e2", sleeve="short", bottom="#4b4747", legwear="pants", shoes="flats", shoe="#2a2422",
                            hair="ponytail", skin=1, extras=["collar", "lanyard", "belt", "glasses", "sling"], accent="#3a302c"),
    "student_m": dict(top="#f2f0ea", sleeve="short", bottom="#2b2d36", legwear="shorts", shoes="leather", shoe="#222225",
                      hair="side", skin=0, extras=["collar", "lanyard", "backpack", "socks"], accent="#2d3a5a"),
    "student_f": dict(top="#f2f0ea", sleeve="short", bottom="#35405e", legwear="skirt", shoes="leather", shoe="#3a2a24",
                      hair="long", skin=2, extras=["collar", "ribbon", "lanyard", "backpack", "socks"], accent="#7a5138"),
    "technician_m": dict(top="#454c5c", sleeve="short", bottom="#454c5c", legwear="pants", shoes="boots", shoe="#222124",
                         hair="short", skin=3, hat="cap_back", hatcol="#363c4c", extras=["collar", "belt", "pocket_chest", "cargo", "gloves"], accent="#2e3340"),
    "technician_f": dict(top="#454c5c", sleeve="short", bottom="#454c5c", legwear="pants", shoes="boots", shoe="#222124",
                         hair="ponytail", skin=1, hat="cap", hatcol="#363c4c", extras=["collar", "belt", "stripe", "cargo", "gloves"], accent="#2e3340"),
    "delivery_m": dict(top="#e07a2c", sleeve="long", bottom="#3a3b40", legwear="pants", shoes="sneakers", shoe="#d8d5ce",
                       hair="short", skin=1, hat="cap", hatcol="#2c3450", extras=["hood", "stripe", "flag", "sling", "cargo", "gloves"], accent="#33343a"),
    "delivery_f": dict(top="#d9776c", sleeve="long", bottom="#35363c", legwear="shorts", shoes="sneakers", shoe="#e6e3dc",
                       hair="ponytail", skin=2, hat="cap", hatcol="#c76a62", extras=["hood", "delivery_box", "socks"], accent="#8c3f55"),
    "misc_m": dict(top="#ede3cf", sleeve="none", bottom="#6d5c4a", legwear="shorts", shoes="slippers", shoe="#4a352a",
                   hair="short", haircol=GREY, skin=3, hat="straw", hatcol="#cda865", extras=["towel", "mustache"], accent="#7d6a55"),
    "misc_f": dict(top="#cf827d", sleeve="short", bottom="#4c4d55", legwear="skirt_long", shoes="slippers", shoe="#6a4634",
                   hair="bun", haircol=GREY, skin=1, extras=["sling", "elder"], accent="#6a4a38"),
}


# =======================================================================================
# Skeleton plan
# =======================================================================================

def plan(female, elder):
    p = {"female": female}
    if female:
        # torso sections: (z, half width, front depth, back depth)
        p["torso"] = [(0.86, 0.152, 0.094, 0.112), (0.93, 0.165, 0.098, 0.116), (1.00, 0.132, 0.084, 0.092),
                      (1.07, 0.122, 0.082, 0.088), (1.17, 0.136, 0.112, 0.092), (1.25, 0.146, 0.108, 0.092),
                      (1.31, 0.152, 0.088, 0.088), (1.355, 0.128, 0.070, 0.074), (1.385, 0.060, 0.046, 0.048)]
        p.update(shoulder_w=0.152, shoulder_z=1.318, upper=0.245, fore=0.215, hip_w=0.082, hip_z=0.90, knee_z=0.485,
                 head_z=1.545, arm_r=0.049, leg_r=0.08)
    else:
        p["torso"] = [(0.88, 0.146, 0.098, 0.108), (0.96, 0.154, 0.098, 0.108), (1.03, 0.144, 0.096, 0.098),
                      (1.13, 0.156, 0.104, 0.100), (1.25, 0.180, 0.114, 0.106), (1.35, 0.192, 0.106, 0.102),
                      (1.41, 0.168, 0.086, 0.088), (1.45, 0.070, 0.052, 0.052)]
        p.update(shoulder_w=0.186, shoulder_z=1.375, upper=0.270, fore=0.240, hip_w=0.090, hip_z=0.93, knee_z=0.505,
                 head_z=1.615, arm_r=0.061, leg_r=0.09)
    if elder:
        p["torso"] = [(z, w * 1.08, f * 1.1, b * 1.06) for z, w, f, b in p["torso"]]
        p["arm_r"] *= 1.08
    p["ankle_z"] = 0.085
    return p


def arm_pts(p, side):
    s = Vector((side * p["shoulder_w"], 0.004, p["shoulder_z"]))
    d = Vector((side * math.sin(ARM_OUT), 0.0, -math.cos(ARM_OUT)))
    e = s + d * p["upper"]
    w = e + d * p["fore"]
    return s, e, w, d


def leg_pts(p, side):
    h = Vector((side * p["hip_w"], 0.0, p["hip_z"]))
    k = Vector((side * (p["hip_w"] + 0.008), -0.006, p["knee_z"]))
    a = Vector((side * (p["hip_w"] + 0.014), 0.006, p["ankle_z"]))
    return h, k, a


def bones_of(p):
    hips, top = p["torso"][1][0], p["torso"][-1][0]
    mid = (hips + top) / 2
    b = {
        "Hips": (Vector((0, 0, hips)), Vector((0, 0, hips + 0.08)), None),
        "Spine02": (Vector((0, 0, hips + 0.08)), Vector((0, 0, mid)), "Hips"),
        "Spine01": (Vector((0, 0, mid)), Vector((0, 0, mid + 0.1)), "Spine02"),
        "Spine": (Vector((0, 0, mid + 0.1)), Vector((0, 0, top - 0.03)), "Spine01"),
        "neck": (Vector((0, 0, top - 0.03)), Vector((0, 0, top + 0.055)), "Spine"),
        "Head": (Vector((0, 0, top + 0.055)), Vector((0, 0, top + 0.3)), "neck"),
    }
    for side, pre in ((1, "Left"), (-1, "Right")):
        s, e, w, d = arm_pts(p, side)
        h, k, a = leg_pts(p, side)
        toe = Vector((a.x, -0.11, 0.025))
        b[pre + "Shoulder"] = (Vector((side * 0.03, 0, s.z)), s, "Spine")
        b[pre + "Arm"] = (s, e, pre + "Shoulder")
        b[pre + "ForeArm"] = (e, w, pre + "Arm")
        b[pre + "Hand"] = (w, w + d * 0.09, pre + "ForeArm")
        b[pre + "UpLeg"] = (h, k, "Hips")
        b[pre + "Leg"] = (k, a, pre + "UpLeg")
        b[pre + "Foot"] = (a, toe, pre + "Leg")
        b[pre + "ToeBase"] = (toe, toe + Vector((0, -0.05, 0)), pre + "Foot")
    return b


# =======================================================================================
# Shape helpers
# =======================================================================================

def ring(c, u, v, ru, rv_front, rv_back, count, n=2.2):
    """Cross-section around center c in the plane (u, v). v points to the front."""
    pts = []
    for i in range(count):
        cs, sn = se(TAU * i / count, n)
        pts.append(c + u * (ru * cs) + v * ((rv_front if sn > 0 else rv_back) * sn))
    return pts


def hring(z, cx, cy, w, front, back, count=16, n=2.4):
    return ring(Vector((cx, cy, z)), Vector((1, 0, 0)), Vector((0, -1, 0)), w, front, back, count, n)


def limb_rings(path, radii, count=10, depth=1.0):
    """Rings along a polyline, each perpendicular to it."""
    out = []
    for i, (pt, r) in enumerate(zip(path, radii)):
        d = (path[min(i + 1, len(path) - 1)] - path[max(i - 1, 0)]).normalized()
        u = d.cross(Vector((0, -1, 0))).normalized()
        v = u.cross(d).normalized()
        if v.y > 0:
            v = -v
        out.append(ring(pt, u, v, r, r * depth, r * depth, count, 2.2))
    return out


def blob(part, center, rx, ry, rz, mat, rows=5, count=10):
    """A rounded lump (hair bun, nose, knot)."""
    c = Vector(center)
    rings_ = []
    for i in range(rows + 1):
        t = math.pi * (i + 0.35) / (rows + 0.7)
        rings_.append(hring(c.z + rz * math.cos(t), c.x, c.y, rx * math.sin(t), ry * math.sin(t), ry * math.sin(t), count, 2.0))
    loft(part, rings_, mat)


def front_y(p, x, z):
    """The torso's front surface (y) at (x, z), for laying things on the chest."""
    secs = p["torso"]
    z = max(secs[0][0], min(secs[-1][0], z))
    for (z0, w0, f0, _b0), (z1, w1, f1, _b1) in zip(secs, secs[1:]):
        if z0 <= z <= z1:
            t = (z - z0) / (z1 - z0)
            w, f = w0 + (w1 - w0) * t, f0 + (f1 - f0) * t
            c = min(abs(x) / w, 0.99)
            return -f * (1 - c ** 2.4) ** (1 / 2.4)
    return -secs[0][2]


def back_y(p, z):
    secs = p["torso"]
    z = max(secs[0][0], min(secs[-1][0], z))
    for (z0, _w0, _f0, b0), (z1, _w1, _f1, b1) in zip(secs, secs[1:]):
        if z0 <= z <= z1:
            return b0 + (b1 - b0) * (z - z0) / (z1 - z0)
    return secs[0][3]


def chest_strip(part, p, points, width, mat, lift=0.007):
    """A flat strap/patch lying on the chest through (x, z) points."""
    path = [Vector((x, front_y(p, x, z) - lift, z)) for x, z in points]
    sweep(part, path, rrect(0.004, width / 2, n=8), mat, up=Vector((0, -1, 0)))


def torso_band(part, p, z, height, mat, grow=0.006):
    """A ring around the body (belt, stripe, hem)."""
    def at(zz):
        for (z0, w0, f0, b0), (z1, w1, f1, b1) in zip(p["torso"], p["torso"][1:]):
            if z0 <= zz <= z1:
                t = (zz - z0) / (z1 - z0)
                return w0 + (w1 - w0) * t, f0 + (f1 - f0) * t, b0 + (b1 - b0) * t
        return p["torso"][0][1:]
    rows = []
    for zz in (z - height / 2, z + height / 2):
        w, f, b = at(zz)
        rows.append(hring(zz, 0, 0, w + grow, f + grow, b + grow, 20))
    loft(part, rows, mat, cap0=False, cap1=False)


# =======================================================================================
# Body
# =======================================================================================

def torso(p, look):
    part = Part("torso")
    skirt = look["legwear"].startswith("skirt")
    split = p["torso"][1][0] + 0.02   # where the top ends and the bottoms begin
    rows = catmull(p["torso"], 2)
    loft(part, [hring(z, 0, 0, w, f, b, 20) for z, w, f, b in rows],
         lambda c, n: "Bottom" if c.z < split else "Top")
    torso_band(part, p, split, 0.03, "Top2" if not skirt else "Bottom")   # shirt hem
    # neckline
    top = p["torso"][-1][0]
    loft(part, [hring(top - 0.008, 0, 0, 0.066, 0.058, 0.056, 16, 2.0), hring(top + 0.012, 0, 0, 0.056, 0.049, 0.048, 16, 2.0)],
         "Top2", cap0=False, cap1=False)
    return part, ["Hips", "Spine02", "Spine01", "Spine", "neck", "LeftShoulder", "RightShoulder", "LeftArm", "RightArm"]


def arm(p, look, side):
    part = Part("arm")
    s, e, w, d = arm_pts(p, side)
    r = p["arm_r"]
    long_sleeve = look["sleeve"] == "long"
    path = [s - d * 0.035 - Vector((side * 0.02, 0, 0)), s + d * 0.02, s + d * p["upper"] * 0.55, e - d * 0.03, e,
            e + d * 0.045, e + d * p["fore"] * 0.6, w]
    radii = [r * 0.9, r * 1.06, r * 0.92, r * 0.78, r * 0.76, r * 0.8, r * 0.68, r * 0.52]
    if long_sleeve:
        radii = [r * 1.05, r * 1.22, r * 1.1, r * 0.98, r * 0.98, r * 1.0, r * 0.9, r * 0.66]
    loft(part, limb_rings(path, radii, 12), "Top" if long_sleeve else "Skin")
    if long_sleeve:   # cuff
        loft(part, limb_rings([w - d * 0.035, w - d * 0.002], [r * 0.82, r * 0.78], 12), "Top2")
    elif look["sleeve"] == "short":
        sp = [s - d * 0.03 - Vector((side * 0.018, 0, 0)), s + d * 0.025, s + d * 0.075, s + d * 0.135]
        loft(part, limb_rings(sp, [r * 1.0, r * 1.22, r * 1.12, r * 1.1], 12), "Top", cap1=False)
        loft(part, limb_rings([s + d * 0.128, s + d * 0.146], [r * 1.13, r * 1.12], 12), "Top2", cap0=False, cap1=False)
    # hand: palm + fingers block + thumb
    hand_mat = "Glove" if "gloves" in look["extras"] else "Skin"
    hs = 0.9 if p["female"] else 1.0
    u = d.cross(Vector((0, 1, 0))).normalized()
    v = Vector((0, 1, 0))
    palm = [w - d * 0.006, w + d * 0.03, w + d * 0.058]
    loft(part, [ring(c, u, v, t * hs, wd * hs, wd * hs, 10, 2.6) for c, t, wd in
                zip(palm, (0.018, 0.021, 0.019), (0.026, 0.036, 0.036))], hand_mat)
    tips = [w + d * 0.056, w + d * 0.085, w + d * 0.098]
    loft(part, [ring(c, u, v, t * hs, wd * hs, wd * hs, 10, 2.8) for c, t, wd in
                zip(tips, (0.018, 0.015, 0.009), (0.034, 0.031, 0.022))], "Skin")
    tube(part, w + d * 0.012 + Vector((0, -0.026, 0)), w + d * 0.052 + Vector((0, -0.045, 0)), 0.012 * hs, hand_mat, sides=8)
    pre = "Left" if side > 0 else "Right"
    return part, [pre + "Shoulder", pre + "Arm", pre + "ForeArm", pre + "Hand"]


def leg(p, look, side):
    part = Part("leg")
    h, k, a = leg_pts(p, side)
    r = p["leg_r"]
    wear = look["legwear"]
    cut = {"pants": 0.10, "capri": 0.24, "shorts": p["knee_z"] - 0.015}.get(wear, p["knee_z"] + 0.12)
    loose = 1.13 if wear == "pants" and not p["female"] else 1.0
    path = [h + Vector((0, 0, 0.055)), h - Vector((0, 0, 0.02)), h.lerp(k, 0.45), k + Vector((0, 0, 0.045)), k,
            k - Vector((0, 0, 0.055)), k.lerp(a, 0.45), a + Vector((0, 0, 0.06)), a]
    radii = [r * 0.92, r * 1.0, r * 0.86, r * 0.68, r * 0.66, r * 0.68, r * 0.64, r * 0.46, r * 0.44]
    if wear == "pants":
        radii = [r * 0.96, r * 1.05, r * 0.94 * loose, r * 0.8 * loose, r * 0.78 * loose, r * 0.78 * loose,
                 r * 0.74 * loose, r * 0.68 * loose, r * 0.66 * loose]
    sock_top = 0.2 if "socks" in look["extras"] else 0.0

    def mat(c, n):
        if c.z > cut and not wear.startswith("skirt"):
            return "Bottom"
        return "Sock" if c.z < sock_top else "Skin"
    loft(part, limb_rings(path, radii, 12), mat)
    if wear in ("shorts", "capri"):   # open hem
        loft(part, limb_rings([Vector((k.x, k.y, cut + 0.07)), Vector((k.x, k.y, cut))], [r * 0.86, r * 0.84], 12), "Bottom", cap0=False, cap1=False)
    if wear == "pants":
        loft(part, limb_rings([a + Vector((0, 0, 0.05)), a + Vector((0, 0, 0.012))], [r * 0.72 * loose, r * 0.7 * loose], 12), "Bottom")
    if "cargo" in look["extras"]:
        rbox(part, (h.x + side * r * 0.95, -0.005, k.z + 0.13), (0.035, 0.105, 0.13), "Bottom", bevel=0.012, segs=1)
        rbox(part, (h.x + side * (r * 0.95 + 0.019), -0.005, k.z + 0.185), (0.008, 0.11, 0.026), "Top2" if wear != "pants" else "BottomDark", bevel=0.003, segs=1)
    pre = "Left" if side > 0 else "Right"
    return part, [pre + "UpLeg", pre + "Leg", pre + "Foot", "Hips"]


def foot_ring(x, y, z0, w, h, count=14):
    pts = []
    for i in range(count):
        cs, sn = se(TAU * i / count, 2.8)
        pts.append(Vector((x + w * cs, y, z0 + h / 2 + h / 2 * sn)))
    return pts


def foot(p, look, side):
    part = Part("foot")
    _h, _k, a = leg_pts(p, side)
    x = a.x
    s = 0.92 if p["female"] else 1.0
    kind = look["shoes"]

    def shape(profile, z0, mat):
        loft(part, [foot_ring(x, y * s, z0, w * s, h * s) for y, w, h in profile], mat)
    if kind == "slippers":
        shape([(0.062, 0.032, 0.02), (0.03, 0.05, 0.022), (-0.06, 0.056, 0.022), (-0.14, 0.05, 0.022), (-0.165, 0.03, 0.018)], 0.0, "Shoe")
        shape([(0.05, 0.028, 0.05), (0.02, 0.038, 0.07), (-0.05, 0.044, 0.045), (-0.12, 0.044, 0.03), (-0.152, 0.03, 0.018)], 0.02, "Skin")
        for s2 in (-1, 1):
            sweep(part, [Vector((x + s2 * 0.05, -0.03, 0.028)), Vector((x + s2 * 0.028, -0.075, 0.062)), Vector((x, -0.112, 0.045))],
                  rrect(0.005, 0.01, n=6), "Strap")
    else:
        high = 0.125 if kind == "boots" else (0.095 if kind == "sneakers" else 0.07)
        shape([(0.062, 0.036, 0.03), (0.032, 0.054, 0.032), (-0.07, 0.058, 0.032), (-0.155, 0.052, 0.032), (-0.178, 0.03, 0.026)], 0.0, "Sole")
        shape([(0.056, 0.034, high * 0.8), (0.025, 0.048, high), (-0.04, 0.052, high * 0.82), (-0.105, 0.05, 0.052), (-0.162, 0.042, 0.032), (-0.176, 0.02, 0.018)], 0.028, "Shoe")
        if kind == "sneakers":
            for i in range(3):
                rbox(part, (x, -0.045 - i * 0.022, 0.028 + high * 0.8 - i * 0.012), (0.045 * s, 0.008, 0.006), "Sole", bevel=0.002, segs=1)
    pre = "Left" if side > 0 else "Right"
    return part, [pre + "Foot", pre + "ToeBase"]


def skirt(p, look):
    part = Part("skirt")
    hips = p["torso"][1]
    long_one = look["legwear"] == "skirt_long"
    low = 0.24 if long_one else p["knee_z"] + 0.03
    pleats = not long_one
    rows = []
    for i in range(7):
        t = i / 6
        z = hips[0] + 0.04 - (hips[0] + 0.04 - low) * t
        w = hips[1] + 0.012 + 0.06 * t
        d = hips[2] + 0.016 + 0.045 * t
        pts = []
        for j in range(28):
            cs, sn = se(TAU * j / 28, 2.2)
            k = 1.0 + (0.07 * t if pleats and j % 2 == 0 else 0.0)
            pts.append(Vector((w * cs * k, (-d if sn > 0 else d * 1.12) * abs(sn) * k, z)))
        rows.append(pts)
    loft(part, rows, "Bottom", cap0=False, cap1=False, smooth=not pleats)
    return part, "skirt"


# =======================================================================================
# Head, face, hair, hats
# =======================================================================================

HEAD = [  # (height from center, half width, front depth, back depth, forward shift)
    (0.128, 0.004, 0.004, 0.004, 0.0), (0.115, 0.062, 0.058, 0.066, 0.0), (0.088, 0.096, 0.09, 0.102, 0.0),
    (0.045, 0.11, 0.104, 0.114, 0.0), (0.0, 0.11, 0.106, 0.11, 0.0), (-0.04, 0.103, 0.102, 0.098, 0.0),
    (-0.072, 0.088, 0.096, 0.078, -0.004), (-0.098, 0.064, 0.086, 0.052, -0.01), (-0.115, 0.036, 0.07, 0.028, -0.015),
    (-0.123, 0.008, 0.05, 0.008, -0.02)]


def head_dims(dz):
    if dz >= HEAD[0][0]:
        return HEAD[0][1:]
    for a, b in zip(HEAD, HEAD[1:]):
        if b[0] <= dz <= a[0]:
            t = (a[0] - dz) / (a[0] - b[0])
            return [u + (v - u) * t for u, v in zip(a[1:], b[1:])]
    return HEAD[-1][1:]


def on_head(c, angle, dz, s=1.0):
    """Point on the head: angle 0 = the front, positive toward +X."""
    w, f, b, sh = head_dims(dz)
    co = math.cos(angle)
    return Vector((math.sin(angle) * w * s, c.y + sh - (f if co > 0 else b) * co * s, c.z + dz))


def head(p, look):
    part = Part("head")
    c = Vector((0, -0.008, p["head_z"]))
    rows = catmull(HEAD[1:], 2)   # (no sharp point on the crown)
    loft(part, [hring(c.z + dz, 0, c.y + sh, w, f, b, 24, 2.15) for dz, w, f, b, sh in rows], "Skin")
    top = p["torso"][-1][0]
    loft(part, [hring(z, 0, 0.004, r, r, r, 14, 2.0) for z, r in ((top - 0.03, 0.052), (top + 0.03, 0.045), (c.z - 0.075, 0.044))], "Skin")
    for side in (-1, 1):   # ears
        blob(part, (side * 0.108, c.y + 0.012, c.z - 0.012), 0.012, 0.022, 0.03, "Skin", rows=4, count=8)
    # nose
    tip = on_head(c, 0.0, -0.032, 1.0) + Vector((0, -0.001, 0))
    blob(part, tip, 0.0095, 0.009, 0.014, "Skin", rows=4, count=8)

    def surf(x, dz, lift):
        w, f, _b, sh = head_dims(dz)
        ratio = min(abs(x) / w, 0.99)
        return Vector((x, c.y + sh - f * (1 - ratio ** 2.15) ** (1 / 2.15) - lift, c.z + dz))

    def decal(cx, cz, rx, rz, mat, lift, count=12, tilt=0.0):
        mid = part.v(surf(cx, cz, lift + 0.0006))
        pts = []
        for i in range(count):
            a = TAU * i / count
            x = cx + math.cos(a) * rx
            pts.append(part.v(surf(x, cz + math.sin(a) * rz + tilt * (x - cx), lift)))
        for i in range(count):
            part.f((mid, pts[i], pts[(i + 1) % count]), mat)
    female = p["female"]
    for side in (-1, 1):
        ex = side * 0.037
        decal(ex, 0.004, 0.0155, 0.0135 if female else 0.012, "EyeWhite", 0.0022)
        decal(ex - side * 0.001, 0.003, 0.0095, 0.0112, "Eye", 0.0034)
        decal(ex - side * 0.004, 0.008, 0.003, 0.003, "EyeWhite", 0.0046, 8)
        decal(ex, 0.0168 if female else 0.0152, 0.018, 0.0022, "Line", 0.0045, tilt=side * 0.02)   # upper lid
        # brows: soft arch, relaxed (inner end a touch higher than the outer)
        sweep(part, [surf(ex - side * 0.017, 0.0355, 0.003), surf(ex, 0.0405, 0.0034), surf(ex + side * 0.018, 0.035, 0.003)],
              rrect(0.0016, 0.0022 if female else 0.0032, n=8), "Brow", scales=[0.8, 1.0, 0.45], up=Vector((0, -1, 0)))
        decal(side * 0.058, -0.03, 0.014, 0.008, "Blush", 0.0016)
    # a small friendly smile: short pieces rising toward the corners
    smile = [surf(k * 0.0068, -0.064 + (k * k) * 0.00085, 0.0028) for k in range(-3, 4)]
    sweep(part, smile, rrect(0.0014, 0.0028 if female else 0.0022, n=8), "Lip" if female else "Mouth",
          scales=[0.35, 0.8, 1.0, 1.1, 1.0, 0.8, 0.35], up=Vector((0, -1, 0)))
    if "mustache" in look["extras"]:
        decal(0.0, -0.05, 0.03, 0.007, "Hair", 0.004)
    if "elder" in look["extras"]:
        for side in (-1, 1):
            decal(side * 0.045, -0.045, 0.0025, 0.016, "Line", 0.002, 8, tilt=0)
    if "glasses" in look["extras"]:
        for side in (-1, 1):
            centre = surf(side * 0.039, 0.004, 0.012)
            rim = [centre + Vector((math.cos(TAU * i / 16) * 0.027, 0.004 * abs(math.cos(TAU * i / 16)), math.sin(TAU * i / 16) * 0.02))
                   for i in range(17)]
            sweep(part, rim, circle(0.0026, 6), "Frame", caps=False, up=Vector((0, -1, 0)))
            tube(part, centre + Vector((side * 0.026, 0.006, 0.004)), (side * 0.112, c.y + 0.01, c.z - 0.002), 0.0024, "Frame", sides=6)
        tube(part, surf(-0.013, 0.008, 0.014), surf(0.013, 0.008, 0.014), 0.0024, "Frame", sides=6)
    return part, ["Head", "neck"], c


def shell(part, c, mat, front, back, scale=1.075, count=28, rows=10, swoop=0.0):
    scale += 0.025
    """A solid cap of hair/cloth over the skull down to a hairline."""
    rings_ = []
    for k in range(rows):
        pts = []
        for i in range(count):
            a = TAU * i / count - math.pi
            frontness = max(0.0, math.cos(a))
            low = back + (front - back) * frontness ** 1.4 + swoop * math.sin(a) * frontness
            dz = 0.14 + (low - 0.14) * (k / (rows - 1))
            w, f, b, sh = head_dims(min(dz, 0.122))
            grow = scale if k > 0 else 0.25
            co = math.cos(a)
            pts.append(Vector((math.sin(a) * w * grow, c.y + sh - (f if co > 0 else b) * co * grow, c.z + dz + 0.006)))
        rings_.append(pts)
    loft(part, rings_, mat, cap0=True, cap1=False)


def hair(p, look, c):
    part = Part("hair")
    style = look["hair"]
    hat = look.get("hat", "")
    covered = hat in ("cap", "cap_back", "straw", "kerchief")
    if style == "short":
        shell(part, c, "Hair", 0.072, -0.045, 1.07)
    elif style == "side":
        shell(part, c, "Hair", 0.07, -0.05, 1.09, swoop=0.026)
        if not covered:
            for i, (a, dz, r) in enumerate(((-0.55, 0.098, 0.042), (-0.1, 0.108, 0.046), (0.4, 0.103, 0.04))):
                at = on_head(c, a, dz, 0.98)
                blob(part, at, r * 1.15, r * 0.75, r * 0.55, "Hair", rows=4, count=10)
    elif style == "messy":
        shell(part, c, "Hair", 0.066, -0.055, 1.1, swoop=-0.018)
        for a, dz, r in ((-0.8, 0.09, 0.036), (-0.25, 0.1, 0.044), (0.35, 0.095, 0.042), (0.9, 0.085, 0.034),
                         (2.0, 0.09, 0.045), (-2.0, 0.09, 0.045), (3.14, 0.07, 0.05)):
            blob(part, on_head(c, a, dz, 1.0), r, r, r * 0.65, "Hair", rows=3, count=7)
    elif style in ("ponytail", "bun", "long"):
        shell(part, c, "Hair", 0.07, -0.062, 1.085, swoop=0.016)
        for side in (-1, 1):   # side locks framing the face
            sweep(part, [on_head(c, side * 1.05, 0.06, 1.07), on_head(c, side * 1.22, 0.0, 1.09), on_head(c, side * 1.2, -0.07, 1.05)],
                  circle(0.014, 8), "Hair", scales=[1.2, 0.9, 0.25])
        if style == "ponytail":
            base = Vector((0, c.y + 0.118, c.z + 0.05))
            blob(part, base, 0.03, 0.026, 0.028, "HairTie")
            sweep(part, [base + Vector((0, 0.01, 0.005)), base + Vector((0, 0.06, -0.03)), base + Vector((0, 0.065, -0.11)),
                         base + Vector((0, 0.045, -0.19))], circle(0.043, 10), "Hair", scales=[0.65, 1.1, 0.85, 0.15])
        elif style == "bun":
            blob(part, (0, c.y + 0.128, c.z - 0.045), 0.062, 0.05, 0.05, "Hair", rows=6, count=12)
        else:   # long: a curtain down the back
            rows_ = []
            for dz, w, dp, cy in ((0.04, 0.114, 0.045, 0.07), (-0.07, 0.122, 0.048, 0.085), (-0.18, 0.12, 0.04, 0.1),
                                  (-0.25, 0.1, 0.026, 0.112), (-0.28, 0.06, 0.012, 0.115)):
                rows_.append(hring(c.z + dz, 0, c.y + cy, w, dp, dp, 18))
            loft(part, rows_, "Hair")

    if hat in ("cap", "cap_back"):
        shell(part, c, "Hat", 0.058, 0.02, 1.145)
        blob(part, (0, c.y, c.z + 0.149), 0.012, 0.012, 0.007, "Hat")
        d = -1.0 if hat == "cap" else 1.0   # brim forward or backward
        brim_z = c.z + (0.064 if hat == "cap" else 0.036)
        top_pts, bot_pts = [], []
        for i in range(11):
            a = -1.05 + 2.1 * i / 10
            base = Vector((math.sin(a) * 0.12, c.y + d * math.cos(a) * 0.115, brim_z))
            tip = Vector((math.sin(a) * 0.1, c.y + d * (math.cos(a) * 0.115 + 0.075 * math.cos(a * 1.2)), brim_z - 0.012))
            top_pts.append((part.v(base), part.v(tip)))
            bot_pts.append((part.v(base - Vector((0, 0, 0.011))), part.v(tip - Vector((0, 0, 0.007)))))
        for i in range(10):
            (a0, a1), (b0, b1) = top_pts[i], top_pts[i + 1]
            (c0, c1), (d0, d1) = bot_pts[i], bot_pts[i + 1]
            part.f((a0, b0, b1, a1), "Hat", False)
            part.f((c0, c1, d1, d0), "Hat", False)
            part.f((a1, b1, d1, c1), "Hat", False)
        for (a0, a1), (c0, c1) in ((top_pts[0], bot_pts[0]), (top_pts[-1], bot_pts[-1])):
            part.f((a0, a1, c1, c0), "Hat", False)
        if "badge" in look["extras"] and hat == "cap":
            rbox(part, (0, on_head(c, 0, 0.095, 1.17).y - 0.002, c.z + 0.095), (0.028, 0.01, 0.032), "Gold", bevel=0.006, segs=1)
    elif hat == "headband":
        band = [on_head(c, TAU * i / 28, 0.06, 1.115) for i in range(29)]
        sweep(part, band, rrect(0.006, 0.017, n=8), "Hat", caps=False)
        blob(part, on_head(c, math.pi, 0.058, 1.17), 0.022, 0.016, 0.018, "Hat")
        for s in (-1, 1):
            sweep(part, [on_head(c, math.pi, 0.05, 1.18), on_head(c, math.pi + s * 0.3, -0.02, 1.2)], rrect(0.003, 0.014, n=6), "Hat", scales=[1.0, 0.5])
    elif hat == "kerchief":
        shell(part, c, "Hat", 0.086, -0.012, 1.14)
        blob(part, (0, c.y + 0.134, c.z + 0.004), 0.022, 0.016, 0.018, "Hat")
        for s in (-1, 1):
            sweep(part, [Vector((s * 0.012, c.y + 0.138, c.z)), Vector((s * 0.045, c.y + 0.155, c.z - 0.065))], rrect(0.004, 0.016, n=6), "Hat", scales=[1.0, 0.2])
    elif hat == "straw":
        crown = [hring(c.z + dz, 0, c.y + 0.004, r, r, r * 1.04, 24, 2.0) for dz, r in ((0.172, 0.04), (0.165, 0.1), (0.13, 0.122), (0.07, 0.128))]
        loft(part, crown, "Hat", cap1=False)
        loft(part, [hring(c.z + dz, 0, c.y + 0.004, r, r, r * 1.04, 24, 2.0) for dz, r in ((0.075, 0.127), (0.062, 0.21), (0.052, 0.208), (0.064, 0.127))],
             "Hat", cap0=False, cap1=False)
        loft(part, [hring(c.z + dz, 0, c.y + 0.004, r, r, r * 1.04, 24, 2.0) for dz, r in ((0.106, 0.131), (0.078, 0.133))], "HatBand", cap0=False, cap1=False)
    return part, ["Head"]


# =======================================================================================
# Clothes and things
# =======================================================================================

def extras(p, look):
    """Returns a list of (Part, allowed bones)."""
    ex = look["extras"]
    top_z = p["torso"][-1][0]
    hips_z = p["torso"][1][0]
    chest = Part("chest")
    waist = Part("waist")
    out = []
    torso_bones = ["Spine02", "Spine01", "Spine"]

    if "collar" in ex:
        for side in (-1, 1):
            pts = [(0.008, top_z - 0.002), (0.07, top_z - 0.012), (0.05, top_z - 0.065), (0.012, top_z - 0.028)]
            front = [chest.v((side * x, front_y(p, x, z) - 0.012, z)) for x, z in pts]
            back = [chest.v((side * x, front_y(p, x, z) - 0.004, z)) for x, z in pts]
            chest.f(front if side < 0 else front[::-1], "Collar", False)
            for i in range(4):
                j = (i + 1) % 4
                chest.f((front[i], front[j], back[j], back[i]), "Collar", False)
        chest_strip(chest, p, [(0.0, hips_z + 0.05), (0.0, 1.1), (0.0, top_z - 0.07)], 0.014, "Top2")
        for i in range(4):
            z = hips_z + 0.1 + i * 0.085
            blob(chest, (0, front_y(p, 0, z) - 0.012, z), 0.006, 0.004, 0.006, "Button", rows=3, count=8)
    if "tie" in ex:
        chest_strip(chest, p, [(0.0, top_z - 0.04), (0.0, 1.22), (0.0, 1.1)], 0.036, "Accent", 0.014)
    if "ribbon" in ex:
        z = top_z - 0.055
        for side in (-1, 1):
            chest_strip(chest, p, [(0.0, z), (side * 0.035, z + 0.016)], 0.026, "Ribbon", 0.016)
            chest_strip(chest, p, [(0.0, z), (side * 0.022, z - 0.07)], 0.018, "Ribbon", 0.015)
    if "lanyard" in ex:
        for side in (-1, 1):
            chest_strip(chest, p, [(side * 0.055, top_z - 0.02), (side * 0.032, 1.25), (0.0, 1.14)], 0.012, "Lanyard", 0.015)
        z = 1.095
        rbox(chest, (0, front_y(p, 0, z) - 0.018, z), (0.055, 0.008, 0.072), "EyeWhite", bevel=0.004, segs=1)
        rbox(chest, (0, front_y(p, 0, z) - 0.023, z + 0.012), (0.03, 0.004, 0.028), "Lanyard", bevel=0.001, segs=1)
    if "badge" in ex:
        rbox(chest, (-0.085, front_y(p, 0.085, 1.27) - 0.008, 1.27), (0.04, 0.01, 0.044), "Gold", bevel=0.01, segs=1)
        rbox(chest, (0.09, front_y(p, 0.09, 1.31) - 0.018, 1.31), (0.04, 0.032, 0.065), "Dark", bevel=0.008, segs=1)   # radio
        tube(chest, (0.1, front_y(p, 0.09, 1.31) - 0.018, 1.34), (0.1, front_y(p, 0.09, 1.31) - 0.018, 1.39), 0.005, "Dark", sides=6)
    if "vest" in ex:
        rows = [(z, w + 0.012, f + 0.016, b + 0.014) for z, w, f, b in catmull(p["torso"], 2) if 1.02 <= z <= p["shoulder_z"] - 0.025]
        loft(chest, [hring(z, 0, 0, w, f, b, 20) for z, w, f, b in rows], "Accent", cap0=False, cap1=False)
        for x in (-0.062, 0.0, 0.062):
            rbox(chest, (x, front_y(p, x, 1.09) - 0.032, 1.09), (0.05, 0.026, 0.07), "Accent", bevel=0.008, segs=1)
        for side in (-1, 1):
            sweep(chest, [Vector((side * 0.075, front_y(p, 0.075, 1.27) - 0.016, 1.27)), Vector((side * 0.09, -0.02, top_z - 0.012)),
                          Vector((side * 0.075, back_y(p, 1.27) + 0.014, 1.27))], rrect(0.008, 0.026, n=8), "Accent")
    if "pocket_chest" in ex or "vest" not in ex and "badge" in ex:
        for side in (-1, 1):
            z = 1.24 if not p["female"] else 1.14
            rbox(chest, (side * 0.075, front_y(p, 0.075, z) - 0.006, z), (0.068, 0.012, 0.062), "Top", bevel=0.004, segs=1)
            rbox(chest, (side * 0.075, front_y(p, 0.075, z + 0.03) - 0.012, z + 0.03), (0.072, 0.008, 0.018), "Top2", bevel=0.002, segs=1)
    if "stripe" in ex:
        torso_band(chest, p, p["shoulder_z"] - 0.15, 0.04, "Reflect", 0.008)
    if "flag" in ex:
        z = p["shoulder_z"] - 0.07
        for dz, mat in ((0.012, "FlagBlue"), (-0.012, "FlagRed")):
            rbox(chest, (-0.085, front_y(p, 0.085, z + dz) - 0.009, z + dz), (0.07, 0.01, 0.024), mat, bevel=0.0)
        tri = [(-0.12, z + 0.024), (-0.085, z), (-0.12, z - 0.024)]
        vs = [chest.v((x, front_y(p, 0.085, zz) - 0.016, zz)) for x, zz in tri]
        chest.f(vs[::-1], "EyeWhite", False)
    if "hood" in ex:
        loft(chest, [hring(z, 0, cy, w, f, b, 18) for z, w, f, b, cy in
                     ((top_z + 0.035, 0.05, 0.02, 0.03, 0.075), (top_z + 0.01, 0.1, 0.035, 0.065, 0.075),
                      (top_z - 0.04, 0.125, 0.045, 0.08, 0.075), (top_z - 0.1, 0.1, 0.04, 0.06, 0.07), (top_z - 0.135, 0.05, 0.02, 0.03, 0.07))], "Top2")
        for side in (-1, 1):
            chest_strip(chest, p, [(side * 0.03, top_z - 0.02), (side * 0.035, 1.24)], 0.008, "EyeWhite", 0.012)
    if "pocket" in ex:
        chest_strip(waist, p, [(-0.095, hips_z + 0.075), (0.0, hips_z + 0.085), (0.095, hips_z + 0.075)], 0.085, "Top2", 0.002)
    if "headphones" in ex:
        arc = [Vector((math.sin(a) * 0.085, -math.cos(a) * 0.07 + 0.005, top_z + 0.018 - math.cos(a) * 0.022)) for a in np.linspace(0.75, TAU - 0.75, 18)]
        sweep(chest, arc, circle(0.01, 8), "Dark")
        for side in (-1, 1):
            tube(chest, (side * 0.05, -0.07, top_z - 0.012), (side * 0.085, -0.055, top_z - 0.005), 0.032, "Accent", sides=14, smooth=False)
    if "belt" in ex:
        torso_band(waist, p, hips_z + 0.045, 0.042, "Dark", 0.01)
        rbox(waist, (0, front_y(p, 0, hips_z + 0.045) - 0.016, hips_z + 0.045), (0.045, 0.012, 0.036), "Gold", bevel=0.004, segs=1)
    if "pouches" in ex:
        w = p["torso"][1][1]
        for side, x in ((-1, w * 0.92), (1, w * 0.92), (1, w * 0.55)):
            rbox(waist, (side * x, -0.065 if x < w * 0.8 else -0.02, hips_z + 0.015), (0.05, 0.062, 0.088), "Dark", bevel=0.01, segs=1)
    if "apron" in ex:
        apron = Part("apron")
        bib, hem, waist_z = p["shoulder_z"] - 0.09, (0.44 if p["female"] else 0.52), p["torso"][2][0]
        grid_f, grid_b = [], []
        for i in range(11):
            z = bib - (bib - hem) * i / 10
            half = 0.095 if z > waist_z else min(0.175, 0.13 + (waist_z - z) * 0.18)
            row_f, row_b = [], []
            for j in range(7):
                x = -half + 2 * half * j / 6
                y = front_y(p, x, z) - 0.016 if z > hips_z else -0.128 + 0.04 * (x / half) ** 2
                row_f.append(apron.v((x, y, z)))
                row_b.append(apron.v((x, y + 0.008, z)))
            grid_f.append(row_f)
            grid_b.append(row_b)
        for i in range(10):
            for j in range(6):
                apron.f((grid_f[i][j], grid_f[i][j + 1], grid_f[i + 1][j + 1], grid_f[i + 1][j]), "Accent")
                apron.f((grid_b[i][j + 1], grid_b[i][j], grid_b[i + 1][j], grid_b[i + 1][j + 1]), "Accent")
        edges = [(grid_f[i][0], grid_b[i][0], grid_f[i + 1][0], grid_b[i + 1][0]) for i in range(10)]
        edges += [(grid_f[i + 1][6], grid_b[i + 1][6], grid_f[i][6], grid_b[i][6]) for i in range(10)]
        edges += [(grid_f[0][j + 1], grid_b[0][j + 1], grid_f[0][j], grid_b[0][j]) for j in range(6)]
        edges += [(grid_f[10][j], grid_b[10][j], grid_f[10][j + 1], grid_b[10][j + 1]) for j in range(6)]
        for a, b, cc, d in edges:
            apron.f((a, b, d, cc), "Accent", False)
        rbox(apron, (0, -0.138, hips_z - 0.14), (0.17, 0.01, 0.09), "AccentDark", bevel=0.004, segs=1)
        for side in (-1, 1):
            chest_strip(apron, p, [(side * 0.08, bib), (side * 0.07, top_z - 0.02)], 0.02, "AccentDark", 0.012)
        torso_band(apron, p, waist_z, 0.024, "AccentDark", 0.012)
        out.append((apron, "skirt"))
    if "towel" in ex:
        towel = Part("towel")
        x = 0.105
        path = [Vector((x, front_y(p, x, 1.15) - 0.028, 1.15)), Vector((x, front_y(p, x, 1.3) - 0.032, 1.3)),
                Vector((x, -0.055, top_z - 0.008)), Vector((x, 0.045, top_z - 0.004)),
                Vector((x, back_y(p, 1.32) + 0.03, 1.32)), Vector((x, back_y(p, 1.2) + 0.026, 1.2))]
        sweep(towel, [Vector(v) for v in catmull([tuple(v) for v in path], 3)], rrect(0.009, 0.042, n=10, e=4.0), "Towel")
        out.append((towel, ["Spine01", "Spine", "LeftShoulder"]))
    if "backpack" in ex or "delivery_box" in ex:
        pack = Part("pack")
        box = "delivery_box" in ex
        y = back_y(p, 1.22) + (0.115 if box else 0.07)
        if box:
            rbox(pack, (0, y, 1.19), (0.3, 0.19, 0.33), "Accent", bevel=0.025, segs=2)
            rbox(pack, (0, y, 1.37), (0.31, 0.2, 0.04), "AccentDark", bevel=0.012, segs=1)
            rbox(pack, (0, y + 0.099, 1.19), (0.12, 0.006, 0.08), "EyeWhite", bevel=0.002, segs=1)
        else:
            rbox(pack, (0, y, 1.18), (0.24, 0.125, 0.31), "Accent", bevel=0.055, segs=3)
            rbox(pack, (0, y + 0.068, 1.12), (0.18, 0.03, 0.14), "AccentDark", bevel=0.014, segs=1)
        for side in (-1, 1):
            x = side * p["shoulder_w"] * 0.58
            pts = [(x, y - 0.06, p["shoulder_z"] - 0.03), (x, 0.02, top_z + 0.004), (x, front_y(p, abs(x), top_z - 0.05) - 0.014, top_z - 0.045),
                   (x * 1.08, front_y(p, abs(x), 1.2) - 0.016, 1.2), (x * 1.3, front_y(p, abs(x) * 1.3, 1.08) - 0.012, 1.08)]
            sweep(pack, [Vector(v) for v in catmull(pts, 3)], rrect(0.006, 0.019, n=8), "AccentDark")
        out.append((pack, ["Spine01", "Spine"]))
    if "tote" in ex or "sling" in ex:
        bag = Part("bag")
        side = -1 if "sling" in ex else 1
        w = p["torso"][1][1]
        bx, bz = side * (w + 0.055), hips_z + (0.02 if "sling" in ex else 0.08)
        size = (0.075, 0.2, 0.16) if "sling" in ex else (0.09, 0.24, 0.23)
        rbox(bag, (bx, 0.0, bz), size, "Accent", bevel=0.025, segs=2)
        rbox(bag, (bx + side * size[0] * 0.5, 0.0, bz + size[2] * 0.22), (0.012, size[1] * 0.92, size[2] * 0.42), "AccentDark", bevel=0.004, segs=1)
        if "sling" in ex:   # across the body from the other shoulder
            ox = -side * p["shoulder_w"] * 0.6
            pts = [(bx, -0.05, bz + 0.07), (side * w * 0.55, front_y(p, w * 0.55, 1.1) - 0.016, 1.1),
                   (0.0, front_y(p, 0, 1.22) - 0.018, 1.22), (ox, front_y(p, abs(ox), top_z - 0.05) - 0.014, top_z - 0.045),
                   (ox, 0.04, top_z), (0.0, back_y(p, 1.22) + 0.012, 1.22), (bx, 0.07, bz + 0.07)]
        else:               # tote strap over the same shoulder
            sx = side * p["shoulder_w"] * 0.75
            pts = [(bx, -0.07, bz + 0.1), (sx, front_y(p, abs(sx), 1.26) - 0.02, 1.26), (sx, 0.0, p["shoulder_z"] + 0.055),
                   (sx, back_y(p, 1.26) + 0.016, 1.26), (bx, 0.07, bz + 0.1)]
        sweep(bag, [Vector(v) for v in catmull(pts, 4)], rrect(0.005, 0.015, n=8), "AccentDark")
        out.append((bag, ["Hips", "Spine02", "Spine01", "Spine"]))
    if chest.bm.verts:
        out.append((chest, torso_bones))
    if waist.bm.verts:
        out.append((waist, ["Hips", "Spine02"]))
    return out


# =======================================================================================
# Materials, skinning, export
# =======================================================================================

def shade_hex(hexc, k):
    h = hexc.lstrip("#")
    return "#" + "".join("%02x" % max(0, min(255, int(int(h[i:i + 2], 16) * k))) for i in (0, 2, 4))


def materials(look):
    skin = SKIN[look["skin"]]
    haircol = look.get("haircol", BLACK)
    colors = {
        "Skin": skin, "Hair": haircol, "HairTie": "#a8453f", "Top": look["top"], "Top2": shade_hex(look["top"], 0.86),
        "Collar": shade_hex(look["top"], 1.07), "Bottom": look["bottom"], "BottomDark": shade_hex(look["bottom"], 0.75),
        "Shoe": look["shoe"], "Sole": "#e8e4da" if look["shoes"] == "sneakers" else shade_hex(look["shoe"], 0.65),
        "Strap": shade_hex(look["shoe"], 0.7), "Sock": "#efece4", "Hat": look.get("hatcol", "#333333"), "HatBand": "#6b4630",
        "Accent": look.get("accent", "#555555"), "AccentDark": shade_hex(look.get("accent", "#555555"), 0.75),
        "Glove": "#27282c", "Dark": "#232428", "Gold": "#d3a840", "Button": "#f1eee6", "Frame": "#2b2522",
        "EyeWhite": "#f7f3ea", "Eye": "#3b2418", "Line": "#241916", "Brow": shade_hex(haircol, 0.9),
        "Mouth": shade_hex(skin, 0.52), "Lip": "#a94f4c", "Blush": shade_hex(skin, 0.93), "Towel": "#efe9db", "Ribbon": "#b03a3c", "Lanyard": "#2f4f8c",
        "Reflect": "#dfe3de", "FlagBlue": "#0b4aa8", "FlagRed": "#ce2029",
    }
    out = {}
    for name, hexc in colors.items():
        m = bpy.data.materials.new(name)
        try:
            m.use_nodes = True
        except Exception:
            pass
        b = m.node_tree.nodes.get("Principled BSDF")
        b.inputs["Base Color"].default_value = srgb_to_linear(hexc)
        b.inputs["Roughness"].default_value = 0.35 if name in ("Gold", "Eye") else 0.85
        b.inputs["Metallic"].default_value = 0.6 if name == "Gold" else 0.0
        out[name] = m
    return out


def weigh(obj, bones, allowed, p):
    """Smooth weights from the nearest allowed bones. "skirt" = hips at the top, easing into
    both thighs lower down, so it drapes when sitting and swings a little when walking."""
    names = ["Hips", "LeftUpLeg", "RightUpLeg", "Spine02", "Spine01"] if allowed == "skirt" else allowed
    groups = {n: obj.vertex_groups.new(name=n) for n in names}
    for v in obj.data.vertices:
        co = v.co
        if allowed == "skirt":
            hips_z = p["torso"][1][0]
            if co.z > hips_z + 0.09:
                weights = {"Spine02": 0.5, "Spine01": 0.5} if co.z > hips_z + 0.2 else {"Spine02": 1.0}
            else:
                drop = max(0.0, min(1.0, (hips_z - co.z) / 0.3))
                left = max(0.0, min(1.0, 0.5 + co.x / 0.14))
                weights = {"Hips": 1.0 - drop * 0.85, "LeftUpLeg": drop * 0.85 * left, "RightUpLeg": drop * 0.85 * (1 - left)}
        else:
            found = []
            for n in names:
                h, t, _ = bones[n]
                d = seg_dist(co, h, t)
                found.append((1.0 / (d * d + 2.5e-4) ** 3, n))
            found.sort(reverse=True)
            found = found[:2]
            total = sum(w for w, _ in found)
            weights = {n: w / total for w, n in found}
        for n, w in weights.items():
            if w > 0.01:
                groups[n].add([v.index], w, "REPLACE")


def build(name):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    look = LOOKS[name]
    female = name.endswith("_f")
    p = plan(female, "elder" in look["extras"])
    materials(look)
    bones = bones_of(p)

    pieces = [torso(p, look)]
    for side in (1, -1):
        pieces += [arm(p, look, side), leg(p, look, side), foot(p, look, side)]
    if look["legwear"].startswith("skirt"):
        pieces.append(skirt(p, look))
    head_part, head_bones, c = head(p, look)
    pieces.append((head_part, head_bones))
    pieces.append(hair(p, look, c))
    pieces += extras(p, look)

    objs = []
    for part, allowed in pieces:
        obj = part.build(sharp_deg=48.0)
        weigh(obj, bones, allowed, p)
        objs.append(obj)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    body = objs[0]
    body.name = name
    body.data.name = name
    arm_obj = make_armature(bones)
    body.parent = arm_obj
    body.modifiers.new("Armature", "ARMATURE").object = arm_obj
    os.makedirs(OUT_DIR, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT_DIR, name + ".glb"), export_format="GLB")
    print("  %s: %d triangles" % (name, sum(len(q.vertices) - 2 for q in body.data.polygons)))


def main():
    names = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else list(LOOKS)
    for name in names:
        build(name)


main()
