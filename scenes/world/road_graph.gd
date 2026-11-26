class_name RoadGraph
extends RefCounted
## The road network as points (intersections / bends) connected by road segments.
## Used by the GPS (shortest route) and the minimap (drawing roads).
## The test city builds a grid; the real Bacolod map (Milestone 6) will build it from OSM.

const CELL := 100.0   # spatial grid cell (meters) for fast "what's near me" lookups

var _astar := AStar3D.new()
var _points: Array[Vector3] = []
## Each segment: {"a": id, "b": id, "width": meters, "major": bool}
var segments: Array[Dictionary] = []
var _seg_grid: Dictionary = {}     # Vector2i cell -> Array[int] segment indexes
var _point_grid: Dictionary = {}   # Vector2i cell -> Array[int] point ids
var _width := {}                   # "a_b" (smaller id first) -> road width
var _major_points := {}            # point id -> true if a major road touches it


func add_point(pos: Vector3) -> int:
	var id := _points.size()
	_points.append(Vector3(pos.x, 0, pos.z))
	_astar.add_point(id, _points[id])
	var cell := _cell_of(_points[id])
	if not _point_grid.has(cell):
		_point_grid[cell] = []
	(_point_grid[cell] as Array).append(id)
	return id


func add_road(a: int, b: int, width: float, major: bool = false) -> void:
	_astar.connect_points(a, b, true)
	var idx := segments.size()
	segments.append({"a": a, "b": b, "width": width, "major": major})
	_width[_key(a, b)] = width
	if major:
		_major_points[a] = true
		_major_points[b] = true
	# register the segment in every grid cell it passes through
	var pa := _points[a]
	var pb := _points[b]
	var steps := maxi(1, int(pa.distance_to(pb) / (CELL * 0.5)))
	var seen := {}
	for i in steps + 1:
		var cell := _cell_of(pa.lerp(pb, float(i) / steps))
		if seen.has(cell):
			continue
		seen[cell] = true
		if not _seg_grid.has(cell):
			_seg_grid[cell] = []
		(_seg_grid[cell] as Array).append(idx)


func _cell_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.z / CELL))


## Indexes of road segments within about `radius` of `center`.
func segments_near(center: Vector3, radius: float) -> Array[int]:
	var out: Array[int] = []
	var seen := {}
	var c := _cell_of(center)
	var r := ceili(radius / CELL)
	for x in range(c.x - r, c.x + r + 1):
		for z in range(c.y - r, c.y + r + 1):
			for idx: int in _seg_grid.get(Vector2i(x, z), []):
				if not seen.has(idx):
					seen[idx] = true
					out.append(idx)
	return out


## Road points within `radius` of `center`.
func points_near(center: Vector3, radius: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var c := _cell_of(center)
	var r := ceili(radius / CELL)
	for x in range(c.x - r, c.x + r + 1):
		for z in range(c.y - r, c.y + r + 1):
			for id: int in _point_grid.get(Vector2i(x, z), []):
				if _points[id].distance_to(Vector3(center.x, 0, center.z)) <= radius:
					out.append(_points[id])
	return out


func point_count() -> int:
	return _points.size()


# --- Helpers for traffic and pedestrians ------------------------------------------

static func _key(a: int, b: int) -> String:
	return "%d_%d" % [mini(a, b), maxi(a, b)]


## Points connected to `id` by a road.
func neighbors(id: int) -> PackedInt64Array:
	return _astar.get_point_connections(id)


func degree(id: int) -> int:
	return _astar.get_point_connections(id).size()


func road_width(a: int, b: int) -> float:
	return float(_width.get(_key(a, b), 6.0))


func is_major_point(id: int) -> bool:
	return _major_points.has(id)


## Ids of road points within `radius` of `center`.
func point_ids_near(center: Vector3, radius: float) -> Array[int]:
	var out: Array[int] = []
	var c := _cell_of(center)
	var r := ceili(radius / CELL)
	var flat := Vector3(center.x, 0, center.z)
	for x in range(c.x - r, c.x + r + 1):
		for z in range(c.y - r, c.y + r + 1):
			for id: int in _point_grid.get(Vector2i(x, z), []):
				if _points[id].distance_to(flat) <= radius:
					out.append(id)
	return out


func get_point(id: int) -> Vector3:
	return _points[id]


func segment_ends(seg: Dictionary) -> Array[Vector3]:
	return [_points[int(seg["a"])], _points[int(seg["b"])]]


## Shortest route along roads from `from` to `to` (both any world positions).
## Returns the list of points to follow, starting at `from` and ending at `to`.
func route(from: Vector3, to: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	if segments.is_empty():
		out.append(from)
		out.append(to)
		return out
	var s_seg := _nearest_segment(from)
	var e_seg := _nearest_segment(to)
	var best_len := INF
	var best_path := PackedVector3Array()
	# Try both ends of the start road and both ends of the end road; keep the shortest.
	for sa: int in [int(s_seg["a"]), int(s_seg["b"])]:
		for eb: int in [int(e_seg["a"]), int(e_seg["b"])]:
			var ids := _astar.get_id_path(sa, eb)
			if ids.is_empty():
				continue
			var path := PackedVector3Array()
			path.append(_project(from, s_seg))
			for id in ids:
				path.append(_points[id])
			path.append(_project(to, e_seg))
			# Skip a first/last point that would make us double back along the same road.
			path = _trim_backtrack(path)
			var length := _length(path)
			if length < best_len:
				best_len = length
				best_path = path
	out.append(from)
	out.append_array(best_path)
	out.append(to)
	return out


static func path_length(path: PackedVector3Array) -> float:
	return _length(path)


func _nearest_segment(p: Vector3) -> Dictionary:
	var best: Dictionary = segments[0]
	var best_d := INF
	var candidates := segments_near(p, CELL)
	if candidates.is_empty():
		candidates = segments_near(p, CELL * 6.0)
	for idx in candidates:
		var seg: Dictionary = segments[idx]
		var d := p.distance_squared_to(_project(p, seg))
		if d < best_d:
			best_d = d
			best = seg
	return best


## Closest point on a road segment to `p` (on the ground).
func _project(p: Vector3, seg: Dictionary) -> Vector3:
	var a := _points[int(seg["a"])]
	var b := _points[int(seg["b"])]
	var flat := Vector3(p.x, 0, p.z)
	var ab := b - a
	var t := clampf((flat - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return a + ab * t


static func _trim_backtrack(path: PackedVector3Array) -> PackedVector3Array:
	# If start -> node1 -> node2 goes back the way it came, drop node1 (same for the end).
	if path.size() >= 3 and _is_backtrack(path[0], path[1], path[2]):
		path.remove_at(1)
	var n := path.size()
	if n >= 3 and _is_backtrack(path[n - 1], path[n - 2], path[n - 3]):
		path.remove_at(n - 2)
	return path


static func _is_backtrack(p0: Vector3, p1: Vector3, p2: Vector3) -> bool:
	var d1 := (p1 - p0)
	var d2 := (p2 - p1)
	if d1.length() < 0.5 or d2.length() < 0.5:
		return false
	return d1.normalized().dot(d2.normalized()) < -0.9


static func _length(path: PackedVector3Array) -> float:
	var total := 0.0
	for i in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
	return total
