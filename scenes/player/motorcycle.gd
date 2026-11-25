class_name Motorcycle
extends CharacterBody3D
## Arcade-style scooter. We don't simulate real wheels/suspension: we keep a single
## `speed` number and a `heading` angle, and move the body forward with move_and_slide().
## That's simpler and feels more "game-y" than VehicleBody3D for a motorcycle.
## The model faces -Z. Stats come from config/motors.gd.

signal crashed(impact_speed: float, wall_normal: Vector3)
signal ran_out_of_fuel
signal bumped(impact_speed: float)   # small hit that doesn't throw you off

const GRAVITY := 22.0
const BRAKE_DECEL := 14.0        # m/s^2 with full brake
const HANDBRAKE_DECEL := 9.0
const ROLL_DRAG := 1.6           # slowdown when you let go of the gas
const REVERSE_MAX := 2.5         # m/s, slow "walking it backwards" reverse
const BASE_TURN_RATE := 1.9      # radians/second at handling 1.0
const CRASH_SPEED := 8.5         # m/s (~30 km/h) head-on hit that throws you off
const MAX_LEAN := 0.5            # radians (~29 degrees)
const WHEEL_RADIUS := 0.27
const MIX_RATE := 22050.0        # placeholder engine/horn sound sample rate
const PUSH_SPEED := 1.6          # m/s when pushing the motor with no gas
const PASSENGER_SEAT := Vector3(0, 0.02, 0.6)

var motor_id: String = ""
var stats: Dictionary = {}
var speed := 0.0          # forward speed in m/s (negative = reversing)
var heading := 0.0        # which way the motor faces (radians around Y)
var fuel_liters := 0.0
var damage := 0.0         # 0 - 100
var is_ridden := false
var is_fallen := false
var throttle_input := 0.0
var steer_input := 0.0
var last_accel := 0.0     # m/s^2 this frame (negative = braking), for passenger comfort
var passenger: Node3D = null

var _lean_pivot: Node3D
var _fork: Node3D
var _front_wheel: Node3D
var _rear_wheel: Node3D
var _rider: CharacterModel
var _paint: StandardMaterial3D
var _crash_cooldown := 0.0
var _bump_cooldown := 0.0

var _audio: AudioStreamPlayer3D
var _playback: AudioStreamGeneratorPlayback
var _engine_phase := 0.0
var _horn_phase_a := 0.0
var _horn_phase_b := 0.0


func _ready() -> void:
	collision_layer = 4     # "motorcycles" layer
	collision_mask = 1      # only bumps into the world
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(50.0)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.6, 1.0, 1.9)
	shape.shape = box
	shape.position = Vector3(0, 0.5, 0)
	add_child(shape)

	_paint = StandardMaterial3D.new()
	_paint.roughness = 0.5
	_build_model()
	_setup_audio()
	if motor_id == "":
		setup(Motors.DEFAULT_MOTOR_ID)


## Load a motor's stats from config/motors.gd and fill the tank.
func setup(id: String) -> void:
	motor_id = id
	stats = Motors.get_motor(id)
	fuel_liters = float(stats["tank_liters"])
	var colors: Array = stats["colors"]
	_paint.albedo_color = Color(str(colors[0]))


## Put the motor somewhere instantly, standing still.
func place(pos: Vector3, new_heading: float) -> void:
	global_position = pos
	heading = new_heading
	rotation = Vector3(0, heading, 0)
	speed = 0.0
	velocity = Vector3.ZERO
	is_fallen = false
	reset_physics_interpolation()


func set_ridden(on: bool) -> void:
	is_ridden = on
	_rider.visible = on
	if on:
		is_fallen = false   # picking the motor back up


func fall_over() -> void:
	is_fallen = true


## Add gas. Returns how many liters actually fit.
func refuel(liters: float) -> float:
	var tank: float = stats["tank_liters"]
	var added := clampf(liters, 0.0, tank - fuel_liters)
	fuel_liters += added
	return added


func get_tank_liters() -> float:
	return float(stats["tank_liters"])


