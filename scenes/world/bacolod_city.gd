class_name BacolodCity
extends GameWorld
## The real Bacolod City, built from OpenStreetMap data (tools/osm_convert.py output).
## Map data (c) OpenStreetMap contributors, ODbL.
##
## Always loaded: ground, sea, big parks, road graph (GPS), game places, landmarks, mountains.
## Streamed in 200 m chunks around the player: roads, buildings, small parks, rivers,
## street lamps, trees, sari-sari stores. Chunks build a few at a time so the game doesn't freeze.

const MAP_DIR := "res://data/map/bacolod/"
const BUILD_BUDGET_MSEC := 4       # max time per frame spent finishing chunks
const MAX_THREADS := 3             # chunks prepared in the background at the same time
const STREAM_INTERVAL := 0.5       # seconds between "which chunks do I need" checks
const POST_ROAD_CLEARANCE := 0.5   # includes the post's 0.3 m collision box
const ROAD_SURFACE_CELL := 100.0

const WALL_COLORS := ["#f2c14e", "#f78154", "#4d9de0", "#7bc96f", "#e8a0a0", "#f4e9cd",
	"#c9a7eb", "#5fc4b8", "#ffb5a7", "#e8e288", "#a3d5ff", "#d9d4c7"]
const ROOF_COLORS := ["#9aa5ab", "#b5652b", "#3d6fa0", "#8c3b2f", "#7d8b8f", "#4f7a4a"]
const AREA_COLORS := {
	"park": Color("#6fae5a"), "grass": Color("#86b96a"), "pitch": Color("#5f9e4c"),
	"cemetery": Color("#93a97f"), "beach": Color("#e9d8a6"), "water": Color("#3f87b5"),
}
const MAJOR_CLASSES := ["motorway", "trunk", "primary", "secondary", "trunk_link", "primary_link"]
const FLOOR_H := 3.2

var meta: Dictionary = {}
var landmarks: Array[Dictionary] = []
var street_labels: Array = []        # {"pos": Vector2, "angle", "name", "len", "major"} for the map

var _chunk_size := 200.0
var _available := {}                 # chunk key -> true
var _loaded := {}                    # chunk key -> Node3D
var _queue: Array[String] = []       # chunks waiting to be built (nearest first)
var _needed := {}                    # chunks that should be loaded right now
var _tasks := {}                     # chunk key -> background task id
var _prepared := {}                  # chunk key -> prepared data (filled by threads)
var _mutex := Mutex.new()
var _stream_center := Vector3.ZERO
var _stream_timer := 0.0
var _map_rect := Rect2()
var _play_rect := Rect2()
var _sea := PackedVector2Array()
var _boundary := PackedVector2Array()   # Bacolod city limits
var _stalls_by_chunk := {}           # chunk key -> Array of generated stall dicts
var _road_surface_grid := {}        # cell -> asphalt triangles; read-only during streaming

var _mat_wall: ShaderMaterial
var _mat_roof: StandardMaterial3D
var _mat_road: StandardMaterial3D
var _mat_sidewalk: StandardMaterial3D
var _mat_paint: StandardMaterial3D
var _mat_ground: StandardMaterial3D
var _mat_water: StandardMaterial3D
var _mat_flat: StandardMaterial3D
var _mat_lamp: StandardMaterial3D
var _pole_mesh: Mesh
var _lamp_mesh: Mesh
var _trunk_mesh: Mesh
var _leaves_mesh: Mesh
var _wire_mesh: Mesh


func _ready() -> void:
	meta = _read_json(MAP_DIR + "meta.json")
	if meta.is_empty():
		push_error("Bacolod map data missing. Run: python tools/osm_convert.py")
		return
	_chunk_size = float(meta.get("chunk_size", 200.0))
	for k: String in meta.get("chunks", []):
		_available[k] = true
	var b: Array = meta["bounds"]
	_map_rect = Rect2(float(b[0]), float(b[1]), float(b[2]) - float(b[0]), float(b[3]) - float(b[1]))
	_play_rect = _map_rect.grow(-40.0)
	for p: Array in meta.get("sea", []):
		_sea.append(Vector2(float(p[0]), float(p[1])))
	for p: Array in meta.get("boundary", []):
		_boundary.append(Vector2(float(p[0]), float(p[1])))

	build_environment(0.0022)
	_make_materials()
	_load_graph()
	_load_places()
	_build_ground()
	_build_sea()
	_build_big_areas()
	_build_places()
	_build_landmarks()
	_build_backdrop()
	update_streaming(get_place("home").get("door", Vector3.ZERO), true)


# --- GameWorld API ---------------------------------------------------------------

func get_map_rect() -> Rect2:
	return _map_rect


func get_sea_polygon() -> PackedVector2Array:
	return _sea


func get_map_credit() -> String:
	return "Map data © OpenStreetMap contributors"


func is_in_bounds(pos: Vector3) -> bool:
	var p := Vector2(pos.x, pos.z)
	if not _play_rect.has_point(p):
		return false
	if _sea.size() >= 3 and Geometry2D.is_point_in_polygon(p, _sea):
		return false
	if _boundary.size() >= 3 and not Geometry2D.is_point_in_polygon(p, _boundary):
		return false   # past the city limits (Talisay, Silay, Murcia, Bago...)
	return true


func get_boundary_polygon() -> PackedVector2Array:
	return _boundary


## How many chunks around you stay loaded (graphics setting).
func _stream_radius() -> int:
	match Settings.graphics:
		"low":
			return 1
		"high":
			return 3
	return 2


