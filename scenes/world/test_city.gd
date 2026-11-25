class_name TestCity
extends Node3D
## Placeholder low-poly city used until the real Bacolod OSM map (Milestone 6).
##
## Layout: an N x N grid of city blocks separated by roads.
## Directions: -Z is "north", +X is "east". The sea is to the west, mountains to the east
## (roughly like Bacolod: Guimaras Strait on the west, Mt. Kanlaon to the east).
##
## Performance: repeated things (buildings, windows, posts, trees) are drawn with
## MultiMesh = one draw call for thousands of copies. Collisions are simple boxes.

const BLOCK := 44.0           # size of one city block (meters)
const ROAD_W := 10.0          # road width
const CELL := BLOCK + ROAD_W  # block + one road
const N := 8                  # blocks per side
const HALF := N * CELL * 0.5  # half the city size
const SIDEWALK := 3.0
const LOT := (BLOCK - 2.0 * SIDEWALK) / 3.0   # each block = 3 x 3 lots
const FLOOR_H := 3.0
const CITY_SEED := 20261125   # same seed = same city every time

## Special places: "blockX,blockZ,lotX,lotZ" -> id. lotZ 0 faces north road, 2 faces south road.
const SPECIAL_LOTS := {
	"3,3,1,0": "home",
	"2,3,1,0": "motor_shop",
	"5,3,1,0": "gas_station",
	"3,2,1,2": "clinic",
	"1,5,1,0": "driving_school",
}
const SCHOOL_BLOCK := Vector2i(1, 5)  # this whole block is the driving school yard

const WALL_COLORS := ["#f2c14e", "#f78154", "#4d9de0", "#7bc96f", "#e15554", "#f4e9cd",
	"#c9a7eb", "#5fc4b8", "#ffb5a7", "#e8e288", "#a3d5ff", "#ffd6e0"]
const ROOF_COLORS := ["#9aa5ab", "#b5652b", "#3d6fa0", "#8c3b2f", "#7d8b8f", "#4f7a4a"]
const AWNING_COLORS := ["#e63946", "#2a9d8f", "#f4a261", "#3a86ff", "#ffbe0b"]
const TREE_COLORS := ["#3f8f3a", "#4ea64a", "#2f7a3b", "#5bab45"]
const FLOOR_CHOICES := [1, 1, 2, 2, 2, 3, 3, 4]

const ASPHALT := Color("#3a3f44")
const LANE_PAINT := Color("#e8e6d9")
const SIDEWALK_COLOR := Color("#c9c5bb")
const YARD_COLOR := Color("#9cc27a")
const WINDOW_COLOR := Color("#2b3a4a")
const POLE_COLOR := Color("#8a8a80")
const WIRE_COLOR := Color("#1a1a1a")
const TRUNK_COLOR := Color("#7a5230")

## Filled while building: [{id, name, door: Vector3, front_z: float}]
var places: Array[Dictionary] = []

var _rng := RandomNumberGenerator.new()
var _collision: StaticBody3D
## MultiMesh buckets: name -> {"xforms": Array, "colors": Array}
var _buckets: Dictionary = {}


func _ready() -> void:
	_rng.seed = CITY_SEED
	_collision = StaticBody3D.new()
	_collision.name = "CityCollision"
	add_child(_collision)

	_build_environment()
	_build_ground()
	_build_roads()
	_build_blocks()
	_build_posts()
	_build_boundary()
	_build_backdrop()
	_flush_multimeshes()


# --- Public API --------------------------------------------------------------

func get_place(id: String) -> Dictionary:
	for p in places:
		if p["id"] == id:
			return p
	return {}


## Where the player and motor start (outside the house).
func get_spawn() -> Dictionary:
	var home := get_place("home")
	var door: Vector3 = home["door"]
	var fz: float = home["front_z"]
	return {
		"player_pos": door + Vector3(0, 0.2, 0),
		"motor_pos": door + Vector3(2.5, 0.2, fz * 3.2),  # parked at the road edge
		"motor_heading": -PI * 0.5,   # facing east along the street
		"camera_yaw": -PI * 0.5,      # camera looks east too
	}


# --- Environment -------------------------------------------------------------

