class_name Minimap
extends Control
## Corner minimap (turns with the camera) or full-screen map (north up, whole city).
## Draws: roads, GPS route, places (home, gas, shop...), food stalls, target, and you.
## Everything is drawn in code each frame from the world's RoadGraph.

const ROAD_COLOR := Color("#5b6470")
const BG_COLOR := Color(0.13, 0.2, 0.16, 0.88)
const ROUTE_COLOR := Color("#29b6f6")
const STALL_COLOR := Color("#f4a261")
const ICONS := {
	"home": ["H", Color("#ffd166")],
	"gas_station": ["G", Color("#e63946")],
	"motor_shop": ["M", Color("#3d8bd9")],
	"clinic": ["+", Color("#f8f9fa")],
	"driving_school": ["S", Color("#7bc96f")],
}

var world: TestCity
var full := false            # true = full-screen map (north up)
var meters_across := 240.0   # minimap zoom (how many meters fit across)

var center := Vector3.ZERO   # usually the player
var view_yaw := 0.0          # camera yaw: minimap rotates so "up" = where you look
var facing_yaw := 0.0        # which way you face (arrow)
var route := PackedVector3Array()
var has_target := false
var target := Vector3.ZERO
var target_color := Color.WHITE

var _scale := 1.0
var _origin := Vector2.ZERO
var _font: Font


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font


func refresh() -> void:
	queue_redraw()


func _draw() -> void:
	if world == null:
		return
	var rect := Rect2(Vector2.ZERO, size)
	var bg := StyleBoxFlat.new()
	bg.bg_color = BG_COLOR
	bg.set_corner_radius_all(16 if not full else 10)
	bg.border_color = Color(1, 1, 1, 0.25)
	bg.set_border_width_all(2)
	draw_style_box(bg, rect)

	if full:
		var m := world.get_map_rect()
		_scale = minf(size.x / m.size.x, size.y / m.size.y) * 0.95
		_origin = size * 0.5
	else:
		_scale = minf(size.x, size.y) / meters_across
		_origin = size * 0.5

	# Roads
	for seg in world.road_graph.segments:
		var ends := world.road_graph.segment_ends(seg)
		var w := maxf(2.0, float(seg["width"]) * _scale)
		draw_line(_to_screen(ends[0]), _to_screen(ends[1]), ROAD_COLOR, w)

	# GPS route
	if route.size() >= 2:
		var pts := PackedVector2Array()
		for p in route:
			pts.append(_to_screen(p))
		draw_polyline(pts, ROUTE_COLOR, 4.0 if not full else 3.0, true)

	# Food stalls (small dots)
	for s in world.food_stalls:
		var sp := _to_screen(s)
		if rect.grow(-4).has_point(sp):
			draw_circle(sp, 3.0 if not full else 2.5, STALL_COLOR)

	# Places
	for place in world.places:
		var id: String = place["id"]
		if not ICONS.has(id):
			continue
		var icon: Array = ICONS[id]
		var pos := _to_screen(place["door"])
		if not full:
			pos = _clamp_to_edge(pos, 12.0) if id == "home" else pos
		_draw_icon(pos, icon[0], icon[1], 9.0 if id == "home" else 7.5)

	# Target (pickup / drop-off / home...): stays on the edge if off the minimap
	if has_target:
		var tp := _to_screen(target)
		if not full:
			tp = _clamp_to_edge(tp, 10.0)
		draw_circle(tp, 8.0, Color(0, 0, 0, 0.5))
		draw_circle(tp, 6.5, target_color)

	# You (arrow)
	var me := _to_screen(center)
	var fwd := Vector2(-sin(facing_yaw), -cos(facing_yaw))
	if not full:
		fwd = fwd.rotated(view_yaw)
	var side := Vector2(-fwd.y, fwd.x)
	var arrow := PackedVector2Array([me + fwd * 10.0, me - fwd * 6.0 + side * 7.0, me - fwd * 3.0, me - fwd * 6.0 - side * 7.0])
	draw_colored_polygon(arrow, Color.WHITE)
	draw_polyline(PackedVector2Array([arrow[0], arrow[1], arrow[2], arrow[3], arrow[0]]), Color(0, 0, 0, 0.6), 1.5)

	# North marker (minimap only)
	if not full:
		var north := (Vector2(0, -1).rotated(view_yaw) * (minf(size.x, size.y) * 0.5 - 12.0)) + _origin
		draw_string(_font, north + Vector2(-5, 5), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#ff6b6b"))
	else:
		draw_string(_font, Vector2(12, size.y - 12), "M: close map", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.7))


func _to_screen(p: Vector3) -> Vector2:
	var c := center
	if full:
		var m := world.get_map_rect()
		c = Vector3(m.get_center().x, 0, m.get_center().y)
	var rel := Vector2(p.x - c.x, p.z - c.z)
	if not full:
		rel = rel.rotated(view_yaw)
	return _origin + rel * _scale


func _clamp_to_edge(p: Vector2, margin: float) -> Vector2:
	var half := size * 0.5 - Vector2(margin, margin)
	var rel := p - _origin
	var k := maxf(absf(rel.x) / half.x, absf(rel.y) / half.y)
	return _origin + rel / k if k > 1.0 else p


func _draw_icon(pos: Vector2, letter: String, color: Color, radius: float) -> void:
	draw_circle(pos, radius + 1.5, Color(0, 0, 0, 0.55))
	draw_circle(pos, radius, color)
	var fs := int(radius * 1.5)
	draw_string(_font, pos + Vector2(-radius, fs * 0.36), letter, HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, fs, Color("#1d2733"))
