"""Habal-Habal Simulator - traffic vehicles (original models, built by code, no real brands).

Lighter than the player's scooter (many of these drive around at once):
    car_sedan, car_hatch, car_pickup   about 3-5k triangles each
    jeepney                            long open-back body, chrome hood, stripes, benches
    tricycle                           small scooter with a covered sidecar
    motorbike                          small scooter (the game adds a rider)

Run without opening Blender's window (from the project folder):
    "D:\\Tools\\Blender\\blender-5.3.0-windows-x64\\blender.exe" -b -P tools/blender/make_traffic.py

Output:
    assets/vehicles/traffic.glb    (the game loads this; one object per vehicle, all at the origin)
    assets/vehicles/traffic.blend  (for editing in Blender; spread out side by side)

Conventions: Blender Z is up, vehicles face +Y (Godot -Z), origin on the ground at the middle.
Material names the game swaps per vehicle: "Paint" (body color), "Accent" and "Accent2"
(jeepney / tricycle stripes), and "HeadLight", "TailLight", "Signal" (made to glow).
"""
import bpy
import math
import os
import sys
from mathutils import Vector, Matrix

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from shapes import *   # noqa: E402,F403

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.normpath(os.path.join(HERE, "..", "..", "assets", "vehicles"))


def paint_or_trim(c, nrm):
    return "Trim" if nrm.z < -0.55 else "Paint"


def revolve_at(p, center, prof, mat, segs):
    rings = []
    for i in range(segs):
        a = TAU * i / segs
        rings.append([Vector((center.x + x, center.y + r * math.cos(a), center.z + r * math.sin(a))) for r, x in prof])
    loft(p, rings, mat, wrap=True)


def wheel(p, center, r, width, rim_mat="Metal", segs=18):
    """A light wheel: rounded tire, a rim on the outer side with 5 spokes, a hub cap."""
    center = Vector(center)
    w = width / 2
    s = 1.0 if center.x >= 0 else -1.0   # outer side
    rim = r * 0.62
    revolve_at(p, center, [(rim, -w * 0.45), (r * 0.9, -w * 0.5), (r * 0.985, -w * 0.38), (r, -w * 0.15),
                           (r, w * 0.15), (r * 0.985, w * 0.38), (r * 0.9, w * 0.5), (rim, w * 0.45)], "Rubber", segs)
    revolve_at(p, center, [(r * 0.12, s * w * 0.25), (rim, s * w * 0.3), (rim, s * w * 0.46),
                           (rim * 0.88, s * w * 0.4), (r * 0.12, s * w * 0.32)], "Rim", 16)
    for k in range(5):
        a = TAU * k / 5
        d = Vector((0, math.cos(a), math.sin(a)))
        o = center + Vector((s * w * 0.4, 0, 0))
        bar(p, o + d * r * 0.14, o + d * rim * 0.93, (1, 0, 0), 0.02, r * 0.13, rim_mat)
    tube(p, center + Vector((s * w * 0.35, 0, 0)), center + Vector((s * w * 0.5, 0, 0)), r * 0.16, rim_mat, sides=8)


def sample_ys(y_front, y_back, wheel_ys, r):
    """Front-to-back stations for a body: coarse, but dense around the wheel arches."""
    ys = set()
    y = y_front
    while y > y_back:
        ys.add(round(y, 3))
        y -= 0.2
    ys.add(y_back)
    for wy in wheel_ys:
        k = -r
        while k <= r:
            ys.add(round(wy + k, 3))
            k += 0.07
    return sorted((y for y in ys if y_back <= y <= y_front), reverse=True)


def interp(keys, y):
    """keys = [(y, a, b, ...)] sorted front (high y) to back. Linear blend at y."""
    for k0, k1 in zip(keys, keys[1:]):
        if k1[0] <= y <= k0[0]:
            t = (k0[0] - y) / max(k0[0] - k1[0], 1e-6)
            return [u + (v - u) * t for u, v in zip(k0[1:], k1[1:])]
    return list(keys[0][1:] if y > keys[0][0] else keys[-1][1:])