func update_streaming(pos: Vector3, now: bool = false) -> void:
	_stream_center = pos
	var r := _stream_radius()
	var cx := floori(pos.x / _chunk_size)
	var cz := floori(pos.z / _chunk_size)
	var needed := {}
	var wanted: Array = []
	for x in range(cx - r, cx + r + 1):
		for z in range(cz - r, cz + r + 1):
			var key := "%d_%d" % [x, z]
			if not _available.has(key):
				continue
			needed[key] = true
			if not _loaded.has(key) and not _queue.has(key):
				wanted.append([Vector2(x - cx, z - cz).length(), key])
	wanted.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for w: Array in wanted:
		_queue.append(w[1])
	# Unload chunks that are far away
	for key: String in _loaded.keys():
		var parts := key.split("_")
		if absi(int(parts[0]) - cx) > r + 1 or absi(int(parts[1]) - cz) > r + 1:
			(_loaded[key] as Node3D).queue_free()
			_loaded.erase(key)
	_queue = _queue.filter(func(k: String) -> bool: return needed.has(k))
	_needed = needed
	if now:
		# load everything right away (spawn / teleport): no waiting for threads
		for key: String in _queue:
			if not _loaded.has(key):
				_add_chunk(key, _prepare_chunk(key))
		_queue.clear()


## Start background preparation of queued chunks, and finish prepared ones (a little per frame).
func _process(delta: float) -> void:
	_stream_timer -= delta
	while not _queue.is_empty() and _tasks.size() < MAX_THREADS:
		var key: String = _queue.pop_front()
		if _loaded.has(key) or _tasks.has(key):
			continue
		_tasks[key] = WorkerThreadPool.add_task(_prepare_task.bind(key), false, "chunk " + key)
	var start := Time.get_ticks_msec()
	for key: String in _tasks.keys():
		if Time.get_ticks_msec() - start >= BUILD_BUDGET_MSEC:
			break
		if not WorkerThreadPool.is_task_completed(_tasks[key]):
			continue
		WorkerThreadPool.wait_for_task_completion(_tasks[key])
		_tasks.erase(key)
		_mutex.lock()
		var d: Dictionary = _prepared.get(key, {})
		_prepared.erase(key)
		_mutex.unlock()
		if not d.is_empty() and _needed.has(key) and not _loaded.has(key):
			_add_chunk(key, d)


func _prepare_task(key: String) -> void:
	var d := _prepare_chunk(key)
	_mutex.lock()
	_prepared[key] = d
	_mutex.unlock()


func _add_chunk(key: String, d: Dictionary) -> void:
	var node := _finish_chunk(key, d)
	_loaded[key] = node
	add_child(node)


func _exit_tree() -> void:
	for key: String in _tasks:
		WorkerThreadPool.wait_for_task_completion(_tasks[key])
	_tasks.clear()


# --- Loading data -------------------------------------------------------------------

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _load_graph() -> void:
	var g := _read_json(MAP_DIR + "graph.json")
	var nodes: Array = g.get("nodes", [])
	var classes: Array = g.get("classes", [])
	var ids: Array[int] = []
	for n: Array in nodes:
		ids.append(road_graph.add_point(Vector3(float(n[0]), 0, float(n[1]))))
	var names: Array = g.get("names", [])
	for e: Dictionary in g.get("edges", []):
		var pts: Array = e["pts"]
		_add_street_label(e, pts, names, classes)
		var width := float(e["w"])
		_index_road_surface(_pts(pts), width)
		var major := MAJOR_CLASSES.has(str(classes[int(e["k"])]))
		var prev := ids[int(e["a"])]
		for i in range(1, pts.size() - 1):
			var p: Array = pts[i]
			var id := road_graph.add_point(Vector3(float(p[0]), 0, float(p[1])))
			road_graph.add_road(prev, id, width, major)
			prev = id
		road_graph.add_road(prev, ids[int(e["b"])], width, major)


## Index the same asphalt geometry that chunks render, including mitered bends.
## Build this for the whole map before workers start: neighboring roads may be in other chunks.
func _index_road_surface(pts: PackedVector2Array, width: float) -> void:
	var surface := MeshBuilder.new()
	_strip(surface, pts, width * 0.5, 0.0, 5.0)
	for i in range(0, surface.verts.size(), 3):
		var tri := PackedVector2Array()
		for j in 3:
			var v := surface.verts[i + j]
			tri.append(Vector2(v.x, v.z))
		var bounds := Rect2(tri[0], Vector2.ZERO).expand(tri[1]).expand(tri[2]).grow(POST_ROAD_CLEARANCE)
		for x in range(floori(bounds.position.x / ROAD_SURFACE_CELL), floori(bounds.end.x / ROAD_SURFACE_CELL) + 1):
			for z in range(floori(bounds.position.y / ROAD_SURFACE_CELL), floori(bounds.end.y / ROAD_SURFACE_CELL) + 1):
				var cell := Vector2i(x, z)
				if not _road_surface_grid.has(cell):
					_road_surface_grid[cell] = []
				(_road_surface_grid[cell] as Array).append(tri)


func _post_clear_of_roads(p: Vector2) -> bool:
	var cell := Vector2i(floori(p.x / ROAD_SURFACE_CELL), floori(p.y / ROAD_SURFACE_CELL))
	for tri: PackedVector2Array in _road_surface_grid.get(cell, []):
		if Geometry2D.is_point_in_polygon(p, tri):
			return false
		for i in 3:
			var nearest := Geometry2D.get_closest_point_to_segment(p, tri[i], tri[(i + 1) % 3])
			if p.distance_squared_to(nearest) <= POST_ROAD_CLEARANCE * POST_ROAD_CLEARANCE:
				return false
	return true


