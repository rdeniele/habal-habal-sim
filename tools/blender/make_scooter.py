"""Habal-Habal Simulator - the player's scooter (original model, built by code).

A step-through scooter like the ones habal-habal riders use: rounded body panels, a leg
shield, a two-level seat, grab rail, alloy wheels with tire tread, telescopic fork, brake
disc and caliper, rear shock with a coil spring, CVT case, exhaust, lights and mirrors.

Run without opening Blender's window (from the project folder):
    "D:\\Tools\\Blender\\blender-5.3.0-windows-x64\\blender.exe" -b -P tools/blender/make_scooter.py

Output:
    assets/vehicles/scooter.glb    (the game loads this)
    assets/vehicles/scooter.blend  (for editing in Blender)

Conventions (so the game can move the parts):
  - Blender Z is up, the scooter faces +Y (glTF turns that into Godot's -Z = forward).
  - The ground is z = 0. The rear wheel axle is at y = -0.62, the front axle at y = +0.65.
  - Node names the game looks for:
      Body                      everything that doesn't move
      RearWheel                 spins (origin = axle)
      SteerPivot/Fork           Fork turns around its local up axis (= the tilted steering axis)
      Fork/FrontBody            handlebar, fork tubes, fender, headlight (turn with the bars)
      Fork/FrontWheel           spins (origin = axle)
      Fork/MirrorL, MirrorR     where the game puts the live mirror pictures (they face back)
      Fork/HeadlightMount       where the game puts the headlight's light
  - Material names the game looks for: "Paint" (gets the motor's color), "HeadLight",
    "TailLight", "Signal" (made to glow in the game).
"""
import bpy
import math
import os
import sys
from mathutils import Vector, Matrix

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from shapes import *   # noqa: E402,F403  (Part, loft, sweep, rbox, ... and the materials)

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.normpath(os.path.join(HERE, "..", "..", "assets", "vehicles"))

RW = Vector((0.0, -0.62, 0.27))   # rear axle
FW = Vector((0.0, 0.65, 0.27))    # front axle
RAKE = math.radians(18.0)         # steering axis tilt (top leans back)
AXIS = Vector((0.0, -math.sin(RAKE), math.cos(RAKE)))
RIM_R = 0.185


def steer_pt(t, x=0.0):
    """A point on the steering axis, t meters up from the front axle."""
    return Vector((x, FW.y + AXIS.y * t, FW.z + AXIS.z * t))


# ---------------------------------------------------------------------------------------
# Wheels (built around their own axle at the origin, axle along X)
# ---------------------------------------------------------------------------------------

def wheel(name, width, front):
    p = Part(name)
    w = width / 2
    # Tire: a rounded cross-section spun around the axle. Tread blocks are little dips,
    # staggered left/right like a real scooter tire.
    prof = [(RIM_R - 0.004, -0.8 * w), (0.203, -0.98 * w), (0.226, -1.0 * w), (0.248, -0.92 * w),
            (0.262, -0.72 * w), (0.269, -0.38 * w), (0.271, 0.0), (0.269, 0.38 * w), (0.262, 0.72 * w),
            (0.248, 0.92 * w), (0.226, 1.0 * w), (0.203, 0.98 * w), (RIM_R - 0.004, 0.8 * w)]

    def tread(i, k):
        if k in (4, 5) and i % 3 == 0:
            return -0.006
        if k in (7, 8) and (i + 1) % 3 == 0:
            return -0.006
        if k == 6 and i % 6 == 2:
            return -0.003
        return 0.0
    revolve(p, prof, "Rubber", 72, bump=tread)

    # Rim hoop with lips on both sides
    rim = [(RIM_R - 0.02, -0.52 * w), (RIM_R + 0.008, -0.64 * w), (RIM_R + 0.011, -0.56 * w),
           (RIM_R - 0.003, -0.46 * w), (RIM_R - 0.003, 0.46 * w), (RIM_R + 0.011, 0.56 * w),
           (RIM_R + 0.008, 0.64 * w), (RIM_R - 0.02, 0.52 * w)]
    revolve(p, rim, "Rim", 40)
    # Hub
    hub_w = 0.55 * w
    revolve(p, [(0.012, -hub_w), (0.05, -hub_w), (0.055, -hub_w * 0.6), (0.055, hub_w * 0.6),
                (0.05, hub_w), (0.012, hub_w)], "Rim", 20)
    if not front:
        # rear drum brake housing on the left
        revolve(p, [(0.03, -w * 0.95), (0.088, -w * 0.95), (0.092, -w * 0.7), (0.06, -w * 0.4),
                    (0.03, -w * 0.4)], "Metal", 24)
    # 5 Y-shaped spokes
    for k in range(5):
        a = TAU * k / 5 + 0.3
        d = Vector((0, math.cos(a), math.sin(a)))
        bar(p, d * 0.045, d * 0.112, (1, 0, 0), 0.024, 0.026, "Rim")
        for side in (-1, 1):
            b = a + side * 0.2
            d2 = Vector((0, math.cos(b), math.sin(b)))
            bar(p, d * 0.105, d2 * (RIM_R - 0.008), (1, 0, 0), 0.02, 0.016, "Rim")
    # Axle nuts
    for side in (-1, 1):
        tube(p, (side * hub_w, 0, 0), (side * (hub_w + 0.016), 0, 0), 0.016, "Metal", sides=6, smooth=False)
    if front:
        # Brake disc on the left (a flat ring with a slotted edge look)
        x = -(hub_w + 0.006)
        revolve(p, [(0.062, x - 0.0025), (0.112, x - 0.0025), (0.112, x + 0.0025), (0.062, x + 0.0025)],
                "Disc", 36)
        for k in range(5):
            a = TAU * k / 5
            d = Vector((0, math.cos(a), math.sin(a)))
            bar(p, d * 0.03 + Vector((x, 0, 0)), d * 0.07 + Vector((x, 0, 0)), (1, 0, 0), 0.006, 0.016, "Rim")
    return p.build()


