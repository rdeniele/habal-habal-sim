"""Type-specific anime heads for the TripoSR NPC bodies; vendor heads stay unchanged."""
import math

import numpy as np
from mathutils import Vector

import make_npc as N
from shapes import Part, loft, sweep, tube, circle, rrect, rbox

TYPES = ("vendor", "enforcer", "customer", "pedestrian", "fellow_rider",
         "office_worker", "student", "technician", "delivery", "misc")


def colors_for(kind, female):
    if kind not in TYPES:
        raise ValueError("Unknown NPC type: " + kind)
    colors = {"Skin": "#d39b6e" if female else "#c98d61", "Hair": "#29221f",
              "Cloth": "#d98c8a" if female else "#efe9dc", "Headwear": "#454c59",
              "HeadwearTrim": "#303640", "Badge": "#bb9859", "Frame": "#383632",
              "HairTie": "#b86e66"}
    shirts = {"vendor": ("#46464c", "#c4807e"), "enforcer": ("#8999b3", "#8999b3"),
              "customer": ("#e3d8cb", "#e4d4bf"), "pedestrian": ("#48464a", "#b9987c"),
              "fellow_rider": ("#404c35", "#404c35"), "office_worker": ("#b6a9b7", "#e2d8cd"),
              "student": ("#e3dad2", "#e3dad2"), "technician": ("#444951", "#444951"),
              "delivery": ("#cf773b", "#c78077"), "misc": ("#e5d6bd", "#bc8077")}
    colors["Shirt"] = shirts[kind][int(female)]
    if kind == "vendor":
        colors["Hair"] = "#2a1f1a" if female else "#1d1a19"
    if kind == "pedestrian" and female:
        colors["Headwear"] = "#ba9875"
        colors["HeadwearTrim"] = "#9c7b5e"
    if kind == "delivery" and female:
        colors["Headwear"] = "#bb7775"
        colors["HeadwearTrim"] = "#975f61"
    if kind == "misc":
        colors["Skin"] = "#cd9469" if not female else "#d39e79"
        colors["Hair"] = "#34302a" if not female else "#79736e"
        colors["Headwear"] = "#bd965d"
        colors["HeadwearTrim"] = "#70543b"
    return colors


def face_for(kind, female, colors):
    image = N.paint_face("face", colors["Skin"], colors["Hair"], female, blush=kind != "misc")
    if kind == "misc":
        # Age lines painted in the face UV space, matching the existing face painter.
        pixels = np.array(image.pixels[:], dtype=np.float32).reshape(256, 512, 4)[::-1].copy()
        for side in (-1, 1):
            x = 256 + side * 43
            for y in (133, 142, 172):
                pixels[y:y+1, x-4:x+5, :3] *= 0.66
        for y in (91, 97):
            pixels[y, 243:269, :3] *= 0.82
        image.pixels.foreach_set(pixels[::-1].copy().ravel())
        image.pack()
    return image


def short_hair(hair, p, capped=False, neat=False):
    N.hair_shell(hair, p, 1.055, 0.075, -0.055, "Hair", bumpy=0.008 if neat else 0.02)
    for a in (-0.65, -0.34, 0.0, 0.34, 0.65):
        N.tuft(hair, N.on_head(p, a, 0.08), (0.15, -0.35, -0.9),
               0.023, 0.045 if neat else 0.055, "Hair", sides=6)
    if not capped:
        for a in (-2.7, -1.7, -0.7, 0.8, 1.8, 2.8):
            N.tuft(hair, N.on_head(p, a, 0.10), (math.sin(a)*0.65, 0.25, 0.3),
                   0.034, 0.038 if neat else 0.057, "Hair", sides=6)


def ponytail(hair, p, length=0.21, high=False, bun=False):
    c = p["head_c"]
    z = c.z + (0.055 if high else -0.005)
    y = c.y + 0.105
    if bun:
        rows = [(z+0.025, 0.008), (z+0.005, 0.047), (z-0.03, 0.052), (z-0.065, 0.032), (z-0.075, 0.008)]
        loft(hair, [N.ring(dz, 0, y+0.02, r, r, r, n=2, count=14) for dz,r in rows], "Hair")
    else:
        path = [(0, y, z), (0.015, y+0.055, z+0.018), (0.025, y+0.085, z-0.04),
                (0.045, y+0.08, z-length*0.65), (0.035, y+0.055, z-length)]
        sweep(hair, N.catmull(path, 3), rrect(0.044, 0.032, n=12, e=2), "Hair",
              scales=[1.0-(i/(12))*0.7 for i in range(13)])
    tube(hair, (0, y-0.008, z), (0, y+0.02, z), 0.027, "HairTie", sides=12)