## One label per named road piece (for the zoomed-in full map). Longest / biggest first.
func _add_street_label(e: Dictionary, pts: Array, names: Array, classes: Array) -> void:
	var n := int(e.get("n", 0))
	if n <= 0 or n >= names.size() or pts.size() < 2:
		return
	var length := 0.0
	for i in range(1, pts.size()):
		length += Vector2(float(pts[i][0]), float(pts[i][1])).distance_to(Vector2(float(pts[i - 1][0]), float(pts[i - 1][1])))
	if length < 40.0:
		return
	var mid := pts.size() / 2
	var a: Array = pts[maxi(mid - 1, 0)]
	var b: Array = pts[mini(mid, pts.size() - 1)] if pts.size() > 2 else pts[1]
	var pa := Vector2(float(a[0]), float(a[1]))
	var pb := Vector2(float(b[0]), float(b[1]))
	var angle := (pb - pa).angle()
	if angle > PI * 0.5:
		angle -= PI           # keep the text upright
	elif angle < -PI * 0.5:
		angle += PI
	street_labels.append({"pos": (pa + pb) * 0.5, "angle": angle, "name": str(names[n]), "len": length,
		"major": MAJOR_CLASSES.has(str(classes[int(e["k"])]))})


func _load_places() -> void:
	for p: Dictionary in meta.get("places", []):
		places.append({
			"id": p["id"], "type": p["type"], "name": p["name"],
			"door": Vector3(float(p["x"]), 0, float(p["z"])),
			"front": Vector3(float(p["fx"]), 0, float(p["fz"])).normalized(),
		})
	for a: Dictionary in meta.get("addresses", []):
		address_points.append({
			"pos": Vector3(float(a["x"]), 0, float(a["z"])),
			"road_dir": Vector3(float(a["rx"]), 0, float(a["rz"])),
			"street": a["s"], "label": a["l"],
		})
	for s: Dictionary in meta.get("food_stalls", []):
		var pos := Vector3(float(s["x"]), 0, float(s["z"]))
		food_stalls.append(pos)
		if int(s.get("gen", 0)) == 1:
			var key := "%d_%d" % [floori(pos.x / _chunk_size), floori(pos.z / _chunk_size)]
			if not _stalls_by_chunk.has(key):
				_stalls_by_chunk[key] = []
			(_stalls_by_chunk[key] as Array).append(s)
	for lm: Dictionary in meta.get("landmarks", []):
		landmarks.append(lm)


# --- Materials & shared meshes --------------------------------------------------------

func _make_materials() -> void:
	_mat_wall = BuildingArt.wall_material()   # painted facade images, lit windows at night
	glow_materials.append(_mat_wall)
	_mat_roof = BuildingArt.roof_material()
	_mat_road = TextureFactory.material(TextureFactory.asphalt(), false)
	_mat_sidewalk = TextureFactory.material(TextureFactory.sidewalk(), false)
	_mat_ground = TextureFactory.material(TextureFactory.grass())
	_mat_water = TextureFactory.material(TextureFactory.water(), true, 0.2)
	_mat_paint = StandardMaterial3D.new()
	_mat_paint.albedo_color = Color("#e8e6d9")
	_mat_flat = StandardMaterial3D.new()
	_mat_flat.vertex_color_use_as_albedo = true
	_mat_flat.roughness = 0.9
	_mat_lamp = StandardMaterial3D.new()
	_mat_lamp.albedo_color = Color("#fff3c4")
	_mat_lamp.emission_enabled = true
	_mat_lamp.emission = Color("#ffe9a8")
	_mat_lamp.emission_energy_multiplier = 0.0
	_mat_lamp.set_meta("max_energy", 4.0)
	glow_materials.append(_mat_lamp)

	var pole := CylinderMesh.new()
	pole.top_radius = 0.11
	pole.bottom_radius = 0.14
	pole.height = 7.5
	pole.radial_segments = 6
	pole.rings = 0
	pole.material = LowPoly.mat(Color("#8a8a80"))
	_pole_mesh = pole
	var lamp := BoxMesh.new()
	lamp.size = Vector3(0.4, 0.14, 0.9)
	lamp.material = _mat_lamp
	_lamp_mesh = lamp
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.15
	trunk.bottom_radius = 0.2
	trunk.height = 2.4
	trunk.radial_segments = 6
	trunk.rings = 0
	trunk.material = LowPoly.mat(Color("#7a5230"))
	_trunk_mesh = trunk
	var leaves := CylinderMesh.new()
	leaves.top_radius = 0.0
	leaves.bottom_radius = 1.6
	leaves.height = 3.6
	leaves.radial_segments = 7
	leaves.rings = 0
	leaves.material = LowPoly.mat(Color("#3f8f3a"))
	_leaves_mesh = leaves
	var wire := BoxMesh.new()
	wire.size = Vector3(0.03, 0.03, 1.0)
	wire.material = LowPoly.mat(Color("#1a1a1a"))
	_wire_mesh = wire


# --- Always-loaded parts --------------------------------------------------------------

func _build_ground() -> void:
	var r := _map_rect.grow(2500.0)
	var mb := MeshBuilder.new()
	var a := Vector2(r.position.x, r.position.y)
	var c := r.end
	var col := Color("#9a9d80")   # dusty city ground (parks are greener)
	mb.add_flat_tri(a, Vector2(c.x, a.y), c, 0.0, col, 0.25)
	mb.add_flat_tri(a, c, Vector2(a.x, c.y), 0.0, col, 0.25)
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit(_mat_ground)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(r.size.x, 1.0, r.size.y)
	cs.shape = shape
	cs.position = Vector3(r.get_center().x, -0.5, r.get_center().y)
	body.add_child(cs)
	add_child(body)