func is_out_of_fuel() -> bool:
	return fuel_liters <= 0.0


# --- Passenger ---------------------------------------------------------------

## The node passengers sit on (so they lean with the motor).
func get_seat_mount() -> Node3D:
	return _lean_pivot


func attach_passenger(p: Node3D) -> void:
	passenger = p


func detach_passenger() -> Node3D:
	var p := passenger
	passenger = null
	return p


# --- Getters for HUD and other systems ---------------------------------------

func get_top_speed() -> float:
	# Damage lowers top speed by up to 30%.
	return float(stats.get("top_speed_kmh", 90.0)) / 3.6 * (1.0 - damage * 0.003)


func get_speed_kmh() -> float:
	return absf(speed) * 3.6


func get_fuel_ratio() -> float:
	return clampf(fuel_liters / float(stats["tank_liters"]), 0.0, 1.0)


func get_display_name() -> String:
	return str(stats.get("name", "Motor"))


func get_forward() -> Vector3:
	return Vector3(-sin(heading), 0.0, -cos(heading))


# --- Driving -----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_crash_cooldown = maxf(0.0, _crash_cooldown - delta)
	_bump_cooldown = maxf(0.0, _bump_cooldown - delta)

	var throttle := 0.0
	var brake := 0.0
	var steer := 0.0
	var handbrake := false
	if is_ridden:
		throttle = Input.get_action_strength("accelerate")
		brake = Input.get_action_strength("brake")
		steer = Input.get_axis("steer_right", "steer_left")   # left = positive
		handbrake = Input.is_action_pressed("handbrake")
	var pushing := fuel_liters <= 0.0 and throttle > 0.0
	if fuel_liters <= 0.0:
		throttle = 0.0
	throttle_input = throttle
	var start_speed := speed
	steer_input = steer

	var top := get_top_speed()
	var accel: float = stats["acceleration"]

	# Gas: strong pickup at low speed, fading as we reach top speed.
	if throttle > 0.0 and speed >= -0.2:
		var fade := clampf(1.0 - speed / top, 0.0, 1.0)
		speed = minf(speed + accel * throttle * (0.35 + 0.65 * fade) * delta, top)
	elif throttle > 0.0:
		speed = move_toward(speed, 0.0, BRAKE_DECEL * delta)   # stop reversing first

	# Brake, and if nearly stopped, slowly reverse.
	if brake > 0.0:
		if speed > 0.3:
			speed = move_toward(speed, 0.0, BRAKE_DECEL * brake * delta)
		else:
			speed = move_toward(speed, -REVERSE_MAX, 3.0 * brake * delta)
	if pushing:
		# No gas: you can only push it at walking speed ("tulod anay!")
		speed = move_toward(speed, PUSH_SPEED, 2.0 * delta)
	elif throttle == 0.0 and brake == 0.0:
		speed = move_toward(speed, 0.0, ROLL_DRAG * delta)
	if handbrake:
		speed = move_toward(speed, 0.0, HANDBRAKE_DECEL * delta)
	if is_fallen:
		speed = move_toward(speed, 0.0, 20.0 * delta)
	last_accel = (speed - start_speed) / delta

	# Steering: needs some speed to turn, and turns wider when going fast.
	var abs_speed := absf(speed)
	var low_speed_factor := clampf(abs_speed / 3.0, 0.0, 1.0)
	var high_speed_factor := lerpf(1.0, 0.45, clampf(abs_speed / top, 0.0, 1.0))
	var turn_rate: float = BASE_TURN_RATE * float(stats["handling"]) * low_speed_factor * high_speed_factor
	if handbrake:
		turn_rate *= 1.6
	heading += steer * turn_rate * signf(speed) * delta
	rotation = Vector3(0, heading, 0)

	var forward := get_forward()
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= GRAVITY * delta
	velocity.x = forward.x * speed
	velocity.z = forward.z * speed

	var prev_pos := global_position
	var pre_speed := speed
	move_and_slide()
	_handle_collisions(forward, pre_speed)

	var moved := Vector2(global_position.x - prev_pos.x, global_position.z - prev_pos.z).length()
	_use_fuel(moved)
	_update_visuals(delta, steer, top)


