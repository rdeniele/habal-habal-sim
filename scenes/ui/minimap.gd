class_name Minimap
extends Control
## Corner minimap (turns with the camera) or full-screen map (north up, whole city).
## Two layers so it stays fast on a big city:
##   this Control      -> background, sea, roads (minimap: only nearby roads; full map: drawn once)
##   _overlay (child)  -> GPS route, places, landmarks, pin, target, you (redrawn every frame)
## Performance: the full map's ~15,000 roads and ~1,400 food stalls are packed once into a few
## big line lists and drawn in 3 calls (drawing them one by one made opening the map lag).
## Full map: left click = drop a pin (GPS takes you there), right click = remove the pin.

signal clicked(world_pos: Vector3, button: int)

const ROAD_COLOR := Color("#5b6470")
const MAJOR_ROAD_COLOR := Color("#8d96a3")
const BG_COLOR := Color(0.13, 0.2, 0.16, 0.9)
const SEA_COLOR := Color(0.16, 0.36, 0.55, 0.95)
const ROUTE_COLOR := Color("#29b6f6")
const STALL_COLOR := Color("#f4a261")
const PIN_COLOR := Color("#ff5dc8")
const LANDMARK_COLOR := Color("#c77dff")
const ENFORCER_COLOR := Color("#d4ff3a")
const ICONS := {
	"home": ["H", Color("#ffd166")],
	"gas_station": ["G", Color("#e63946")],
	"motor_shop": ["M", Color("#3d8bd9")],
	"clinic": ["+", Color("#f8f9fa")],
	"driving_school": ["S", Color("#7bc96f")],
}
## Short names for the big places (shown on the maps).
const LANDMARK_SHORT := {
	"cathedral": "Cathedral", "plaza": "Plaza", "capitol": "Capitol", "lagoon": "Lagoon",
	"sm": "SM City", "ayala": "Ayala",
}

var world: GameWorld:
	set(value):
		world = value
		_sea_tris = PackedInt32Array()
		_sea_checked = false
		_packed = false
		queue_redraw()
var full := false            # true = full-screen map (north up)
var meters_across := 260.0   # minimap zoom (how many meters fit across)

var center := Vector3.ZERO   # usually the player
var view_yaw := 0.0          # camera yaw: minimap rotates so "up" = where you look
var facing_yaw := 0.0        # which way you face (arrow)
var route := PackedVector3Array()
var has_target := false
var target := Vector3.ZERO
var target_color := Color.WHITE
var has_pin := false
var pin := Vector3.ZERO
var enforcers := PackedVector3Array()   # traffic enforcers nearby (minimap only)

var _scale := 1.0
var _origin := Vector2.ZERO
var _font: Font
var _overlay: Control
var _sea_tris := PackedInt32Array()
var _sea_checked := false
# packed full-map geometry (world x/z coordinates)
var _packed := false
var _minor := PackedVector2Array()
var _major := PackedVector2Array()
var _stalls := PackedVector2Array()


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP if full else Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	resized.connect(queue_redraw)


## Called every frame. The full map's roads only redraw when asked (redraw_roads()).
func refresh() -> void:
	if not full:
		queue_redraw()
	_overlay.queue_redraw()


func redraw_roads() -> void:
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not full or world == null:
		return
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			_update_transform()
			clicked.emit(_to_world(mb.position), mb.button_index)
			accept_event()


func _update_transform() -> void:
	if full and world != null:
		var m := world.get_map_rect()
		_scale = minf(size.x / m.size.x, size.y / m.size.y) * 0.96
	else:
		_scale = minf(size.x, size.y) / meters_across
	_origin = size * 0.5


## Meters per screen pixel (to turn "click within 12 px" into meters).
func meters_per_pixel() -> float:
	_update_transform()
	return 1.0 / maxf(_scale, 0.0001)


## The big named places (SM, Ayala, Cathedral...) if this world has them.
func get_landmarks() -> Array:
	if world == null:
		return []
	var lms: Variant = world.get("landmarks")
	return lms if lms is Array else []


# --- Background layer: sea + roads ---------------------------------------------

