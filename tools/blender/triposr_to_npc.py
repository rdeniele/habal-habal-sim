"""Turn a TripoSR result (mesh.obj + texture.png) into a game NPC: the TripoSR body and outfit,
a clean anime head from make_npc.py, a skeleton, smaller mesh.

Why the head swap: TripoSR copies clothes well but blurs faces. Arms that are in pockets in the
drawing stay fused to the body, so they don't follow the arm bones (they stay put, like walking
with hands in pockets); the legs and the head move.

    blender -b -P tools/blender/triposr_to_npc.py -- mesh.obj texture.png vendor_m vendor [turn_degrees]
turn_degrees: how much to turn the TripoSR mesh around Z so it faces -Y (default -90).
Output: assets/characters/npc/<name>.glb (+ .blend).
"""
import bpy
import bmesh
import math
import os
import sys
import time

from mathutils import Vector, Matrix

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_npc as N   # noqa: E402  (head builder, skeleton, skinning helpers)
import npc_heads as H   # noqa: E402
from shapes import Part, loft   # noqa: E402

HEIGHT = {"m": 1.70, "f": 1.61}
BODY_TRIS = 20000   # only reduce if much bigger: reducing after the paint breaks the colors


def load_body(obj_path, tex_path, height, turn):
    bpy.ops.wm.obj_import(filepath=obj_path)
    o = [x for x in bpy.data.objects if x.type == "MESH"][0]
    o.name = "body"
    o.rotation_euler = (0, 0, 0)   # we orient the mesh data ourselves
    o.data.transform(Matrix.Rotation(math.radians(turn), 4, "Z"))
    pts = [v.co.copy() for v in o.data.vertices]
    k = height / (max(p.z for p in pts) - min(p.z for p in pts))
    cx = (max(p.x for p in pts) + min(p.x for p in pts)) / 2
    cy = (max(p.y for p in pts) + min(p.y for p in pts)) / 2
    z0 = min(p.z for p in pts)
    for v in o.data.vertices:
        v.co = Vector(((v.co.x - cx) * k, (v.co.y - cy) * k, (v.co.z - z0) * k))
    m = bpy.data.materials.new("Body")
    try:
        m.use_nodes = True
    except Exception:
        pass
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = bpy.data.images.load(tex_path)
    t.image.pack()
    nt.links.new(t.outputs["Color"], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.85
    o.data.materials.clear()
    o.data.materials.append(m)
    return o


def slice_width(o, z, band=0.006):
    xs = [v.co for v in o.data.vertices if abs(v.co.z - z) < band]
    if len(xs) < 4:
        return None
    # width, and the middle of the slice (not the average, which a towel or hood would pull back)
    return (max(p.x for p in xs) - min(p.x for p in xs), (max(p.x for p in xs) + min(p.x for p in xs)) / 2,
            (max(p.y for p in xs) + min(p.y for p in xs)) / 2)


def find_neck(o, height):
    """The narrowest slice between the shoulders and the head = the neck."""
    best = None
    z = height * 0.76
    while z < height * 0.92:
        w = slice_width(o, z)
        if w and (best is None or w[0] < best[1][0]):
            best = (z, w)
        z += 0.005
    return best[0], best[1][2]


def cut_above(o, z, precise=False):
    """Remove the TripoSR head, and any loose bits (pieces of neighbors from the picture)."""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    if precise:
        # A planar cut retains intersecting triangles and gives the replacement neck
        # a continuous rim. Deleting whole vertices leaves spikes and holes.
        bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:],
                              plane_co=(0, 0, z), plane_no=(0, 0, 1),
                              clear_outer=True, dist=1e-6)
    else:
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z > z], context="VERTS")
    # weld the color-map seams first (the file splits the mesh along them; colors are kept)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-5)
    # keep only the biggest connected piece
    bm.verts.index_update()
    bm.verts.ensure_lookup_table()
    seen = set()
    pieces = []
    for v in bm.verts:
        if v.index in seen:
            continue
        stack, piece = [v], []
        seen.add(v.index)
        while stack:
            cur = stack.pop()
            piece.append(cur)
            for e in cur.link_edges:
                o2 = e.other_vert(cur)
                if o2.index not in seen:
                    seen.add(o2.index)
                    stack.append(o2)
        pieces.append(piece)
    pieces.sort(key=len, reverse=True)
    extra = [v for piece in pieces[1:] for v in piece]
    if extra:
        print("  removed %d loose pieces (%d points)" % (len(pieces) - 1, len(extra)))
        bmesh.ops.delete(bm, geom=extra, context="VERTS")
    bm.to_mesh(o.data)
    bm.free()