func _handle_collisions(forward: Vector3, pre_speed: float) -> void:
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var n := col.get_normal()
		if absf(n.y) > 0.6:
			continue   # that's the ground, not a wall
		# 1.0 = drove straight into it, 0.0 = just brushing along it
		var head_on := -forward.dot(n) * signf(pre_speed)
		if head_on <= 0.05:
			continue
		var impact := absf(pre_speed) * head_on
		speed *= clampf(1.0 - head_on * 1.2, 0.0, 1.0)
		if is_ridden and impact >= CRASH_SPEED and _crash_cooldown <= 0.0:
			_crash_cooldown = 1.0
			damage = minf(100.0, damage + impact * 1.5)
			crashed.emit(impact, Vector3(n.x, 0.0, n.z).normalized())
			return
		elif impact > 3.0 and _bump_cooldown <= 0.0:
			_bump_cooldown = 0.6
			damage = minf(100.0, damage + impact * 0.2)
			bumped.emit(impact)


func _use_fuel(meters: float) -> void:
	if fuel_liters <= 0.0 or meters <= 0.0:
		return
	var kmpl: float = stats["km_per_liter"]
	fuel_liters -= meters / 1000.0 / kmpl * Economy.FUEL_USE_MULTIPLIER
	if fuel_liters <= 0.0:
		fuel_liters = 0.0
		ran_out_of_fuel.emit()


func _update_visuals(delta: float, steer: float, top: float) -> void:
	# Lean into turns (more lean at higher speed). Lie on the side if fallen.
	var lean_target := 1.35 if is_fallen else steer * MAX_LEAN * clampf(absf(speed) / (top * 0.6), 0.0, 1.0)
	_lean_pivot.rotation.z = lerpf(_lean_pivot.rotation.z, lean_target, 1.0 - exp(-6.0 * delta))
	# Turn the handlebar (less at high speed).
	var bar := steer * 0.45 * (1.0 - clampf(absf(speed) / top, 0.0, 1.0) * 0.7)
	_fork.rotation.y = lerpf(_fork.rotation.y, bar, 1.0 - exp(-10.0 * delta))
	# Spin wheels.
	var spin := speed / WHEEL_RADIUS * delta
	_front_wheel.rotation.x -= spin
	_rear_wheel.rotation.x -= spin


# --- Model (placeholder scooter built from boxes) ----------------------------