def car_body(p, keys, wheels_y, wr, n=4.0):
    """Lower body: rounded box sections; the bottom rises over each wheel (wheel arches)."""
    dense = catmull(keys, 4)
    arch_r = wr + 0.07
    rings = []
    for y in sample_ys(keys[0][0], keys[-1][0], wheels_y, arch_r):
        zb, zt, hw = interp(dense, y)
        for wy in wheels_y:
            d = abs(y - wy)
            if d < arch_r:
                zb = max(zb, wr + math.sqrt(arch_r * arch_r - d * d))
        zb = min(zb, zt - 0.08)
        cz = (zb + zt) / 2
        rings.append(ring_y(y, 0.0, cz, hw, zt - cz, zt - cz, n=n, count=22))
    loft(p, rings, paint_or_trim)


def ring_cabin(y, zb, zt, hwb, hwt, n=6.0, count=20):
    pts = []
    for i in range(count):
        cs, sn = se(TAU * i / count, n)
        z = (zb + zt) / 2 + (zt - zb) / 2 * sn
        f = (z - zb) / max(zt - zb, 1e-6)
        pts.append(Vector(((hwb + (hwt - hwb) * f) * cs, y, z)))
    return pts


def cabin(p, rows, zb, hwb, hwt, pillars):
    """Greenhouse: glass on the sides/front/back, paint on the roof and pillars."""
    def mat(c, nrm):
        if nrm.z > 0.8 or nrm.z < -0.5:
            return "Paint"
        for a, b in pillars:
            if a <= c.y <= b:
                return "Paint"
        if abs(nrm.x) > 0.55 or (abs(nrm.y) > 0.3 and abs(nrm.x) < 0.45):
            return "Glass"
        return "Paint"
    loft(p, [ring_cabin(y, zb, zt, hwb, hwt) for y, zt in rows], mat)


def car_details(p, s):
    yf, yr, hw = s["front"], s["rear"], s["hw"]
    for side in (-1, 1):
        x = side * (hw - 0.27)
        rbox(p, (x, yf - 0.05, s["light_z"]), (0.34, 0.1, 0.11), "HeadLight", bevel=0.03, segs=1, rot=(0, 0, side * 6))
        rbox(p, (x, yr + 0.05, s["tail_z"]), (0.32, 0.1, 0.12), "TailLight", bevel=0.03, segs=1, rot=(0, 0, -side * 6))
        rbox(p, (side * (hw - 0.07), yf - 0.12, s["light_z"] - 0.12), (0.08, 0.06, 0.04), "Signal", bevel=0.01, segs=1)
        # side mirror + door handles + a door seam
        mz, my = s["mirror"]
        rbox(p, (side * (hw + 0.03), my, mz - 0.03), (0.12, 0.07, 0.09), "Paint", bevel=0.025, segs=1)
        rbox(p, (side * (hw - 0.04), my + 0.02, mz - 0.07), (0.12, 0.05, 0.03), "Trim", bevel=0.01, segs=1)
        for hy in s["handles"]:
            rbox(p, (side * (hw + 0.008), hy, s["handle_z"]), (0.02, 0.13, 0.028), "Chrome", bevel=0.008, segs=1)
        for sy in s["seams"]:
            rbox(p, (side * (hw - 0.004), sy, s["handle_z"] - 0.15), (0.014, 0.012, 0.3), "Trim", bevel=0.0)
    rbox(p, (0, yf - 0.02, s["light_z"] - 0.05), (0.8, 0.08, 0.15), "Trim", bevel=0.03, segs=1)        # grille
    for k in range(3):
        rbox(p, (0, yf + 0.005, s["light_z"] - 0.1 + k * 0.05), (0.74, 0.02, 0.012), "Chrome", bevel=0.0)
    rbox(p, (0, yf - 0.03, 0.36), (2 * hw - 0.18, 0.12, 0.13), "Trim", bevel=0.04, segs=1)              # bumpers
    rbox(p, (0, yr + 0.03, 0.40), (2 * hw - 0.18, 0.12, 0.13), "Trim", bevel=0.04, segs=1)
    rbox(p, (0, yf + 0.04, 0.37), (0.36, 0.02, 0.11), "Plate", bevel=0.0)
    rbox(p, (0, yr - 0.04, s["plate_z"]), (0.36, 0.02, 0.11), "Plate", bevel=0.0)
    rbox(p, (0, (yf + yr) / 2, 0.36), (2 * hw - 0.42, abs(yf - yr) - 0.8, 0.28), "Trim", bevel=0.0)   # underbody
    for wy in s["wheels_y"]:
        for side in (-1, 1):
            wheel(p, (side * s["track"], wy, s["wr"]), s["wr"], s["ww"])