func _build_sea() -> void:
	if _sea.size() < 3:
		return
	var tris := Geometry2D.triangulate_polygon(_sea)
	var mb := MeshBuilder.new()
	if tris.is_empty():
		# Coastline too messy to fill: just cover everything west of the coast.
		var min_x := INF
		for p in _sea:
			min_x = minf(min_x, p.x)
		var r := Rect2(min_x - 4000.0, _map_rect.position.y - 3000.0, 4000.0, _map_rect.size.y + 6000.0)
		mb.add_flat_tri(r.position, Vector2(r.end.x, r.position.y), r.end, 0.06, Color.WHITE, 0.1)
		mb.add_flat_tri(r.position, r.end, Vector2(r.position.x, r.end.y), 0.06, Color.WHITE, 0.1)
	else:
		for i in range(0, tris.size(), 3):
			mb.add_flat_tri(_sea[tris[i]], _sea[tris[i + 1]], _sea[tris[i + 2]], 0.06, Color.WHITE, 0.1)
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit(_mat_water)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_big_areas() -> void:
	var mb := MeshBuilder.new()
	for a: Dictionary in meta.get("big_areas", []):
		_add_area(mb, a)
	if not mb.is_empty():
		var mi := MeshInstance3D.new()
		mi.mesh = mb.commit(_mat_ground)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


func _add_area(mb: MeshBuilder, a: Dictionary) -> PackedVector2Array:
	var poly := PackedVector2Array()
	for p: Array in a["p"]:
		poly.append(Vector2(float(p[0]), float(p[1])))
	if poly.size() < 3:
		return poly
	var tris := Geometry2D.triangulate_polygon(poly)
	var kind: String = a["k"]
	var col: Color = AREA_COLORS.get(kind, Color("#86b96a"))
	var y := 0.025 if kind != "water" else 0.035
	for i in range(0, tris.size(), 3):
		mb.add_flat_tri(poly[tris[i]], poly[tris[i + 1]], poly[tris[i + 2]], y, col, 0.25)
	return poly


func _build_backdrop() -> void:
	# Distant mountains (Mt. Kanlaon to the east) and Guimaras island (west), not drivable.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#7d9aa8")
	mat.disable_fog = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var specs := [
		[Vector3(_map_rect.end.x + 9000, 0, -2000), 9000.0, 2400.0],
		[Vector3(_map_rect.end.x + 7000, 0, 4000), 6000.0, 1100.0],
		[Vector3(_map_rect.position.x - 9000, 0, 1500), 7000.0, 350.0],
	]
	for s: Array in specs:
		var m := CylinderMesh.new()
		m.top_radius = 0.0
		m.bottom_radius = float(s[1]) * 0.5
		m.height = float(s[2])
		m.radial_segments = 10
		m.rings = 0
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = (s[0] as Vector3) + Vector3(0, float(s[2]) * 0.5 - 20.0, 0)
		add_child(mi)


# --- Chunks ---------------------------------------------------------------------------

## Heavy part, safe to run on a background thread: read the chunk file and compute all
## geometry (no scene nodes are touched here).
func _prepare_chunk(key: String) -> Dictionary:
	var data := _read_json(MAP_DIR + "chunks/" + key + ".json")
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var out := {
		"side": MeshBuilder.new(), "road": MeshBuilder.new(), "paint": MeshBuilder.new(),
		"area": MeshBuilder.new(), "wall": MeshBuilder.new(), "roof": MeshBuilder.new(),
		"faces": PackedVector3Array(), "posts": [] as Array[Transform3D], "lamps": [] as Array[Transform3D],
		"wires": [] as Array[Transform3D], "trees": [] as Array[Transform3D],
	}
	# Roads: sidewalk band underneath, asphalt on top, dashed center lines on big roads
	for r: Dictionary in data.get("roads", []):
		var pts := _pts(r["pts"])
		var w := float(r["w"])
		var k: String = r["k"]
		var lift := 0.005 if MAJOR_CLASSES.has(k) else 0.0
		if k != "service":
			_strip(out["side"], pts, w * 0.5 + 1.8, 0.02, 4.0)
		_strip(out["road"], pts, w * 0.5, 0.04 + lift, 5.0)
		if w >= 9.0:
			_dashes(out["paint"], pts, 0.06 + lift)
		if w >= 6.0 and k != "service":
			_street_posts(pts, w, out["posts"], out["lamps"], out["wires"])
	# Small parks / water areas + trees in parks
	for a: Dictionary in data.get("areas", []):
		var poly := _add_area(out["area"], a)
		if a["k"] in ["park", "grass", "cemetery"] and poly.size() >= 3:
			_scatter_trees(poly, rng, out["trees"])
	for rv: Dictionary in data.get("rivers", []):
		_strip(out["area"], _pts(rv["pts"]), float(rv["w"]) * 0.5, 0.03, 6.0, Color("#3f87b5"))
	# Buildings
	var faces := PackedVector3Array()
	for bd: Dictionary in data.get("buildings", []):
		_add_building(bd, out["wall"], out["roof"], faces)
	out["faces"] = faces
	return out


