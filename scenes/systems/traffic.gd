class_name Traffic
extends Node3D
## Keeps AI vehicles and pedestrians around the player, and runs traffic lights.
## - Vehicles spawn 90-260 m away on random roads and are removed past 320 m.
## - How many depends on the graphics setting, rush hour (more) and late night (fewer).
## - Traffic lights sit at intersections of major roads (3+ roads meeting). The two crossing
##   directions take turns: 12 s green, 3 s yellow, then red while the other side goes.

signal vehicle_cut_off(vehicle: TrafficVehicle)
signal vehicles_crashed(a: TrafficVehicle, b: TrafficVehicle)

const LAYER_TRAFFIC := 8
const SPAWN_MIN := 90.0
const SPAWN_MAX := 260.0
const DESPAWN := 320.0
const LIGHT_RADIUS := 220.0
const CYCLE := 32.0

var world: GameWorld
var player: Player
var motor: Motorcycle
var pedestrians: Pedestrians
var enabled := true

var vehicles: Array[TrafficVehicle] = []
var _rng := RandomNumberGenerator.new()
var _clock := 0.0
var _tick := 0.0
var _crash_tick := 0.0
var _crash_sfx: AudioStreamPlayer3D
var _signal_cache := {}      # point id -> bool (is a traffic light)
var _light_nodes := {}       # point id -> {"node": Node3D, "heads": Array}
var _mat_off: StandardMaterial3D
var _mats_on: Array[StandardMaterial3D] = []


func setup(p_world: GameWorld, p_player: Player, p_motor: Motorcycle) -> void:
	world = p_world
	player = p_player
	motor = p_motor
	_rng.randomize()
	VehicleModels.prewarm()                    # build vehicle templates now (not while riding)
	CharacterModel.prewarm(16, 90.0, false)    # and people templates
	_mat_off = LowPoly.mat(Color("#2a2a2a"))
	_crash_sfx = AudioStreamPlayer3D.new()
	_crash_sfx.bus = "SFX"
	_crash_sfx.unit_size = 15.0
	add_child(_crash_sfx)
	for c: String in ["#ff3b30", "#ffcc00", "#34c759"]:
		_mats_on.append(LowPoly.glow(Color(c), 3.0))


## Target number of vehicles right now.
func target_count() -> int:
	var base := {"low": 10, "medium": 20, "high": 34}.get(Settings.graphics, 20) as int
	var h := GameState.hour_of_day()
	var mult := 1.0
	if Economy.is_surge(h):
		mult = 1.4
	elif h >= 21.0 or h < 5.0:
		mult = 0.45
	return int(base * mult)


func player_pos() -> Vector3:
	return motor.global_position if player.state == Player.State.RIDING else player.global_position


func _physics_process(delta: float) -> void:
	if world == null:
		return
	_clock += delta
	_crash_tick -= delta
	if _crash_tick <= 0.0:
		_crash_tick = 0.1
		_check_vehicle_crashes()
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.25
	var center := player_pos()
	# remove far vehicles
	for v in vehicles.duplicate():
		if not is_instance_valid(v):
			vehicles.erase(v)
		elif v.global_position.distance_to(center) > DESPAWN and not v.stopped_for_rage:
			vehicles.erase(v)
			v.queue_free()
	# spawn new ones
	if enabled:
		var want := target_count()
		for i in 3:
			if vehicles.size() >= want:
				break
			_spawn_one(center)
	_update_lights(center)


func _spawn_one(center: Vector3) -> void:
	var g := world.road_graph
	var ids := g.point_ids_near(center, SPAWN_MAX)
	if ids.is_empty():
		return
	for attempt in 6:
		var a: int = ids[_rng.randi() % ids.size()]
		var pa := g.get_point(a)
		if pa.distance_to(Vector3(center.x, 0, center.z)) < SPAWN_MIN:
			continue
		var nb := g.neighbors(a)
		if nb.is_empty():
			continue
		var b: int = nb[_rng.randi() % nb.size()]
		if _occupied(pa, 14.0):
			continue
		var v := TrafficVehicle.new()
		add_child(v)
		v.setup(self, _rng, a, b)
		v.cut_off.connect(func() -> void: vehicle_cut_off.emit(v))
		vehicles.append(v)
		return