def sedan():
    p = Part("car_sedan")
    body = [(2.2, 0.34, 0.62, 0.72), (2.14, 0.27, 0.70, 0.84), (1.9, 0.25, 0.77, 0.875), (1.3, 0.25, 0.83, 0.885),
            (0.7, 0.25, 0.88, 0.89), (0.0, 0.25, 0.90, 0.895), (-1.2, 0.26, 0.91, 0.89), (-1.7, 0.27, 0.93, 0.88),
            (-2.1, 0.31, 0.92, 0.85), (-2.2, 0.38, 0.86, 0.74)]
    car_body(p, body, (1.35, -1.35), 0.32)
    rows = [(0.72, 0.87), (0.45, 1.06), (0.15, 1.26), (-0.05, 1.34), (-0.30, 1.37), (-0.42, 1.375), (-0.7, 1.37),
            (-0.95, 1.36), (-1.2, 1.30), (-1.45, 1.12), (-1.68, 0.94)]
    cabin(p, rows, 0.84, 0.83, 0.68, [(-0.43, -0.29)])
    car_details(p, {"front": 2.2, "rear": -2.2, "hw": 0.89, "light_z": 0.66, "tail_z": 0.78, "plate_z": 0.56,
                    "mirror": (0.98, 0.55), "handles": (0.05, -0.75), "handle_z": 0.8, "seams": (0.62, -0.35, -1.15),
                    "wheels_y": (1.35, -1.35), "wr": 0.32, "ww": 0.2, "track": 0.78})
    return p.build()


def hatch():
    p = Part("car_hatch")
    body = [(1.95, 0.34, 0.62, 0.70), (1.9, 0.27, 0.70, 0.82), (1.6, 0.25, 0.78, 0.85), (1.0, 0.25, 0.86, 0.86),
            (0.5, 0.25, 0.90, 0.865), (-1.2, 0.26, 0.93, 0.86), (-1.75, 0.28, 0.95, 0.85), (-1.93, 0.32, 0.94, 0.80),
            (-1.97, 0.40, 0.90, 0.72)]
    car_body(p, body, (1.25, -1.25), 0.3)
    rows = [(0.55, 0.88), (0.3, 1.06), (0.0, 1.28), (-0.2, 1.38), (-0.32, 1.39), (-0.44, 1.39), (-1.0, 1.385),
            (-1.3, 1.37), (-1.6, 1.33), (-1.8, 1.20), (-1.9, 0.97)]
    cabin(p, rows, 0.86, 0.80, 0.66, [(-0.45, -0.31), (-1.62, -1.3)])
    car_details(p, {"front": 1.95, "rear": -1.97, "hw": 0.86, "light_z": 0.68, "tail_z": 0.86, "plate_z": 0.6,
                    "mirror": (0.99, 0.4), "handles": (-0.1, -0.85), "handle_z": 0.82, "seams": (0.45, -0.38),
                    "wheels_y": (1.25, -1.25), "wr": 0.3, "ww": 0.19, "track": 0.75})
    return p.build()