## Quick part, on the main thread: turn prepared data into meshes, collision and props.
func _finish_chunk(key: String, d: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Chunk_" + key
	for pair: Array in [["side", _mat_sidewalk, false], ["road", _mat_road, false], ["paint", _mat_paint, false],
			["area", _mat_ground, false], ["wall", _mat_wall, true], ["roof", _mat_roof, true]]:
		var mb: MeshBuilder = d[pair[0]]
		if mb.is_empty():
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = mb.commit(pair[1])
		if not pair[2]:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)

	var posts: Array[Transform3D] = d["posts"]
	var faces: PackedVector3Array = d["faces"]
	if not faces.is_empty() or not posts.is_empty():
		var body := StaticBody3D.new()
		if not faces.is_empty():
			var cs := CollisionShape3D.new()
			var shape := ConcavePolygonShape3D.new()
			shape.backface_collision = true
			shape.set_faces(faces)
			cs.shape = shape
			body.add_child(cs)
		# Street posts are solid too
		var post_box := BoxShape3D.new()
		post_box.size = Vector3(0.3, 7.5, 0.3)
		for t in posts:
			var pcs := CollisionShape3D.new()
			pcs.shape = post_box
			pcs.transform = t
			body.add_child(pcs)
		root.add_child(body)

	_add_multimesh(root, _pole_mesh, posts, true)
	_add_multimesh(root, _lamp_mesh, d["lamps"], false)
	_add_multimesh(root, _wire_mesh, d["wires"], false)
	var trees: Array[Transform3D] = d["trees"]
	var leaves: Array[Transform3D] = []
	for t in trees:
		leaves.append(t.translated_local(Vector3(0, 2.9, 0)))
	_add_multimesh(root, _trunk_mesh, trees, true)
	_add_multimesh(root, _leaves_mesh, leaves, true)

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key) + 1
	for st: Dictionary in _stalls_by_chunk.get(key, []):
		_add_stall_prop(root, st, rng)
	return root


func _pts(arr: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Array in arr:
		out.append(Vector2(float(p[0]), float(p[1])))
	return out


## A flat band along a polyline (roads, sidewalks, rivers), with mitered corners.
func _strip(mb: MeshBuilder, pts: PackedVector2Array, half_w: float, y: float, uv_len: float,
		color: Color = Color.WHITE) -> void:
	var n := pts.size()
	if n < 2:
		return
	var lefts := PackedVector2Array()
	var rights := PackedVector2Array()
	for i in n:
		var d_prev := Vector2.ZERO
		var d_next := Vector2.ZERO
		if i > 0:
			d_prev = (pts[i] - pts[i - 1]).normalized()
		if i < n - 1:
			d_next = (pts[i + 1] - pts[i]).normalized()
		var d := d_prev + d_next
		d = d.normalized() if d.length() > 0.001 else (d_next if i < n - 1 else d_prev)
		var nrm := Vector2(-d.y, d.x)
		var miter := 1.0
		if i > 0 and i < n - 1:
			miter = clampf(1.0 / maxf(nrm.dot(Vector2(-d_next.y, d_next.x)), 0.4), 1.0, 2.5)
		lefts.append(pts[i] + nrm * half_w * miter)
		rights.append(pts[i] - nrm * half_w * miter)
	var along := 0.0
	var across := half_w * 2.0 / uv_len
	for i in n - 1:
		var seg := pts[i].distance_to(pts[i + 1])
		var v0 := along / uv_len
		var v1 := (along + seg) / uv_len
		mb.add_flat_quad_uv(lefts[i], rights[i], rights[i + 1], lefts[i + 1], y, color,
			Vector2(0, v0), Vector2(across, v0), Vector2(across, v1), Vector2(0, v1))
		along += seg


## Dashed center line: 3 m paint, 4 m gap.
func _dashes(mb: MeshBuilder, pts: PackedVector2Array, y: float) -> void:
	var phase := 0.0
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var seg := a.distance_to(b)
		if seg < 0.5:
			continue
		var dir := (b - a) / seg
		var nrm := Vector2(-dir.y, dir.x) * 0.11
		var t := phase
		while t < seg:
			var t1 := minf(t + 3.0, seg)
			var p0 := a + dir * t
			var p1 := a + dir * t1
			mb.add_flat_quad_uv(p0 + nrm, p0 - nrm, p1 - nrm, p1 + nrm, y, Color.WHITE,
				Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN)
			t += 7.0
		phase = t - seg


## Electric posts every ~40 m on one side, with a lamp over the road and sagging wires.
func _street_posts(pts: PackedVector2Array, w: float, posts: Array[Transform3D],
		lamps: Array[Transform3D], wires: Array[Transform3D]) -> void:
	var acc := 20.0
	var prev_top := Vector3.INF
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var seg := a.distance_to(b)
		if seg < 0.5:
			continue
		var dir := (b - a) / seg
		var nrm := Vector2(-dir.y, dir.x)
		var t := 0.0
		while t < seg:
			var step := minf(40.0 - acc, seg - t)
			t += step
			acc += step
			if acc >= 40.0:
				acc = 0.0
				var p := a + dir * t + nrm * (w * 0.5 + 0.9)
				if not _post_clear_of_roads(p):
					continue
				var base := Vector3(p.x, 3.75, p.y)
				posts.append(Transform3D(Basis.IDENTITY, base))
				var yaw := atan2(nrm.x, nrm.y)
				var lamp_pos := Vector3(p.x - nrm.x * 1.3, 6.8, p.y - nrm.y * 1.3)
				lamps.append(Transform3D(Basis(Vector3.UP, yaw), lamp_pos))
				var top := Vector3(p.x, 7.0, p.y)
				if prev_top != Vector3.INF and prev_top.distance_to(top) < 60.0:
					_wire(prev_top, top, wires)
				prev_top = top


func _wire(a: Vector3, b: Vector3, out: Array[Transform3D]) -> void:
	var mid := (a + b) * 0.5 - Vector3(0, 0.5, 0)
	for pair: Array in [[a, mid], [mid, b]]:
		var p0: Vector3 = pair[0]
		var p1: Vector3 = pair[1]
		var basis := Basis.looking_at(p1 - p0, Vector3.UP).scaled_local(Vector3(1, 1, p0.distance_to(p1)))
		out.append(Transform3D(basis, (p0 + p1) * 0.5))


func _scatter_trees(poly: PackedVector2Array, rng: RandomNumberGenerator, out: Array[Transform3D]) -> void:
	var r := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		r = r.expand(p)
	var count := mini(int(r.get_area() / 300.0), 25)
	for i in count * 3:
		if count <= 0:
			break
		var p := Vector2(rng.randf_range(r.position.x, r.end.x), rng.randf_range(r.position.y, r.end.y))
		if Geometry2D.is_point_in_polygon(p, poly):
			var s := rng.randf_range(0.8, 1.3)
			out.append(Transform3D(Basis.from_scale(Vector3(s, s, s)), Vector3(p.x, 1.2 * s, p.y)))
			count -= 1


func _add_multimesh(parent: Node3D, mesh: Mesh, xforms: Array[Transform3D], shadows: bool) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)