def trim_neckline(o, cut, precise=False):
    """After the cut: remove leftovers sticking out beside the neck (old hair, jaw), and return
    the neck opening as (center x, center y, half width, half depth)."""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    top = [v.co for v in bm.verts if v.co.z > cut - 0.012]
    ys = sorted(c.y for c in top)
    xs = sorted(c.x for c in top)
    # the middle of the opening (percentiles, so a stray flap doesn't move it)
    lo, hi = int(len(top) * 0.1), int(len(top) * 0.9)
    cx, cy = (xs[lo] + xs[hi]) / 2, (ys[lo] + ys[hi]) / 2
    if not precise:
        flaps = [v for v in bm.verts if v.co.z > cut - 0.03 and math.hypot(v.co.x - cx, v.co.y - cy) > 0.1]
        bmesh.ops.delete(bm, geom=flaps, context="VERTS")
    rim = [v.co.copy() for v in bm.verts if v.is_boundary and v.co.z > cut - 0.04
           and (precise or math.hypot(v.co.x - cx, v.co.y - cy) < 0.14)]
    bm.to_mesh(o.data)
    bm.free()
    return cx, cy, rim


def neckline(cx, cy, rim, count=32, precise=False):
    """Close the opening: shoulders/shirt that start ON the body's cut edge and rise to the neck.
    For every direction around the neck, take the farthest edge point that way."""
    edge = [None] * count
    for c in rim:
        i = int((math.atan2(c.y - cy, c.x - cx) % math.tau) / math.tau * count) % count
        r = math.hypot(c.x - cx, c.y - cy)
        if edge[i] is None or r > edge[i][0]:
            edge[i] = (r, c.z)
    known = [i for i in range(count) if edge[i]]
    for i in range(count):   # fill directions with no edge point from the nearest ones
        if not edge[i]:
            j = min(known, key=lambda k: min((k - i) % count, (i - k) % count))
            edge[i] = edge[j]
    # smooth out the ragged cut
    sm = [(sum(edge[(i + d) % count][0] for d in (-1, 0, 1)) / 3,
           sum(edge[(i + d) % count][1] for d in (-1, 0, 1)) / 3) for i in range(count)]
    # Rebuild the upper shirt/shoulder slope as well as the neck opening, so the
    # original reconstructed chin cannot remain as a second throat under the head.
    top = max(z for _, z in sm) + (0.075 if precise else 0.012)
    neck_r = 0.052

    def ring_at(f_r, f_z, drop=0.0, out=0.0):
        pts = []
        for i in range(count):
            a = (i + 0.5) / count * math.tau
            r0, z0 = sm[i]
            r = r0 + (neck_r - r0) * f_r + out
            z = z0 + (top - z0) * f_z - drop
            pts.append(Vector((cx + math.cos(a) * r, cy + math.sin(a) * r, z)))
        return pts
    part = Part("collar")
    rows = [ring_at(0.0, 0.0, drop=0.012 if precise else 0.03, out=0.002),
            ring_at(0.0, 0.0, out=0.002 if precise else 0.006), ring_at(0.45, 0.35 if precise else 0.65),
            ring_at(1.0, 1.0, out=0.002 if precise else 0.006),
            ring_at(1.0, 1.0, drop=0.012, out=-0.006)]
    loft(part, rows, "Shirt", cap0=False, cap1=False)
    return part, top


def decimate(o, tris):
    now = sum(len(p.vertices) - 2 for p in o.data.polygons)
    if now <= tris:
        return
    mod = o.modifiers.new("dec", "DECIMATE")
    mod.ratio = tris / now
    bpy.context.view_layer.objects.active = o
    o.select_set(True)
    bpy.ops.object.modifier_apply(modifier=mod.name)
    for p in o.data.polygons:
        p.use_smooth = True


