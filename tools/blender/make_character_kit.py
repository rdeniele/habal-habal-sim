"""Habal-Habal Simulator - character parts kit (original low-poly models).

Builds every body part the game's CharacterModel uses, in an early-2000s low-poly style
(about 1,500 triangles per person), and exports them to one .glb file.
Also saves a .blend so you can open the parts in Blender and tweak them by hand.

Run without opening Blender's window (from the project folder):
    "D:\\Tools\\Blender\\blender-5.3.0-windows-x64\\blender.exe" -b -P tools/blender/make_character_kit.py

Output:
    assets/characters/character_kit.glb    (the game loads this)
    assets/characters/character_kit.blend  (for editing in Blender)

Conventions (so the parts fit the game's skeleton):
  - Blender Z is up, the character faces +Y (glTF turns that into Godot's -Z = forward).
  - Every part's origin (0,0,0) is its JOINT: limbs hang down -Z from the shoulder/elbow/hip/knee,
    the torso and hips start at the hip height line, the head's origin is its center.
  - UVs wrap around each part like a label on a can: u = around (0.5 = front), v = 0 top -> 1 bottom.
    The game paints faces and clothes onto that layout.
"""
import bpy
import bmesh
import math
import os
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.normpath(os.path.join(HERE, "..", "..", "assets", "characters"))
TAU = math.tau

# Same measurements as scenes/common/character_model.gd (meters, adult)
THIGH = 0.44
SHIN = 0.42
UPPER_ARM = 0.28
FOREARM = 0.25
HEAD_TOP = 0.128      # head extents (relative to head center) - must match the face texture
HEAD_BOTTOM = -0.125


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for m in list(bpy.data.meshes):
        bpy.data.meshes.remove(m)