## Extruded footprint: textured walls + roof, and collision triangles for the walls.
func _add_building(bd: Dictionary, mb_wall: MeshBuilder, mb_roof: MeshBuilder, faces: PackedVector3Array) -> void:
	var poly := _pts(bd["p"])
	var n := poly.size()
	if n < 3:
		return
	var h := float(bd["h"])
	var ci := int(bd["c"])
	var wall_col := Color(WALL_COLORS[ci % WALL_COLORS.size()])
	var roof_col := Color(ROOF_COLORS[ci % ROOF_COLORS.size()])
	if str(bd.get("t", "")) in ["church", "cathedral"]:
		wall_col = Color("#e8dcc4")
	var church := str(bd.get("t", "")) in ["church", "cathedral"]
	# the same building always gets the same look
	var look := RandomNumberGenerator.new()
	look.seed = hash(poly[0]) + ci
	var floors := maxi(1, roundi(h / FLOOR_H))
	var floor_h := h / floors
	var upper: int = BuildingArt.CHURCH if church else BuildingArt.UPPER[look.randi() % BuildingArt.UPPER.size()]
	var u := 0.0
	for i in n:
		var p0 := poly[i]
		var p1 := poly[(i + 1) % n]
		var d := p1 - p0
		var length := d.length()
		if length < 0.05:
			continue
		var normal := Vector3(d.y, 0, -d.x) / length   # outward for our footprint winding
		var bays := maxi(1, roundi(length / FLOOR_H))
		# ground floor: each bay is its own house front or shop
		for k in bays:
			mb_wall.layer = BuildingArt.CHURCH if church else BuildingArt.GROUND[look.randi() % BuildingArt.GROUND.size()]
			mb_wall.add_wall(p0 + d * (float(k) / bays), p0 + d * (float(k + 1) / bays), 0.0, floor_h, normal, wall_col,
				1.0, 0.0, 1.0 / floor_h)   # right-to-left from outside, so signs read
		if floors > 1:
			mb_wall.layer = upper
			mb_wall.add_wall(p0, p1, floor_h, h, normal, wall_col, u + bays, u, 1.0 / floor_h)
		u += bays
		var a := Vector3(p0.x, 0, p0.y)
		var b := Vector3(p1.x, 0, p1.y)
		var c := Vector3(p1.x, h, p1.y)
		var e := Vector3(p0.x, h, p0.y)
		faces.append_array(PackedVector3Array([a, b, c, a, c, e]))
	var tris := Geometry2D.triangulate_polygon(poly)
	for i in range(0, tris.size(), 3):
		mb_roof.add_flat_tri(poly[tris[i]], poly[tris[i + 1]], poly[tris[i + 2]], h + 0.02, roof_col, 0.5)


## Generated sari-sari store: little stall with an awning facing the road.
func _add_stall_prop(root: Node3D, s: Dictionary, rng: RandomNumberGenerator) -> void:
	var pos := Vector3(float(s["x"]), 0, float(s["z"]))
	var front := Vector3(float(s.get("fx", 0.0)), 0, float(s.get("fz", 1.0))).normalized()
	var lot := Node3D.new()
	lot.transform = _lot_transform(pos - front * 1.0, front)
	root.add_child(lot)
	var awning := Color(["#e63946", "#2a9d8f", "#f4a261", "#3a86ff", "#ffbe0b"][rng.randi() % 5])
	LowPoly.box(lot, Vector3(2.4, 1.0, 0.9), Color("#5a4632"), Vector3(0, 0.5, 0.6))        # counter
	var aw := LowPoly.box(lot, Vector3(2.8, 0.08, 1.4), awning, Vector3(0, 2.4, 0.1))       # awning
	aw.rotation.x = 0.22
	LowPoly.box(lot, Vector3(0.1, 2.4, 0.1), Color("#6b5b4b"), Vector3(-1.3, 1.2, -0.5))
	LowPoly.box(lot, Vector3(0.1, 2.4, 0.1), Color("#6b5b4b"), Vector3(1.3, 1.2, -0.5))
	LowPoly.box(lot, Vector3(1.8, 0.5, 0.06), Color("#d62828"), Vector3(0, 2.85, -0.3))     # sign
	MeshMerger.merge(lot, [], 250.0)