def pickup():
    p = Part("car_pickup")
    body = [(2.45, 0.40, 0.75, 0.74), (2.38, 0.33, 0.86, 0.86), (2.0, 0.31, 0.95, 0.90), (1.2, 0.31, 1.02, 0.91),
            (0.5, 0.31, 1.05, 0.92), (-2.3, 0.33, 1.05, 0.92), (-2.45, 0.40, 1.0, 0.88)]
    car_body(p, body, (1.55, -1.6), 0.36, n=5.0)
    rows = [(0.55, 1.07), (0.30, 1.30), (0.05, 1.55), (-0.15, 1.62), (-0.30, 1.625), (-0.40, 1.625),
            (-0.8, 1.62), (-1.0, 1.60), (-1.04, 1.30), (-1.06, 1.04)]
    cabin(p, rows, 1.0, 0.86, 0.74, [(-0.41, -0.29)])
    # Open bed: raised side rails and tailgate around a dark floor
    for side in (-1, 1):
        rbox(p, (side * 0.88, -1.75, 1.13), (0.08, 1.35, 0.17), "Paint", bevel=0.02, segs=1)
    rbox(p, (0, -2.4, 1.13), (1.84, 0.08, 0.17), "Paint", bevel=0.02, segs=1)
    rbox(p, (0, -1.1, 1.13), (1.84, 0.06, 0.17), "Paint", bevel=0.02, segs=1)
    rbox(p, (0, -1.75, 1.058), (1.68, 1.25, 0.02), "Interior", bevel=0.0)
    car_details(p, {"front": 2.45, "rear": -2.45, "hw": 0.92, "light_z": 0.8, "tail_z": 0.86, "plate_z": 0.58,
                    "mirror": (1.18, 0.5), "handles": (-0.05,), "handle_z": 0.95, "seams": (0.55, -1.0),
                    "wheels_y": (1.55, -1.6), "wr": 0.36, "ww": 0.24, "track": 0.82})
    return p.build()


# ---------------------------------------------------------------------------------------