def long_hair(hair, p):
    c = p["head_c"]
    # Broad curtain behind the neck; front stays clear for the face and hoodie.
    rows = []
    for dz,w in ((0.07,0.092),(-0.01,0.117),(-0.13,0.12),(-0.27,0.11),(-0.31,0.095)):
        rows.append([Vector((w*math.cos(math.pi*i/16), c.y+0.035+0.095*math.sin(math.pi*i/16), c.z+dz))
                     for i in range(17)])
    N.panel(hair, rows, 0.018, "Hair")


def cap(hair, p, backward=False, badge=False):
    c = p["head_c"]
    loft(hair, [N.ring(c.z+z, 0, c.y+0.005, w, d, d, n=2.3, count=28)
                for z,w,d in ((0.063,0.118,0.119),(0.084,0.12,0.12),
                              (0.145,0.103,0.10),(0.175,0.055,0.058),(0.18,0.004,0.004))], "Headwear")
    direction = 1 if backward else -1
    # Curved visor: a closed, thin panel extending from the cap's front band.
    rows = []
    for t in (0,0.5,1):
        row=[]
        for i in range(17):
            a=-math.pi/2 + math.pi*i/16
            row.append(Vector((math.sin(a)*(0.106+0.017*t),
                       c.y + direction*(0.08 + math.cos(a)*(0.025+0.12*t)),
                       c.z+0.073 - 0.014*t + 0.01*math.sin(a)**2)))
        rows.append(row)
    N.panel(hair, rows, 0.006, "Headwear")
    if badge:
        rbox(hair, (0,c.y-0.106,c.z+0.118), (0.036,0.012,0.038), "Badge", bevel=0.009, segs=3)
        rbox(hair, (0,c.y-0.114,c.z+0.118), (0.013,0.004,0.018), "HeadwearTrim", bevel=0.003)


def straw_hat(hair, p):
    c = p["head_c"]
    loft(hair, [N.ring(c.z+z, 0,c.y,w,d,d,n=2,count=36)
                for z,w,d in ((0.052,0.203,0.18),(0.068,0.202,0.179),
                              (0.082,0.121,0.119),(0.17,0.102,0.103),
                              (0.185,0.075,0.078),(0.19,0.004,0.004))], "Headwear")
    loft(hair, [N.ring(c.z+z,0,c.y,0.123,0.12,0.12,n=2,count=36)
                for z in (0.081,0.102)], "HeadwearTrim", cap0=False,cap1=False)


def glasses(hair, p):
    c = p["head_c"]
    for side in (-1,1):
        path = [(side*0.045 + 0.036*math.cos(math.tau*i/32),
                 c.y-0.108+0.008*abs(math.cos(math.tau*i/32)),
                 c.z-0.009+0.027*math.sin(math.tau*i/32)) for i in range(33)]
        sweep(hair, path, circle(0.0026,6), "Frame", caps=False)
        tube(hair,(side*0.08,c.y-0.098,c.z-0.005),(side*0.113,c.y+0.018,c.z+0.002),0.0025,"Frame",sides=6)
    tube(hair,(-0.012,c.y-0.11,c.z-0.005),(0.012,c.y-0.11,c.z-0.005),0.0025,"Frame",sides=6)


def build_head(kind, p, female):
    if kind == "vendor":
        return N.vendor_head(p, female)
    if kind not in TYPES:
        raise ValueError("Unknown NPC type: " + kind)
    head, hair = N.build_head(p,"Skin"), Part("hair")
    capped = kind in ("enforcer","pedestrian","technician","delivery")
    short_hair(hair,p,capped=capped,neat=kind in ("office_worker","enforcer","misc"))
    if female:
        if kind in ("customer","misc"):
            ponytail(hair,p,bun=True)
        elif kind == "pedestrian":
            long_hair(hair,p)
        else:
            ponytail(hair,p,length=0.26 if kind=="student" else 0.18,
                     high=kind in ("student","fellow_rider"))
    if capped:
        cap(hair,p,backward=(kind in ("pedestrian","technician") and not female),badge=kind=="enforcer")
    if kind == "office_worker":
        glasses(hair,p)
    if kind == "misc" and not female:
        straw_hat(hair,p)
    return head,hair
