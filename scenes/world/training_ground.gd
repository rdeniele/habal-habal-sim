class_name TrainingGround
extends Node3D
## The Driving School's private training ground: a fenced lot far outside the city
## (20 km away, nothing else around). Lessons and the passenger test happen here, so no
## traffic or people drive through the training. Built when the driving school starts and
## removed when you go back to the city for your license.
##
##   - cone yard (the lesson oval) on the left side
##   - a practice loop road around the lot (passenger training checkpoints)
##   - the school's training office, a wall all around, trees outside

const ORIGIN := Vector3(20000, 0, 20000)
const LOT_X := 110.0          # half size of the fenced lot
const LOT_Z := 75.0
const LOOP_X := 88.0          # practice loop center line (half size)
const LOOP_Z := 56.0
const LOOP_W := 9.0
const YARD := Vector3(-30, 0, 0)   # lesson oval center (local)
const OFFICE := Vector3(-30, 0, -38)


func _ready() -> void:
	position = ORIGIN
	_build()


# --- Positions the story uses (world space) ---------------------------------------

func yard_center() -> Vector3:
	return ORIGIN + YARD


## Where the jeepney drops you off: in front of the training office.
func arrival_point() -> Vector3:
	return ORIGIN + OFFICE + Vector3(0, 0, 8)


func office_door() -> Vector3:
	return ORIGIN + OFFICE + Vector3(0, 0, 4.2)


## Passenger training checkpoints: once around the practice loop.
func route_points() -> Array[Vector3]:
	var local: Array[Vector3] = [
		Vector3(30, 0, -LOOP_Z), Vector3(LOOP_X, 0, -15), Vector3(LOOP_X, 0, 25),
		Vector3(20, 0, LOOP_Z), Vector3(-60, 0, LOOP_Z), Vector3(-LOOP_X, 0, 10),
	]
	var out: Array[Vector3] = []
	for p in local:
		out.append(ORIGIN + p)
	return out


## Is this spot at the training ground? (the game's "you left Bacolod" check skips it)
static func contains(pos: Vector3) -> bool:
	return absf(pos.x - ORIGIN.x) < LOT_X + 60.0 and absf(pos.z - ORIGIN.z) < LOT_Z + 60.0


# --- Building it ------------------------------------------------------------------