func _draw() -> void:
	if world == null:
		return
	_update_transform()
	var bg := StyleBoxFlat.new()
	bg.bg_color = BG_COLOR
	bg.set_corner_radius_all(16 if not full else 10)
	bg.border_color = Color(1, 1, 1, 0.25)
	bg.set_border_width_all(2)
	draw_style_box(bg, Rect2(Vector2.ZERO, size))
	_draw_sea()
	if full:
		var border := world.get_boundary_polygon()
		if border.size() >= 3:
			var pts := PackedVector2Array()
			for p in border:
				pts.append(_to_screen(Vector3(p.x, 0, p.y)))
			pts.append(pts[0])
			draw_polyline(pts, Color(1.0, 0.85, 0.4, 0.7), 2.0)
		_draw_full_roads()
		return

	var rg := world.road_graph
	var ids := rg.segments_near(center, meters_across * 0.75)
	# minor roads first, then major roads on top
	for pass_major: bool in [false, true]:
		for idx: int in ids:
			var seg: Dictionary = rg.segments[idx]
			var major: bool = seg.get("major", false)
			if major != pass_major:
				continue
			var ends := rg.segment_ends(seg)
			var w := maxf(2.0, float(seg["width"]) * _scale)
			draw_line(_to_screen(ends[0]), _to_screen(ends[1]), MAJOR_ROAD_COLOR if major else ROAD_COLOR, w)


## Pack every road and food stall into 3 line lists (once), then draw them in 3 calls.
func _pack_full_map() -> void:
	_packed = true
	_minor.clear()
	_major.clear()
	_stalls.clear()
	var rg := world.road_graph
	for seg in rg.segments:
		var ends := rg.segment_ends(seg)
		var arr := _major if bool(seg.get("major", false)) else _minor
		arr.append(Vector2(ends[0].x, ends[0].z))
		arr.append(Vector2(ends[1].x, ends[1].z))
	for s in world.food_stalls:
		_stalls.append(Vector2(s.x - 4.0, s.z))   # a short thick line = a little square dot
		_stalls.append(Vector2(s.x + 4.0, s.z))


func _draw_full_roads() -> void:
	if not _packed:
		_pack_full_map()
	var m := world.get_map_rect()
	var c := m.get_center()
	# draw in world meters, scaled to the screen by the canvas transform
	draw_set_transform(_origin - c * _scale, 0.0, Vector2(_scale, _scale))
	var px := 1.0 / _scale
	if not _minor.is_empty():
		draw_multiline(_minor, ROAD_COLOR, 1.3 * px)
	if not _major.is_empty():
		draw_multiline(_major, MAJOR_ROAD_COLOR, 2.4 * px)
	if not _stalls.is_empty():
		draw_multiline(_stalls, STALL_COLOR, 3.0 * px)
	draw_set_transform(Vector2.ZERO)


func _draw_sea() -> void:
	var sea := world.get_sea_polygon()
	if sea.size() < 3:
		return
	if not _sea_checked:
		_sea_checked = true
		_sea_tris = Geometry2D.triangulate_polygon(sea)
	if _sea_tris.is_empty():
		return
	var pts := PackedVector2Array()
	for p in sea:
		pts.append(_to_screen(Vector3(p.x, 0, p.y)))
	# Already triangulated: hand the triangles straight to the renderer (no re-triangulation).
	var colors := PackedColorArray()
	colors.resize(pts.size())
	colors.fill(SEA_COLOR)
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), _sea_tris, pts, colors)


# --- Overlay layer: route, places, you -------------------------------------------

