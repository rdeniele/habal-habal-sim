class_name VehicleModels
extends RefCounted
## Low-poly vehicle models made in code (original, no real brands). All face -Z, origin on the ground.
## Each returns {"node": Node3D, "size": Vector3 (collision box), "speed": max m/s, "kind": String}.

const CAR_COLORS := ["#e63946", "#f1faee", "#1d3557", "#adb5bd", "#2a9d8f", "#222222", "#ffb703", "#6d6875"]
const JEEP_COLORS := ["#e63946", "#3a86ff", "#ffbe0b", "#8338ec", "#2a9d8f", "#fb5607"]


const VARIANTS := 8   # different color/rider versions per vehicle kind
static var _cache: Dictionary = {}   # "kind_variant" -> {"mesh", "size", "speed", "kind"}


## A random traffic vehicle. Performance: each kind/variant is built and merged into ONE mesh
## only once, then reused (new vehicles appear instantly).
static func random_vehicle(rng: RandomNumberGenerator) -> Dictionary:
	var r := rng.randf()
	var kind := "car" if r < 0.42 else ("jeepney" if r < 0.62 else ("tricycle" if r < 0.82 else "motorbike"))
	var key := "%s_%d" % [kind, rng.randi() % VARIANTS]
	if not _cache.has(key):
		_cache[key] = _build_cached(kind, rng)
	var c: Dictionary = _cache[key]
	var mi := MeshInstance3D.new()
	mi.mesh = c["mesh"]
	mi.visibility_range_end = 260.0
	mi.visibility_range_end_margin = 10.0
	return {"node": mi, "size": c["size"], "speed": c["speed"], "kind": c["kind"]}


static func _build_cached(kind: String, rng: RandomNumberGenerator) -> Dictionary:
	var v: Dictionary
	match kind:
		"car":
			v = car(rng)
		"jeepney":
			v = jeepney(rng)
		"tricycle":
			v = tricycle(rng)
		_:
			v = motorbike(rng)
	var node: Node3D = v["node"]
	var merged := MeshMerger.merge(node)
	var mesh: Mesh = merged.mesh if merged != null else null
	node.free()
	return {"mesh": mesh, "size": v["size"], "speed": v["speed"], "kind": v["kind"]}


static func clear_cache() -> void:
	_cache.clear()


## Build every vehicle variant ahead of time (call during loading).
static func prewarm() -> void:
	var rng := RandomNumberGenerator.new()
	for kind: String in ["car", "jeepney", "tricycle", "motorbike"]:
		for i in VARIANTS:
			rng.seed = hash(kind) + i
			var key := "%s_%d" % [kind, i]
			if not _cache.has(key):
				_cache[key] = _build_cached(kind, rng)


static func _wheel(parent: Node3D, pos: Vector3, radius: float, width: float) -> void:
	var w := LowPoly.cylinder(parent, radius, width, Color("#1c1c1c"), pos, 10)
	w.rotation.z = PI * 0.5
	var hub := LowPoly.cylinder(parent, radius * 0.45, width + 0.02, Color("#9ea3a8"), pos, 8)
	hub.rotation.z = PI * 0.5


static func _lights(parent: Node3D, half_w: float, y: float, front_z: float, back_z: float) -> void:
	for sx: float in [-1.0, 1.0]:
		LowPoly.box(parent, Vector3(0.28, 0.12, 0.05), Color.WHITE, Vector3(sx * (half_w - 0.25), y, front_z), LowPoly.glow(Color("#fff6d5"), 1.5))
		LowPoly.box(parent, Vector3(0.24, 0.1, 0.05), Color.RED, Vector3(sx * (half_w - 0.25), y, back_z), LowPoly.glow(Color("#ff2a2a"), 1.5))


static func car(rng: RandomNumberGenerator) -> Dictionary:
	var n := Node3D.new()
	var col := Color(CAR_COLORS[rng.randi() % CAR_COLORS.size()])
	LowPoly.box(n, Vector3(1.8, 0.62, 4.3), col, Vector3(0, 0.6, 0))                       # body
	LowPoly.box(n, Vector3(1.62, 0.55, 2.2), col.darkened(0.05), Vector3(0, 1.18, 0.25))  # cabin
	LowPoly.box(n, Vector3(1.64, 0.42, 0.05), Color("#2b3a4a"), Vector3(0, 1.17, -0.86))  # windshield
	LowPoly.box(n, Vector3(1.64, 0.38, 0.05), Color("#2b3a4a"), Vector3(0, 1.17, 1.36))   # rear glass
	LowPoly.box(n, Vector3(1.66, 0.36, 1.9), Color("#2b3a4a"), Vector3(0, 1.18, 0.25))    # side windows
	LowPoly.box(n, Vector3(1.84, 0.18, 0.2), Color("#3b3b3b"), Vector3(0, 0.38, -2.15))   # bumpers
	LowPoly.box(n, Vector3(1.84, 0.18, 0.2), Color("#3b3b3b"), Vector3(0, 0.38, 2.15))
	for sx: float in [-0.86, 0.86]:
		for sz: float in [-1.35, 1.35]:
			_wheel(n, Vector3(sx, 0.34, sz), 0.34, 0.22)
	_lights(n, 0.9, 0.68, -2.16, 2.16)
	return {"node": n, "size": Vector3(1.9, 1.5, 4.4), "speed": 13.0, "kind": "car"}