# ---------------------------------------------------------------------------------------
# Body (everything that doesn't steer or spin)
# ---------------------------------------------------------------------------------------

# Apron / leg shield sections, bottom to top: (z, center y, half width, front depth, back depth)
APRON = [(0.32, 0.305, 0.17, 0.04, 0.03), (0.42, 0.315, 0.20, 0.05, 0.03), (0.52, 0.355, 0.21, 0.085, 0.03),
         (0.62, 0.405, 0.21, 0.13, 0.035), (0.75, 0.42, 0.19, 0.12, 0.035), (0.88, 0.40, 0.15, 0.09, 0.035),
         (0.95, 0.39, 0.10, 0.06, 0.03), (0.975, 0.385, 0.05, 0.03, 0.02)]
APRON_N = 2.2


def apron_front(z, x):
    """How far forward the apron's front face is at height z, x meters from the middle."""
    for (z0, *a), (z1, *b) in zip(APRON, APRON[1:]):
        if z0 <= z <= z1:
            t = (z - z0) / (z1 - z0)
            cy, hw, df, _ = [u + (v - u) * t for u, v in zip(a, b)]
            c = min(abs(x) / hw, 1.0)
            return cy + df * (1.0 - c ** APRON_N) ** (1.0 / APRON_N)
    return APRON[-1][1]