func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#4f9fe0")
	sky_mat.sky_horizon_color = Color("#cfe8f5")
	sky_mat.ground_horizon_color = Color("#cfe8f5")
	sky_mat.ground_bottom_color = Color("#6b8f71")
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color("#cfe3ee")
	env.fog_density = 0.0018
	env.fog_sky_affect = 0.25

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	# The sun. Milestone 4 will rotate this over the day.
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_energy = 1.25
	sun.light_color = Color("#fff4e0")
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 110.0
	add_child(sun)


func _build_ground() -> void:
	# Land from the coast (west) to far east, plus a big collision box.
	var land_center := Vector3(320, -0.5, 0)
	var land_size := Vector3(1760, 1.0, 2400)
	_mm("flat", land_center, land_size, Color("#7fb069"))
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = land_size
	cs.shape = shape
	cs.position = land_center
	_collision.add_child(cs)

	# Beach + sea on the west side
	_mm("flat", Vector3(-575, -0.45, 0), Vector3(30, 1.0, 2400), Color("#e9d8a6"))
	_mm("flat", Vector3(-1840, -0.9, 0), Vector3(2500, 1.0, 2400), Color("#2f7fb5"))


# --- Roads -------------------------------------------------------------------

func _build_roads() -> void:
	var length := 2.0 * HALF + ROAD_W
	for i in N + 1:
		var c := -HALF + CELL * i
		_mm("flat", Vector3(c, 0.015, 0), Vector3(ROAD_W, 0.03, length), ASPHALT)   # north-south
		_mm("flat", Vector3(0, 0.015, c), Vector3(length, 0.03, ROAD_W), ASPHALT)   # east-west
		# Dashed center lines (skipped inside intersections)
		var t := -HALF
		while t < HALF:
			var d := fposmod(t + HALF, CELL)
			var dist_to_cross := minf(d, CELL - d)
			if dist_to_cross > ROAD_W * 0.5 + 1.5:
				_mm("flat", Vector3(c, 0.035, t), Vector3(0.22, 0.02, 2.4), LANE_PAINT)
				_mm("flat", Vector3(t, 0.035, c), Vector3(2.4, 0.02, 0.22), LANE_PAINT)
			t += 6.0


# --- Blocks, lots, buildings -------------------------------------------------

func _block_center(bx: int, bz: int) -> Vector3:
	return Vector3(-HALF + CELL * (bx + 0.5), 0.0, -HALF + CELL * (bz + 0.5))


func _lot_center(bx: int, bz: int, lx: int, lz: int) -> Vector3:
	var inner := BLOCK * 0.5 - SIDEWALK
	return _block_center(bx, bz) + Vector3(-inner + LOT * (lx + 0.5), 0.0, -inner + LOT * (lz + 0.5))


## Which way a lot's "front" faces (towards the nearest road).
func _front_dir(lx: int, lz: int) -> Vector3:
	if lz == 0:
		return Vector3.FORWARD   # -Z
	if lz == 2:
		return Vector3.BACK      # +Z
	if lx == 0:
		return Vector3.LEFT
	return Vector3.RIGHT


func _build_blocks() -> void:
	for bx in N:
		for bz in N:
			var c := _block_center(bx, bz)
			_mm("flat", c + Vector3(0, 0.03, 0), Vector3(BLOCK, 0.06, BLOCK), SIDEWALK_COLOR)
			_mm("flat", c + Vector3(0, 0.035, 0), Vector3(BLOCK - 2.0 * SIDEWALK, 0.07, BLOCK - 2.0 * SIDEWALK), YARD_COLOR)
			var is_school := Vector2i(bx, bz) == SCHOOL_BLOCK
			for lx in 3:
				for lz in 3:
					var key := "%d,%d,%d,%d" % [bx, bz, lx, lz]
					var lc := _lot_center(bx, bz, lx, lz)
					if SPECIAL_LOTS.has(key):
						_build_special(SPECIAL_LOTS[key], lc, -1.0 if lz == 0 else 1.0)
					elif is_school:
						continue  # the rest of this block is the school yard
					elif lx == 1 and lz == 1:
						_build_backyard(lc)
					elif _rng.randf() < 0.88:
						_build_random_building(lc, lx, lz)
					else:
						_add_tree(lc + Vector3(_rng.randf_range(-3, 3), 0, _rng.randf_range(-3, 3)))
			if is_school:
				_build_school_yard(c)


