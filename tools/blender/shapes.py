"""Shared modeling tools for the Blender scripts (scooter, traffic vehicles).

A Part collects many shapes into one mesh; shapes are lofts (rings of points joined into a
surface), sweeps (a profile moved along a path), rounded boxes and revolved profiles.
Blender Z is up and models face +Y (glTF turns that into Godot's -Z = forward).
"""
import bpy
import bmesh
import math
from mathutils import Vector, Matrix, Euler

TAU = math.tau

# ---------------------------------------------------------------------------------------
# Materials: name -> (sRGB hex, metallic, roughness, glow)
# ---------------------------------------------------------------------------------------
MAT_DEFS = {
    "Paint": ("#e9e9e4", 0.2, 0.32, 0.0),
    "Trim": ("#1d1f22", 0.0, 0.55, 0.0),
    "Seat": ("#141416", 0.0, 0.6, 0.0),
    "Rubber": ("#121212", 0.0, 0.9, 0.0),
    "Chrome": ("#d8dbe0", 1.0, 0.14, 0.0),
    "Metal": ("#9ba0a7", 0.85, 0.38, 0.0),
    "DarkMetal": ("#38393d", 0.7, 0.45, 0.0),
    "Rim": ("#2a2c30", 0.6, 0.32, 0.0),
    "Disc": ("#a7a9ad", 0.9, 0.3, 0.0),
    "Caliper": ("#c48a1c", 0.4, 0.4, 0.0),
    "Spring": ("#b3171b", 0.3, 0.35, 0.0),
    "Glass": ("#101418", 0.0, 0.05, 0.0),
    "Plate": ("#eeeeE6", 0.0, 0.6, 0.0),
    "HeadLight": ("#fff3d6", 0.0, 0.1, 1.5),
    "TailLight": ("#c8121a", 0.0, 0.2, 0.6),
    "Signal": ("#ff9a1a", 0.0, 0.2, 0.4),
    "Accent": ("#f2c230", 0.1, 0.4, 0.0),
    "Accent2": ("#2f6fd6", 0.1, 0.4, 0.0),
    "Interior": ("#2a2622", 0.0, 0.8, 0.0),
}