def body():
    p = Part("Body")

    def paint_or_trim(c, nrm):
        return "Trim" if nrm.z < -0.55 else "Paint"

    # Under-seat body: (y, bottom z, top z, half width)
    cowl = [(-0.925, 0.69, 0.79, 0.10), (-0.88, 0.62, 0.805, 0.14), (-0.75, 0.53, 0.805, 0.175),
            (-0.55, 0.48, 0.80, 0.19), (-0.30, 0.44, 0.80, 0.19), (-0.10, 0.40, 0.80, 0.18),
            (0.02, 0.36, 0.74, 0.16), (0.10, 0.34, 0.62, 0.14), (0.14, 0.34, 0.52, 0.11)]
    rings = []
    for y, zb, zt, hw in catmull(cowl, 3):
        cz = (zb + zt) / 2
        rings.append(ring_y(y, 0.0, cz, hw, zt - cz, zt - cz, n=2.7, count=32))
    loft(p, rings, paint_or_trim)

    # Seat: two levels (rider + passenger hump)
    seat = [(-0.745, 0.78, 0.82, 0.08), (-0.69, 0.78, 0.855, 0.14), (-0.46, 0.78, 0.872, 0.155),
            (-0.30, 0.78, 0.848, 0.16), (-0.10, 0.78, 0.842, 0.17), (0.02, 0.76, 0.832, 0.16),
            (0.09, 0.72, 0.795, 0.12), (0.12, 0.72, 0.755, 0.06)]
    rings = []
    for y, zb, zt, hw in catmull(seat, 3):
        cz = (zb + zt) / 2
        rings.append(ring_y(y, 0.0, cz, hw, zt - cz, zt - cz, n=3.4, count=28))
    loft(p, rings, "Seat")
    # piping line along the seat edge
    edge = [(x * 0.165, y, 0.795) for x, y in ((-1, 0.0), (-1.0, -0.3), (-0.95, -0.6), (-0.6, -0.72))]
    for side in (-1, 1):
        sweep(p, [Vector((side * abs(a), b, c)) for a, b, c in catmull(edge, 3)], circle(0.006, 6), "Trim")

    # Leg shield / front apron (lofted bottom to top)
    def apron_mat(c, nrm):
        if nrm.y < -0.55:
            return "Trim"     # rider side
        return "Paint"
    rows = catmull([tuple(r) for r in APRON], 2)
    rings = [ring_z(z, 0.0, cy, hw, df, db, n=APRON_N, count=32) for z, cy, hw, df, db in rows]
    loft(p, rings, apron_mat)
    # badge + front turn signals
    rbox(p, (0, apron_front(0.86, 0) + 0.002, 0.86), (0.07, 0.012, 0.022), "Chrome", bevel=0.005)
    for side in (-1, 1):
        x = side * 0.125
        rbox(p, (x, apron_front(0.80, x) - 0.008, 0.80), (0.07, 0.03, 0.026), "Signal", bevel=0.01,
             rot=(0, 0, side * -25))

    # Floorboard with rubber ribs, and the dark underbody
    rbox(p, (0, 0.20, 0.335), (0.36, 0.30, 0.05), "Trim", bevel=0.015)
    for k in range(5):
        rbox(p, (0, 0.09 + k * 0.055, 0.3625), (0.29, 0.014, 0.008), "Rubber", bevel=0.003, segs=1)
    rbox(p, (0, -0.08, 0.275), (0.22, 0.50, 0.09), "Trim", bevel=0.02)
    rbox(p, (-0.02, 0.02, 0.255), (0.2, 0.16, 0.12), "DarkMetal", bevel=0.02)

    # Side vents and emblems
    for side in (-1, 1):
        for k in range(3):
            rbox(p, (side * 0.165, 0.0, 0.53 + k * 0.025), (0.012, 0.10, 0.012), "Trim", bevel=0.004, segs=1,
                 rot=(0, 0, side * 12))
        rbox(p, (side * 0.19, -0.38, 0.64), (0.008, 0.13, 0.026), "Chrome", bevel=0.003, segs=1)

    # Grab rail (black) with its posts
    rail = [(-0.16, -0.40, 0.80), (-0.172, -0.58, 0.812), (-0.152, -0.76, 0.83), (-0.08, -0.852, 0.836),
            (0.0, -0.866, 0.837), (0.08, -0.852, 0.836), (0.152, -0.76, 0.83), (0.172, -0.58, 0.812),
            (0.16, -0.40, 0.80)]
    sweep(p, catmull(rail, 4), circle(0.015, 10), "Trim")
    for side in (-1, 1):
        for y in (-0.45, -0.72):
            tube(p, (side * 0.166, y, 0.81), (side * 0.15, y, 0.70), 0.012, "Trim", sides=8)

    # Tail light and rear turn signals
    rbox(p, (0, -0.928, 0.745), (0.175, 0.03, 0.055), "TailLight", bevel=0.012)
    for side in (-1, 1):
        rbox(p, (side * 0.125, -0.895, 0.70), (0.055, 0.03, 0.026), "Signal", bevel=0.01, rot=(0, 0, side * 20))

    # Plate holder + license plate
    rbox(p, (0, -0.96, 0.60), (0.12, 0.17, 0.012), "Trim", bevel=0.004, rot=(45, 0, 0))
    rbox(p, (0, -1.03, 0.53), (0.215, 0.006, 0.13), "Trim", bevel=0.004, rot=(-12, 0, 0))
    rbox(p, (0, -1.035, 0.53), (0.2, 0.006, 0.115), "Plate", bevel=0.004, rot=(-12, 0, 0))

    # Rear hugger (mudguard over the rear wheel)
    arc = [(0, RW.y + 0.30 * math.cos(math.radians(a)), RW.z + 0.30 * math.sin(math.radians(a)))
           for a in range(60, 165, 7)]
    sweep(p, arc, rrect(0.006, 0.07), "Trim")

    # CVT / swingarm case on the left: (y, center z, half width, top, bottom)
    cvt = [(0.06, 0.30, 0.04, 0.06, 0.06), (0.0, 0.31, 0.055, 0.095, 0.09), (-0.15, 0.31, 0.06, 0.09, 0.085),
           (-0.40, 0.295, 0.055, 0.075, 0.07), (-0.60, 0.275, 0.05, 0.06, 0.06), (-0.68, 0.27, 0.04, 0.045, 0.045)]
    rings = [ring_y(y, -0.13, cz, hw, ht, hb, n=3.0, count=24) for y, cz, hw, ht, hb in catmull(cvt, 2)]
    loft(p, rings, "Metal")
    for k in range(4):
        rbox(p, (-0.187, -0.25, 0.27 + k * 0.022), (0.008, 0.32, 0.008), "DarkMetal", bevel=0.003, segs=1)
    rbox(p, (-0.12, -0.32, 0.44), (0.09, 0.34, 0.08), "Trim", bevel=0.02)   # air filter box

    # Rear shock with a red coil spring (left side)
    s0, s1 = Vector((-0.125, -0.62, 0.34)), Vector((-0.125, -0.52, 0.62))
    tube(p, s0, s1, 0.014, "DarkMetal", sides=10)
    tube(p, s0 + Vector((0.02, 0, 0)), s0 - Vector((0.02, 0, 0)), 0.018, "DarkMetal", sides=10)
    ax = (s1 - s0).normalized()
    ux = Vector((1, 0, 0))
    uy = ax.cross(ux)
    a0, a1 = s0 + ax * 0.04, s1 - ax * 0.10
    turns, steps = 6, 6 * 14
    helix = []
    for i in range(steps + 1):
        t = i / steps
        ang = t * turns * TAU
        helix.append(a0 + (a1 - a0) * t + (ux * math.cos(ang) + uy * math.sin(ang)) * 0.03)
    sweep(p, helix, circle(0.0055, 6), "Spring")

    # Exhaust on the right: header pipe, muffler, chrome heat shield and tip
    header = [(0.03, 0.12, 0.20), (0.08, 0.02, 0.20), (0.13, -0.12, 0.24), (0.165, -0.24, 0.29)]
    sweep(p, catmull(header, 3), circle(0.018, 10), "DarkMetal")
    m0, m1 = Vector((0.165, -0.24, 0.29)), Vector((0.178, -0.80, 0.41))
    path = [m0 + (m1 - m0) * (i / 8) for i in range(9)]
    sweep(p, path, circle(0.055, 18), "DarkMetal", scales=[0.45, 0.85, 1, 1, 1, 1, 1, 0.92, 0.7])
    shield = [(0.064 * math.sin(math.radians(a)), -0.064 * math.cos(math.radians(a))) for a in range(-75, 80, 15)]
    shield += [(0.058 * math.sin(math.radians(a)), -0.058 * math.cos(math.radians(a))) for a in range(75, -80, -15)]
    sweep(p, [m0 + (m1 - m0) * t for t in (0.22, 0.4, 0.6, 0.78)], shield, "Metal", up=Vector((0, 0, 1)))
    tip0 = m1 - (m1 - m0).normalized() * 0.01
    tip1 = m1 + (m1 - m0).normalized() * 0.05
    tube(p, tip0, tip1, 0.021, "Chrome", sides=14)
    tube(p, tip1, tip1 + (m1 - m0).normalized() * 0.002, 0.015, "Trim", sides=14)
    bar(p, (0.085, -0.38, 0.30), (0.085, -0.62, 0.27), (1, 0, 0), 0.02, 0.04, "DarkMetal")   # right swingarm

    # Side stand (folded) and passenger foot pegs
    stand = [(-0.10, 0.02, 0.24), (-0.15, -0.10, 0.21), (-0.19, -0.22, 0.19)]
    sweep(p, catmull(stand, 2), circle(0.011, 8), "DarkMetal")
    rbox(p, (-0.195, -0.235, 0.188), (0.03, 0.04, 0.015), "DarkMetal", bevel=0.004, segs=1)
    for side in (-1, 1):
        rbox(p, (side * 0.18, -0.33, 0.43), (0.04, 0.05, 0.04), "Trim", bevel=0.01)
        rbox(p, (side * 0.222, -0.33, 0.42), (0.07, 0.035, 0.022), "Rubber", bevel=0.008)
    return p.build()