## Jeepney: long colorful body, open back, silver roof, chrome hood.
static func jeepney(rng: RandomNumberGenerator) -> Dictionary:
	var n := Node3D.new()
	var col := Color(JEEP_COLORS[rng.randi() % JEEP_COLORS.size()])
	var chrome := Color("#c9ced3")
	LowPoly.box(n, Vector3(2.0, 1.0, 4.4), col, Vector3(0, 1.0, 0.6))                      # passenger body
	LowPoly.box(n, Vector3(2.02, 0.45, 3.6), Color("#1d2733"), Vector3(0, 1.6, 0.8))       # window band
	LowPoly.box(n, Vector3(2.15, 0.14, 5.0), chrome, Vector3(0, 2.0, 0.4))                 # roof
	for sz: float in [-1.0, 0.4, 1.8, 2.7]:
		for sx: float in [-0.98, 0.98]:
			LowPoly.box(n, Vector3(0.06, 0.5, 0.06), chrome, Vector3(sx, 1.72, sz))           # roof posts
	LowPoly.box(n, Vector3(1.8, 0.75, 1.4), chrome, Vector3(0, 0.85, -2.4))                # hood
	LowPoly.box(n, Vector3(1.86, 0.6, 0.12), Color("#3b3b3b"), Vector3(0, 0.75, -3.12))    # grille
	LowPoly.box(n, Vector3(1.9, 0.8, 0.9), col.lightened(0.2), Vector3(0, 1.6, -1.6))      # cab top
	LowPoly.box(n, Vector3(1.9, 0.45, 0.05), Color("#2b3a4a"), Vector3(0, 1.55, -2.06))    # windshield
	for stripe: float in [0.75, 1.3]:
		for sx: float in [-1.01, 1.01]:
			LowPoly.box(n, Vector3(0.02, 0.1, 4.2), Color(JEEP_COLORS[rng.randi() % JEEP_COLORS.size()]), Vector3(sx, stripe, 0.6))
	for sx: float in [-0.88, 0.88]:
		for sz: float in [-2.3, 1.9]:
			_wheel(n, Vector3(sx, 0.4, sz), 0.4, 0.26)
	_lights(n, 0.9, 0.8, -3.15, 2.82)
	return {"node": n, "size": Vector3(2.1, 2.1, 6.2), "speed": 10.0, "kind": "jeepney"}


## Tricycle: a motorbike with a covered sidecar.
static func tricycle(rng: RandomNumberGenerator) -> Dictionary:
	var n := Node3D.new()
	var col := Color(JEEP_COLORS[rng.randi() % JEEP_COLORS.size()])
	_bike_body(n, Color("#2b2d31"), Vector3(-0.45, 0, 0))
	LowPoly.box(n, Vector3(1.2, 0.9, 1.8), col, Vector3(0.45, 0.85, 0.1))       # sidecar body
	LowPoly.box(n, Vector3(1.3, 0.1, 2.4), col.darkened(0.2), Vector3(0.2, 1.95, 0.1))   # roof
	LowPoly.box(n, Vector3(0.06, 0.8, 0.06), Color("#555555"), Vector3(1.0, 1.55, -0.8))
	LowPoly.box(n, Vector3(0.06, 0.8, 0.06), Color("#555555"), Vector3(1.0, 1.55, 1.0))
	_wheel(n, Vector3(1.05, 0.28, 0.4), 0.28, 0.14)
	_rider(n, rng, Vector3(-0.45, 0, 0))
	return {"node": n, "size": Vector3(2.0, 2.0, 2.4), "speed": 8.5, "kind": "tricycle"}


static func motorbike(rng: RandomNumberGenerator) -> Dictionary:
	var n := Node3D.new()
	_bike_body(n, Color(CAR_COLORS[rng.randi() % CAR_COLORS.size()]), Vector3.ZERO)
	_rider(n, rng, Vector3.ZERO)
	return {"node": n, "size": Vector3(0.7, 1.6, 1.9), "speed": 12.0, "kind": "motorbike"}


static func _bike_body(n: Node3D, col: Color, off: Vector3) -> void:
	_wheel(n, off + Vector3(0, 0.27, 0.62), 0.27, 0.12)
	_wheel(n, off + Vector3(0, 0.27, -0.62), 0.27, 0.12)
	LowPoly.box(n, Vector3(0.4, 0.36, 0.78), col, off + Vector3(0, 0.56, 0.36))
	LowPoly.box(n, Vector3(0.34, 0.1, 0.7), Color("#151515"), off + Vector3(0, 0.79, 0.32))
	LowPoly.box(n, Vector3(0.42, 0.62, 0.12), col, off + Vector3(0, 0.62, -0.42))
	LowPoly.box(n, Vector3(0.66, 0.05, 0.05), Color("#151515"), off + Vector3(0, 1.02, -0.42))


static func _rider(n: Node3D, rng: RandomNumberGenerator, off: Vector3) -> void:
	var m := CharacterModel.new()
	var look := CharacterModel.random_look(rng, rng.randf() < 0.3, "")
	look["helmet"] = Color(CAR_COLORS[rng.randi() % CAR_COLORS.size()])
	m.build_look(look)
	m.pose_sit()
	m.position = off + Vector3(0, -0.1, 0.3)
	n.add_child(m)
