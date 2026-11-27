class_name VehicleModels
extends RefCounted
## Traffic vehicle models (original, no real brands), made in Blender by
## tools/blender/make_traffic.py -> assets/vehicles/traffic.glb. All face -Z, origin on the ground.
## Each kind/variant gets its own paint colors (and a rider on two-wheelers).

const CAR_COLORS := ["#e63946", "#f1faee", "#1d3557", "#adb5bd", "#2a9d8f", "#222222", "#ffb703", "#6d6875"]
const JEEP_COLORS := ["#e63946", "#3a86ff", "#ffbe0b", "#8338ec", "#2a9d8f", "#fb5607"]
const MODEL_PATH := "res://assets/vehicles/traffic.glb"
const CAR_MODELS := ["car_sedan", "car_hatch", "car_pickup"]
## model -> [collision box size, top speed m/s, kind]
const SPECS := {
	"car_sedan": [Vector3(1.9, 1.5, 4.5), 13.0, "car"],
	"car_hatch": [Vector3(1.85, 1.5, 4.0), 13.0, "car"],
	"car_pickup": [Vector3(2.0, 1.75, 5.0), 12.5, "car"],
	"jeepney": [Vector3(2.1, 2.2, 6.3), 10.0, "jeepney"],
	"tricycle": [Vector3(2.0, 2.0, 2.4), 8.5, "tricycle"],
	"motorbike": [Vector3(0.7, 1.6, 1.9), 12.0, "motorbike"],
}


const VARIANTS := 8   # different color/rider versions per vehicle kind
static var _cache: Dictionary = {}   # "kind_variant" -> {"mesh", "size", "speed", "kind"}
static var _glow: Dictionary = {}    # shared glowing light materials


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
	var model: String = kind
	if kind == "car":
		model = CAR_MODELS[rng.randi() % CAR_MODELS.size()]
	var n := Node3D.new()
	var src := (load(MODEL_PATH) as PackedScene).instantiate()
	var part := src.find_child(model, true, false) as MeshInstance3D
	part.owner = null
	part.get_parent().remove_child(part)
	part.transform = Transform3D.IDENTITY
	n.add_child(part)
	src.free()
	var palette: Array = CAR_COLORS if kind == "car" or kind == "motorbike" else JEEP_COLORS
	var paint := Color(palette[rng.randi() % palette.size()])
	var accent := Color(JEEP_COLORS[rng.randi() % JEEP_COLORS.size()])
	var accent2 := Color(JEEP_COLORS[rng.randi() % JEEP_COLORS.size()])
	if accent2 == accent or accent2 == paint:
		accent2 = Color("#f1faee")
	_paint_part(part, {"Paint": paint, "Accent": accent, "Accent2": accent2})
	if kind == "motorbike":
		_rider(n, rng, Vector3.ZERO)
	elif kind == "tricycle":
		_rider(n, rng, Vector3(-0.45, 0, 0))
	var merged := MeshMerger.merge(n, [], 260.0)   # (a range > 0 makes it merge even one part)
	var mesh: Mesh = merged.mesh if merged != null else part.mesh
	n.free()
	var spec: Array = SPECS[model]
	return {"mesh": mesh, "size": spec[0], "speed": spec[1], "kind": spec[2]}


## Give the model's named materials their colors for this variant; make the lights glow.
static func _paint_part(mi: MeshInstance3D, colors: Dictionary) -> void:
	for i in mi.mesh.get_surface_count():
		var m := mi.mesh.surface_get_material(i)
		if m == null:
			continue
		var name := m.resource_name
		if colors.has(name):
			var pm := StandardMaterial3D.new()
			pm.albedo_color = colors[name]
			pm.roughness = 0.35
			pm.metallic = 0.2
			mi.set_surface_override_material(i, pm)
		elif name in ["HeadLight", "TailLight", "Signal"]:
			mi.set_surface_override_material(i, _glow_mat(name))


static func _glow_mat(name: String) -> Material:
	if not _glow.has(name):
		match name:
			"HeadLight":
				_glow[name] = LowPoly.glow(Color("#fff6d5"), 1.5)
			"TailLight":
				_glow[name] = LowPoly.glow(Color("#ff2a2a"), 1.5)
			_:
				_glow[name] = LowPoly.glow(Color("#ff9a1a"), 0.5)
	return _glow[name]


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


static func _rider(n: Node3D, rng: RandomNumberGenerator, off: Vector3) -> void:
	var m := CharacterModel.new()
	var look := CharacterModel.random_look(rng, rng.randf() < 0.3, "")
	look["helmet"] = Color(CAR_COLORS[rng.randi() % CAR_COLORS.size()])
	m.build_look(look)
	m.pose_sit()
	m.position = off + Vector3(0, -0.1, 0.3)
	n.add_child(m)