def smoothstep(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


# ---------------------------------------------------------------------------------------
# The one tool we need: a "loft". A list of rings (cross-sections) from top to bottom; each
# ring is a function angle -> (x, y, z). angle 0 = front (+Y), it goes around to the back.
# ---------------------------------------------------------------------------------------

def loft(name, rings, sides, cap_top=True, cap_bottom=True, v_range=None):
    """rings: list of callables ring(a) -> (x, y, z), ordered TOP to BOTTOM."""
    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")
    grid = []
    for ring in rings:
        row = []
        for i in range(sides):
            u = i / sides
            a = (u - 0.5) * TAU   # u = 0.5 -> front
            row.append(bm.verts.new(ring(a)))
        grid.append(row)
    zs = [v.co.z for row in grid for v in row]
    z_top, z_bot = (v_range if v_range else (max(zs), min(zs)))
    span = max(z_top - z_bot, 1e-6)

    def v_of(z):
        return (z_top - z) / span

    for r in range(len(grid) - 1):
        top, bot = grid[r], grid[r + 1]
        for i in range(sides):
            j = (i + 1) % sides
            f = bm.faces.new((top[i], top[j], bot[j], bot[i]))
            u0, u1 = i / sides, (i + 1) / sides
            for loop, (u, vert) in zip(f.loops, ((u0, top[i]), (u1, top[j]), (u1, bot[j]), (u0, bot[i]))):
                loop[uv_layer].uv = (u, 1.0 - v_of(vert.co.z))   # Blender UV y is flipped vs. Godot
    for cap, row in ((cap_top, grid[0]), (cap_bottom, grid[-1])):
        if not cap:
            continue
        cx = sum(v.co.x for v in row) / sides
        cy = sum(v.co.y for v in row) / sides
        cz = sum(v.co.z for v in row) / sides
        center = bm.verts.new((cx, cy, cz))
        for i in range(sides):
            j = (i + 1) % sides
            f = bm.faces.new((row[i], row[j], center))
            for loop in f.loops:
                vert = loop.vert
                u = (i + 0.5) / sides if vert is center else (i / sides if vert is row[i] else (i + 1) / sides)
                loop[uv_layer].uv = (u, 1.0 - v_of(vert.co.z))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:
        f.smooth = True
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def ellipse(z, rx, ry_front, ry_back=None, cx=0.0, cy=0.0, shape=None):
    """A ring: ellipse at height z, front/back depth can differ. shape(a) can add bumps (meters)."""
    ry_back = ry_front if ry_back is None else ry_back

    def ring(a):
        s, c = math.sin(a), math.cos(a)
        ry = ry_front if c > 0 else ry_back
        x, y = s * rx, c * ry
        if shape:
            dx, dy, dz = shape(a)
            return (cx + x + dx, cy + y + dy, z + dz)
        return (cx + x, cy + y, z)
    return ring


def cylinder_uv(obj, z_top=HEAD_TOP, z_bottom=HEAD_BOTTOM):
    """Re-wrap UVs around the Z axis from each vertex position (so joined pieces like ears land on
    the right spot of the face texture). u = 0.5 at the front (+Y), v = 0 at z_top."""
    me = obj.data
    uv = me.uv_layers.active.data
    for poly in me.polygons:
        us = []
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            us.append(math.atan2(co.x, co.y) / TAU + 0.5)
        if max(us) - min(us) > 0.5:          # face crosses the seam at the back: keep it in one piece
            us = [u + 1.0 if u < 0.5 else u for u in us]
        for li, u in zip(poly.loop_indices, us):
            co = me.vertices[me.loops[li].vertex_index].co
            uv[li].uv = (u, 1.0 - (z_top - co.z) / (z_top - z_bottom))


def mirrored_copy(src, name):
    """Copy of a mesh mirrored left/right, with the faces turned the right way out."""
    me = src.data.copy()
    me.name = name
    for v in me.vertices:
        v.co.x = -v.co.x
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.reverse_faces(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(obj)
    return obj


def join(name, objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    objs[0].name = name
    objs[0].data.name = name
    return objs[0]


# ---------------------------------------------------------------------------------------
# Head (origin = head center). Jaw, cheekbones, brow, nose bump, ears.
# ---------------------------------------------------------------------------------------

def head():
    def bumps(z):
        def shape(a):
            front = max(0.0, math.cos(a))
            dy = 0.0
            # nose: narrow bump in the middle of the face
            if -0.06 < z < 0.0:
                dy += 0.022 * math.exp(-(a / 0.22) ** 2) * smoothstep(-0.06, -0.03, z) * (1 - smoothstep(-0.012, 0.0, z))
            # brow ridge
            if 0.015 < z < 0.045:
                dy += 0.007 * front ** 4
            # cheekbones
            if -0.05 < z < -0.01:
                dy += 0.006 * math.exp(-((abs(a) - 0.75) / 0.25) ** 2)
            return (0.0, dy, 0.0)
        return shape

    rings = [
        # z, half width, front depth, back depth
        (0.128, 0.0005, 0.0005, 0.0005),
        (0.118, 0.055, 0.05, 0.06),
        (0.095, 0.092, 0.085, 0.098),
        (0.06, 0.108, 0.1, 0.112),
        (0.03, 0.112, 0.106, 0.113),
        (0.0, 0.11, 0.108, 0.11),
        (-0.03, 0.104, 0.104, 0.104),
        (-0.06, 0.092, 0.098, 0.094),      # cheeks
        (-0.08, 0.08, 0.092, 0.078),       # jaw line
        (-0.1, 0.058, 0.084, 0.05),
        (-0.115, 0.036, 0.07, 0.03),       # chin (squarer, a bit forward)
        (-0.125, 0.0005, 0.03, 0.0005),
    ]
    obj = loft("head", [ellipse(z, rx, f, b, shape=bumps(z)) for z, rx, f, b in rings], 16,
               cap_top=False, cap_bottom=False, v_range=(HEAD_TOP, HEAD_BOTTOM))
    ears = []
    for side in (-1, 1):
        e = loft("ear", [ellipse(z, 0.012, w, w * 0.6) for z, w in ((0.02, 0.012), (0.0, 0.022), (-0.03, 0.02), (-0.045, 0.008))],
                 6, v_range=(HEAD_TOP, HEAD_BOTTOM))
        e.location = (side * 0.107, -0.005, 0.0)
        bpy.context.view_layer.objects.active = e
        e.select_set(True)
        bpy.ops.object.transform_apply(location=True)
        ears.append(e)
    h = join("head", [obj] + ears)
    cylinder_uv(h)
    return h


# ---------------------------------------------------------------------------------------
# Torso (origin = hip line, goes up to the neck). Chest, shoulders, back, belly.
# ---------------------------------------------------------------------------------------

def torso(name, female=False, heavy=False):
    sh = 0.175 if female else 0.2            # shoulder half width (joint position)
    waist = 0.125 if female else 0.142
    belly = 0.045 if heavy else 0.0
    wide = 0.025 if heavy else 0.0

    def chest(z):
        def shape(a):
            front = max(0.0, math.cos(a))
            dy = 0.0
            if female and 0.3 < z < 0.46:
                k = math.sin((z - 0.3) / 0.16 * math.pi)
                dy += 0.035 * k * math.exp(-((abs(a) - 0.38) / 0.28) ** 2)
            if heavy and 0.03 < z < 0.34:
                dy += belly * math.sin((z - 0.03) / 0.31 * math.pi) * front ** 0.8
            return (0.0, dy, 0.0)
        return shape

    rings = [
        (0.585, 0.05, 0.045, 0.045),                         # neck hole
        (0.565, sh - 0.075, 0.085, 0.08),                    # top of shoulders (traps)
        (0.53, sh + 0.035 + wide, 0.1, 0.095),               # shoulder caps
        (0.47, sh + 0.025 + wide, 0.112, 0.1),               # chest
        (0.38, sh - 0.005 + wide, 0.108, 0.098),
        (0.28, waist + 0.02 + wide, 0.1, 0.092),             # ribs
        (0.22, waist + 0.01 + wide, 0.097, 0.09),
        (0.17, waist + wide, 0.094 + belly * 0.3, 0.088),    # waist
        (0.12, waist + 0.002 + wide, 0.094, 0.089),
        (0.07, waist + 0.006 + wide, 0.094, 0.09),
        (0.0, waist + 0.012 + wide, 0.096, 0.092),           # hip line
    ]
    return loft(name, [ellipse(z, rx, f, b, shape=chest(z)) for z, rx, f, b in rings], 14, cap_top=True, cap_bottom=True)


def pelvis(name, female=False, heavy=False):
    w = (0.16 if female else 0.148) + (0.02 if heavy else 0.0)
    # top ring sits INSIDE the torso's bottom so the shirt always covers the waistband
    rings = [(0.0, w - 0.03, 0.08, 0.076), (-0.05, w + 0.004, 0.098, 0.1 if not female else 0.11),
             (-0.11, w - 0.01, 0.09, 0.098), (-0.15, w - 0.05, 0.07, 0.07)]
    return loft(name, [ellipse(z, rx, f, b) for z, rx, f, b in rings], 12)


# ---------------------------------------------------------------------------------------
# Limbs (origin = joint, hanging down -Z)
# ---------------------------------------------------------------------------------------

def limb(name, length, profile, sides=8, cap_top=True):
    """profile: list of (t 0..1 along the limb, half width, front depth, back depth)."""
    return loft(name, [ellipse(-t * length, rx, f, b) for t, rx, f, b in profile], sides, cap_top=cap_top)


def upper_arm():
    return limb("upper_arm", UPPER_ARM, [(-0.12, 0.03, 0.03, 0.03), (0.0, 0.056, 0.052, 0.052), (0.25, 0.054, 0.056, 0.05),
                                         (0.5, 0.05, 0.054, 0.046), (0.8, 0.042, 0.042, 0.042), (1.0, 0.038, 0.038, 0.04)])


def forearm():
    return limb("forearm", FOREARM, [(-0.05, 0.036, 0.036, 0.038), (0.2, 0.044, 0.044, 0.042), (0.5, 0.039, 0.036, 0.036),
                                     (1.0, 0.03, 0.026, 0.026)])


def sleeve(name, length):
    """Cloth tube over the upper arm (short sleeves). Slightly flared opening."""
    return limb(name, length, [(-0.18, 0.035, 0.035, 0.035), (0.0, 0.064, 0.06, 0.06), (0.6, 0.062, 0.062, 0.058),
                               (1.0, 0.066, 0.066, 0.062)], sides=10, cap_top=True)


def thigh():
    return limb("thigh", THIGH, [(-0.05, 0.07, 0.07, 0.07), (0.08, 0.088, 0.09, 0.09), (0.35, 0.08, 0.088, 0.08),
                                 (0.75, 0.066, 0.066, 0.064), (1.0, 0.06, 0.06, 0.058)])


def shin():
    return limb("shin", SHIN, [(-0.04, 0.058, 0.058, 0.056), (0.15, 0.058, 0.054, 0.066), (0.35, 0.056, 0.05, 0.068),
                               (0.7, 0.044, 0.042, 0.046), (1.0, 0.038, 0.04, 0.038)])


def shorts_leg():
    """Wide cloth tube for shorts (over the thigh)."""
    return limb("shorts_leg", THIGH * 0.62, [(-0.05, 0.088, 0.088, 0.088), (0.2, 0.098, 0.1, 0.098), (1.0, 0.094, 0.094, 0.092)],
                sides=10)


def fist():
    """A closed fist (origin = wrist). Knuckles at the front of the hand, thumb across."""
    hand = loft("fist", [ellipse(z, rx, f, b) for z, rx, f, b in
                         [(0.005, 0.026, 0.022, 0.022), (-0.03, 0.036, 0.026, 0.024), (-0.07, 0.038, 0.032, 0.026),
                          (-0.095, 0.034, 0.03, 0.024), (-0.105, 0.02, 0.018, 0.015)]], 8)
    thumb = loft("thumb", [ellipse(z, 0.012, 0.013, 0.013, cx=-0.028, cy=0.012) for z in (-0.02, -0.045, -0.065)], 6)
    return join("fist", [hand, thumb])


def shoe(name, slipper=False):
    """Origin = ankle. The foot points forward (+Y)."""
    objs = []
    if slipper:
        sole = loft(name + "_sole", [ellipse(z, 0.05, 0.13, 0.11, cy=0.05) for z in (-0.06, -0.075)], 10)
        strap = loft(name + "_strap", [ellipse(z, 0.046, 0.04, 0.03, cy=0.08) for z in (-0.04, -0.06)], 8, cap_top=False, cap_bottom=False)
        objs = [sole, strap]
    else:
        # sneaker: lofted along the length of the foot (rings across, from heel to toe)
        bm_rings = []
        for t, half_w, top, bottom in [(0.0, 0.035, -0.02, -0.085), (0.25, 0.048, -0.03, -0.088), (0.55, 0.052, -0.05, -0.088),
                                       (0.85, 0.048, -0.06, -0.088), (1.0, 0.03, -0.068, -0.086)]:
            y = -0.06 + t * 0.26
            mid = (top + bottom) / 2
            hz = (top - bottom) / 2

            def ring(a, y=y, w=half_w, mid=mid, hz=hz):
                return (math.sin(a) * w, y, mid + math.cos(a) * hz)
            bm_rings.append(ring)
        body = loft(name + "_body", bm_rings, 8)
        objs = [body]
    return join(name, objs)


def neck():
    return limb("neck", 0.09, [(-0.6, 0.044, 0.044, 0.044), (0.0, 0.05, 0.05, 0.052), (1.0, 0.056, 0.054, 0.058)], sides=8)


def skirt(name, length, flare):
    return limb(name, length, [(0.0, 0.15, 0.1, 0.1), (0.5, 0.15 + flare * 0.5, 0.11 + flare * 0.4, 0.11 + flare * 0.4),
                               (1.0, 0.15 + flare, 0.12 + flare * 0.8, 0.12 + flare * 0.8)], sides=12, cap_top=False)


def collar():
    return loft("collar", [ellipse(z, rx, f, b, cy=-0.002) for z, rx, f, b in [(0.03, 0.062, 0.058, 0.06), (0.0, 0.07, 0.07, 0.066)]],
                12, cap_top=False, cap_bottom=False)


# ---------------------------------------------------------------------------------------
# Hair (origin = head center). Shells a bit bigger than the head, cut at the hairline.
# ---------------------------------------------------------------------------------------

def hair_shell(name, scale, front_line, back_line, bumpy=0.0, sides=16):
    """front_line/back_line: lowest z of the hair at the forehead / at the back of the head."""
    def line(a):
        front = (math.cos(a) + 1) / 2         # 1 front .. 0 back
        return back_line + (front_line - back_line) * front ** 1.6

    head_rings = [(0.128, 0.0005, 0.0005, 0.0005), (0.118, 0.055, 0.05, 0.06), (0.095, 0.092, 0.085, 0.098),
                  (0.06, 0.108, 0.1, 0.112), (0.03, 0.112, 0.106, 0.113), (0.0, 0.11, 0.108, 0.11),
                  (-0.03, 0.104, 0.104, 0.104), (-0.06, 0.095, 0.098, 0.096), (-0.085, 0.082, 0.09, 0.083)]

    def head_at(z):
        z = min(z, head_rings[0][0])   # above the crown = the crown (no wide ring on top)
        for k in range(len(head_rings) - 1):
            z0, x0, f0, b0 = head_rings[k]
            z1, x1, f1, b1 = head_rings[k + 1]
            if z1 <= z <= z0:
                t = (z0 - z) / (z0 - z1)
                return x0 + (x1 - x0) * t, f0 + (f1 - f0) * t, b0 + (b1 - b0) * t
        return head_rings[-1][1:]

    steps = 7
    rings = []
    for k in range(steps):
        def ring(a, k=k):
            low = line(a)
            z = 0.131 + (low - 0.131) * (k / (steps - 1))
            rx, f, b = head_at(z)
            c = math.cos(a)
            ry = f if c > 0 else b
            bump = 1.0 + bumpy * (0.5 + 0.5 * math.sin(a * 7 + k * 1.7))
            s = scale * bump
            return (math.sin(a) * rx * s, c * ry * s, z)
        rings.append(ring)
    return loft(name, rings, sides, cap_top=False, cap_bottom=False, v_range=(HEAD_TOP, HEAD_BOTTOM))


def hair_parts():
    out = []
    out.append(hair_shell("hair_short", 1.07, 0.075, -0.05))
    out.append(hair_shell("hair_buzz", 1.035, 0.07, -0.035))
    out.append(hair_shell("hair_curly", 1.12, 0.078, -0.045, bumpy=0.05))
    side = hair_shell("hair_side", 1.08, 0.07, -0.055)
    # side part: a swoop of hair over one side of the forehead
    sweep = loft("swoop", [ellipse(z, 0.05, 0.03, 0.03, cx=-0.03, cy=0.08) for z in (0.11, 0.085, 0.06)], 6)
    out.append(join("hair_side", [side, sweep]))
    # long hair: the cap + a panel down the back to the shoulders
    cap = hair_shell("hair_long_cap", 1.08, 0.08, -0.06)
    back = limb("hair_long_back", 0.26, [(0.0, 0.11, 0.0, 0.08), (0.5, 0.115, -0.02, 0.07), (1.0, 0.1, -0.03, 0.045)], sides=10)
    back.location = (0, -0.0, -0.02)
    out.append(join("hair_long", [cap, back]))
    cap = hair_shell("hair_bob_cap", 1.09, 0.08, -0.07)
    bob = limb("hair_bob_back", 0.11, [(0.0, 0.118, 0.06, 0.12), (1.0, 0.115, 0.05, 0.11)], sides=12)
    bob.location = (0, 0, -0.04)
    out.append(join("hair_bob", [cap, bob]))
    cap = hair_shell("hair_pony_cap", 1.065, 0.08, -0.05)
    tail = limb("hair_tail", 0.22, [(0.0, 0.03, 0.03, 0.03), (0.4, 0.035, 0.035, 0.035), (1.0, 0.012, 0.012, 0.012)], sides=6)
    tail.location = (0, -0.13, -0.02)
    tail.rotation_euler = (math.radians(-25), 0, 0)
    out.append(join("hair_ponytail", [cap, tail]))
    cap = hair_shell("hair_bun_cap", 1.065, 0.08, -0.05)
    bun = loft("bun", [ellipse(z, r, r, r, cy=-0.1) for z, r in ((0.17, 0.01), (0.15, 0.05), (0.11, 0.06), (0.075, 0.04), (0.06, 0.01))], 8)
    out.append(join("hair_bun", [cap, bun]))
    for o in out:
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.select_all(action="DESELECT")
        o.select_set(True)
        bpy.ops.object.transform_apply(location=True, rotation=True)
    return out


# ---------------------------------------------------------------------------------------
# Rider gear and extra clothes: messy hair, rider ponytail, hood, baggy cargo pants with
# pockets, glove cuffs, backpack with straps, cap, cane.
# ---------------------------------------------------------------------------------------

def to_object(name, bm):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:
        f.smooth = True
    if not bm.loops.layers.uv:
        bm.loops.layers.uv.new("UVMap")
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(obj)
    return obj


def tuft(name, base, direction, r, length, sides=5):
    """A pointed clump of hair: a small cone from `base` along `direction`."""
    d = Vector(direction).normalized()
    base = Vector(base)
    ref = Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0))
    u = d.cross(ref).normalized()
    w = d.cross(u)
    bm = bmesh.new()
    ring = [bm.verts.new(base + (u * math.cos(TAU * i / sides) + w * math.sin(TAU * i / sides)) * r) for i in range(sides)]
    tip = bm.verts.new(base + d * length)
    back = bm.verts.new(base - d * r * 0.6)
    for i in range(sides):
        j = (i + 1) % sides
        bm.faces.new((ring[i], ring[j], tip))
        bm.faces.new((ring[j], ring[i], back))
    return to_object(name, bm)


def band(name, points, width, thick):
    """A flat strap following points (width along X), like a backpack strap."""
    pts = [Vector(p) for p in points]
    bm = bmesh.new()
    rows = []
    for i, p in enumerate(pts):
        t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        side = Vector((1, 0, 0))
        n = t.cross(side).normalized()
        rows.append([bm.verts.new(p + side * sx * width / 2 + n * sy * thick / 2)
                     for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))])
    for a, b in zip(rows, rows[1:]):
        for i in range(4):
            j = (i + 1) % 4
            bm.faces.new((a[i], a[j], b[j], b[i]))
    bm.faces.new(rows[0][::-1])
    bm.faces.new(rows[-1])
    return to_object(name, bm)