func _build_random_building(lc: Vector3, lx: int, lz: int) -> void:
	var front := _front_dir(lx, lz)
	var w := _rng.randf_range(0.62, 0.92) * LOT
	var d := _rng.randf_range(0.6, 0.9) * LOT
	var floors: int = FLOOR_CHOICES[_rng.randi() % FLOOR_CHOICES.size()]
	var sari_sari := _rng.randf() < 0.3
	if sari_sari:
		floors = 1
	# Push the building to the street side so buildings line the road.
	var slack := (LOT - (d if front.x == 0.0 else w)) * 0.5 - 0.3
	var pos := lc + front * slack
	var wall := Color(_pick(WALL_COLORS))
	var roof := Color(_pick(ROOF_COLORS))
	_add_building(pos, Vector3(w, floors * FLOOR_H, d), wall, roof, 0)
	if sari_sari:
		_add_sari_sari_front(pos, w, d, front)


## A box building with a GI-sheet roof and windows from floor `first_window_floor` up.
func _add_building(pos: Vector3, size: Vector3, wall: Color, roof: Color, first_window_floor: int) -> void:
	var center := pos + Vector3(0, size.y * 0.5, 0)
	_mm("box", center, size, wall)
	_add_collider(center, size)
	# GI roof: slightly bigger, slightly tilted
	var tilt := Basis(Vector3.RIGHT, _rng.randf_range(-0.09, 0.09))
	_mm("box", pos + Vector3(0, size.y + 0.15, 0), Vector3(size.x + 0.7, 0.18, size.z + 0.7), roof, tilt)
	var floors := int(round(size.y / FLOOR_H))
	for f in range(first_window_floor, floors):
		_add_window_row(pos, size, f * FLOOR_H + 1.7)


func _add_window_row(pos: Vector3, size: Vector3, y: float) -> void:
	var nx := int(size.x / 3.2)
	var nz := int(size.z / 3.2)
	for i in nx:
		var x := -size.x * 0.5 + size.x * (i + 0.5) / nx
		for s: float in [-1.0, 1.0]:
			_mm("box", pos + Vector3(x, y, s * (size.z * 0.5 + 0.03)), Vector3(1.1, 1.2, 0.08), WINDOW_COLOR)
	for i in nz:
		var z := -size.z * 0.5 + size.z * (i + 0.5) / nz
		for s: float in [-1.0, 1.0]:
			_mm("box", pos + Vector3(s * (size.x * 0.5 + 0.03), y, z), Vector3(0.08, 1.2, 1.1), WINDOW_COLOR)


## Sari-sari store details: colorful awning, store window with grill, sign board.
func _add_sari_sari_front(pos: Vector3, w: float, d: float, front: Vector3) -> void:
	var awning_color := Color(_pick(AWNING_COLORS))
	if front.z != 0.0:
		var face := pos + front * (d * 0.5)
		_mm("box", face + front * 0.7 + Vector3(0, 2.7, 0), Vector3(w * 0.8, 0.1, 1.4), awning_color, Basis(Vector3.RIGHT, 0.25 * front.z))
		_mm("box", face + front * 0.05 + Vector3(0, 1.3, 0), Vector3(w * 0.5, 1.0, 0.08), Color("#5a4632"))
		_mm("box", face + front * 0.06 + Vector3(0, 3.4, 0), Vector3(w * 0.6, 0.6, 0.06), Color("#d62828"))
	else:
		var face := pos + front * (w * 0.5)
		_mm("box", face + front * 0.7 + Vector3(0, 2.7, 0), Vector3(1.4, 0.1, d * 0.8), awning_color, Basis(Vector3.BACK, -0.25 * front.x))
		_mm("box", face + front * 0.05 + Vector3(0, 1.3, 0), Vector3(0.08, 1.0, d * 0.5), Color("#5a4632"))
		_mm("box", face + front * 0.06 + Vector3(0, 3.4, 0), Vector3(0.06, 0.6, d * 0.6), Color("#d62828"))


func _build_backyard(lc: Vector3) -> void:
	for i in _rng.randi_range(1, 3):
		_add_tree(lc + Vector3(_rng.randf_range(-4, 4), 0, _rng.randf_range(-4, 4)))