## Transform for building things at a place: origin at `door`,
## local -Z points to the road (front), local +Z goes back into the lot.
func _lot_transform(door: Vector3, front: Vector3) -> Transform3D:
	var side := Vector3(-front.z, 0, front.x)
	return Transform3D(Basis(side, Vector3.UP, -front), door)


# --- Game places (home, shop, school, gas, clinics) -------------------------------------

func _build_places() -> void:
	var body := StaticBody3D.new()
	add_child(body)
	for p in places:
		var lot := Node3D.new()
		lot.transform = _lot_transform(p["door"], p["front"])
		add_child(lot)
		match str(p["type"]):
			"home":
				_place_box(lot, body, Vector3(8.5, 5.6, 7.0), Vector3(0, 0, 5.0), Color("#ffd6a5"), Color("#b5652b"))
				LowPoly.box(lot, Vector3(1.3, 2.2, 0.12), Color("#6b4226"), Vector3(0, 1.1, 1.45))
				for sx: float in [-1.0, 1.0]:
					var fence_pos := Vector3(sx * 3.4, 0.5, 0.6)
					LowPoly.box(lot, Vector3(4.6, 1.0, 0.15), Color("#e9e4d8"), fence_pos)
					_add_box_collider(body, lot, fence_pos, Vector3(4.6, 1.0, 0.15))
				LowPoly.label(lot, p["name"], Vector3(0, 8.0, 5.0), 1.1)
			"motor_shop":
				_place_box(lot, body, Vector3(11.0, 4.5, 9.0), Vector3(0, 0, 5.5), Color("#3d8bd9"), Color("#9aa5ab"))
				LowPoly.box(lot, Vector3(6.5, 3.2, 0.1), Color("#2b2d31"), Vector3(0, 1.6, 0.96))
				LowPoly.box(lot, Vector3(11.2, 0.9, 0.2), Color("#ffd166"), Vector3(0, 3.95, 0.9))
				LowPoly.label(lot, p["name"], Vector3(0, 7.0, 5.5), 1.1)
			"driving_school":
				_place_box(lot, body, Vector3(10.0, 4.0, 6.0), Vector3(-12.0, 0, 4.0), Color("#7bc96f"), Color("#3d6fa0"))
				var pave := MeshInstance3D.new()
				var disc := CylinderMesh.new()
				disc.top_radius = 21.0
				disc.bottom_radius = 21.0
				disc.height = 0.1
				disc.radial_segments = 24
				disc.rings = 0
				pave.mesh = disc
				pave.material_override = LowPoly.mat(Color("#8d9399"))
				pave.position = Vector3(0, 0.05, 22.0)
				lot.add_child(pave)
				LowPoly.label(lot, p["name"], Vector3(-12.0, 6.5, 4.0), 1.1)
				_build_cones(get_school_yard_center())
			"gas_station":
				_build_gas_station(lot, body)
				LowPoly.label(lot, "Gasolinahan", Vector3(0, 7.2, 3.0), 0.9)
			"clinic":
				LowPoly.box(lot, Vector3(0.2, 3.0, 0.2), Color("#dddddd"), Vector3(1.5, 1.5, 0.3))
				LowPoly.box(lot, Vector3(1.0, 0.3, 0.1), Color("#e63946"), Vector3(1.5, 3.1, 0.3))
				LowPoly.box(lot, Vector3(0.3, 1.0, 0.1), Color("#e63946"), Vector3(1.5, 3.1, 0.3))
				LowPoly.label(lot, p["name"], Vector3(1.5, 4.4, 0.3), 0.6)
		MeshMerger.merge(lot, [], 600.0)   # performance: one mesh per place


func _place_box(lot: Node3D, body: StaticBody3D, size: Vector3, pos: Vector3, wall: Color, roof: Color) -> void:
	var center := pos + Vector3(0, size.y * 0.5, 0)
	LowPoly.box(lot, size, wall, center)
	LowPoly.box(lot, Vector3(size.x + 0.6, 0.2, size.z + 0.6), roof, pos + Vector3(0, size.y + 0.1, 0))
	_add_box_collider(body, lot, center, size)


