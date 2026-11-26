"""
Converts raw OpenStreetMap data (data/osm_raw/*.json from tools/osm_download.sh)
into game-ready JSON for Godot (data/map/bacolod/).

Map data (c) OpenStreetMap contributors, ODbL.

Run from the project folder:
    python tools/osm_convert.py

Output:
    data/map/bacolod/meta.json     origin, bounds, chunk list, places, POIs, sea, boundary
    data/map/bacolod/graph.json    drivable road network (for GPS, and traffic later)
    data/map/bacolod/chunks/X_Z.json   roads, buildings, areas per 200 m x 200 m chunk

Coordinates: meters. +X = east, -Z = north. (0, 0) = Bacolod Public Plaza.
"""
import json
import math
import os
import random
from collections import defaultdict

RAW = "data/osm_raw"
OUT = "data/map/bacolod"
CHUNK = 200.0

# Bacolod Public Plaza (in front of San Sebastian Cathedral) = world origin
LAT0 = 10.6703
LON0 = 122.9483
M_PER_DEG_LAT = 110540.0
M_PER_DEG_LON = 111320.0 * math.cos(math.radians(LAT0))

# Drivable road classes -> default width in meters
ROAD_WIDTH = {
    "motorway": 16, "trunk": 14, "primary": 12, "secondary": 10, "tertiary": 9,
    "motorway_link": 8, "trunk_link": 8, "primary_link": 8, "secondary_link": 7, "tertiary_link": 7,
    "unclassified": 7, "residential": 6.5, "living_street": 5, "service": 4.5, "road": 6,
}
ROAD_CLASSES = list(ROAD_WIDTH.keys())
SKIP_SERVICE = {"parking_aisle", "drive-through", "emergency_access"}

# Where to put the game's own places (lat, lon targets; the script snaps them to real roads)
HOME_TARGET = (10.6650, 122.9560)        # a residential area ~1 km south-east of the plaza
SCHOOL_TARGET = (10.6780, 122.9400)      # open land in the reclamation area (north-west)

LANDMARKS = [
    # id, display name, name regex parts to search in OSM, fallback lat/lon, clear radius (m)
    ("cathedral", "San Sebastian Cathedral", ["san sebastian cathedral"], (10.6706, 122.9471), 30.0),
    ("plaza", "Bacolod Public Plaza", ["bacolod public plaza", "bacolod city plaza"], (10.6703, 122.9483), 0.0),
    ("capitol", "Provincial Capitol", ["provincial capitol"], (10.6766, 122.9509), 42.0),
    ("lagoon", "Capitol Park & Lagoon", ["capitol lagoon", "capitol park"], (10.6782, 122.9512), 0.0),
    ("sm", "SM City Bacolod", ["sm city bacolod north wing", "sm city bacolod"], (10.6712, 122.9449), 0.0),
    ("ayala", "Ayala Malls Capitol Central", ["capitol central"], (10.6776, 122.9499), 0.0),
]

FOOD_SHOPS = {"convenience", "kiosk", "bakery", "general", "supermarket", "variety_store", "deli"}
FOOD_AMENITIES = {"fast_food", "restaurant", "cafe", "food_court"}
DESTINATION_AMENITIES = {
    "place_of_worship", "school", "college", "university", "hospital", "clinic", "marketplace",
    "townhall", "bank", "pharmacy", "fast_food", "restaurant", "cafe", "police", "library",
    "bus_station", "post_office", "fuel",
}

random.seed(20261126)


# --- Helpers -----------------------------------------------------------------

def proj(lat, lon):
    """lat/lon -> game meters (x east, z south)."""
    return ((lon - LON0) * M_PER_DEG_LON, -(lat - LAT0) * M_PER_DEG_LAT)


def load(name):
    path = os.path.join(RAW, name)
    if not os.path.exists(path):
        print("  (missing %s, skipped)" % name)
        return []
    with open(path, encoding="utf-8") as f:
        return json.load(f).get("elements", [])


def r1(v):
    return round(v, 1)