def jeepney():
    p = Part("jeepney")
    wr, track = 0.40, 0.86
    rbox(p, (0, 0.15, 0.45), (1.5, 5.6, 0.25), "Trim", bevel=0.0)    # chassis

    # Stainless hood
    hood = [(3.13, 0.56, 1.05, 0.66), (3.05, 0.52, 1.12, 0.72), (2.6, 0.52, 1.16, 0.74), (1.86, 0.52, 1.24, 0.76)]
    rings = []
    for y, zb, zt, hw in catmull(hood, 3):
        cz = (zb + zt) / 2
        rings.append(ring_y(y, 0, cz, hw, zt - cz, zt - cz, n=5.0, count=20))
    loft(p, rings, "Chrome")
    # Hood ornament (a chrome fin with wings) and two antenna whips with little flags
    rbox(p, (0, 3.0, 1.22), (0.03, 0.2, 0.13), "Chrome", bevel=0.01, segs=1, rot=(-25, 0, 0))
    for side in (-1, 1):
        bar(p, (0, 2.97, 1.2), (side * 0.16, 2.9, 1.27), (0, 0, 1), 0.012, 0.05, "Chrome")
        tube(p, (side * 0.7, 2.75, 1.15), (side * 0.72, 2.7, 1.95), 0.008, "Chrome", sides=5)
        rbox(p, (side * 0.76, 2.7, 1.88), (0.08, 0.005, 0.06), "Accent", bevel=0.0)

    # Grille, headlights, bumper
    rbox(p, (0, 3.13, 0.78), (1.15, 0.05, 0.42), "Trim", bevel=0.01, segs=1)
    for k in range(-5, 6):
        rbox(p, (k * 0.1, 3.16, 0.78), (0.025, 0.03, 0.38), "Chrome", bevel=0.0)
    for side in (-1, 1):
        for x in (0.36, 0.58):
            c = Vector((side * x, 3.15, 1.0))
            tube(p, c - Vector((0, 0.03, 0)), c + Vector((0, 0.03, 0)), 0.1, "Chrome", sides=14)
            tube(p, c + Vector((0, 0.03, 0)), c + Vector((0, 0.04, 0)), 0.082, "HeadLight", sides=14)
    rbox(p, (0, 3.22, 0.52), (2.0, 0.14, 0.18), "Chrome", bevel=0.04, segs=1)
    for side in (-1, 1):
        tube(p, (side * 0.5, 3.24, 0.6), (side * 0.5, 3.24, 0.98), 0.02, "Chrome", sides=6)
    rbox(p, (0, 3.3, 0.5), (0.4, 0.02, 0.12), "Plate", bevel=0.0)

    # Front fenders over the wheels, and the wheels
    for side in (-1, 1):
        arc = [(side * track, 2.3 + 0.5 * math.cos(math.radians(a)), wr + 0.5 * math.sin(math.radians(a)))
               for a in range(5, 180, 12)]
        sweep(p, arc, rrect(0.014, 0.17, n=8), "Paint")
        for wy in (2.3, -1.9):
            wheel(p, (side * track, wy, wr), wr, 0.26, rim_mat="Chrome")
        rbox(p, (side * track, -2.42, 0.45), (0.28, 0.02, 0.3), "Trim", bevel=0.0)   # mud flaps

    # Windshield, dashboard, steering wheel (driver on the left)
    rbox(p, (0, 1.83, 1.55), (1.72, 0.04, 0.58), "Glass", bevel=0.0, rot=(-12, 0, 0))
    rbox(p, (0, 1.88, 1.25), (1.9, 0.1, 0.1), "Paint", bevel=0.02, segs=1)
    rbox(p, (0, 1.6, 1.3), (1.7, 0.3, 0.12), "Interior", bevel=0.02, segs=1)
    wheel_ring = [(-0.45 + 0.18 * math.cos(TAU * i / 12), 1.42 + 0.06 * math.sin(TAU * i / 12),
                   1.42 + 0.17 * math.sin(TAU * i / 12)) for i in range(13)]
    sweep(p, wheel_ring, circle(0.015, 5), "Trim", caps=False)

    # Side walls: lower panels (with a cut over the rear wheel), stripes, posts, upper band
    for side in (-1, 1):
        x = side * 0.98
        for y0, y1, zb in ((1.85, -1.38, 0.55), (-1.38, -2.42, 0.88), (-2.42, -2.85, 0.55)):
            rbox(p, (x, (y0 + y1) / 2, (zb + 1.3) / 2), (0.05, y0 - y1, 1.3 - zb), "Paint", bevel=0.012, segs=1)
        rbox(p, (x * 1.026, -0.5, 1.2), (0.012, 4.65, 0.06), "Accent", bevel=0.0)
        rbox(p, (x * 1.026, -0.5, 1.11), (0.012, 4.65, 0.04), "Accent2", bevel=0.0)
        rbox(p, (x * 1.026, 0.25, 0.63), (0.014, 3.2, 0.03), "Chrome", bevel=0.0)
        for k in range(9):   # little diamond panels along the side
            rbox(p, (x * 1.026, 1.45 - k * 0.36, 0.88 if k < 8 else 1.0), (0.012, 0.12, 0.12),
                 "Accent" if k % 2 == 0 else "Accent2", bevel=0.0, rot=(45, 0, 0))
        for k in range(9):   # window posts
            y = 1.82 - k * 0.58
            tube(p, (x, y, 1.3), (x, y, 1.88), 0.025, "Chrome", sides=6)
        rbox(p, (x, -0.5, 1.92), (0.05, 4.7, 0.12), "Paint", bevel=0.012, segs=1)
        rbox(p, (x * 1.015, -0.5, 1.99), (0.02, 4.75, 0.03), "Chrome", bevel=0.0)
        # tall side mirror on the front fender
        tube(p, (side * 0.95, 2.45, 0.95), (side * 1.1, 2.4, 1.45), 0.01, "Chrome", sides=5)
        rbox(p, (side * 1.12, 2.4, 1.52), (0.08, 0.03, 0.14), "Chrome", bevel=0.01, segs=1)

    # Roof with a route sign on the front
    rbox(p, (0, -0.43, 2.02), (2.08, 4.9, 0.08), "Paint", bevel=0.03, segs=1)
    rbox(p, (0, 1.98, 2.18), (1.5, 0.05, 0.24), "Plate", bevel=0.01, segs=1)
    rbox(p, (0, 1.99, 2.27), (1.5, 0.055, 0.05), "Accent2", bevel=0.0)
    for k, w in enumerate((0.5, 0.3, 0.42)):
        rbox(p, (-0.4 + k * 0.4, 2.01, 2.15), (w * 0.6, 0.01, 0.06), "Trim", bevel=0.0)
    for side in (-1, 1):
        tube(p, (side * 0.85, 1.7, 2.1), (side * 0.85, -2.6, 2.1), 0.015, "Chrome", sides=5)

    # Back: panels beside the entrance, step, grab rails, lights
    for side in (-1, 1):
        rbox(p, (side * 0.72, -2.85, 1.2), (0.55, 0.05, 1.32), "Paint", bevel=0.012, segs=1)
        rbox(p, (side * 0.75, -2.88, 0.85), (0.18, 0.04, 0.12), "TailLight", bevel=0.01, segs=1)
        tube(p, (side * 0.42, -2.88, 0.95), (side * 0.42, -2.88, 1.8), 0.02, "Chrome", sides=6)
    rbox(p, (0, -2.85, 1.85), (0.9, 0.05, 0.3), "Paint", bevel=0.012, segs=1)
    rbox(p, (0, -2.97, 0.5), (1.0, 0.28, 0.06), "Trim", bevel=0.01, segs=1)
    rbox(p, (0, -2.89, 0.68), (0.36, 0.02, 0.11), "Plate", bevel=0.0)

    # Inside: floor and two long benches facing each other
    rbox(p, (0, -0.6, 0.6), (1.86, 4.5, 0.05), "Interior", bevel=0.0)
    for side in (-1, 1):
        rbox(p, (side * 0.72, -0.65, 0.92), (0.4, 3.9, 0.1), "Seat", bevel=0.03, segs=1)
        rbox(p, (side * 0.72, -0.65, 0.75), (0.36, 3.9, 0.3), "Interior", bevel=0.0)
        rbox(p, (side * 0.93, -0.65, 1.15), (0.06, 3.9, 0.32), "Seat", bevel=0.02, segs=1)
    return p.build()