func _add_box_collider(body: StaticBody3D, lot: Node3D, local_pos: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.transform = lot.transform * Transform3D(Basis.IDENTITY, local_pos)
	body.add_child(cs)


func _build_gas_station(lot: Node3D, body: StaticBody3D) -> void:
	for px: float in [-4.0, 4.0]:
		for pz: float in [-2.6, 2.6]:
			var pc := Vector3(px, 2.3, pz)
			LowPoly.box(lot, Vector3(0.4, 4.6, 0.4), Color("#f5f5f5"), pc)
			_add_box_collider(body, lot, pc, Vector3(0.4, 4.6, 0.4))
	LowPoly.box(lot, Vector3(10.5, 0.6, 7.5), Color("#f5f5f5"), Vector3(0, 4.9, 0))
	LowPoly.box(lot, Vector3(10.6, 0.25, 7.6), Color("#e63946"), Vector3(0, 4.6, 0))
	for px: float in [-1.8, 1.8]:
		var pump := Vector3(px, 0.75, 0)
		LowPoly.box(lot, Vector3(0.7, 1.5, 0.5), Color("#e63946"), pump)
		_add_box_collider(body, lot, pump, Vector3(0.7, 1.5, 0.5))
	LowPoly.box(lot, Vector3(11.0, 0.08, 9.0), Color("#a9adb1"), Vector3(0, 0.04, 0))


func _build_cones(c: Vector3) -> void:
	var mm_x: Array[Transform3D] = []
	for ring: float in [1.0, 0.55]:
		var count := 22 if ring > 0.9 else 12
		for i in count:
			var a := TAU * i / count
			mm_x.append(Transform3D(Basis.IDENTITY, c + Vector3(cos(a) * 15.0 * ring, 0.35, sin(a) * 9.0 * ring)))
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.22
	cone.height = 0.7
	cone.radial_segments = 7
	cone.rings = 0
	cone.material = LowPoly.mat(Color("#ff7b1c"))
	_add_multimesh(self, cone, mm_x, false)


# --- Landmarks (hand-made, stylized) ---------------------------------------------------------

func _build_landmarks() -> void:
	var body := StaticBody3D.new()
	add_child(body)
	for lm in landmarks:
		var pos := Vector3(float(lm["x"]), 0, float(lm["z"]))
		var node := Node3D.new()
		node.position = pos
		add_child(node)
		match str(lm["id"]):
			"cathedral":
				_cathedral(node, body)
			"plaza":
				_plaza(node)
			"capitol":
				_capitol(node, body)
			_:
				pass
		MeshMerger.merge(node)   # performance: one mesh per landmark
		LowPoly.label(node, str(lm["name"]), Vector3(0, _landmark_label_height(str(lm["id"])), 0), 2.0)


func _landmark_label_height(id: String) -> float:
	match id:
		"cathedral":
			return 36.0
		"capitol":
			return 30.0
		"sm", "ayala":
			return 26.0
	return 12.0


## San Sebastian Cathedral: coral-stone nave with twin bell towers, facing east (the plaza).
func _cathedral(node: Node3D, body: StaticBody3D) -> void:
	node.rotation.y = -PI * 0.5   # front (-Z) faces east (+X)
	var stone := Color("#c9b79c")
	_solid(node, body, Vector3(16, 14, 38), Vector3(0, 7, 6), stone)                 # nave
	var roof := LowPoly.box(node, Vector3(17, 1.0, 39), Color("#8c3b2f"), Vector3(0, 14.5, 6))
	roof.scale = Vector3(1, 1, 1)
	for sx: float in [-6.0, 6.0]:
		_solid(node, body, Vector3(6, 26, 6), Vector3(sx, 13, -14), stone.darkened(0.08))   # towers
		var spire := LowPoly.cylinder(node, 3.6, 6.0, Color("#6e6a63"), Vector3(sx, 29, -14), 4)
		spire.rotation.y = PI * 0.25
		(spire.mesh as CylinderMesh).top_radius = 0.0
		LowPoly.box(node, Vector3(0.3, 2.2, 0.3), Color("#d9c27a"), Vector3(sx, 33, -14))      # cross
		LowPoly.box(node, Vector3(1.2, 0.3, 0.3), Color("#d9c27a"), Vector3(sx, 33.4, -14))
	LowPoly.box(node, Vector3(4, 7, 0.3), Color("#5a3e2b"), Vector3(0, 3.5, -13.1))          # main door
	LowPoly.cylinder(node, 1.6, 0.3, Color("#e8dcc4"), Vector3(0, 11, -13.2), 12).rotation.x = PI * 0.5   # rose window


## Public Plaza: bandstand (kiosk) with a dome and some trees.
func _plaza(node: Node3D) -> void:
	LowPoly.cylinder(node, 7.0, 0.6, Color("#d9d4c7"), Vector3(0, 0.3, 0), 8)
	for i in 8:
		var a := TAU * i / 8.0
		LowPoly.box(node, Vector3(0.4, 4.5, 0.4), Color("#f4f1de"), Vector3(cos(a) * 5.5, 2.8, sin(a) * 5.5))
	var dome := LowPoly.cylinder(node, 6.4, 3.0, Color("#4f7a4a"), Vector3(0, 6.6, 0), 8)
	(dome.mesh as CylinderMesh).top_radius = 1.0
	LowPoly.cylinder(node, 0.8, 1.6, Color("#f4f1de"), Vector3(0, 8.9, 0), 8)


## Provincial Capitol: neoclassical building with columns and a dome, facing the lagoon (north).
func _capitol(node: Node3D, body: StaticBody3D) -> void:
	var cream := Color("#efe6d2")
	_solid(node, body, Vector3(64, 16, 22), Vector3(0, 8, 0), cream)
	LowPoly.box(node, Vector3(66, 1.2, 24), Color("#d8ccb2"), Vector3(0, 16.6, 0))
	_solid(node, body, Vector3(20, 6, 22), Vector3(0, 20, 0), cream)
	LowPoly.cylinder(node, 7.5, 6.0, Color("#d8ccb2"), Vector3(0, 26, 0), 12)
	var dome := LowPoly.cylinder(node, 7.0, 5.0, Color("#b9c4c9"), Vector3(0, 31.5, 0), 12)
	(dome.mesh as CylinderMesh).top_radius = 2.0
	for i in 8:
		LowPoly.cylinder(node, 0.7, 14.0, Color.WHITE, Vector3(-10.5 + i * 3.0, 7.5, -12.5), 8)
	var pediment := LowPoly.box(node, Vector3(26, 3.0, 2.0), cream, Vector3(0, 16.5, -12.5))
	pediment.scale = Vector3(1, 1, 1)
	LowPoly.box(node, Vector3(24, 1.2, 6), Color("#d8ccb2"), Vector3(0, 0.6, -15.5))   # front steps


func _solid(node: Node3D, body: StaticBody3D, size: Vector3, pos: Vector3, color: Color) -> void:
	LowPoly.box(node, size, color, pos)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.transform = node.transform * Transform3D(Basis.IDENTITY, pos)
	body.add_child(cs)