func _add_tree(pos: Vector3) -> void:
	var s := _rng.randf_range(0.8, 1.3)
	if _rng.randf() < 0.4:
		# Coconut tree: tall trunk + drooping fronds
		var h := 6.5 * s
		_mm("cyl", pos + Vector3(0, h * 0.5, 0), Vector3(0.32, h, 0.32), TRUNK_COLOR)
		var top := pos + Vector3(0, h, 0)
		for k in 6:
			var a := TAU * k / 6.0 + _rng.randf_range(-0.2, 0.2)
			var dir := Vector3(cos(a), 0, -sin(a))
			var b := Basis(Vector3.UP, a) * Basis(Vector3.BACK, -0.4)
			_mm("box", top + dir * 1.1 + Vector3(0, -0.3, 0), Vector3(2.6, 0.08, 0.55), Color("#4f9a3c"), b)
	else:
		_mm("cyl", pos + Vector3(0, 1.1 * s, 0), Vector3(0.36, 2.2 * s, 0.36), TRUNK_COLOR)
		_mm("cone", pos + Vector3(0, 3.8 * s, 0), Vector3(2.8 * s, 3.4 * s, 2.8 * s), Color(_pick(TREE_COLORS)))
	_add_collider(pos + Vector3(0, 1.5, 0), Vector3(0.4, 3.0, 0.4))


# --- Special places ----------------------------------------------------------

func _build_special(id: String, lc: Vector3, front_z: float) -> void:
	var front_edge := lc.z + front_z * LOT * 0.5   # where this lot meets the sidewalk
	var door := Vector3(lc.x, 0.0, front_edge + front_z * 1.3)
	var display_name := ""
	var label_pos := Vector3.ZERO

	match id:
		"home":
			display_name = "Balay (Home)"
			var size := Vector3(9.0, 5.6, 7.5)
			var pos := Vector3(lc.x, 0, front_edge - front_z * (size.z * 0.5 + 2.0))
			_add_building(pos, size, Color("#ffd6a5"), Color("#b5652b"), 1)
			_add_front_door(pos, size, front_z, Color("#6b4226"))
			# Low fence with a gate gap in the middle
			for sx: float in [-1.0, 1.0]:
				var fc := Vector3(lc.x + sx * 3.6, 0.5, front_edge - front_z * 0.3)
				_mm("box", fc, Vector3(5.0, 1.0, 0.15), Color("#e9e4d8"))
				_add_collider(fc, Vector3(5.0, 1.0, 0.15))
			label_pos = pos + Vector3(0, size.y + 2.0, 0)

		"motor_shop":
			display_name = "Motor Shop"
			var size := Vector3(11.0, 4.5, 9.0)
			var pos := Vector3(lc.x, 0, front_edge - front_z * (size.z * 0.5 + 0.3))
			_add_building(pos, size, Color("#3d8bd9"), Color("#9aa5ab"), 99)
			var face_z := pos.z + front_z * (size.z * 0.5 + 0.04)
			_mm("box", Vector3(pos.x, 1.6, face_z), Vector3(6.5, 3.2, 0.1), Color("#2b2d31"))   # garage opening
			_mm("box", Vector3(pos.x, 3.95, face_z + front_z * 0.05), Vector3(11.2, 0.9, 0.2), Color("#ffd166"))  # sign band
			label_pos = pos + Vector3(0, size.y + 2.0, 0)

		"gas_station":
			display_name = "Gasolinahan (Gas Station)"
			var canopy_z := front_edge - front_z * 3.6
			_mm("flat", Vector3(lc.x, 0.06, front_edge - front_z * 5.0), Vector3(LOT, 0.08, 10.0), Color("#a9adb1"))
			for px: float in [-4.0, 4.0]:
				for pz: float in [-2.8, 2.8]:
					var pc := Vector3(lc.x + px, 2.3, canopy_z + pz)
					_mm("box", pc, Vector3(0.4, 4.6, 0.4), Color("#f5f5f5"))
					_add_collider(pc, Vector3(0.4, 4.6, 0.4))
			_mm("box", Vector3(lc.x, 4.9, canopy_z), Vector3(10.5, 0.6, 7.5), Color("#f5f5f5"))
			_mm("box", Vector3(lc.x, 4.6, canopy_z), Vector3(10.6, 0.25, 7.6), Color("#e63946"))
			for px: float in [-1.8, 1.8]:
				var pump := Vector3(lc.x + px, 0.75, canopy_z)
				_mm("box", pump, Vector3(0.7, 1.5, 0.5), Color("#e63946"))
				_mm("box", pump + Vector3(0, 0.85, 0), Vector3(0.75, 0.2, 0.55), Color("#f5f5f5"))
				_add_collider(pump, Vector3(0.7, 1.5, 0.5))
			var kiosk := Vector3(lc.x, 0, front_edge - front_z * (LOT - 2.0))
			_add_building(kiosk, Vector3(6.0, 3.0, 3.5), Color("#f1faee"), Color("#e63946"), 99)
			door = Vector3(lc.x, 0, canopy_z)   # you "interact" at the pumps
			label_pos = Vector3(lc.x, 7.0, canopy_z)

		"clinic":
			display_name = "Clinic"
			var size := Vector3(10.0, 6.0, 8.5)
			var pos := Vector3(lc.x, 0, front_edge - front_z * (size.z * 0.5 + 1.5))
			_add_building(pos, size, Color("#f4f6f8"), Color("#7d8b8f"), 1)
			_add_front_door(pos, size, front_z, Color("#5fa8d3"))
			var cross := Vector3(pos.x, 3.3, pos.z + front_z * (size.z * 0.5 + 0.05))
			_mm("box", cross, Vector3(1.6, 0.5, 0.1), Color("#e63946"))
			_mm("box", cross, Vector3(0.5, 1.6, 0.1), Color("#e63946"))
			label_pos = pos + Vector3(0, size.y + 2.0, 0)

		"driving_school":
			display_name = "Driving School"
			var size := Vector3(10.0, 4.0, 7.0)
			var pos := Vector3(lc.x, 0, front_edge - front_z * (size.z * 0.5 + 1.0))
			_add_building(pos, size, Color("#7bc96f"), Color("#3d6fa0"), 99)
			_add_front_door(pos, size, front_z, Color("#2b2d31"))
			_mm("box", Vector3(pos.x, 3.4, pos.z + front_z * (size.z * 0.5 + 0.08)), Vector3(8.0, 0.8, 0.15), Color("#ffffff"))
			label_pos = pos + Vector3(0, size.y + 2.0, 0)

	LowPoly.label(self, display_name, label_pos, 1.1)
	places.append({"id": id, "name": display_name, "door": door, "front_z": front_z})