# ---------------------------------------------------------------------------------------
# Small scooter (traffic riders, and the tricycle's bike). Same layout as the player's.
# ---------------------------------------------------------------------------------------

def small_scooter(p, ox):
    o = Vector((ox, 0, 0))
    for wy in (0.65, -0.62):
        wheel(p, o + Vector((0, wy, 0.27)), 0.27, 0.11, rim_mat="Rim", segs=16)
    cowl = [(-0.925, 0.69, 0.79, 0.10), (-0.88, 0.62, 0.805, 0.14), (-0.75, 0.53, 0.805, 0.175),
            (-0.4, 0.46, 0.80, 0.19), (-0.10, 0.40, 0.80, 0.18), (0.02, 0.36, 0.74, 0.16), (0.12, 0.34, 0.55, 0.12)]
    rings = []
    for y, zb, zt, hw in catmull(cowl, 2):
        cz = (zb + zt) / 2
        rings.append(ring_y(y, ox, cz, hw, zt - cz, zt - cz, n=2.7, count=16))
    loft(p, rings, paint_or_trim)
    seat = [(-0.74, 0.78, 0.82, 0.08), (-0.6, 0.78, 0.87, 0.15), (-0.3, 0.78, 0.848, 0.16), (0.0, 0.76, 0.835, 0.165),
            (0.1, 0.72, 0.78, 0.1)]
    rings = []
    for y, zb, zt, hw in catmull(seat, 2):
        cz = (zb + zt) / 2
        rings.append(ring_y(y, ox, cz, hw, zt - cz, zt - cz, n=3.4, count=14))
    loft(p, rings, "Seat")
    apron = [(0.32, 0.305, 0.17, 0.04, 0.03), (0.52, 0.355, 0.21, 0.085, 0.03), (0.62, 0.405, 0.21, 0.13, 0.035),
             (0.80, 0.415, 0.18, 0.11, 0.035), (0.95, 0.39, 0.10, 0.06, 0.03), (0.975, 0.385, 0.05, 0.03, 0.02)]
    loft(p, [ring_z(z, ox, cy, hw, df, db, n=2.2, count=16) for z, cy, hw, df, db in apron],
         lambda c, n: "Trim" if n.y < -0.55 else "Paint")
    rbox(p, o + Vector((0, 0.2, 0.335)), (0.36, 0.3, 0.05), "Trim", bevel=0.015, segs=1)
    rbox(p, o + Vector((-0.13, -0.3, 0.3)), (0.11, 0.7, 0.16), "Metal", bevel=0.04, segs=1)
    sweep(p, [o + Vector((0.17, -0.25, 0.3)), o + Vector((0.18, -0.8, 0.41))], circle(0.05, 10), "DarkMetal")
    rbox(p, o + Vector((0, -0.925, 0.745)), (0.17, 0.03, 0.055), "TailLight", bevel=0.01, segs=1)
    # front: fork, fender, handlebar cover with headlight, bars, mirrors
    rake = math.radians(18)
    ax = Vector((0, -math.sin(rake), math.cos(rake)))
    fw = o + Vector((0, 0.65, 0.27))
    for side in (-1, 1):
        tube(p, fw + Vector((side * 0.07, 0, 0)), fw + Vector((side * 0.07, 0, 0)) + ax * 0.55, 0.02, "Chrome", sides=6)
    arc = [fw + Vector((0, 0.3 * math.cos(math.radians(a)), 0.3 * math.sin(math.radians(a)))) for a in range(18, 140, 15)]
    sweep(p, arc, rrect(0.007, 0.066, n=8), "Paint")
    cover = [(-0.19, 0.05, 0.04, 0.026), (-0.16, 0.10, 0.075, 0.05), (0.0, 0.12, 0.085, 0.058), (0.16, 0.10, 0.075, 0.05),
             (0.19, 0.05, 0.04, 0.026)]
    loft(p, [ring_x(ox + x, 0.432, 1.02, df, db, h, h, n=2.6, count=14) for x, df, db, h in cover],
         lambda c, n: "Trim" if n.z < -0.5 else "Paint")
    rbox(p, o + Vector((0, 0.55, 1.005)), (0.17, 0.03, 0.07), "HeadLight", bevel=0.015, segs=1)
    for side in (-1, 1):
        tube(p, o + Vector((side * 0.15, 0.41, 1.02)), o + Vector((side * 0.37, 0.38, 1.025)), 0.016, "Rubber", sides=6)
        tube(p, o + Vector((side * 0.15, 0.41, 1.06)), o + Vector((side * 0.29, 0.42, 1.17)), 0.007, "Trim", sides=4)
        rbox(p, o + Vector((side * 0.315, 0.425, 1.2)), (0.14, 0.03, 0.09), "Trim", bevel=0.02, segs=1,
             rot=(0, 0, side * 14))