HEAD_R = [(0.118, 0.055), (0.095, 0.092), (0.06, 0.108), (0.03, 0.112), (0.0, 0.11), (-0.03, 0.104)]


def head_radius(z):
    for (z0, r0), (z1, r1) in zip(HEAD_R, HEAD_R[1:]):
        if z1 <= z <= z0:
            return r0 + (r1 - r0) * (z0 - z) / (z0 - z1)
    return HEAD_R[0][1] if z > HEAD_R[0][0] else HEAD_R[-1][1]


def on_head(a, z, s=1.06):
    r = head_radius(z) * s
    return (math.sin(a) * r, math.cos(a) * r, z)


def gear_parts():
    out = []
    # Messy hair: a cap with spiky clumps on top, a fringe over the forehead, tufts at the sides
    parts = [hair_shell("hair_messy_cap", 1.08, 0.07, -0.05, bumpy=0.03)]
    for a in (-0.55, -0.2, 0.15, 0.5):
        parts.append(tuft("fringe", on_head(a, 0.085), (math.sin(a) * 0.5, 0.75, -0.65), 0.028, 0.062))
    for a in (0.0, 1.1, 2.2, 3.14, -1.1, -2.2, 0.55, -0.55):
        z = 0.112 if abs(a) < 0.7 else 0.1
        parts.append(tuft("top", on_head(a, z, 0.95), (math.sin(a) * 0.8, math.cos(a) * 0.8 - 0.3, 0.7), 0.034, 0.05))
    for a in (1.6, -1.6, 2.4, -2.4, 3.0, -3.0):
        parts.append(tuft("side", on_head(a, 0.03), (math.sin(a), math.cos(a), -0.8), 0.028, 0.045))
    out.append(join("hair_messy", parts))

    # Rider ponytail: tied high at the back, a few loose strands framing the face
    cap = hair_shell("hair_ponyr_cap", 1.07, 0.078, -0.04, bumpy=0.015)
    tail = limb("hair_ponyr_tail", 0.25, [(0.0, 0.035, 0.035, 0.035), (0.3, 0.05, 0.045, 0.045), (0.7, 0.04, 0.035, 0.035),
                                          (1.0, 0.012, 0.012, 0.012)], sides=7)
    tail.location = (0, -0.115, 0.075)
    tail.rotation_euler = (math.radians(-40), 0, 0)
    tie = loft("hair_ponyr_tie", [ellipse(z, 0.03, 0.03, 0.03, cy=-0.115) for z in (0.09, 0.07)], 6)
    for o in (tail,):
        bpy.ops.object.select_all(action="DESELECT")
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.transform_apply(location=True, rotation=True)
    parts = [cap, tail, tie]
    for side in (-1, 1):
        parts.append(tuft("strand", on_head(side * 1.15, 0.05), (side * 0.15, 0.2, -1.0), 0.014, 0.13))
    for a in (-0.35, 0.0, 0.35):
        parts.append(tuft("bang", on_head(a, 0.09), (math.sin(a) * 0.4, 0.7, -0.7), 0.02, 0.055))
    out.append(join("hair_ponyr", parts))

    # Hood lying on the back of the neck (torso space: origin = hip line)
    out.append(loft("hood", [ellipse(z, rx, f, b, cy=cy) for z, rx, f, b, cy in
                             [(0.67, 0.05, 0.02, 0.05, -0.085), (0.645, 0.1, 0.05, 0.09, -0.065),
                              (0.6, 0.125, 0.08, 0.11, -0.05), (0.55, 0.12, 0.08, 0.1, -0.055),
                              (0.52, 0.08, 0.05, 0.07, -0.07)]], 12))

    # Baggy cargo pants legs, side pockets (left and right), glove cuff
    out.append(limb("thigh_baggy", THIGH, [(-0.05, 0.082, 0.082, 0.082), (0.08, 0.1, 0.102, 0.102), (0.5, 0.094, 0.1, 0.094),
                                           (1.0, 0.082, 0.084, 0.082)], sides=10))
    out.append(limb("shin_baggy", SHIN, [(-0.04, 0.08, 0.08, 0.08), (0.4, 0.076, 0.076, 0.078), (0.85, 0.072, 0.072, 0.072),
                                         (1.0, 0.07, 0.07, 0.07)], sides=10))
    pocket = loft("cargo_pocket", [ellipse(z, w, d, d, cx=0.094) for z, w, d in
                                   [(-0.14, 0.006, 0.04), (-0.15, 0.022, 0.055), (-0.29, 0.024, 0.055), (-0.3, 0.008, 0.045)]], 8)
    out.append(pocket)
    out.append(mirrored_copy(pocket, "cargo_pocket_l"))
    out.append(limb("glove_cuff", 0.04, [(0.0, 0.041, 0.04, 0.04), (1.0, 0.04, 0.037, 0.037)], sides=8))

    # Backpack (torso space) with two shoulder straps
    pack = loft("pack", [ellipse(z, rx, f, b, cy=-0.17) for z, rx, f, b in
                         [(0.555, 0.07, 0.03, 0.03), (0.54, 0.125, 0.055, 0.065), (0.31, 0.135, 0.06, 0.075),
                          (0.24, 0.12, 0.05, 0.06), (0.225, 0.06, 0.03, 0.03)]], 12)
    front = loft("pack_pocket", [ellipse(z, rx, f, b, cy=-0.24) for z, rx, f, b in
                                 [(0.41, 0.06, 0.01, 0.01), (0.4, 0.095, 0.02, 0.03), (0.27, 0.1, 0.02, 0.035),
                                  (0.26, 0.05, 0.01, 0.01)]], 10)
    parts = [pack, front]
    for side in (-1, 1):
        x = side * 0.105
        parts.append(band("strap", [(x, -0.13, 0.5), (x, -0.08, 0.595), (x, 0.0, 0.615), (x, 0.075, 0.575),
                                    (x * 1.02, 0.112, 0.48), (x * 1.05, 0.114, 0.38), (x * 1.08, 0.104, 0.3)], 0.042, 0.01))
    out.append(join("backpack", parts))

    # Baseball cap (head space)
    crown = hair_shell("cap_crown", 1.12, 0.07, 0.025)
    brim = loft("cap_brim", [ellipse(z, 0.095, 0.2, 0.02) for z in (0.074, 0.066)], 12)
    out.append(join("cap", [crown, brim]))

    # Walking cane (forearm space: hangs from the hand)
    stick = limb("cane", 0.86, [(0.0, 0.011, 0.011, 0.011), (1.0, 0.011, 0.011, 0.011)], sides=6)
    hook = limb("cane_hook", 0.09, [(0.0, 0.012, 0.012, 0.012), (1.0, 0.012, 0.012, 0.012)], sides=6)
    hook.rotation_euler = (math.radians(-90), 0, 0)
    bpy.ops.object.select_all(action="DESELECT")
    hook.select_set(True)
    bpy.context.view_layer.objects.active = hook
    bpy.ops.object.transform_apply(location=True, rotation=True)
    out.append(join("cane", [stick, hook]))
    return out