def dist(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


def simplify(pts, tol):
    """Douglas-Peucker line simplification."""
    if len(pts) < 3:
        return pts
    a, b = pts[0], pts[-1]
    best_i, best_d = 0, 0.0
    ax, az = a
    bx, bz = b
    l2 = (bx - ax) ** 2 + (bz - az) ** 2
    for i in range(1, len(pts) - 1):
        px, pz = pts[i]
        if l2 == 0:
            d = math.hypot(px - ax, pz - az)
        else:
            t = max(0, min(1, ((px - ax) * (bx - ax) + (pz - az) * (bz - az)) / l2))
            d = math.hypot(px - (ax + t * (bx - ax)), pz - (az + t * (bz - az)))
        if d > best_d:
            best_i, best_d = i, d
    if best_d > tol:
        left = simplify(pts[: best_i + 1], tol)
        right = simplify(pts[best_i:], tol)
        return left[:-1] + right
    return [a, b]


def poly_area(p):
    s = 0.0
    for i in range(len(p)):
        x1, z1 = p[i]
        x2, z2 = p[(i + 1) % len(p)]
        s += x1 * z2 - x2 * z1
    return s / 2.0


def centroid(p):
    xs = [q[0] for q in p]
    zs = [q[1] for q in p]
    return (sum(xs) / len(xs), sum(zs) / len(zs))


def point_in_poly(pt, poly):
    x, z = pt
    inside = False
    j = len(poly) - 1
    for i in range(len(poly)):
        xi, zi = poly[i]
        xj, zj = poly[j]
        if (zi > z) != (zj > z) and x < (xj - xi) * (z - zi) / (zj - zi + 1e-12) + xi:
            inside = not inside
        j = i
    return inside


def chunk_key(x, z):
    return "%d_%d" % (math.floor(x / CHUNK), math.floor(z / CHUNK))


def closest_on_segment(p, a, b):
    ax, az = a
    bx, bz = b
    l2 = (bx - ax) ** 2 + (bz - az) ** 2
    t = 0 if l2 == 0 else max(0, min(1, ((p[0] - ax) * (bx - ax) + (p[1] - az) * (bz - az)) / l2))
    return (ax + t * (bx - ax), az + t * (bz - az)), t


def geom_pts(el):
    return [proj(g["lat"], g["lon"]) for g in el.get("geometry", []) if g]


# --- Roads & graph -----------------------------------------------------------

def build_roads(elements):
    ways = []
    use_count = defaultdict(int)
    for el in elements:
        if el.get("type") != "way":
            continue
        tags = el.get("tags", {})
        hw = tags.get("highway")
        if hw not in ROAD_WIDTH:
            continue
        if hw == "service" and tags.get("service") in SKIP_SERVICE:
            continue
        nodes = el.get("nodes", [])
        geom = el.get("geometry", [])
        if len(nodes) != len(geom) or len(nodes) < 2:
            continue
        width = float(ROAD_WIDTH[hw])
        try:
            lanes = int(tags.get("lanes", "0").split(";")[0])
            if lanes > 0:
                width = max(width, min(lanes * 3.3, 20))
        except ValueError:
            pass
        ways.append({
            "id": el["id"], "nodes": nodes, "pts": [proj(g["lat"], g["lon"]) for g in geom],
            "w": width, "k": hw, "name": tags.get("name", ""),
            "oneway": tags.get("oneway") in ("yes", "1", "true") or tags.get("junction") == "roundabout",
        })
        for i, n in enumerate(nodes):
            use_count[n] += 1
            if i in (0, len(nodes) - 1):
                use_count[n] += 1   # endpoints always become graph nodes

    node_index = {}
    graph_nodes = []
    names = [""]
    name_index = {"": 0}
    edges = []

    def gnode(osm_id, pt):
        if osm_id not in node_index:
            node_index[osm_id] = len(graph_nodes)
            graph_nodes.append([r1(pt[0]), r1(pt[1])])
        return node_index[osm_id]

    for w in ways:
        if w["name"] not in name_index:
            name_index[w["name"]] = len(names)
            names.append(w["name"])
        start = 0
        for i in range(1, len(w["nodes"])):
            if use_count[w["nodes"][i]] >= 2 or i == len(w["nodes"]) - 1:
                piece = w["pts"][start: i + 1]
                piece = simplify(piece, 0.8)
                a = gnode(w["nodes"][start], w["pts"][start])
                b = gnode(w["nodes"][i], w["pts"][i])
                if a != b:
                    edges.append({
                        "a": a, "b": b, "w": w["w"], "k": ROAD_CLASSES.index(w["k"]),
                        "n": name_index[w["name"]], "o": 1 if w["oneway"] else 0,
                        "pts": [[r1(x), r1(z)] for x, z in piece],
                    })
                start = i
    return graph_nodes, edges, names


# --- Buildings ---------------------------------------------------------------

def building_height(tags, rng):
    if "height" in tags:
        try:
            return max(3.0, min(80.0, float(tags["height"].replace("m", "").strip())))
        except ValueError:
            pass
    if "building:levels" in tags:
        try:
            return max(1, min(25, int(float(tags["building:levels"])))) * 3.2
        except ValueError:
            pass
    b = tags.get("building", "yes")
    if b in ("church", "cathedral"):
        return 14.0
    if b in ("commercial", "retail", "office", "hotel"):
        return rng.choice([6.4, 9.6, 9.6, 12.8, 16.0])
    if b in ("apartments", "dormitory"):
        return rng.choice([9.6, 12.8, 16.0])
    if b in ("roof", "carport"):
        return 4.0
    if b in ("hut", "shed", "garage"):
        return 3.0
    return rng.choice([3.2, 3.2, 6.4, 6.4, 6.4, 9.6])


def build_buildings(elements):
    out = []
    for el in elements:
        if el.get("type") != "way":
            continue
        pts = geom_pts(el)
        if len(pts) < 4:
            continue
        if pts[0] == pts[-1]:
            pts = pts[:-1]
        pts = simplify(pts + [pts[0]], 0.4)[:-1]
        if len(pts) < 3:
            continue
        area = poly_area(pts)
        if abs(area) < 12.0:
            continue
        if area < 0:
            pts = list(reversed(pts))   # make all footprints the same winding
        tags = el.get("tags", {})
        rng = random.Random(el["id"])
        out.append({
            "id": el["id"],
            "p": [[r1(x), r1(z)] for x, z in pts],
            "h": round(building_height(tags, rng), 1),
            "t": tags.get("building", "yes"),
            "n": tags.get("name", ""),
            "c": rng.randint(0, 11),
            "c0": centroid(pts),
            "a": abs(area),
        })
    return out


# --- Areas (parks, water), rivers, coastline -----------------------------------

def build_areas(elements):
    areas, rivers, coast = [], [], []
    for el in elements:
        tags = el.get("tags", {})
        if el.get("type") == "relation":
            # multipolygon water: just use outer members as separate polygons
            for m in el.get("members", []):
                if m.get("role") == "outer" and m.get("geometry"):
                    pts = [proj(g["lat"], g["lon"]) for g in m["geometry"] if g]
                    if len(pts) >= 4:
                        areas.append({"k": "water", "p": pts[:-1] if pts[0] == pts[-1] else pts})
            continue
        pts = geom_pts(el)
        if len(pts) < 2:
            continue
        if tags.get("natural") == "coastline":
            coast.append({"nodes": el.get("nodes", []), "pts": pts})
            continue
        if "waterway" in tags:
            w = {"river": 14.0, "canal": 6.0, "stream": 3.0}.get(tags["waterway"], 3.0)
            rivers.append({"w": w, "pts": [[r1(x), r1(z)] for x, z in simplify(pts, 1.5)]})
            continue
        if len(pts) < 4 or pts[0] != pts[-1]:
            continue
        pts = simplify(pts, 0.8)[:-1]
        if len(pts) < 3:
            continue
        kind = "park"
        if tags.get("natural") == "water":
            kind = "water"
        elif tags.get("natural") in ("beach", "sand"):
            kind = "beach"
        elif tags.get("leisure") in ("pitch", "stadium"):
            kind = "pitch"
        elif tags.get("landuse") in ("cemetery",):
            kind = "cemetery"
        elif tags.get("landuse") in ("farmland", "meadow", "grass"):
            kind = "grass"
        if poly_area(pts) < 0:
            pts = list(reversed(pts))
        areas.append({"k": kind, "p": pts, "n": tags.get("name", "")})
    return areas, rivers, coast


def build_sea(coast, west_x):
    """Chain coastline pieces into one line and close it to the west (Bacolod's sea side)."""
    if not coast:
        return []
    pieces = [c["pts"] for c in coast]
    line = pieces.pop(0)
    changed = True
    while pieces and changed:
        changed = False
        for i, p in enumerate(pieces):
            if dist(line[-1], p[0]) < 1.0:
                line = line + p[1:]
            elif dist(p[-1], line[0]) < 1.0:
                line = p[:-1] + line
            elif dist(line[-1], p[-1]) < 1.0:
                line = line + list(reversed(p))[1:]
            elif dist(p[0], line[0]) < 1.0:
                line = list(reversed(p))[:-1] + line
            else:
                continue
            pieces.pop(i)
            changed = True
            break
    # Add the longest leftover piece if chaining failed badly
    line = simplify(line, 2.0)
    if len(line) < 2:
        return []
    far = west_x - 3000.0
    first, last = line[0], line[-1]
    poly = line + [(far, last[1]), (far, first[1])]
    if poly_area(poly) < 0:
        poly = list(reversed(poly))
    return [[r1(x), r1(z)] for x, z in poly]


def build_boundary(elements):
    polys = []
    for el in elements:
        if el.get("type") != "relation":
            continue
        name = el.get("tags", {}).get("name", "")
        if "Bacolod" not in name:
            continue
        for m in el.get("members", []):
            if m.get("role") == "outer" and m.get("geometry"):
                polys.append([proj(g["lat"], g["lon"]) for g in m["geometry"] if g])
        if polys:
            break
    if not polys:
        return []
    # Chain outer ways into one ring
    ring = polys.pop(0)
    while polys:
        best = None
        for i, p in enumerate(polys):
            for rev in (False, True):
                q = list(reversed(p)) if rev else p
                d = dist(ring[-1], q[0])
                if best is None or d < best[0]:
                    best = (d, i, q)
        _, i, q = best
        ring = ring + q[1:]
        polys.pop(i)
    ring = simplify(ring, 10.0)
    return [[r1(x), r1(z)] for x, z in ring]


# --- POIs --------------------------------------------------------------------

def build_pois(elements):
    pois = []
    for el in elements:
        tags = el.get("tags", {})
        if el.get("type") == "node":
            lat, lon = el.get("lat"), el.get("lon")
        else:
            c = el.get("center")
            if not c:
                continue
            lat, lon = c["lat"], c["lon"]
        if lat is None:
            continue
        x, z = proj(lat, lon)
        pois.append({
            "x": r1(x), "z": r1(z), "name": tags.get("name", ""),
            "amenity": tags.get("amenity", ""), "shop": tags.get("shop", ""),
            "tourism": tags.get("tourism", ""), "leisure": tags.get("leisure", ""),
        })
    return pois


# --- Snapping things to roads ------------------------------------------------

class RoadIndex:
    """Grid index of road segments so we can find the nearest road quickly."""

    def __init__(self, nodes, edges, cell=60.0):
        self.cell = cell
        self.grid = defaultdict(list)
        self.edges = edges
        for ei, e in enumerate(edges):
            pts = e["pts"]
            for i in range(len(pts) - 1):
                a, b = pts[i], pts[i + 1]
                for gx in range(int(math.floor(min(a[0], b[0]) / cell)), int(math.floor(max(a[0], b[0]) / cell)) + 1):
                    for gz in range(int(math.floor(min(a[1], b[1]) / cell)), int(math.floor(max(a[1], b[1]) / cell)) + 1):
                        self.grid[(gx, gz)].append((ei, i))

    def nearest(self, p, classes=None, max_r=3):
        best = None
        cx, cz = int(math.floor(p[0] / self.cell)), int(math.floor(p[1] / self.cell))
        for r in range(max_r + 1):
            for gx in range(cx - r, cx + r + 1):
                for gz in range(cz - r, cz + r + 1):
                    for ei, si in self.grid.get((gx, gz), []):
                        e = self.edges[ei]
                        if classes is not None and ROAD_CLASSES[e["k"]] not in classes:
                            continue
                        q, _ = closest_on_segment(p, e["pts"][si], e["pts"][si + 1])
                        d = dist(p, q)
                        if best is None or d < best[0]:
                            best = (d, ei, si, q)
            if best is not None and best[0] < r * self.cell:
                break
        return best

    def sidewalk_spot(self, p, extra=1.6, classes=None):
        """Point on the sidewalk next to the road nearest p, on p's side. Returns (spot, toward_road)."""
        hit = self.nearest(p, classes)
        if hit is None:
            return None
        d, ei, si, q = hit
        e = self.edges[ei]
        a, b = e["pts"][si], e["pts"][si + 1]
        dx, dz = b[0] - a[0], b[1] - a[1]
        ln = math.hypot(dx, dz) or 1.0
        nx, nz = -dz / ln, dx / ln
        side = 1.0 if (p[0] - q[0]) * nx + (p[1] - q[1]) * nz >= 0 else -1.0
        off = e["w"] * 0.5 + extra
        spot = (q[0] + nx * side * off, q[1] + nz * side * off)
        return spot, (-nx * side, -nz * side), e, q


def empty_spot(buildings_grid, center, radius, rng_try=40, search=400.0, road_index=None):
    """Find a place near `center` with no building centroid within `radius`, next to a road."""
    rng = random.Random(7)
    best = None
    for i in range(rng_try * 10):
        ang = rng.uniform(0, math.tau)
        r = rng.uniform(0, search)
        p = (center[0] + math.cos(ang) * r, center[1] + math.sin(ang) * r)
        hit = road_index.nearest(p, {"residential", "tertiary", "unclassified", "secondary"})
        if hit is None or hit[0] > radius + 12 or hit[0] < radius * 0.7:
            continue
        crowd = count_near(buildings_grid, p, radius)
        score = crowd * 1000 + dist(p, center)
        if best is None or score < best[0]:
            best = (score, p)
        if crowd == 0 and dist(p, center) < search * 0.5:
            break
    return best[1] if best else center


def grid_buildings(buildings, cell=50.0):
    g = defaultdict(list)
    for bi, b in enumerate(buildings):
        g[(int(math.floor(b["c0"][0] / cell)), int(math.floor(b["c0"][1] / cell)))].append(bi)
    return g, buildings, cell


def count_near(bgrid, p, r):
    g, buildings, cell = bgrid
    n = 0
    cx, cz = int(math.floor(p[0] / cell)), int(math.floor(p[1] / cell))
    k = int(math.ceil(r / cell))
    for gx in range(cx - k, cx + k + 1):
        for gz in range(cz - k, cz + k + 1):
            for bi in g.get((gx, gz), []):
                if dist(buildings[bi]["c0"], p) < r:
                    n += 1
    return n


# --- Buildings on roads ---------------------------------------------------------
# OpenStreetMap buildings and roads are drawn by different people, and our road widths are
# estimates, so some buildings poke into the street (or even sit across it, like covered
# walkways/bridgeways over a road). In the game that looks like a building blocking the lane.
# Fix: buildings that a road runs THROUGH are removed; buildings that only poke into the lane
# get those corners pushed back to the curb.

SKIP_CLASSES = {"footway", "path", "pedestrian", "steps", "track", "service", "cycleway"}
CURB_GAP = 0.4    # keep corners at least this far outside the road edge


def _point_in_poly(p, poly):
    x, z = p
    inside = False
    for i in range(len(poly)):
        x1, z1 = poly[i]
        x2, z2 = poly[(i + 1) % len(poly)]
        if (z1 > z) != (z2 > z) and x < (x2 - x1) * (z - z1) / (z2 - z1) + x1:
            inside = not inside
    return inside


def fix_buildings_on_roads(buildings, road_index):
    kept, removed, pushed = [], 0, 0
    cell = road_index.cell
    for b in buildings:
        poly = [list(q) for q in b["p"]]
        xs = [q[0] for q in poly]
        zs = [q[1] for q in poly]
        segs = set()
        for gx in range(int(math.floor(min(xs) / cell)) - 1, int(math.floor(max(xs) / cell)) + 2):
            for gz in range(int(math.floor(min(zs) / cell)) - 1, int(math.floor(max(zs) / cell)) + 2):
                for ei, si in road_index.grid.get((gx, gz), []):
                    if ROAD_CLASSES[road_index.edges[ei]["k"]] not in SKIP_CLASSES:
                        segs.add((ei, si))
        if not segs:
            kept.append(b)
            continue
        # 1) a road runs through the footprint -> remove the building
        through = False
        for ei, si in segs:
            a = road_index.edges[ei]["pts"][si]
            c = road_index.edges[ei]["pts"][si + 1]
            n = max(2, int(dist(a, c)))
            for k in range(n + 1):
                t = k / n
                if _point_in_poly((a[0] + (c[0] - a[0]) * t, a[1] + (c[1] - a[1]) * t), poly):
                    through = True
                    break
            if through:
                break
        if through:
            removed += 1
            continue
        # 2) corners inside the road corridor -> push them back to the curb
        moved = False
        too_deep = False
        for _ in range(3):
            changed = False
            for vi, v in enumerate(poly):
                for ei, si in segs:
                    e = road_index.edges[ei]
                    q, _t = closest_on_segment(v, e["pts"][si], e["pts"][si + 1])
                    d = dist(v, q)
                    limit = e["w"] * 0.5 + CURB_GAP
                    if d >= limit:
                        continue
                    if limit - d > 4.0 or d < 0.05:
                        too_deep = True
                        break
                    k = limit / d
                    poly[vi] = [q[0] + (v[0] - q[0]) * k, q[1] + (v[1] - q[1]) * k]
                    v = poly[vi]
                    changed = moved = True
                if too_deep:
                    break
            if too_deep or not changed:
                break
        if too_deep:
            removed += 1
            continue
        if moved:
            area = poly_area(poly)
            orig = poly_area(b["p"])
            if area * orig <= 0 or abs(area) < 0.4 * abs(orig):
                removed += 1   # pushing made it too thin / twisted: drop it
                continue
            b = dict(b)
            b["p"] = [[r1(x), r1(z)] for x, z in poly]
            pushed += 1
        kept.append(b)
    return kept, removed, pushed


# --- Filler buildings ----------------------------------------------------------
# OpenStreetMap doesn't have every building in Bacolod mapped, which leaves streets
# looking empty. Where a street has no mapped buildings, we add simple houses/stores
# along it (only on free land: not on roads, other buildings, parks, water or game places).

OCC = 2.0   # occupancy grid cell size (m) for existing buildings / parks


def occ_cell(x, z):
    return (int(math.floor(x / OCC)), int(math.floor(z / OCC)))


def mark_rect_cells(occ, x0, z0, x1, z1):
    for ix in range(int(math.floor(x0 / OCC)), int(math.floor(x1 / OCC)) + 1):
        for iz in range(int(math.floor(z0 / OCC)), int(math.floor(z1 / OCC)) + 1):
            occ.add((ix, iz))


def build_occupancy(buildings, edges, areas):
    occ = set()
    for b in buildings:
        xs = [q[0] for q in b["p"]]
        zs = [q[1] for q in b["p"]]
        mark_rect_cells(occ, min(xs), min(zs), max(xs), max(zs))
    for a in areas:
        if a["k"] in ("water", "park", "pitch", "beach", "cemetery"):
            xs = [q[0] for q in a["p"]]
            zs = [q[1] for q in a["p"]]
            # coarse: mark the inside of the polygon on a 6 m grid
            for x in range(int(min(xs)), int(max(xs)) + 1, 6):
                for z in range(int(min(zs)), int(max(zs)) + 1, 6):
                    if point_in_poly((x, z), a["p"]):
                        mark_rect_cells(occ, x - 3, z - 3, x + 3, z + 3)
    return occ


def clear_of_roads(road_index, x, z):
    """True if (x, z) is at least 1 m outside every road's edge."""
    hit = road_index.nearest((x, z), None, 1)
    if hit is None:
        return True
    d, ei, si, q = hit
    return d - road_index.edges[ei]["w"] * 0.5 >= 1.0


def make_fillers(edges, occ, exclusions, sea, limit_r, road_index):
    rng = random.Random(99)
    out = []
    big = {"primary", "secondary", "trunk", "tertiary"}
    for e in edges:
        cls = ROAD_CLASSES[e["k"]]
        if cls not in big and cls not in ("residential", "unclassified", "living_street"):
            continue
        pts = e["pts"]
        for i in range(len(pts) - 1):
            a, b = pts[i], pts[i + 1]
            seg = dist(a, b)
            if seg < 8:
                continue
            dx, dz = (b[0] - a[0]) / seg, (b[1] - a[1]) / seg
            nx, nz = -dz, dx
            for side in (-1, 1):
                t = rng.uniform(2, 6)
                while t < seg - 3:
                    width = rng.uniform(6, 10) if cls not in big else rng.uniform(8, 14)
                    depth = rng.uniform(7, 12) if cls not in big else rng.uniform(10, 16)
                    cx = a[0] + dx * (t + width / 2) + nx * side * (e["w"] / 2 + 2.6 + depth / 2)
                    cz = a[1] + dz * (t + width / 2) + nz * side * (e["w"] / 2 + 2.6 + depth / 2)
                    t += width + rng.uniform(0.8, 3.0)
                    if math.hypot(cx, cz) > limit_r:
                        continue
                    if any(dist((cx, cz), (ex, ez)) < er + 8 for ex, ez, er in exclusions):
                        continue
                    if sea and point_in_poly((cx, cz), sea):
                        continue
                    # rectangle corners (along road = d, away from road = n*side)
                    hw, hd = width / 2, depth / 2
                    corners = []
                    for su, sv in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
                        corners.append((cx + dx * su * hw + nx * side * sv * hd, cz + dz * su * hw + nz * side * sv * hd))
                    # free? sample inside the rectangle
                    free = True
                    for su in (-0.9, -0.3, 0.3, 0.9):
                        for sv in (-0.9, -0.3, 0.3, 0.9):
                            x = cx + dx * su * hw + nx * side * sv * hd
                            z = cz + dz * su * hw + nz * side * sv * hd
                            if occ_cell(x, z) in occ:
                                free = False
                                break
                        if not free:
                            break
                    if not free:
                        continue
                    if not all(clear_of_roads(road_index, x, z) for x, z in corners + [(cx, cz)]):
                        continue
                    xs = [q[0] for q in corners]
                    zs = [q[1] for q in corners]
                    mark_rect_cells(occ, min(xs), min(zs), max(xs), max(zs))
                    if poly_area(corners) < 0:
                        corners = list(reversed(corners))
                    if cls in big:
                        h = rng.choice([6.4, 6.4, 9.6, 9.6, 12.8])
                    else:
                        h = rng.choice([3.2, 3.2, 3.2, 6.4, 6.4, 9.6])
                    out.append({"p": [[r1(x), r1(z)] for x, z in corners], "h": h, "c": rng.randint(0, 11),
                                "t": "filler", "n": "", "c0": (cx, cz)})
    return out


# --- Main ---------------------------------------------------------------------

def main():
    print("Loading raw OSM data...")
    road_el = load("roads.json")
    building_el = load("buildings.json")
    area_el = load("areas.json") + load("coast.json")
    poi_el = load("pois.json")
    boundary_el = load("boundary.json")

    print("Roads...")
    nodes, edges, names = build_roads(road_el)
    print("  %d graph nodes, %d road pieces" % (len(nodes), len(edges)))
    road_index = RoadIndex(nodes, edges)

    print("Buildings...")
    buildings = build_buildings(building_el)
    print("  %d buildings" % len(buildings))
    bgrid = grid_buildings(buildings)

    print("Areas...")
    areas, rivers, coast = build_areas(area_el)
    all_x = [n[0] for n in nodes]
    all_z = [n[1] for n in nodes]
    bounds = [min(all_x), min(all_z), max(all_x), max(all_z)]
    sea = build_sea(coast, bounds[0])
    print("  %d areas, %d rivers, coastline pieces %d, sea polygon %d pts" % (len(areas), len(rivers), len(coast), len(sea)))
    boundary = build_boundary(boundary_el)
    print("  city boundary: %d points" % len(boundary))

    print("POIs...")
    pois = build_pois(poi_el)
    print("  %d POIs" % len(pois))

    # --- Landmarks: find them by name in POIs / buildings / areas ---
    landmarks = []
    named = [(p["name"].lower(), (p["x"], p["z"])) for p in pois if p["name"]]
    named += [(b["n"].lower(), b["c0"]) for b in buildings if b["n"]]
    named += [(a.get("n", "").lower(), centroid(a["p"])) for a in areas if a.get("n")]
    for lid, label, keys, fallback, clear in LANDMARKS:
        pos = None
        for nm, pt in named:
            if any(k in nm for k in keys):
                pos = pt
                break
        if pos is None:
            pos = proj(*fallback)
            print("  landmark %s: not found by name, using fallback" % lid)
        else:
            print("  landmark %s at (%.0f, %.0f)" % (lid, pos[0], pos[1]))
        landmarks.append({"id": lid, "name": label, "x": r1(pos[0]), "z": r1(pos[1]), "clear": clear})

    # --- Game places ---
    places = []
    exclusions = []   # (x, z, radius): buildings removed here

    def add_place(pid, ptype, name, spot_info, clear_r):
        spot, toward, e, q = spot_info
        door = (spot[0], spot[1])
        places.append({"id": pid, "type": ptype, "name": name, "x": r1(door[0]), "z": r1(door[1]),
                       "fx": round(toward[0], 3), "fz": round(toward[1], 3)})
        if clear_r > 0:
            # clear the lot behind the door (away from the road)
            cx = door[0] - toward[0] * (clear_r * 0.9)
            cz = door[1] - toward[1] * (clear_r * 0.9)
            exclusions.append((cx, cz, clear_r))

    home_p = proj(*HOME_TARGET)
    home = road_index.sidewalk_spot(home_p, 1.6, {"residential", "unclassified", "living_street"})
    add_place("home", "home", "Balay (Home)", home, 9.0)
    # Motor shop: on a bigger road a short walk (40-250 m) from home
    shop = None
    for r in range(60, 260, 20):
        for k in range(12):
            ang = k * math.tau / 12
            probe = (home[0][0] + math.cos(ang) * r, home[0][1] + math.sin(ang) * r)
            info = road_index.sidewalk_spot(probe, 1.6, {"tertiary", "secondary", "primary"})
            if info and 40 < dist(info[0], home[0]) < 250 and (shop is None or dist(info[0], home[0]) < dist(shop[0], home[0])):
                shop = info
        if shop:
            break
    if shop is None:
        shop = road_index.sidewalk_spot((home[0][0] + 80, home[0][1]), 1.6)
    add_place("motor_shop", "motor_shop", "Motor Shop", shop, 10.0)
    school_center = empty_spot(bgrid, proj(*SCHOOL_TARGET), 30.0, road_index=road_index)
    school = road_index.sidewalk_spot(school_center, 1.6)
    add_place("driving_school", "driving_school", "Driving School", school, 34.0)
    print("  home (%.0f, %.0f), shop (%.0f, %.0f), school (%.0f, %.0f)" % (
        home[0][0], home[0][1], shop[0][0], shop[0][1], school[0][0], school[0][1]))

    # Gas stations and clinics from OSM
    gas_n = clinic_n = 0
    for p in pois:
        if p["amenity"] == "fuel":
            info = road_index.sidewalk_spot((p["x"], p["z"]), 5.0)
            if info is None or info[0] and dist(info[0], (p["x"], p["z"])) > 80:
                continue
            gas_n += 1
            spot, toward, e, q = info
            places.append({"id": "gas_station_%d" % gas_n, "type": "gas_station", "name": "Gasolinahan",
                           "x": r1(spot[0]), "z": r1(spot[1]), "fx": round(toward[0], 3), "fz": round(toward[1], 3)})
            exclusions.append((spot[0], spot[1], 9.0))
        elif p["amenity"] in ("hospital", "clinic") and p["name"]:
            info = road_index.sidewalk_spot((p["x"], p["z"]), 1.6)
            if info is None:
                continue
            clinic_n += 1
            spot, toward, e, q = info
            places.append({"id": "clinic_%d" % clinic_n, "type": "clinic", "name": p["name"],
                           "x": r1(spot[0]), "z": r1(spot[1]), "fx": round(toward[0], 3), "fz": round(toward[1], 3)})
    if clinic_n == 0:
        info = road_index.sidewalk_spot((home[0][0] + 150, home[0][1]), 1.6)
        spot, toward, e, q = info
        places.append({"id": "clinic_1", "type": "clinic", "name": "Clinic", "x": r1(spot[0]), "z": r1(spot[1]),
                       "fx": round(toward[0], 3), "fz": round(toward[1], 3)})
    print("  %d gas stations, %d clinics" % (gas_n, clinic_n))

    for lm in landmarks:
        if lm["clear"] > 0:
            exclusions.append((lm["x"], lm["z"], lm["clear"]))

    # --- Food stalls: real food shops + generated sari-sari stores along residential roads ---
    stalls = []
    for p in pois:
        if p["shop"] in FOOD_SHOPS or p["amenity"] in FOOD_AMENITIES:
            info = road_index.sidewalk_spot((p["x"], p["z"]), 1.4)
            if info and dist(info[0], (p["x"], p["z"])) < 40:
                stalls.append({"x": r1(info[0][0]), "z": r1(info[0][1]), "n": p["name"], "gen": 0})
    rng = random.Random(42)
    for e in edges:
        if ROAD_CLASSES[e["k"]] not in ("residential", "unclassified", "tertiary"):
            continue
        pts = e["pts"]
        for i in range(len(pts) - 1):
            a, b = pts[i], pts[i + 1]
            seg = dist(a, b)
            if seg < 30 or rng.random() > seg / 700.0:
                continue
            t = rng.uniform(0.25, 0.75)
            q = (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
            nx, nz = -(b[1] - a[1]) / seg, (b[0] - a[0]) / seg
            side = rng.choice([-1, 1])
            off = e["w"] * 0.5 + 1.4
            sp = (q[0] + nx * side * off, q[1] + nz * side * off)
            stalls.append({"x": r1(sp[0]), "z": r1(sp[1]), "n": "", "gen": 1,
                           "fx": round(-nx * side, 3), "fz": round(-nz * side, 3)})
    print("  %d food stalls" % len(stalls))

    # --- Address points (pickup / drop-off spots) ---
    named_pois = [p for p in pois if p["name"] and (p["amenity"] in DESTINATION_AMENITIES or p["shop"] or p["tourism"])]
    poi_grid = defaultdict(list)
    for p in named_pois:
        poi_grid[(int(p["x"] // 60), int(p["z"] // 60))].append(p)
    kinds = ["House", "Apartment", "Sari-sari store", "Waiting shed", "Barangay hall", "Boarding house",
             "Carinderia", "Bakery", "Chapel", "Vulcanizing shop"]
    addresses = []
    for e in edges:
        cls = ROAD_CLASSES[e["k"]]
        if cls in ("service", "motorway", "motorway_link", "trunk_link", "primary_link"):
            continue
        street = names[e["n"]]
        pts = e["pts"]
        acc = 0.0
        for i in range(len(pts) - 1):
            a, b = pts[i], pts[i + 1]
            seg = dist(a, b)
            if seg < 1:
                continue
            nx, nz = -(b[1] - a[1]) / seg, (b[0] - a[0]) / seg
            t = 0.0
            while t < seg:
                if acc >= 90.0:
                    acc = 0.0
                    q = (a[0] + (b[0] - a[0]) * t / seg, a[1] + (b[1] - a[1]) * t / seg)
                    side = rng.choice([-1, 1])
                    off = e["w"] * 0.5 + 1.6
                    sp = (q[0] + nx * side * off, q[1] + nz * side * off)
                    # label: nearby named place, else "<kind>, <street>"
                    label = ""
                    gx, gz = int(sp[0] // 60), int(sp[1] // 60)
                    bestd = 45.0
                    for ddx in (-1, 0, 1):
                        for ddz in (-1, 0, 1):
                            for p in poi_grid.get((gx + ddx, gz + ddz), []):
                                d = dist((p["x"], p["z"]), sp)
                                if d < bestd:
                                    bestd, label = d, p["name"]
                    if not label:
                        label = "%s, %s" % (rng.choice(kinds), street) if street else "%s (near %s)" % (rng.choice(kinds), cls.replace("_", " "))
                        if not street:
                            continue   # skip unnamed small roads without a landmark nearby
                    addresses.append({"x": r1(sp[0]), "z": r1(sp[1]), "rx": round(-nx * side, 3),
                                      "rz": round(-nz * side, 3), "s": street, "l": label})
                step = min(seg - t, 90.0 - acc)
                t += max(step, 0.5)
                acc += max(step, 0.5)
    print("  %d address points" % len(addresses))

    # --- Filler buildings on empty streets (within ~3.5 km of the plaza) ---
    occ = build_occupancy(buildings, edges, areas)
    fillers = make_fillers(edges, occ, exclusions, sea, 3500.0, road_index)
    print("  %d filler buildings added on empty streets" % len(fillers))
    buildings = buildings + fillers
    buildings, gone, pushed = fix_buildings_on_roads(buildings, road_index)
    print("  buildings on roads: %d removed (road runs through them), %d trimmed back to the curb" % (gone, pushed))

    # --- Chunks ---
    print("Writing chunks...")
    chunks = defaultdict(lambda: {"roads": [], "buildings": [], "areas": [], "rivers": []})
    removed = 0
    for b in buildings:
        if any(dist(b["c0"], (ex, ez)) < er for ex, ez, er in exclusions):
            removed += 1
            continue
        chunks[chunk_key(*b["c0"])]["buildings"].append({"p": b["p"], "h": b["h"], "c": b["c"], "t": b["t"], "n": b["n"]})
    for e in edges:
        pts = e["pts"]
        mid = pts[len(pts) // 2]
        chunks[chunk_key(*mid)]["roads"].append({"pts": pts, "w": e["w"], "k": ROAD_CLASSES[e["k"]], "n": names[e["n"]]})
    big_areas = []
    for a in areas:
        xs = [q[0] for q in a["p"]]
        zs = [q[1] for q in a["p"]]
        if max(xs) - min(xs) > CHUNK * 1.5 or max(zs) - min(zs) > CHUNK * 1.5:
            big_areas.append({"k": a["k"], "p": [[r1(x), r1(z)] for x, z in a["p"]]})
        else:
            chunks[chunk_key(*centroid(a["p"]))]["areas"].append({"k": a["k"], "p": [[r1(x), r1(z)] for x, z in a["p"]]})
    for rv in rivers:
        mid = rv["pts"][len(rv["pts"]) // 2]
        chunks[chunk_key(*mid)]["rivers"].append(rv)
    print("  %d buildings cleared for game places/landmarks" % removed)

    os.makedirs(os.path.join(OUT, "chunks"), exist_ok=True)
    for f in os.listdir(os.path.join(OUT, "chunks")):
        os.remove(os.path.join(OUT, "chunks", f))
    for key, data in chunks.items():
        with open(os.path.join(OUT, "chunks", key + ".json"), "w", encoding="utf-8") as f:
            json.dump(data, f, separators=(",", ":"))

    meta = {
        "credit": "Map data (c) OpenStreetMap contributors, ODbL",
        "origin": [LAT0, LON0], "chunk_size": CHUNK,
        "bounds": [r1(v) for v in bounds],
        "chunks": sorted(chunks.keys()),
        "places": places, "landmarks": landmarks, "food_stalls": stalls,
        "addresses": addresses, "sea": sea, "boundary": boundary, "big_areas": big_areas,
    }
    with open(os.path.join(OUT, "meta.json"), "w", encoding="utf-8") as f:
        json.dump(meta, f, separators=(",", ":"))
    with open(os.path.join(OUT, "graph.json"), "w", encoding="utf-8") as f:
        json.dump({"nodes": nodes, "edges": edges, "names": names, "classes": ROAD_CLASSES}, f, separators=(",", ":"))

    total = sum(os.path.getsize(os.path.join(OUT, "chunks", f)) for f in os.listdir(os.path.join(OUT, "chunks")))
    print("Done: %d chunks (%.1f MB), meta %.1f MB, graph %.1f MB" % (
        len(chunks), total / 1e6, os.path.getsize(os.path.join(OUT, "meta.json")) / 1e6,
        os.path.getsize(os.path.join(OUT, "graph.json")) / 1e6))


if __name__ == "__main__":
    main()