def leg_centers(o, z, band=0.015):
    """The middle of each leg at height z: (left xy, right xy). The drawings stand in a
    three-quarter pose, so legs are not centered or side by side: split the slice into two
    groups (2-means on x, y). Left = the larger x."""
    pts = [Vector((v.co.x, v.co.y)) for v in o.data.vertices if abs(v.co.z - z) < band]
    if len(pts) < 8:
        return Vector((0.09, 0.0)), Vector((-0.09, 0.0))
    c = [max(pts, key=lambda q: q.x).copy(), min(pts, key=lambda q: q.x).copy()]
    for _ in range(12):
        groups = ([], [])
        for q in pts:
            groups[0 if (q - c[0]).length < (q - c[1]).length else 1].append(q)
        for i, g in enumerate(groups):
            if g:   # middle of the group's box (even if one side has more points)
                c[i] = Vector(((min(q.x for q in g) + max(q.x for q in g)) / 2,
                               (min(q.y for q in g) + max(q.y for q in g)) / 2))
    return (c[0], c[1]) if c[0].x >= c[1].x else (c[1], c[0])


def leg_axes(o, height, body_y):
    """{"Left": [hip, knee, ankle], "Right": [...]} fitted inside the mesh."""
    knee_z, ankle_z, hip_z = height * 0.29, height * 0.075, height * 0.53
    knees = leg_centers(o, knee_z)
    ankles = leg_centers(o, ankle_z + 0.02)
    mid_x = (knees[0].x + knees[1].x) / 2
    spread = max(0.065, min(0.11, (knees[0].x - knees[1].x) * 0.45))
    axes = {}
    for i, (pre, side) in enumerate((("Left", 1), ("Right", -1))):
        k, an = knees[i], ankles[i]
        hip = Vector((mid_x + side * spread, (k.y + body_y) / 2, hip_z))
        axes[pre] = [hip, Vector((k.x, k.y, knee_z)), Vector((an.x, an.y + 0.015, ankle_z))]
    return axes


def fit_bones(bones, axes, body_x, body_y):
    """Move the spine over the body's middle and put the leg bones inside the real legs."""
    shift = Vector((body_x, body_y, 0.0))
    for name, (h, t, parent) in list(bones.items()):
        bones[name] = (h + shift, t + shift, parent)
    for pre, (hip, knee, ankle) in axes.items():
        toe = Vector((ankle.x, ankle.y - 0.12, 0.025))
        bones[pre + "UpLeg"] = (hip, knee, "Hips")
        bones[pre + "Leg"] = (knee, ankle, pre + "UpLeg")
        bones[pre + "Foot"] = (ankle, toe, pre + "Leg")
        bones[pre + "ToeBase"] = (toe, toe + Vector((0, -0.06, 0)), pre + "Foot")


def axis_xy(axis, z):
    """Where a leg's middle is at height z."""
    hip, knee, ankle = axis
    a, b = (hip, knee) if z >= knee.z else (knee, ankle)
    t = max(0.0, min(1.0, (a.z - z) / max(a.z - b.z, 1e-6)))
    return Vector((a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t))


def separate_legs(o, height, axes, skirt=False):
    """Remove the thin ground/shadow web TripoSR sometimes builds between the feet.

    It is almost invisible at rest, but its two sides follow opposite legs and turn
    into meter-long triangles during a stride. Skirts keep their upper cloth intact.
    """
    bm = bmesh.new()
    bm.from_mesh(o.data)
    top = height * (0.29 if skirt else 0.45)
    def middle(z):
        return (axis_xy(axes["Left"], z).x + axis_xy(axes["Right"], z).x) / 2
    faces = []
    for f in bm.faces:
        z = max(v.co.z for v in f.verts)
        if z < top and min(v.co.x for v in f.verts) < middle(z) + 0.008 \
                and max(v.co.x for v in f.verts) > middle(z) - 0.008:
            faces.append(f)
    bmesh.ops.delete(bm, geom=faces, context="FACES")
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bm.to_mesh(o.data)
    bm.free()
    print("  removed %d inter-leg shadow faces" % len(faces))


def nearest(p, bones, names, keep=2):
    """Smooth weights among `names` by distance to each bone: {name: weight}, adding up to 1."""
    ws = []
    for name in names:
        h, t, _ = bones[name]
        d = N.seg_dist(p, h, t)
        ws.append((1.0 / (d * d + 1e-4) ** 2, name))
    ws.sort(reverse=True)
    ws = ws[:keep]
    total = sum(w for w, _ in ws)
    return {name: w / total for w, name in ws}


