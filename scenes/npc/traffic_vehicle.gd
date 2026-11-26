class_name TrafficVehicle
extends AnimatableBody3D
## An AI vehicle that drives along the road graph in the right-hand lane (PH drives on the right).
## It slows for vehicles / you / people in front, stops at red lights, and slows down to turn.
## Moved by code each physics frame; the body still blocks you (you can crash into it).

signal cut_off   # had to slam the brakes because of the player
signal crashed_into(other: TrafficVehicle)   # this vehicle hit another one

const ACCEL := 3.0
const BRAKE := 8.0
const STOP_GAP := 4.5          # meters to keep behind whatever is in front
const LOOKAHEAD := 16.0
const LIGHT_STOP_DIST := 7.0   # stop this far before the intersection point

var traffic: Traffic
var graph: RoadGraph
var kind := "car"
var length := 4.0
var box := Vector3(2, 1.5, 4)   # collision box size
var max_speed := 12.0
var speed := 0.0
var from_id := -1
var to_id := -1
var progress := 0.0            # meters along the current road piece
var seg_len := 1.0
var heading := 0.0
var stopped_for_rage := false
var honk_cooldown := 0.0
var careless := false          # ~1 in 10 drivers don't watch crossing traffic (crashes happen)
var crash_time := 0.0          # > 0 while recovering from a crash (stopped, knocked sideways)
var _crash_offset := Vector3.ZERO
var _crash_vel := Vector3.ZERO
var _crash_yaw := 0.0
var _crash_spin := 0.0

var _horn: AudioStreamPlayer3D
var _blocked_time := 0.0


func setup(p_traffic: Traffic, rng: RandomNumberGenerator, a: int, b: int) -> void:
	traffic = p_traffic
	graph = traffic.world.road_graph
	var v := VehicleModels.random_vehicle(rng)
	kind = v["kind"]
	max_speed = float(v["speed"]) * rng.randf_range(0.85, 1.1)
	var size: Vector3 = v["size"]
	box = size
	length = size.z
	add_child(v["node"])
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = Vector3(0, size.y * 0.5, 0)
	add_child(cs)
	collision_layer = Traffic.LAYER_TRAFFIC
	collision_mask = 0
	sync_to_physics = false
	_horn = AudioStreamPlayer3D.new()
	_horn.bus = "SFX"
	_horn.unit_size = 8.0
	add_child(_horn)
	_start_segment(a, b, rng.randf_range(0.0, 0.6))
	speed = max_speed * 0.6
	careless = rng.randf() < 0.1


func _start_segment(a: int, b: int, frac: float = 0.0) -> void:
	from_id = a
	to_id = b
	seg_len = maxf(0.5, graph.get_point(a).distance_to(graph.get_point(b)))
	progress = seg_len * frac
	_place()


func forward() -> Vector3:
	return Vector3(-sin(heading), 0, -cos(heading))


func _physics_process(delta: float) -> void:
	if traffic == null:
		return
	honk_cooldown = maxf(0.0, honk_cooldown - delta)
	if crash_time > 0.0:
		_crash_step(delta)
		return
	var desired := 0.0 if stopped_for_rage else _desired_speed()
	var rate := ACCEL if desired > speed else BRAKE
	var before := speed
	speed = move_toward(speed, desired, rate * delta)
	if before - speed > BRAKE * delta * 0.9 and before > 5.0 and traffic.player_in_front_of(self, 7.0):
		cut_off.emit()
	progress += speed * delta
	while progress >= seg_len:
		progress -= seg_len
		_pick_next()
	_place()


## How fast we want to go right now (obstacles, lights, turns).
func _desired_speed() -> float:
	var want := max_speed
	# Something in front of us (another vehicle, the player, a pedestrian)?
	var gap := traffic.gap_ahead(self, LOOKAHEAD)
	if gap < LOOKAHEAD:
		want = minf(want, maxf(0.0, (gap - STOP_GAP) * 1.3))
		if gap < STOP_GAP + 1.0:
			_blocked_time += get_physics_process_delta_time()
			if _blocked_time > 2.5 and honk_cooldown <= 0.0 and traffic.player_in_front_of(self, 10.0):
				honk()
		else:
			_blocked_time = 0.0
	# Red / yellow light at the end of this road piece?
	var remaining := seg_len - progress
	if remaining < 20.0 and remaining > 2.0 and traffic.must_stop_at(to_id, from_id):
		want = minf(want, maxf(0.0, (remaining - LIGHT_STOP_DIST) * 1.1))
	# Slow down before a sharp turn
	if remaining < 12.0 and _next_turn_sharp:
		want = minf(want, 5.0)
	return want


var _next_id := -1
var _next_turn_sharp := false


func _pick_next() -> void:
	var nxt := _next_id if _next_id != -1 else _choose_next(from_id, to_id)
	_next_id = -1
	_start_segment(to_id, nxt)
	_next_id = _choose_next(from_id, to_id)
	var d1 := (graph.get_point(to_id) - graph.get_point(from_id)).normalized()
	var d2 := (graph.get_point(_next_id) - graph.get_point(to_id)).normalized()
	_next_turn_sharp = d1.dot(d2) < 0.6


## Prefer going roughly straight; sometimes turn; U-turn only at dead ends.
func _choose_next(a: int, b: int) -> int:
	var options := graph.neighbors(b)
	var dir := (graph.get_point(b) - graph.get_point(a)).normalized()
	var best := a
	var best_score := -INF
	for n in options:
		if n == a and options.size() > 1:
			continue
		var d := (graph.get_point(n) - graph.get_point(b)).normalized()
		var score := dir.dot(d) + randf() * 1.2
		if score > best_score:
			best_score = score
			best = n
	return best


## Position on the road, offset into the right-hand lane.
func _place() -> void:
	var a := graph.get_point(from_id)
	var b := graph.get_point(to_id)
	var dir := (b - a) / seg_len
	var right := Vector3(-dir.z, 0, dir.x)
	var lane := clampf(graph.road_width(from_id, to_id) * 0.25, 1.2, 3.2)
	var pos := a + dir * progress + right * lane + _crash_offset
	var target_heading := atan2(-dir.x, -dir.z)
	heading = lerp_angle(heading, target_heading, 0.25) if speed > 0.1 else target_heading
	global_transform = Transform3D(Basis(Vector3.UP, heading + _crash_yaw), Vector3(pos.x, 0.0, pos.z))


## Hit by something: get shoved (`push` m/s) and spin (`spin` rad/s), stop for a few seconds,
## then straighten out and carry on.
func crash(push: Vector3, spin: float, seconds: float = 4.0) -> void:
	speed = 0.0
	crash_time = seconds
	_crash_vel = push
	_crash_spin = spin
	traffic.play_crash(global_position)


func _crash_step(delta: float) -> void:
	crash_time -= delta
	# slide and spin, slowing down quickly
	_crash_offset += _crash_vel * delta
	_crash_vel *= exp(-3.5 * delta)
	_crash_yaw += _crash_spin * delta
	_crash_spin *= exp(-3.0 * delta)
	# last 1.5 s: drive back into the lane
	if crash_time < 1.5:
		var k := 1.0 - exp(-3.0 * delta)
		_crash_offset = _crash_offset.lerp(Vector3.ZERO, k)
		_crash_yaw = lerpf(_crash_yaw, 0.0, k)
	if crash_time <= 0.0:
		_crash_offset = Vector3.ZERO
		_crash_yaw = 0.0
	_place()


func honk() -> void:
	honk_cooldown = 6.0
	_horn.stream = Sfx.horn(kind)
	_horn.play()