def motorbike():
    p = Part("motorbike")
    small_scooter(p, 0.0)
    return p.build()


def tricycle():
    p = Part("tricycle")
    small_scooter(p, -0.45)
    cx = 0.55
    # Sidecar tub
    keys = [(0.78, 0.32, 0.62, 0.25), (0.68, 0.26, 0.82, 0.42), (0.3, 0.23, 0.86, 0.47), (-0.6, 0.23, 0.86, 0.47),
            (-0.8, 0.26, 0.84, 0.45), (-0.86, 0.32, 0.76, 0.38)]
    rings = []
    for y, zb, zt, hw in catmull(keys, 3):
        cz = (zb + zt) / 2
        rings.append(ring_y(y, cx, cz, hw, zt - cz, zt - cz, n=4.0, count=20))
    loft(p, rings, paint_or_trim)
    rbox(p, (cx + 0.475, -0.1, 0.62), (0.012, 1.3, 0.05), "Accent", bevel=0.0)
    rbox(p, (cx + 0.475, -0.1, 0.54), (0.012, 1.3, 0.03), "Accent2", bevel=0.0)
    rbox(p, (cx, 0.775, 0.58), (0.26, 0.02, 0.14), "Plate", bevel=0.0)
    rbox(p, (cx + 0.3, -0.87, 0.72), (0.12, 0.03, 0.08), "TailLight", bevel=0.01, segs=1)
    # Cabin frame, windshield, back wall with a small window, bench
    for px, py0, py1 in ((cx - 0.42, 0.58, 0.52), (cx + 0.42, 0.58, 0.52), (cx - 0.42, -0.76, -0.8),
                         (cx + 0.42, -0.76, -0.8)):
        tube(p, (px, py0, 0.84), (px, py1, 1.82), 0.022, "Trim", sides=6)
    rbox(p, (cx, 0.6, 1.28), (0.82, 0.03, 0.55), "Glass", bevel=0.0, rot=(-8, 0, 0))
    rbox(p, (cx, 0.62, 0.95), (0.86, 0.06, 0.18), "Paint", bevel=0.02, segs=1)
    rbox(p, (cx, -0.8, 1.32), (0.86, 0.04, 0.95), "Paint", bevel=0.012, segs=1)
    rbox(p, (cx, -0.82, 1.45), (0.5, 0.01, 0.25), "Glass", bevel=0.0)
    rbox(p, (cx + 0.44, -0.4, 1.32), (0.03, 0.75, 0.95), "Paint", bevel=0.012, segs=1)   # outer side wall
    rbox(p, (cx + 0.455, -0.4, 1.12), (0.012, 0.75, 0.06), "Accent", bevel=0.0)
    rbox(p, (cx, -0.45, 0.62), (0.8, 0.45, 0.1), "Seat", bevel=0.03, segs=1)
    rbox(p, (cx, -0.7, 0.9), (0.8, 0.08, 0.4), "Seat", bevel=0.02, segs=1)
    # Roof over the sidecar and the driver, with a sign
    rbox(p, (0.15, -0.12, 1.86), (1.8, 1.95, 0.07), "Paint", bevel=0.025, segs=1)
    rbox(p, (0.15, -0.12, 1.83), (1.84, 1.99, 0.03), "Accent2", bevel=0.0)
    rbox(p, (cx, 0.84, 1.95), (0.7, 0.03, 0.16), "Plate", bevel=0.01, segs=1)
    # Sidecar wheel with its fender, and the frame to the bike
    wheel(p, (1.08, -0.4, 0.28), 0.28, 0.12, rim_mat="Rim", segs=16)
    arc = [(1.08, -0.4 + 0.34 * math.cos(math.radians(a)), 0.28 + 0.34 * math.sin(math.radians(a))) for a in range(15, 170, 15)]
    sweep(p, arc, rrect(0.01, 0.08, n=8), "Paint")
    for y in (0.3, -0.5):
        tube(p, (-0.3, y, 0.32), (cx - 0.3, y, 0.3), 0.02, "DarkMetal", sides=6)
    return p.build()


# ---------------------------------------------------------------------------------------

def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    make_materials()
    print("Building traffic:")
    objs = [sedan(), hatch(), pickup(), jeepney(), tricycle(), motorbike()]
    os.makedirs(OUT_DIR, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT_DIR, "traffic.glb"), export_format="GLB")
    for i, o in enumerate(objs):        # spread out only in the .blend, for editing
        o.location.x = i * 3.0
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT_DIR, "traffic.blend"))
    print("Saved:", OUT_DIR)


main()