func _add_front_door(pos: Vector3, size: Vector3, front_z: float, color: Color) -> void:
	_mm("box", Vector3(pos.x, 1.1, pos.z + front_z * (size.z * 0.5 + 0.06)), Vector3(1.3, 2.2, 0.12), color)


## Open paved yard with a ring of cones (the training course comes in Milestone 3).
func _build_school_yard(block_c: Vector3) -> void:
	var yard_c := block_c + Vector3(0, 0, LOT * 0.5)
	_mm("flat", yard_c + Vector3(0, 0.05, 0), Vector3(BLOCK - 2.0 * SIDEWALK, 0.1, LOT * 2.0), Color("#8d9399"))
	for ring: float in [1.0, 0.55]:
		var count := 22 if ring > 0.9 else 12
		for i in count:
			var a := TAU * i / count
			var p := yard_c + Vector3(cos(a) * 15.0 * ring, 0.45, sin(a) * 9.0 * ring)
			_mm("cone", p, Vector3(0.45, 0.7, 0.45), Color("#ff7b1c"))


# --- Electric posts with messy wires -----------------------------------------

func _build_posts() -> void:
	var off := ROAD_W * 0.5 + 0.7
	for i in N + 1:
		var road := -HALF + CELL * i
		var ns_line: Array[Vector3] = []
		var ew_line: Array[Vector3] = []
		for b in N:
			var bc := -HALF + CELL * (b + 0.5)
			for k: float in [-1.0, 1.0]:
				ns_line.append(Vector3(road + off, 0, bc + k * 12.0))
				ew_line.append(Vector3(bc + k * 12.0, 0, road + off))
		_add_post_line(ns_line, true)
		_add_post_line(ew_line, false)


func _add_post_line(points: Array[Vector3], along_z: bool) -> void:
	for idx in points.size():
		var p := points[idx]
		_mm("cyl", p + Vector3(0, 3.75, 0), Vector3(0.26, 7.5, 0.26), POLE_COLOR)
		var arm := Vector3(1.8, 0.12, 0.12) if along_z else Vector3(0.12, 0.12, 1.8)
		_mm("box", p + Vector3(0, 7.1, 0), arm, POLE_COLOR)
		_add_collider(p + Vector3(0, 3.75, 0), Vector3(0.3, 7.5, 0.3))
		if idx > 0:
			var prev := points[idx - 1]
			var side := Vector3(1, 0, 0) if along_z else Vector3(0, 0, 1)
			for w in 3:
				var o := side * (-0.7 + 0.7 * w) + Vector3(0, 7.0 - 0.25 * w, 0)
				_add_wire(prev + o, p + o, 0.35 + 0.25 * w)