## NPC vehicles that overlap while moving crash into each other.
func _check_vehicle_crashes() -> void:
	var n := vehicles.size()
	for i in n:
		var a := vehicles[i]
		if not is_instance_valid(a) or a.crash_time > 0.0:
			continue
		for j in range(i + 1, n):
			var b := vehicles[j]
			if not is_instance_valid(b) or b.crash_time > 0.0:
				continue
			var rel := b.global_position - a.global_position
			if rel.length() > (a.length + b.length) * 0.5:
				continue
			# overlapping boxes? check along both vehicles' sides (rough but cheap)
			var fa := a.forward()
			var ra := Vector3(-fa.z, 0, fa.x)
			if absf(rel.dot(fa)) > (a.length + b.box.x) * 0.45 or absf(rel.dot(ra)) > (a.box.x + b.length) * 0.45:
				continue
			var closing := (a.forward() * a.speed - b.forward() * b.speed).length()
			if closing < 2.0:
				continue
			var dir := rel.normalized()
			a.crash(-dir * closing * 0.35, randf_range(-1.5, 1.5))
			b.crash(dir * closing * 0.35, randf_range(-1.5, 1.5))
			vehicles_crashed.emit(a, b)


func play_crash(where: Vector3) -> void:
	_crash_sfx.global_position = where
	_crash_sfx.stream = Sfx.tones([110.0, 80.0, 60.0, 140.0], 0.06, 0.6)
	_crash_sfx.play()


func _occupied(p: Vector3, r: float) -> bool:
	for v in vehicles:
		if is_instance_valid(v) and v.global_position.distance_to(p) < r:
			return true
	return false


## Distance to the nearest thing in front of `v` in its lane (vehicles, you, people).
func gap_ahead(v: TrafficVehicle, max_d: float) -> float:
	var f := v.forward()
	var right := Vector3(-f.z, 0, f.x)
	var p := v.global_position
	var best := max_d
	for o in vehicles:
		if o == v or not is_instance_valid(o):
			continue
		var rel := o.global_position - p
		var along := rel.dot(f)
		if along <= 0.0 or along > max_d + o.length:
			continue
		if absf(rel.dot(right)) > 1.8:
			continue
		if v.careless and absf(o.forward().dot(f)) < 0.5:
			continue   # careless driver doesn't see crossing traffic...
		best = minf(best, along - (v.length + o.length) * 0.5)
	var pp := player_pos() - p
	var pa := pp.dot(f)
	if pa > 0.0 and pa < max_d + 2.0 and absf(pp.dot(right)) < 1.7:
		best = minf(best, pa - v.length * 0.5 - 1.0)
	if pedestrians != null:
		best = minf(best, pedestrians.gap_ahead(p, f, right, v.length, max_d))
	return best


func player_in_front_of(v: TrafficVehicle, dist: float) -> bool:
	var f := v.forward()
	var rel := player_pos() - v.global_position
	var along := rel.dot(f)
	return along > 0.0 and along < dist + v.length * 0.5 and absf(rel.dot(Vector3(-f.z, 0, f.x))) < 2.0


# --- Traffic lights -----------------------------------------------------------------

func is_signal(id: int) -> bool:
	if not _signal_cache.has(id):
		var g := world.road_graph
		_signal_cache[id] = g.degree(id) >= 3 and g.is_major_point(id)
	return _signal_cache[id]


## Which of the two directions an approach (coming from `from_id`) belongs to.
func _group(id: int, from_id: int) -> int:
	var g := world.road_graph
	var nb := g.neighbors(id)
	var ref := g.get_point(nb[0]) - g.get_point(id)
	var app := g.get_point(from_id) - g.get_point(id)
	var c := absf(ref.normalized().dot(app.normalized()))
	return 0 if c > 0.707 else 1


## 0 = green, 1 = yellow, 2 = red, for traffic coming into `id` from `from_id`.
func light_state(id: int, from_id: int) -> int:
	var t := fmod(_clock + float(id % 97) * 0.37, CYCLE)
	if _group(id, from_id) == 0:
		if t < 12.0:
			return 0
		return 1 if t < 15.0 else 2
	if t < 16.0:
		return 2
	if t < 28.0:
		return 0
	return 1 if t < 31.0 else 2


## Seconds until this approach's light changes (for the countdown timers).
func light_time_left(id: int, from_id: int) -> float:
	var t := fmod(_clock + float(id % 97) * 0.37, CYCLE)
	var changes := [12.0, 15.0, CYCLE] if _group(id, from_id) == 0 else [16.0, 28.0, 31.0, CYCLE]
	for c: float in changes:
		if t < c:
			return c - t
	return 0.0