def weight_body(o, bones, axes, crotch_z, drapes):
    """Legs follow their own leg bones, blending smoothly into the hips over 20 cm around the
    crotch (no tearing when sitting). Things hanging beside the legs (bags, hands, a helmet)
    stay with the hips. With `drapes` (apron, skirt), cloth in front of the legs follows the
    hips half and each thigh a quarter. Above the legs: hips and spine only."""
    torso = ["Hips", "Spine02", "Spine01", "Spine", "neck"]
    groups = {n: o.vertex_groups.new(name=n) for n in torso + ["LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase",
                                                               "RightUpLeg", "RightLeg", "RightFoot", "RightToeBase"]}
    top = crotch_z + 0.05
    knee_z = axes["Left"][1].z
    for v in o.data.vertices:
        p = v.co
        if p.z >= top:
            weights = nearest(p, bones, torso)
        else:
            leg_share = min(1.0, (top - p.z) / 0.2)   # 0 at the top of the blend, 1 lower down
            xy = Vector((p.x, p.y))
            dist = {pre: (xy - axis_xy(axes[pre], p.z)).length for pre in axes}
            pre = min(dist, key=dist.get)
            legs = nearest(p, bones, [pre + "UpLeg", pre + "Leg", pre + "Foot", pre + "ToeBase"])
            # how much this point belongs to the hips instead (0..1, only above the knee)
            above = max(0.0, min(1.0, (p.z - (knee_z - 0.08)) / 0.1))
            hang = max(0.0, min(1.0, (dist[pre] - 0.1) / 0.08)) * above
            if drapes:   # cloth in front of the legs lies on the lap: half hips, a quarter per thigh
                front = max(0.0, min(1.0, (axis_xy(axes[pre], p.z).y - 0.04 - p.y) / 0.06)) * above
                lap = {"LeftUpLeg": 0.25, "RightUpLeg": 0.25, "Hips": 0.5}
                legs = {k: legs.get(k, 0.0) * (1.0 - front) + lap.get(k, 0.0) * front for k in set(legs) | set(lap)}
            legs = {k: w * (1.0 - hang) for k, w in legs.items()}
            legs["Hips"] = legs.get("Hips", 0.0) + hang
            weights = {name: w * leg_share for name, w in legs.items()}
            if leg_share < 1.0:
                weights["Hips"] = weights.get("Hips", 0.0) + (1.0 - leg_share)
        for name, w in weights.items():
            if w > 0.01:
                groups[name].add([v.index], w, "REPLACE")