func _draw_overlay() -> void:
	if world == null:
		return
	_update_transform()
	var o := _overlay
	var rect := Rect2(Vector2.ZERO, size)

	if route.size() >= 2:
		var pts := PackedVector2Array()
		for p in route:
			pts.append(_to_screen(p))
		o.draw_polyline(pts, ROUTE_COLOR, 4.0 if not full else 3.0, true)

	if not full:
		# Food stalls nearby (the full map has them in the road layer)
		var stall_r := meters_across * 0.75
		for s in world.food_stalls:
			if Vector2(s.x - center.x, s.z - center.z).length() > stall_r:
				continue
			var sp := _to_screen(s)
			if rect.grow(-4).has_point(sp):
				o.draw_circle(sp, 3.0, STALL_COLOR)
		# Traffic enforcers nearby (so you know which crossings are watched)
		for e in enforcers:
			var ep := _to_screen(e)
			if rect.grow(-4).has_point(ep):
				o.draw_circle(ep, 4.5, Color(0, 0, 0, 0.6))
				o.draw_circle(ep, 3.2, ENFORCER_COLOR)

	# Landmarks (SM, Ayala, Cathedral...)
	for lm: Dictionary in get_landmarks():
		var lp := _to_screen(Vector3(float(lm["x"]), 0, float(lm["z"])))
		if not full and not rect.grow(-8).has_point(lp):
			continue
		_draw_icon(lp, "★", LANDMARK_COLOR, 7.0 if not full else 6.0)
		if full:
			var name_text: String = LANDMARK_SHORT.get(str(lm["id"]), str(lm.get("name", "")))
			_draw_tag(lp + Vector2(9, -2), name_text, LANDMARK_COLOR)

	# Places
	for place in world.places:
		var type: String = place.get("type", place["id"])
		if not ICONS.has(type):
			continue
		var icon: Array = ICONS[type]
		var pos := _to_screen(place["door"])
		if full and (type == "gas_station" or type == "clinic"):
			o.draw_circle(pos, 3.5, icon[1])   # many of these: small dots on the big map
			continue
		if not full:
			if type == "home":
				pos = _clamp_to_edge(pos, 12.0)   # HOME always shows, at the edge if far away
			elif not rect.grow(-6).has_point(pos):
				continue
		_draw_icon(pos, icon[0], icon[1], 9.0 if type == "home" else 7.0)
		if full and type == "home":
			_draw_tag(pos + Vector2(11, -2), "HOME", icon[1])

	# Your pin
	if has_pin:
		var pp := _to_screen(pin)
		if not full:
			pp = _clamp_to_edge(pp, 12.0)
		_draw_pin(pp)

	if has_target:
		var tp := _to_screen(target)
		if not full:
			tp = _clamp_to_edge(tp, 10.0)
		o.draw_circle(tp, 8.0, Color(0, 0, 0, 0.5))
		o.draw_circle(tp, 6.5, target_color)

	# You (arrow)
	var me := _to_screen(center)
	var fwd := Vector2(-sin(facing_yaw), -cos(facing_yaw))
	if not full:
		fwd = fwd.rotated(view_yaw)
	var side := Vector2(-fwd.y, fwd.x)
	var arrow := PackedVector2Array([me + fwd * 10.0, me - fwd * 6.0 + side * 7.0, me - fwd * 3.0, me - fwd * 6.0 - side * 7.0])
	o.draw_colored_polygon(arrow, Color.WHITE)
	o.draw_polyline(PackedVector2Array([arrow[0], arrow[1], arrow[2], arrow[3], arrow[0]]), Color(0, 0, 0, 0.6), 1.5)

	if not full:
		var north := (Vector2(0, -1).rotated(view_yaw) * (minf(size.x, size.y) * 0.5 - 12.0)) + _origin
		o.draw_string(_font, north + Vector2(-5, 5), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#ff6b6b"))
	else:
		o.draw_string(_font, Vector2(12, size.y - 12), "Left click: drop a pin (GPS)    Right click: remove pin    M: close",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.8))
		var credit := world.get_map_credit()
		if credit != "":
			o.draw_string(_font, Vector2(size.x - 330, 20), credit, HORIZONTAL_ALIGNMENT_RIGHT, 320, 12, Color(1, 1, 1, 0.7))


func _to_screen(p: Vector3) -> Vector2:
	var c := center
	if full:
		var m := world.get_map_rect()
		c = Vector3(m.get_center().x, 0, m.get_center().y)
	var rel := Vector2(p.x - c.x, p.z - c.z)
	if not full:
		rel = rel.rotated(view_yaw)
	return _origin + rel * _scale


## Screen point on the full map -> world position.
func _to_world(sp: Vector2) -> Vector3:
	var m := world.get_map_rect()
	var c := m.get_center()
	var rel := (sp - _origin) / _scale
	return Vector3(c.x + rel.x, 0, c.y + rel.y)


func _clamp_to_edge(p: Vector2, margin: float) -> Vector2:
	var half := size * 0.5 - Vector2(margin, margin)
	var rel := p - _origin
	var k := maxf(absf(rel.x) / half.x, absf(rel.y) / half.y)
	return _origin + rel / k if k > 1.0 else p


func _draw_icon(pos: Vector2, letter: String, color: Color, radius: float) -> void:
	var o := _overlay
	o.draw_circle(pos, radius + 1.5, Color(0, 0, 0, 0.55))
	o.draw_circle(pos, radius, color)
	var fs := int(radius * 1.5)
	o.draw_string(_font, pos + Vector2(-radius, fs * 0.36), letter, HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, fs, Color("#1d2733"))


## A small name tag (full map).
func _draw_tag(pos: Vector2, text: String, color: Color) -> void:
	var o := _overlay
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	o.draw_rect(Rect2(pos + Vector2(-3, -11), Vector2(w + 6, 15)), Color(0, 0, 0, 0.6))
	o.draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)


## Map pin: a pink drop with a white dot, its tip on the spot.
func _draw_pin(tip: Vector2) -> void:
	var o := _overlay
	var head := tip + Vector2(0, -14)
	o.draw_colored_polygon(PackedVector2Array([tip, head + Vector2(-6, 3), head + Vector2(6, 3)]), PIN_COLOR)
	o.draw_circle(head, 8.0, Color(0, 0, 0, 0.5))
	o.draw_circle(head, 7.0, PIN_COLOR)
	o.draw_circle(head, 2.8, Color.WHITE)