## A sagging wire made of two straight segments.
func _add_wire(a: Vector3, b: Vector3, sag: float) -> void:
	var mid := (a + b) * 0.5 - Vector3(0, sag, 0)
	_wire_segment(a, mid)
	_wire_segment(mid, b)


func _wire_segment(a: Vector3, b: Vector3) -> void:
	var length := a.distance_to(b)
	var seg_basis := Basis.looking_at(b - a, Vector3.UP)
	_mm("flat", (a + b) * 0.5, Vector3(0.035, 0.035, length), WIRE_COLOR, seg_basis)


# --- Edges of the world ------------------------------------------------------

func _build_boundary() -> void:
	# Concrete wall around the test city so you can't drive off into nothing.
	var e := HALF + 8.0
	var walls := [
		[Vector3(0, 1.25, -e), Vector3(2.0 * e + 1.0, 2.5, 1.0)],
		[Vector3(0, 1.25, e), Vector3(2.0 * e + 1.0, 2.5, 1.0)],
		[Vector3(-e, 1.25, 0), Vector3(1.0, 2.5, 2.0 * e + 1.0)],
		[Vector3(e, 1.25, 0), Vector3(1.0, 2.5, 2.0 * e + 1.0)],
	]
	for w: Array in walls:
		_mm("box", w[0], w[1], Color("#b8b2a7"))
		_add_collider(w[0], w[1])


func _build_backdrop() -> void:
	# Not drivable, just scenery seen through the fog. Mt. Kanlaon is the big one.
	_mm("mountain", Vector3(1150, 0, 350), Vector3(1500, 560, 1500), Color("#5f8a6a"))
	_mm("mountain", Vector3(950, 0, -500), Vector3(900, 260, 900), Color("#6f9a74"))
	_mm("mountain", Vector3(1000, 0, 1100), Vector3(1000, 300, 1000), Color("#6f9a74"))
	# Guimaras island across the strait (west)
	_mm("mountain", Vector3(-1700, -0.5, 300), Vector3(1400, 120, 900), Color("#6f9a74"))


# --- MultiMesh + collision helpers -------------------------------------------

## Queue one instance of a shape. `size` scales a 1x1x1 mesh.
func _mm(bucket: String, center: Vector3, size: Vector3, color: Color, rot: Basis = Basis.IDENTITY) -> void:
	if not _buckets.has(bucket):
		_buckets[bucket] = {"xforms": [], "colors": []}
	var data: Dictionary = _buckets[bucket]
	(data["xforms"] as Array).append(Transform3D(rot * Basis.from_scale(size), center))
	# Instance colors go straight to the shader, so convert from sRGB (hex) to linear.
	(data["colors"] as Array).append(color.srgb_to_linear())


func _add_collider(center: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = center
	_collision.add_child(cs)


func _bucket_mesh(bucket: String) -> Mesh:
	match bucket:
		"cyl":
			var m := CylinderMesh.new()
			m.top_radius = 0.5
			m.bottom_radius = 0.5
			m.height = 1.0
			m.radial_segments = 7
			m.rings = 0
			return m
		"cone", "mountain":
			var m := CylinderMesh.new()
			m.top_radius = 0.0
			m.bottom_radius = 0.5
			m.height = 1.0
			m.radial_segments = 7 if bucket == "cone" else 9
			m.rings = 0
			return m
	var b := BoxMesh.new()
	b.size = Vector3.ONE
	return b


## Turns every queued bucket into one MultiMeshInstance3D (one draw call each).
func _flush_multimeshes() -> void:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	for bucket: String in _buckets:
		var data: Dictionary = _buckets[bucket]
		var xforms: Array = data["xforms"]
		var colors: Array = data["colors"]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _bucket_mesh(bucket)
		mm.instance_count = xforms.size()
		for i in xforms.size():
			mm.set_instance_transform(i, xforms[i])
			mm.set_instance_color(i, colors[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "MM_" + bucket
		mmi.multimesh = mm
		mmi.material_override = mat
		# Flat ground stuff and far mountains don't need to cast shadows (saves GPU).
		if bucket == "flat" or bucket == "mountain":
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
	_buckets.clear()


func _pick(arr: Array) -> String:
	return arr[_rng.randi() % arr.size()]