def cut_leg_webs(o, axes, crotch_z):
    """TripoSR often joins the two legs with thin skin or ground shadow. Delete faces below the
    crotch that touch both a left-leg point and a right-leg point (they'd stretch when walking)."""
    names = {g.index: g.name for g in o.vertex_groups}
    side = []
    for v in o.data.vertices:
        left = sum(g.weight for g in v.groups if names[g.group].startswith("Left"))
        right = sum(g.weight for g in v.groups if names[g.group].startswith("Right"))
        side.append(1 if left > right + 0.3 else (-1 if right > left + 0.3 else 0))
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bm.verts.ensure_lookup_table()
    bm.verts.index_update()
    faces = [f for f in bm.faces
             if {side[v.index] for v in f.verts} >= {1, -1} and min(v.co.z for v in f.verts) < crotch_z - 0.04]
    bmesh.ops.delete(bm, geom=faces, context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.to_mesh(o.data)
    bm.free()
    print("  cut %d faces joining the legs" % len(faces))


def weight_auto(o, bones):
    """Blender's automatic (bone heat) weights, on the hips, spine and leg bones only: the arms
    are fused to the body in these models, so arm bones must not pull on it.
    Returns False if Blender couldn't solve it (then the distance-based weights are used)."""
    arm = N.make_armature(bones)
    for bone in arm.data.bones:
        bone.use_deform = not any(k in bone.name for k in ("Shoulder", "Arm", "Hand", "Head"))
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    missing = sum(1 for v in o.data.vertices if sum(g.weight for g in v.groups) < 0.01)
    # undo the parenting; main() builds the final armature after joining the head
    world = o.matrix_world.copy()
    o.parent = None
    o.matrix_world = world
    for mod in list(o.modifiers):
        o.modifiers.remove(mod)
    data = arm.data
    bpy.data.objects.remove(arm)
    bpy.data.armatures.remove(data)
    print("  automatic weights: %d of %d points left unweighted" % (missing, len(o.data.vertices)))
    if missing > len(o.data.vertices) * 0.02:
        o.vertex_groups.clear()
        return False
    for v in o.data.vertices:   # the few it missed follow the hips
        if sum(g.weight for g in v.groups) < 0.01:
            (o.vertex_groups.get("Hips") or o.vertex_groups.new(name="Hips")).add([v.index], 1.0, "REPLACE")
    return True


def main():
    args = sys.argv[sys.argv.index("--") + 1:]
    obj_path, tex_path, name, npc_type = args[:4]
    if npc_type not in H.TYPES:
        raise ValueError("Unknown NPC type: " + npc_type)
    turn = float(args[4]) if len(args) > 4 else -90.0
    female = name.endswith("_f")
    height = HEIGHT["f" if female else "m"]
    bpy.ops.wm.read_factory_settings(use_empty=True)

    body = load_body(obj_path, tex_path, height, turn)
    neck_z, _ = find_neck(body, height)
    precise = npc_type != "vendor"
    # TripoSR often folds the underside of a three-quarter-view jaw down onto the
    # chest. Remove that whole bulge before attaching a centered replacement head.
    cut = neck_z - (0.13 if precise else 0.045)
    cut_above(body, cut, precise=precise)
    cx, cy, rim = trim_neckline(body, cut, precise=precise)
    collar, collar_top = neckline(cx, cy, rim, precise=precise)
    print("  cut at z=%.3f, neck center (%.3f, %.3f), neckline top %.3f" % (cut, cx, cy, collar_top))
    decimate(body, BODY_TRIS)
    skirt = female and npc_type in ("student", "misc")
    axes = leg_axes(body, height, cy)
    for pre, (hip, knee, ankle) in axes.items():
        print("  %s leg: knee (%.3f, %.3f) ankle (%.3f, %.3f)" % (pre, knee.x, knee.y, ankle.x, ankle.y))

    # skeleton sized to this body
    p = N.body_plan(female)
    top = neck_z - 0.01
    p["torso"] = [(z * top / p["torso"][-1][0], w, f, b) for z, w, f, b in p["torso"]]
    p["shoulder"].z = top - 0.035
    p["neck"] = (collar_top - 0.06, collar_top + 0.04)
    # built centered (x = 0), then moved sideways as one piece; the chin sits 2 cm above the collar
    p["head_c"] = Vector((0.0, cy - 0.017, collar_top + 0.145))
    p["hip"] = Vector((0.09, 0.0, height * 0.55))
    p["knee_z"] = height * 0.29
    bones = N.bones_of(p)
    fit_bones(bones, axes, cx, cy)
    crotch = height * 0.5

    # Match the sheet's hair, cap, glasses and neckline for each occupation.
    colors = H.colors_for(npc_type, female)
    N.make_mats(colors)
    N.make_face_material(H.face_for(npc_type, female, colors))
    head, hair = H.build_head(npc_type, p, female)
    objs = []
    for part, allowed in ((head, ["Head", "neck"]), (hair, ["Head"]), (collar, ["Spine", "neck"])):
        obj = part.build(sharp_deg=80.0)
        obj.data.uv_layers.new(name="UVMap")
        if part.name == "head":
            N.uv_head(obj, p)
        if part.name != "collar":
            for v in obj.data.vertices:
                v.co.x += cx
        N.weight_object(obj, bones, allowed)
        objs.append(obj)

    drapes = skirt or npc_type == "vendor"
    if os.environ.get("NPC_RIG", "auto") != "auto" or not weight_auto(body, bones):
        weight_body(body, bones, axes, crotch, drapes)
    if not drapes:   # a skirt or apron is meant to join the legs
        cut_leg_webs(body, axes, crotch)
    bpy.ops.object.select_all(action="DESELECT")
    for o in [body] + objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()
    body.name = name
    body.data.name = name
    arm = N.make_armature(bones)
    body.parent = arm
    mod = body.modifiers.new("Armature", "ARMATURE")
    mod.object = arm
    tris = sum(len(pl.vertices) - 2 for pl in body.data.polygons)
    print("  %s: %d triangles" % (name, tris))
    os.makedirs(N.OUT_DIR, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(N.OUT_DIR, name + ".blend"))
    # Export outside Godot's watched asset directory, then replace atomically. On
    # Windows a watcher briefly mapping the old GLB can prevent an in-place write.
    staging = os.path.join(os.path.dirname(os.path.abspath(obj_path)), name + "_export.glb")
    bpy.ops.export_scene.gltf(filepath=staging, export_format="GLB")
    target = os.path.join(N.OUT_DIR, name + ".glb")
    for attempt in range(8):
        try:
            os.replace(staging, target)
            break
        except OSError:
            if attempt == 7:
                raise
            time.sleep(0.15 * (attempt + 1))


if __name__ == "__main__":
    main()