func _build_model() -> void:
	_lean_pivot = Node3D.new()
	_lean_pivot.name = "LeanPivot"
	add_child(_lean_pivot)
	var dark := Color("#2b2d31")
	var black := Color("#151515")

	_rear_wheel = _make_wheel(_lean_pivot, Vector3(0, WHEEL_RADIUS, 0.62))

	# Body
	LowPoly.box(_lean_pivot, Vector3(0.36, 0.08, 0.6), dark, Vector3(0, 0.33, -0.05))             # footboard
	LowPoly.box(_lean_pivot, Vector3(0.4, 0.36, 0.78), Color.WHITE, Vector3(0, 0.56, 0.36), _paint) # rear body
	LowPoly.box(_lean_pivot, Vector3(0.34, 0.1, 0.7), black, Vector3(0, 0.79, 0.32))              # seat
	LowPoly.box(_lean_pivot, Vector3(0.42, 0.62, 0.12), Color.WHITE, Vector3(0, 0.62, -0.42), _paint) # leg shield
	LowPoly.box(_lean_pivot, Vector3(0.14, 0.12, 0.3), black, Vector3(0, 0.5, 0.95))             # rear fender
	LowPoly.box(_lean_pivot, Vector3(0.2, 0.06, 0.04), Color.RED, Vector3(0, 0.66, 0.76), LowPoly.glow(Color("#ff2a2a"), 2.5))  # tail light

	# Front fork: steers left/right with the handlebar
	_fork = Node3D.new()
	_fork.name = "Fork"
	_fork.position = Vector3(0, 0, -0.62)
	_lean_pivot.add_child(_fork)
	_front_wheel = _make_wheel(_fork, Vector3(0, WHEEL_RADIUS, -0.03))
	LowPoly.box(_fork, Vector3(0.16, 0.06, 0.42), Color.WHITE, Vector3(0, 0.58, -0.03), _paint)    # front fender
	LowPoly.box(_fork, Vector3(0.08, 0.62, 0.08), dark, Vector3(0, 0.62, 0.1))                     # steering column
	LowPoly.box(_fork, Vector3(0.3, 0.18, 0.26), Color.WHITE, Vector3(0, 1.0, 0.12), _paint)       # handlebar cover
	LowPoly.box(_fork, Vector3(0.66, 0.05, 0.05), black, Vector3(0, 1.02, 0.2))                    # handlebar
	LowPoly.box(_fork, Vector3(0.18, 0.1, 0.05), Color.WHITE, Vector3(0, 1.0, -0.02), LowPoly.glow(Color("#fff6d5"), 3.0))  # headlight

	# Rider model (only visible while someone is riding)
	_rider = CharacterModel.new()
	_rider.name = "Rider"
	_lean_pivot.add_child(_rider)
	_rider.build(Player.JACKET_COLOR, Player.PANTS_COLOR, Player.HELMET_COLOR)
	_rider.pose_sit()
	_rider.position = Vector3(0, -0.04, 0.28)
	_rider.visible = false


## A wheel = tire + hub + one spoke (so you can see it spinning).
func _make_wheel(parent: Node3D, pos: Vector3) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pos
	parent.add_child(pivot)
	var tire := LowPoly.cylinder(pivot, WHEEL_RADIUS, 0.12, Color("#1c1c1c"), Vector3.ZERO, 12)
	tire.rotation.z = PI * 0.5   # cylinder axis along X
	var hub := LowPoly.cylinder(pivot, 0.12, 0.14, Color("#9ea3a8"), Vector3.ZERO, 8)
	hub.rotation.z = PI * 0.5
	LowPoly.box(pivot, Vector3(0.15, 0.42, 0.05), Color("#9ea3a8"))
	return pivot


# --- Placeholder sound: engine hum + horn, generated in code -----------------
# (Real recorded sounds come in Milestone 7. This just makes testing feel alive.)

func _setup_audio() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = 0.15
	_audio = AudioStreamPlayer3D.new()
	_audio.stream = gen
	_audio.unit_size = 6.0
	add_child(_audio)
	_audio.play()
	_playback = _audio.get_stream_playback() as AudioStreamGeneratorPlayback


func _process(_delta: float) -> void:
	if _playback == null:
		return
	var frames := _playback.get_frames_available()
	if frames <= 0:
		return
	var horn_on := is_ridden and Input.is_action_pressed("horn")
	var rpm := clampf(absf(speed) / maxf(get_top_speed(), 1.0), 0.0, 1.0)
	var engine_freq := 38.0 + rpm * 95.0 + throttle_input * 10.0
	var engine_vol := (0.05 + throttle_input * 0.05) if is_ridden else 0.0
	var buf := PackedVector2Array()
	buf.resize(frames)
	for i in frames:
		var s := 0.0
		if engine_vol > 0.0:
			_engine_phase = fmod(_engine_phase + engine_freq / MIX_RATE, 1.0)
			s += (_engine_phase * 2.0 - 1.0) * engine_vol   # buzzy sawtooth
		if horn_on:
			_horn_phase_a = fmod(_horn_phase_a + 420.0 / MIX_RATE, 1.0)
			_horn_phase_b = fmod(_horn_phase_b + 530.0 / MIX_RATE, 1.0)
			s += ((1.0 if _horn_phase_a < 0.5 else -1.0) + (1.0 if _horn_phase_b < 0.5 else -1.0)) * 0.08
		buf[i] = Vector2(s, s)
	_playback.push_buffer(buf)