def helmet():
    shell = loft("helmet_shell", [ellipse(z, rx, f, b) for z, rx, f, b in
                                  [(0.175, 0.0005, 0.0005, 0.0005), (0.165, 0.075, 0.075, 0.08), (0.13, 0.125, 0.125, 0.13),
                                   (0.07, 0.15, 0.15, 0.155), (0.0, 0.155, 0.152, 0.158), (-0.06, 0.15, 0.14, 0.152),
                                   (-0.09, 0.14, 0.12, 0.145)]], 16, cap_bottom=False)
    return shell


def visor():
    return loft("helmet_visor", [ellipse(z, rx, f, f * 0.4, cy=0.03) for z, rx, f in
                                 [(0.04, 0.135, 0.135), (-0.03, 0.14, 0.14), (-0.06, 0.13, 0.13)]], 12)


# ---------------------------------------------------------------------------------------

def main():
    clear_scene()
    head()
    for female in (False, True):
        for heavy in (False, True):
            tag = ("f" if female else "m") + ("_heavy" if heavy else "")
            torso("torso_" + tag, female, heavy)
            pelvis("pelvis_" + tag, female, heavy)
    upper_arm()
    forearm()
    sleeve("sleeve_short", UPPER_ARM * 0.5)
    sleeve("sleeve_cap", UPPER_ARM * 0.22)
    thigh()
    shin()
    shorts_leg()
    mirrored_copy(fist(), "fist_l")   # "fist" = right hand (thumb inside), "fist_l" = left hand
    shoe("sneaker")
    shoe("slipper", slipper=True)
    neck()
    skirt("skirt", 0.34, 0.08)
    skirt("dress_skirt", 0.46, 0.12)
    collar()
    hair_parts()
    gear_parts()
    helmet()
    visor()

    os.makedirs(OUT_DIR, exist_ok=True)
    tris = 0
    for o in bpy.data.objects:
        if o.type == "MESH":
            tris += sum(len(p.vertices) - 2 for p in o.data.polygons)
    print("Parts: %d meshes, %d triangles in the whole kit" % (len([o for o in bpy.data.objects if o.type == "MESH"]), tris))
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT_DIR, "character_kit.blend"))
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT_DIR, "character_kit.glb"), export_format="GLB")
    print("Saved:", OUT_DIR)


main()