# ---------------------------------------------------------------------------------------
# Front end (turns with the handlebar). Built in world space with the bars straight.
# ---------------------------------------------------------------------------------------
H = steer_pt(0.77)   # handlebar clamp point (about z = 1.0)


def mirror_frame(side):
    """Where the mirror sits and which way it turns (a bit outward)."""
    center = Vector((side * 0.315, H.y + 0.012, 1.205))
    rot = Matrix.Rotation(side * 0.25, 3, "Z")
    return center, rot


def front_body():
    p = Part("FrontBody")

    # Telescopic fork: dark sliders below, chrome tubes above
    for side in (-1, 1):
        x = side * 0.072
        tube(p, steer_pt(-0.04, x), steer_pt(0.22, x), 0.024, "DarkMetal", sides=12)
        tube(p, steer_pt(0.22, x), steer_pt(0.56, x), 0.018, "Chrome", sides=12)
    tube(p, (-0.095, FW.y, FW.z), (0.095, FW.y, FW.z), 0.011, "Metal", sides=8)
    tube(p, steer_pt(0.55), steer_pt(0.76), 0.022, "DarkMetal", sides=10)

    # Front fender hugging the tire
    arc = [(0, FW.y + 0.30 * math.cos(math.radians(a)), FW.z + 0.30 * math.sin(math.radians(a)))
           for a in range(18, 140, 6)]
    sweep(p, arc, rrect(0.007, 0.066, n=16, e=4.0), "Paint")

    # Brake caliper + hose (left)
    cal = FW + Vector((-0.05, 0.10 * math.cos(math.radians(118)), 0.10 * math.sin(math.radians(118))))
    rbox(p, cal, (0.032, 0.055, 0.075), "Caliper", bevel=0.01, rot=(-28, 0, 0))
    hose = [cal + Vector((-0.01, 0.0, 0.04)), (-0.095, 0.56, 0.52), (-0.10, 0.50, 0.70), (-0.08, 0.45, 0.86)]
    sweep(p, catmull([tuple(h) for h in hose], 3), circle(0.005, 6), "Rubber")

    # Handlebar cover (front cowl), lofted left to right: (x, center y, center z, front, back, top, bottom)
    cover = [(-0.19, 0.432, 1.02, 0.05, 0.04, 0.026, 0.026), (-0.17, 0.432, 1.02, 0.09, 0.07, 0.046, 0.045),
             (-0.12, 0.432, 1.02, 0.115, 0.082, 0.057, 0.052), (0.0, 0.432, 1.02, 0.12, 0.085, 0.06, 0.055),
             (0.12, 0.432, 1.02, 0.115, 0.082, 0.057, 0.052), (0.17, 0.432, 1.02, 0.09, 0.07, 0.046, 0.045),
             (0.19, 0.432, 1.02, 0.05, 0.04, 0.026, 0.026)]

    def cover_mat(c, nrm):
        if nrm.z < -0.5:
            return "Trim"
        if nrm.y < -0.55 and c.z > 1.0:
            return "Trim"
        return "Paint"
    rings = [ring_x(x, cy, cz, df, db, ht, hb, n=2.6, count=28) for x, cy, cz, df, db, ht, hb in catmull(cover, 2)]
    loft(p, rings, cover_mat)

    # Headlight: chrome bezel + domed lens
    hl_z = 1.005
    loft(p, [ring_y(0.528, 0, hl_z, 0.09, 0.04, 0.04, n=3.2, count=24),
             ring_y(0.553, 0, hl_z, 0.09, 0.04, 0.04, n=3.2, count=24)], "Chrome", cap0=False, cap1=False)
    lens = [(0.53, 1.0), (0.553, 0.97), (0.561, 0.88), (0.566, 0.6)]
    loft(p, [ring_y(y, 0, hl_z, 0.085 * s, 0.035 * s, 0.035 * s, n=3.2, count=24) for y, s in lens],
         "HeadLight", cap0=True, cap1=True)

    # Dashboard on the back-top of the cover
    rbox(p, (0, 0.385, 1.068), (0.16, 0.085, 0.014), "Trim", bevel=0.006, rot=(32, 0, 0))
    rbox(p, (0, 0.381, 1.075), (0.12, 0.06, 0.006), "Glass", bevel=0.003, segs=1, rot=(32, 0, 0))

    # Handlebar, grips, bar ends, switch boxes, levers
    for side in (-1, 1):
        tube(p, (side * 0.15, H.y - 0.005, 1.02), (side * 0.37, H.y - 0.03, 1.025), 0.011, "Metal", sides=10)
        g0, g1 = Vector((side * 0.25, H.y - 0.019, 1.023)), Vector((side * 0.355, H.y - 0.03, 1.025))
        sweep(p, [g0 + (g1 - g0) * (i / 6) for i in range(7)], circle(0.018, 12), "Rubber",
              scales=[1.2, 1.0, 1.04, 1.0, 1.04, 1.0, 1.0])
        tube(p, g1, g1 + Vector((side * 0.02, -0.002, 0)), 0.02, "Chrome", sides=12)
        rbox(p, (side * 0.228, H.y - 0.015, 1.024), (0.04, 0.05, 0.045), "Trim", bevel=0.01)
        rbox(p, (side * 0.232, H.y + 0.03, 1.036), (0.035, 0.035, 0.03), "Trim", bevel=0.008)
        lever = [(side * 0.235, H.y + 0.045, 1.032), (side * 0.29, H.y + 0.062, 1.026), (side * 0.36, H.y + 0.05, 1.02)]
        sweep(p, catmull(lever, 3), rrect(0.005, 0.009, n=8), "Metal")
    rbox(p, (0.205, H.y, 1.058), (0.045, 0.032, 0.03), "Trim", bevel=0.008)   # brake fluid cup

    # Mirror stalks + housings (the game puts the live mirror picture on the back)
    for side in (-1, 1):
        stalk = [(side * 0.15, H.y, 1.06), (side * 0.21, H.y, 1.10), (side * 0.29, H.y + 0.01, 1.165)]
        sweep(p, catmull(stalk, 3), circle(0.008, 8), "Trim")
        center, rot = mirror_frame(side)
        shell = [(-0.022, 0.074, 0.048), (-0.012, 0.077, 0.051), (0.01, 0.07, 0.044), (0.026, 0.048, 0.03),
                 (0.033, 0.026, 0.017)]
        rings = []
        for ly, hw, hh in shell:
            rings.append([center + rot @ v for v in ring_y(ly, 0, 0, hw, hh, hh, n=2.4, count=20)])
        loft(p, rings, "Trim")
    return p.build()