def srgb_to_linear(hexc):
    h = hexc.lstrip("#")
    out = []
    for i in (0, 2, 4):
        c = int(h[i:i + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return (out[0], out[1], out[2], 1.0)


def make_materials():
    for name, (hexc, met, rough, glow) in MAT_DEFS.items():
        m = bpy.data.materials.new(name)
        try:
            m.use_nodes = True
        except Exception:
            pass
        b = m.node_tree.nodes.get("Principled BSDF")
        col = srgb_to_linear(hexc)
        b.inputs["Base Color"].default_value = col
        b.inputs["Metallic"].default_value = met
        b.inputs["Roughness"].default_value = rough
        if glow > 0:
            b.inputs["Emission Color"].default_value = col
            b.inputs["Emission Strength"].default_value = glow


# ---------------------------------------------------------------------------------------
# A "Part" collects many shapes into one mesh. Materials can be a name, or a function
# (face center, face normal) -> name, decided once all normals point outward.
# ---------------------------------------------------------------------------------------
class Part:
    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.rules = []

    def v(self, co):
        return self.bm.verts.new(co)

    def f(self, verts, mat, smooth=True):
        face = self.bm.faces.new(verts)
        face.smooth = smooth
        self.rules.append((face, mat))
        return face

    def merge(self, tmp, mat, smooth=True):
        vm = {v: self.bm.verts.new(v.co) for v in tmp.verts}
        for face in tmp.faces:
            self.f([vm[v] for v in face.verts], mat, smooth)
        tmp.free()

    def build(self, sharp_deg=42.0):
        bm = self.bm
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        mats = []
        for face, rule in self.rules:
            face.normal_update()
            name = rule if isinstance(rule, str) else rule(face.calc_center_median(), face.normal)
            if name not in mats:
                mats.append(name)
            face.material_index = mats.index(name)
        limit = math.radians(sharp_deg)
        for e in bm.edges:
            if len(e.link_faces) == 2:
                a, b = e.link_faces
                if a.material_index != b.material_index or e.calc_face_angle(0.0) > limit:
                    e.smooth = False
        mesh = bpy.data.meshes.new(self.name)
        bm.to_mesh(mesh)
        bm.free()
        for n in mats:
            mesh.materials.append(bpy.data.materials[n])
        obj = bpy.data.objects.new(self.name, mesh)
        bpy.context.collection.objects.link(obj)
        tris = sum(len(p.vertices) - 2 for p in mesh.polygons)
        print("  %-10s %5d triangles, materials: %s" % (self.name, tris, ", ".join(mats)))
        return obj


# --- basic shape tools ------------------------------------------------------------------

def loft(part, rings, mat, cap0=True, cap1=True, smooth=True, wrap=False):
    """Connect rings (lists of points, same count) into a surface. Each ring is a closed loop.
    wrap=True also connects the last ring back to the first (a donut, like a tire)."""
    grid = [[part.v(p) for p in ring] for ring in rings]
    n = len(rings[0])
    count = len(grid) if wrap else len(grid) - 1
    for r in range(count):
        a, b = grid[r], grid[(r + 1) % len(grid)]
        for i in range(n):
            j = (i + 1) % n
            part.f((a[i], a[j], b[j], b[i]), mat, smooth)
    if wrap:
        return
    for cap, row in ((cap0, grid[0]), (cap1, grid[-1])):
        if cap:
            c = sum((v.co for v in row), Vector()) / n
            cv = part.v(c)
            for i in range(n):
                part.f((row[i], row[(i + 1) % n], cv), mat, smooth)


def se(t, n):
    """Superellipse: n=2 is a circle/ellipse, bigger n = squarer with round corners."""
    c, s = math.cos(t), math.sin(t)
    return math.copysign(abs(c) ** (2.0 / n), c), math.copysign(abs(s) ** (2.0 / n), s)


def ring_y(y, cx, cz, hw, ht, hb, n=2.5, count=32):
    """Cross-section in the XZ plane (for shapes that run front-to-back)."""
    pts = []
    for i in range(count):
        cs, sn = se(TAU * i / count, n)
        pts.append(Vector((cx + hw * cs, y, cz + (ht if sn > 0 else hb) * sn)))
    return pts


def ring_z(z, cx, cy, hw, df, db, n=2.5, count=32):
    """Cross-section in the XY plane (for shapes that run bottom-to-top)."""
    pts = []
    for i in range(count):
        cs, sn = se(TAU * i / count, n)
        pts.append(Vector((cx + hw * cs, cy + (df if sn > 0 else db) * sn, z)))
    return pts


def ring_x(x, cy, cz, df, db, ht, hb, n=2.5, count=28):
    """Cross-section in the YZ plane (for shapes that run left-to-right)."""
    pts = []
    for i in range(count):
        cs, sn = se(TAU * i / count, n)
        pts.append(Vector((x, cy + (df if cs > 0 else db) * cs, cz + (ht if sn > 0 else hb) * sn)))
    return pts


def catmull(points, per):
    """Smooth a list of number-tuples with a Catmull-Rom spline (per = steps between points)."""
    out = []
    n = len(points)
    for i in range(n - 1):
        p0, p1, p2, p3 = points[max(i - 1, 0)], points[i], points[i + 1], points[min(i + 2, n - 1)]
        for k in range(per):
            t = k / per
            out.append(tuple(0.5 * (2 * b + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t * t
                                    + (-a + 3 * b - 3 * c + d) * t ** 3) for a, b, c, d in zip(p0, p1, p2, p3)))
    out.append(tuple(points[-1]))
    return out


def circle(r, n=10):
    return [(r * math.cos(TAU * i / n), r * math.sin(TAU * i / n)) for i in range(n)]


def rrect(hu, hv, n=12, e=5.0):
    """Rounded rectangle profile."""
    out = []
    for i in range(n):
        cs, sn = se(TAU * i / n, e)
        out.append((hu * cs, hv * sn))
    return out


def sweep(part, path, profile, mat, scales=None, caps=True, smooth=True, up=Vector((0, 0, 1))):
    """Move a 2D profile along a path of points (tubes, rails, springs, strips)."""
    path = [Vector(p) for p in path]
    n = len(path)
    tangents = [(path[min(i + 1, n - 1)] - path[max(i - 1, 0)]).normalized() for i in range(n)]
    ref = up if abs(tangents[0].dot(up)) < 0.95 else Vector((1, 0, 0))
    nrm = (ref - tangents[0] * ref.dot(tangents[0])).normalized()
    rings = []
    for i in range(n):
        t = tangents[i]
        nrm = (nrm - t * nrm.dot(t)).normalized()
        bi = t.cross(nrm)
        s = scales[i] if scales else 1.0
        rings.append([path[i] + (nrm * u + bi * w) * s for (u, w) in profile])
    loft(part, rings, mat, caps, caps, smooth)


def tube(part, p0, p1, r, mat, sides=12, caps=True, smooth=True):
    sweep(part, [Vector(p0), Vector(p1)], circle(r, sides), mat, caps=caps, smooth=smooth)


def rbox(part, center, size, mat, bevel=0.01, segs=2, rot=None, smooth=True):
    """A box with rounded edges. rot = (rx, ry, rz) in degrees."""
    tmp = bmesh.new()
    bmesh.ops.create_cube(tmp, size=1.0)
    for v in tmp.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    if bevel > 0:
        bmesh.ops.bevel(tmp, geom=tmp.edges[:], offset=min(bevel, min(size) * 0.45), segments=segs,
                        profile=0.5, affect="EDGES", clamp_overlap=True)
    m = Matrix.Translation(Vector(center))
    if rot:
        m = m @ Euler([math.radians(a) for a in rot]).to_matrix().to_4x4()
    bmesh.ops.transform(tmp, matrix=m, verts=tmp.verts)
    part.merge(tmp, mat, smooth)


def bar(part, p0, p1, thick_axis, thick, width, mat, bevel=0.004):
    """A flat rounded bar from p0 to p1 (thickness measured along thick_axis)."""
    p0, p1 = Vector(p0), Vector(p1)
    z = (p1 - p0)
    length = z.length
    z.normalize()
    x = Vector(thick_axis)
    x = (x - z * x.dot(z)).normalized()
    y = z.cross(x)
    tmp = bmesh.new()
    bmesh.ops.create_cube(tmp, size=1.0)
    for v in tmp.verts:
        v.co = Vector((v.co.x * thick, v.co.y * width, v.co.z * length))
    bmesh.ops.bevel(tmp, geom=tmp.edges[:], offset=min(bevel, thick * 0.45, width * 0.45), segments=1,
                    profile=0.5, affect="EDGES", clamp_overlap=True)
    m = Matrix((
        (x.x, y.x, z.x, (p0.x + p1.x) / 2),
        (x.y, y.y, z.y, (p0.y + p1.y) / 2),
        (x.z, y.z, z.z, (p0.z + p1.z) / 2),
        (0, 0, 0, 1)))
    bmesh.ops.transform(tmp, matrix=m, verts=tmp.verts)
    part.merge(tmp, mat, smooth=False)


def revolve(part, profile_rx, mat, segs, phase=0.0, bump=None):
    """Spin a closed (radius, x) profile around the X axis (wheels, discs, hubs).
    bump(i, k) can push point k of ring i in or out (tire tread)."""
    rings = []
    for i in range(segs):
        a = TAU * i / segs + phase
        ring = []
        for k, (r, x) in enumerate(profile_rx):
            rr = r + (bump(i, k) if bump else 0.0)
            ring.append(Vector((x, rr * math.cos(a), rr * math.sin(a))))
        rings.append(ring)
    loft(part, rings, mat, wrap=True)
