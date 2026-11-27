extends Node
## Focused regression checks for posts obstructing roads. No game, traffic or saves are loaded.
## Run: godot --headless --path . res://tests/street_posts_test.tscn

class FixtureCity extends BacolodCity:
	var graph_data: Dictionary

	func _read_json(_path: String) -> Dictionary:
		return graph_data


var _fails: Array[String] = []


func _ready() -> void:
	_test_crossing()
	_test_parallel_road()
	_test_bend()
	_test_real_map()
	print("STREET POSTS TEST: %s" % ("ALL PASSED" if _fails.is_empty() else "FAILED: " + ", ".join(_fails)))
	get_tree().quit(0 if _fails.is_empty() else 1)


func _test_crossing() -> void:
	var world := _fixture([
		{"pts": [[180, 0], [300, 0]], "w": 6.5},
		{"pts": [[200, -100], [200, 100]], "w": 12.0},
	])
	var result := _posts(world, PackedVector2Array([Vector2(180, 0), Vector2(300, 0)]), 6.5)
	var posts: Array[Transform3D] = result["posts"]
	_check(posts.size() == 2, "crossing across a chunk boundary skips the obstructing post")
	_check(posts.all(func(t: Transform3D) -> bool: return t.origin.x > 206.5), "no post or collider remains in the crossing")
	_check(result["lamps"].size() == posts.size() and result["wires"].size() == 2,
		"lamps and wires only use accepted posts")
	world.free()


func _test_parallel_road() -> void:
	var world := _fixture([
		{"pts": [[0, 0], [120, 0]], "w": 6.5},
		{"pts": [[0, 9], [120, 9]], "w": 10.0},
	])
	var result := _posts(world, PackedVector2Array([Vector2.ZERO, Vector2(120, 0)]), 6.5)
	_check(result["posts"].is_empty() and result["lamps"].is_empty() and result["wires"].is_empty(),
		"a wider parallel road cannot receive posts from its neighbor")
	world.free()
	world = _fixture([{"pts": [[0, 0], [120, 0]], "w": 6.5}])
	result = _posts(world, PackedVector2Array([Vector2.ZERO, Vector2(120, 0)]), 6.5)
	_check(result["posts"].size() == 3, "ordinary roadside posts are preserved")
	world.free()


func _test_bend() -> void:
	# This candidate is outside both centerline widths but inside the rendered miter.
	var world := _fixture([
		{"pts": [[0, 0], [30, 0], [30, 30]], "w": 12.0},
		{"pts": [[15, -9.15], [55, -9.15]], "w": 6.5},
	])
	var result := _posts(world, PackedVector2Array([Vector2(15, -9.15), Vector2(55, -9.15)]), 6.5)
	_check(result["posts"].is_empty(), "posts stay out of the asphalt at mitered bends")
	world.free()


func _fixture(roads: Array[Dictionary]) -> FixtureCity:
	var world := FixtureCity.new()
	var nodes: Array = []
	var edges: Array = []
	for road in roads:
		var pts: Array = road["pts"]
		var a := nodes.size()
		nodes.append(pts.front())
		nodes.append(pts.back())
		edges.append({"a": a, "b": a + 1, "pts": pts, "w": road["w"], "k": 0})
	world.graph_data = {"nodes": nodes, "edges": edges, "classes": ["residential"]}
	world._load_graph()
	return world


func _posts(world: BacolodCity, pts: PackedVector2Array, width: float) -> Dictionary:
	var posts: Array[Transform3D] = []
	var lamps: Array[Transform3D] = []
	var wires: Array[Transform3D] = []
	world._street_posts(pts, width, posts, lamps, wires)
	return {"posts": posts, "lamps": lamps, "wires": wires}


func _test_real_map() -> void:
	var world := BacolodCity.new()
	world._load_graph()
	var graph := world._read_json(BacolodCity.MAP_DIR + "graph.json")
	# Independently collect the actual asphalt triangles, including bends and every road class.
	var triangles := {}
	var roads: Array[Dictionary] = []
	for edge: Dictionary in graph["edges"]:
		var pts := world._pts(edge["pts"])
		var width := float(edge["w"])
		var surface := MeshBuilder.new()
		world._strip(surface, pts, width * 0.5, 0.0, 5.0)
		for i in range(0, surface.verts.size(), 3):
			var tri := PackedVector2Array()
			for j in 3:
				var v := surface.verts[i + j]
				tri.append(Vector2(v.x, v.z))
			var bounds := Rect2(tri[0], Vector2.ZERO).expand(tri[1]).expand(tri[2]).grow(0.22)
			for x in range(floori(bounds.position.x / 100.0), floori(bounds.end.x / 100.0) + 1):
				for z in range(floori(bounds.position.y / 100.0), floori(bounds.end.y / 100.0) + 1):
					var cell := Vector2i(x, z)
					if not triangles.has(cell):
						triangles[cell] = []
					triangles[cell].append(tri)
		if width >= 6.0 and graph["classes"][int(edge["k"])] != "service":
			roads.append({"pts": pts, "w": width})
	var total := 0
	var blocked := 0
	for road in roads:
		var result := _posts(world, road["pts"], road["w"])
		for post: Transform3D in result["posts"]:
			total += 1
			var p := Vector2(post.origin.x, post.origin.z)
			for tri: PackedVector2Array in triangles.get(Vector2i(floori(p.x / 100.0), floori(p.y / 100.0)), []):
				var overlaps := Geometry2D.is_point_in_polygon(p, tri)
				for j in 3:
					overlaps = overlaps or p.distance_to(Geometry2D.get_closest_point_to_segment(p, tri[j], tri[(j + 1) % 3])) < 0.22
				if overlaps:
					blocked += 1
					break
	print("  Bacolod: %d roadside posts checked, %d overlap asphalt or lack collider clearance" % [total, blocked])
	_check(total > 1000 and blocked == 0, "all Bacolod posts and their colliders clear the rendered roads")
	world.free()


func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		_fails.append(what)