## The traffic light you're riding toward (within 60 m ahead), for the HUD.
## Returns {} or {"state": 0/1/2, "secs": float, "dist": float}.
func upcoming_light(pos: Vector3, forward: Vector3) -> Dictionary:
	var g := world.road_graph
	var best := {}
	var best_d := 60.0
	for id in g.point_ids_near(pos, 60.0):
		if not is_signal(id):
			continue
		var rel := g.get_point(id) - Vector3(pos.x, 0, pos.z)
		var along := rel.dot(forward)
		if along < 2.0 or along > best_d or absf(rel.dot(Vector3(-forward.z, 0, forward.x))) > 10.0:
			continue
		# which road are we coming in on? the neighbor most behind us
		var from := -1
		var best_dot := -2.0
		for n in g.neighbors(id):
			var dot := (g.get_point(id) - g.get_point(n)).normalized().dot(forward)
			if dot > best_dot:
				best_dot = dot
				from = n
		if from == -1:
			continue
		best_d = along
		best = {"state": light_state(id, from), "secs": light_time_left(id, from), "dist": along}
	return best


func must_stop_at(id: int, from_id: int) -> bool:
	return is_signal(id) and light_state(id, from_id) != 0


## Build light posts near you, remove far ones, and update their colors.
func _update_lights(center: Vector3) -> void:
	var g := world.road_graph
	var near := {}
	for id in g.point_ids_near(center, LIGHT_RADIUS):
		if is_signal(id):
			near[id] = true
			if not _light_nodes.has(id):
				_light_nodes[id] = _build_light(id)
	for id: int in _light_nodes.keys():
		if not near.has(id):
			(_light_nodes[id]["node"] as Node3D).queue_free()
			_light_nodes.erase(id)
	for id: int in _light_nodes:
		for head: Dictionary in _light_nodes[id]["heads"]:
			var state := light_state(id, int(head["from"]))
			var lamps: Array = head["lamps"]
			for i in 3:
				(lamps[i] as MeshInstance3D).material_override = _mats_on[i] if i == [2, 1, 0][state] else _mat_off
			# countdown timer above the light
			var timer: Label3D = head["timer"]
			timer.text = str(ceili(light_time_left(id, int(head["from"]))))
			timer.modulate = [Color("#34c759"), Color("#ffcc00"), Color("#ff3b30")][state]


## One pole per road coming into the intersection, on the right side, facing the drivers.
func _build_light(id: int) -> Dictionary:
	var g := world.road_graph
	var node := Node3D.new()
	add_child(node)
	var heads: Array = []
	var p := g.get_point(id)
	for from_id in g.neighbors(id):
		var d := (p - g.get_point(from_id)).normalized()   # direction traffic travels
		var right := Vector3(-d.z, 0, d.x)
		var w := g.road_width(id, from_id)
		var pos := p - d * (w * 0.5 + 3.0) + right * (w * 0.5 + 1.2)
		var pole := Node3D.new()
		node.add_child(pole)
		pole.transform = Transform3D(Basis(Vector3.UP, atan2(-d.x, -d.z)), pos)
		LowPoly.box(pole, Vector3(0.14, 4.2, 0.14), Color("#3b3b3b"), Vector3(0, 2.1, 0))
		LowPoly.box(pole, Vector3(0.4, 1.1, 0.3), Color("#1f1f1f"), Vector3(0, 4.5, 0.1))
		var lamps: Array = []
		for i in 3:
			lamps.append(LowPoly.box(pole, Vector3(0.24, 0.24, 0.06), Color.BLACK, Vector3(0, 4.85 - i * 0.34, -0.06)))
		MeshMerger.merge(pole, lamps)   # performance: pole + housing in one mesh
		# countdown seconds above the light (like the timers on real Bacolod intersections)
		var timer := Label3D.new()
		timer.position = Vector3(0, 5.45, -0.05)
		timer.font_size = 64
		timer.pixel_size = 0.008
		timer.outline_size = 14
		timer.outline_modulate = Color(0, 0, 0, 0.9)
		timer.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		pole.add_child(timer)
		heads.append({"from": from_id, "lamps": lamps, "timer": timer})
	return {"node": node, "heads": heads}