# ---------------------------------------------------------------------------------------

def empty(name, world, parent=None):
    e = bpy.data.objects.new(name, None)
    e.empty_display_type = "PLAIN_AXES"
    e.empty_display_size = 0.05
    bpy.context.collection.objects.link(e)
    set_parent(e, parent, world)
    return e


def set_parent(obj, parent, world):
    """Parent obj while keeping it at `world` (a 4x4 matrix in world space)."""
    if parent is None:
        obj.matrix_basis = world
        return
    obj.parent = parent
    obj.matrix_parent_inverse = Matrix.Identity(4)
    obj.matrix_basis = WORLD[parent.name].inverted() @ world
    WORLD[obj.name] = world


WORLD = {}


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    make_materials()
    print("Building scooter:")
    body()
    rear = wheel("RearWheel", 0.11, front=False)
    rear.matrix_basis = Matrix.Translation(RW)

    pivot_world = Matrix.Translation(FW) @ Matrix.Rotation(RAKE, 4, "X")
    pivot = empty("SteerPivot", pivot_world)
    WORLD["SteerPivot"] = pivot_world
    fork = empty("Fork", pivot_world, pivot)
    front = front_body()
    set_parent(front, fork, Matrix.Identity(4))
    fw = wheel("FrontWheel", 0.09, front=True)
    set_parent(fw, fork, Matrix.Translation(FW))
    for side, name in ((-1, "MirrorL"), (1, "MirrorR")):
        center, rot = mirror_frame(side)
        glass = center + rot @ Vector((0, -0.025, 0))
        empty(name, Matrix.Translation(glass) @ rot.to_4x4(), fork)
    empty("HeadlightMount", Matrix.Translation(Vector((0, 0.57, 1.005))), fork)

    tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in bpy.data.objects if o.type == "MESH")
    print("Total: %d triangles" % tris)
    os.makedirs(OUT_DIR, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT_DIR, "scooter.blend"))
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT_DIR, "scooter.glb"), export_format="GLB")
    print("Saved:", OUT_DIR)


main()