func _build() -> void:
	var deco := Node3D.new()   # all the look-only parts, merged into a few meshes at the end
	add_child(deco)

	# Grass all around (with a floor to stand/ride on) + the asphalt lot
	_flat_rect(Rect2(-600, -600, 1200, 1200), 0.0, TextureFactory.material(TextureFactory.grass()), Color("#8fae6a"), 0.25)
	_flat_rect(Rect2(-LOT_X, -LOT_Z, LOT_X * 2.0, LOT_Z * 2.0), 0.02, TextureFactory.material(TextureFactory.asphalt()), Color("#8a8f96"), 0.2)
	var floor_body := StaticBody3D.new()
	add_child(floor_body)
	_box_shape(floor_body, Vector3(1200, 1, 1200), Vector3(0, -0.5, 0))

	# Practice loop: edge lines + dashed center line
	var white := Color("#f4f1de")
	for side: float in [-1.0, 1.0]:
		var ox := LOOP_X + side * LOOP_W * 0.5
		var oz := LOOP_Z + side * LOOP_W * 0.5
		LowPoly.box(deco, Vector3(ox * 2.0, 0.02, 0.18), white, Vector3(0, 0.04, -oz))
		LowPoly.box(deco, Vector3(ox * 2.0, 0.02, 0.18), white, Vector3(0, 0.04, oz))
		LowPoly.box(deco, Vector3(0.18, 0.02, oz * 2.0), white, Vector3(-ox, 0.04, 0))
		LowPoly.box(deco, Vector3(0.18, 0.02, oz * 2.0), white, Vector3(ox, 0.04, 0))
	var yellow := Color("#f2c14e")
	for x in range(-80, 81, 8):
		LowPoly.box(deco, Vector3(3.5, 0.02, 0.16), yellow, Vector3(x, 0.045, -LOOP_Z))
		LowPoly.box(deco, Vector3(3.5, 0.02, 0.16), yellow, Vector3(x, 0.045, LOOP_Z))
	for z in range(-48, 49, 8):
		LowPoly.box(deco, Vector3(0.16, 0.02, 3.5), yellow, Vector3(-LOOP_X, 0.045, z))
		LowPoly.box(deco, Vector3(0.16, 0.02, 3.5), yellow, Vector3(LOOP_X, 0.045, z))

	# Lesson cones: two rings, the track is between them (same as the story's oval)
	var orange := Color("#ff7b1c")
	for ring: float in [1.0, 0.55]:
		var count := 22 if ring > 0.9 else 12
		for i in count:
			var a := TAU * i / count
			_cone(deco, YARD + Vector3(cos(a) * 15.0 * ring, 0, sin(a) * 9.0 * ring), orange)
	# corner cones on the loop (just for looks)
	for cx: float in [-1.0, 1.0]:
		for cz: float in [-1.0, 1.0]:
			for k in 3:
				_cone(deco, Vector3(cx * (LOOP_X - LOOP_W * 0.5 - 1.5 - k * 1.2), 0, cz * (LOOP_Z - LOOP_W * 0.5 - 1.5)), orange)

	# Wall around the lot (solid) with a white/blue paint job
	var walls := StaticBody3D.new()
	add_child(walls)
	var wall_h := 1.4
	for side: float in [-1.0, 1.0]:
		LowPoly.box(deco, Vector3(LOT_X * 2.0, wall_h, 0.4), Color("#e9ecef"), Vector3(0, wall_h * 0.5, side * LOT_Z))
		LowPoly.box(deco, Vector3(LOT_X * 2.0, 0.25, 0.42), Color("#3d5a80"), Vector3(0, wall_h, side * LOT_Z))
		_box_shape(walls, Vector3(LOT_X * 2.0, wall_h, 0.4), Vector3(0, wall_h * 0.5, side * LOT_Z))
		LowPoly.box(deco, Vector3(0.4, wall_h, LOT_Z * 2.0), Color("#e9ecef"), Vector3(side * LOT_X, wall_h * 0.5, 0))
		LowPoly.box(deco, Vector3(0.42, 0.25, LOT_Z * 2.0), Color("#3d5a80"), Vector3(side * LOT_X, wall_h, 0))
		_box_shape(walls, Vector3(0.4, wall_h, LOT_Z * 2.0), Vector3(side * LOT_X, wall_h * 0.5, 0))

	# Training office (solid)
	var office := StaticBody3D.new()
	add_child(office)
	LowPoly.box(deco, Vector3(14, 5.5, 8), Color("#f1e3c6"), OFFICE + Vector3(0, 2.75, 0))
	LowPoly.box(deco, Vector3(15, 0.5, 9), Color("#3d5a80"), OFFICE + Vector3(0, 5.75, 0))
	LowPoly.box(deco, Vector3(1.6, 2.4, 0.1), Color("#6b4f3a"), OFFICE + Vector3(0, 1.2, 4.02))     # door
	for wx: float in [-4.5, 4.5]:
		LowPoly.box(deco, Vector3(2.4, 1.4, 0.1), Color("#9cc3e6"), OFFICE + Vector3(wx, 2.6, 4.02))   # windows
	_box_shape(office, Vector3(14, 5.5, 8), OFFICE + Vector3(0, 2.75, 0))
	LowPoly.label(self, "DRIVING SCHOOL  ·  TRAINING GROUND", OFFICE + Vector3(0, 7.0, 4.2), 1.1)
	LowPoly.label(self, "START / PARK", YARD + Vector3(0, 1.6, 7.0), 0.5)

	# Trees outside the wall (look only)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4041
	for i in 90:
		var a := rng.randf() * TAU
		var r := rng.randf_range(135.0, 320.0)
		var p := Vector3(cos(a) * r * 1.2, 0, sin(a) * r)
		var h := rng.randf_range(3.5, 7.0)
		LowPoly.box(deco, Vector3(0.4, h, 0.4), Color("#6b4f3a"), p + Vector3(0, h * 0.5, 0))
		LowPoly.box(deco, Vector3(h * 0.7, h * 0.55, h * 0.7), Color("#3f7d3a").lerp(Color("#6aa84f"), rng.randf()), p + Vector3(0, h, 0))

	MeshMerger.merge(deco)   # performance: hundreds of little boxes -> a few meshes


func _cone(parent: Node3D, pos: Vector3, color: Color) -> void:
	var c := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = 0.22
	mesh.height = 0.7
	mesh.radial_segments = 7
	mesh.rings = 0
	c.mesh = mesh
	c.material_override = LowPoly.mat(color)
	c.position = pos + Vector3(0, 0.37, 0)
	parent.add_child(c)


## A flat textured rectangle (UVs tile with the size, so textures don't stretch).
func _flat_rect(r: Rect2, y: float, material: Material, color: Color, uv_scale: float) -> void:
	var mb := MeshBuilder.new()
	var a := r.position
	var c := r.end
	mb.add_flat_tri(a, Vector2(c.x, a.y), c, y, color, uv_scale)
	mb.add_flat_tri(a, c, Vector2(a.x, c.y), y, color, uv_scale)
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit(material)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _box_shape(body: StaticBody3D, size: Vector3, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = pos
	body.add_child(cs)
