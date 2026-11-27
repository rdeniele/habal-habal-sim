class_name Motorcycle
extends CharacterBody3D
## Arcade-style scooter. We don't simulate real wheels/suspension: we keep a single
## `speed` number and a `heading` angle, and move the body forward with move_and_slide().
## That's simpler and feels more "game-y" than VehicleBody3D for a motorcycle.
## The model faces -Z. Stats come from config/motors.gd.

signal crashed(impact_speed: float, wall_normal: Vector3)
signal ran_out_of_fuel
signal bumped(impact_speed: float)   # small hit that doesn't throw you off
signal hit_vehicle(vehicle: Node)     # ran into a traffic vehicle (road rage chance)
signal hit_person(person: Node, impact_speed: float)

const GRAVITY := 22.0
const BRAKE_DECEL := 14.0        # m/s^2 with full brake
const HANDBRAKE_DECEL := 9.0
const ROLL_DRAG := 1.6           # slowdown when you let go of the gas
const REVERSE_MAX := 2.5         # m/s, slow "walking it backwards" reverse
const BASE_TURN_RATE := 1.9      # radians/second at handling 1.0
const CRASH_SPEED := 8.5         # m/s (~30 km/h) head-on hit that throws you off
const MAX_LEAN := 0.5            # radians (~29 degrees)
const WHEEL_RADIUS := 0.27
const MODEL_PATH := "res://assets/vehicles/scooter.glb"
const MIX_RATE := 22050.0        # placeholder engine/horn sound sample rate
const PUSH_SPEED := 1.6          # m/s when pushing the motor with no gas
const PASSENGER_SEAT := Vector3(0, -0.07, 0.62)

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
var input_enabled := true   # false while a dialog/menu is open
var drowsiness := 0.0       # 0-1, set by Needs when energy is low: the motor drifts
var _drift_t := 0.0
var is_active := true       # false = hidden (you don't have a motor yet)

var _lean_pivot: Node3D
var _fork: Node3D
var _front_wheel: Node3D
var _rear_wheel: Node3D
var _rider: CharacterModel
var _fp_hidden := false
var _mirrors: Array[Dictionary] = []   # {"viewport": SubViewport, "camera": Camera3D, "glass": Node3D, "side": float}
var _mirrors_active := false
var _mirror_hold := 0.0
var _headlight: SpotLight3D
var _paint: StandardMaterial3D
var _crash_cooldown := 0.0
var _bump_cooldown := 0.0

var _audio: AudioStreamPlayer3D
var _playback: AudioStreamGeneratorPlayback
var _pulse_phase := 0.0     # engine: where we are between two "putts"
var _pulse_len := 1.0       # this putt's length (slightly random = more real)
var _env := 0.0             # loudness of the current putt (decays)
var _body_phase := 0.0      # the exhaust's "boom" tone
var _lp := 0.0              # low-pass filter memory
var _lp2 := 0.0
var _rpm := 0.0             # smoothed engine speed 0..1
var _noise := RandomNumberGenerator.new()
var _horn_phase_a := 0.0
var _horn_phase_b := 0.0
var _horn_lp := 0.0


func _ready() -> void:
	collision_layer = 4     # "motorcycles" layer
	collision_mask = 1 | 8  # the world + traffic and people
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(50.0)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.6, 1.0, 1.9)
	shape.shape = box
	shape.position = Vector3(0, 0.5, 0)
	add_child(shape)

	_paint = StandardMaterial3D.new()
	_paint.roughness = 0.32
	_paint.metallic = 0.2
	_paint.metallic_specular = 0.6
	_build_model()
	_setup_audio()
	if motor_id == "":
		setup(Motors.DEFAULT_MOTOR_ID)


## Load a motor's stats from config/motors.gd, fill the tank, fix all damage.
func setup(id: String, color_index: int = 0) -> void:
	motor_id = id
	stats = Motors.get_motor(id)
	fuel_liters = float(stats["tank_liters"])
	damage = 0.0
	var colors: Array = stats["colors"]
	set_paint(Color(str(colors[clampi(color_index, 0, colors.size() - 1)])))


func set_paint(color: Color) -> void:
	_paint.albedo_color = color


## Show/hide the motor completely (no collision either). Used before you own one.
func set_active(on: bool) -> void:
	is_active = on
	visible = on
	collision_layer = 4 if on else 0
	process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED


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


## Where the rider's eyes are (for the first-person camera).
func get_head_position() -> Vector3:
	if is_ridden and _rider != null:
		return _rider.get_eye_position()   # the rider's real eyes (the body shows in first person)
	return _lean_pivot.global_transform * Vector3(0, 1.56, 0.24)


func get_lean() -> float:
	return _lean_pivot.rotation.z


## First-person camera: hide the rider body so we look out from the helmet.
## First person: keep the rider's body (hands on the grips, arms, knees), hide only the head.
func set_fp_hidden(hidden: bool) -> void:
	_fp_hidden = hidden
	_rider.visible = is_ridden
	_rider.set_first_person(hidden)


## Side mirrors only render while someone looks at them (first person). Call every frame.
func set_mirrors_active(on: bool) -> void:
	_mirror_hold = 0.25 if on else 0.0


## Two side mirrors on the handlebar. Each has a little camera looking back; its picture
## is shown (flipped like a real mirror) on the mirror glass. The model has a "MirrorL" and
## "MirrorR" spot on the back of each mirror housing, already turned to face the rider.
func _build_mirrors() -> void:
	for side: float in [-1.0, 1.0]:
		var spot := _fork.find_child("MirrorL" if side < 0.0 else "MirrorR", true, false) as Node3D
		var sv := SubViewport.new()
		sv.size = Vector2i(192, 128)
		sv.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(sv)
		var cam := Camera3D.new()
		cam.fov = 45.0
		cam.far = 300.0
		sv.add_child(cam)
		var glass := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(0.13, 0.085)
		glass.mesh = quad
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_texture = sv.get_texture()
		mat.uv1_scale = Vector3(-1, 1, 1)   # mirror image (flip left/right)
		mat.uv1_offset = Vector3(1, 0, 0)
		glass.material_override = mat
		spot.add_child(glass)   # quad faces +Z = toward the rider
		_mirrors.append({"viewport": sv, "camera": cam, "glass": glass, "side": side})


func _update_mirrors(delta: float) -> void:
	_mirror_hold = maxf(0.0, _mirror_hold - delta)
	var on := _mirror_hold > 0.0 and is_ridden
	if on != _mirrors_active:
		_mirrors_active = on
		for m in _mirrors:
			(m["viewport"] as SubViewport).render_target_update_mode = \
				SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	if not on:
		return
	var back := -get_forward()
	for m in _mirrors:
		var glass: Node3D = m["glass"]
		var side: float = m["side"]
		var cam: Camera3D = m["camera"]
		# look backward and a little outward, like a real mirror angle
		var dir := back.rotated(Vector3.UP, -side * 0.18)
		cam.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), glass.global_position + Vector3(0, 0.05, 0))


func set_headlight(on: bool) -> void:
	_headlight.visible = on


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


## How far the gas left will take you (in-game fuel use).
func get_range_km() -> float:
	return fuel_liters * float(stats.get("km_per_liter", 50.0)) / Economy.FUEL_USE_MULTIPLIER


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
	if is_ridden and input_enabled:
		throttle = Input.get_action_strength("accelerate")
		brake = Input.get_action_strength("brake")
		steer = Input.get_axis("steer_right", "steer_left")   # left = positive
		handbrake = Input.is_action_pressed("handbrake")
	var pushing := fuel_liters <= 0.0 and throttle > 0.0
	if fuel_liters <= 0.0:
		throttle = 0.0
	# Sleepy rider: slow side-to-side drift you have to correct.
	if drowsiness > 0.0 and is_ridden:
		_drift_t += delta
		steer = clampf(steer + sin(_drift_t * 1.3) * 0.45 * drowsiness, -1.0, 1.0)
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
		var other := col.get_collider()
		if other is Pedestrian and is_ridden:
			hit_person.emit(other, impact)
		elif other is TrafficVehicle and is_ridden and impact > 1.0:
			hit_vehicle.emit(other)
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


# --- Model (made in Blender: tools/blender/make_scooter.py) -------------------

func _build_model() -> void:
	_lean_pivot = Node3D.new()
	_lean_pivot.name = "LeanPivot"
	add_child(_lean_pivot)

	var scene: PackedScene = load(MODEL_PATH)
	var model := scene.instantiate() as Node3D
	model.name = "Scooter"
	_lean_pivot.add_child(model)
	# The parts the game moves (names set in the Blender script)
	_fork = model.find_child("Fork", true, false) as Node3D             # turns around the tilted steering axis
	_front_wheel = model.find_child("FrontWheel", true, false) as Node3D
	_rear_wheel = model.find_child("RearWheel", true, false) as Node3D
	_apply_model_materials(model)

	# Real light from the headlight, switched on at night by the DayCycle
	_headlight = SpotLight3D.new()
	_headlight.rotation_degrees = Vector3(-10, 0, 0)
	_headlight.spot_range = 30.0
	_headlight.spot_angle = 34.0
	_headlight.light_energy = 5.0
	_headlight.light_color = Color("#fff1d0")
	_headlight.visible = false
	model.find_child("HeadlightMount", true, false).add_child(_headlight)

	# Rider model (only visible while someone is riding)
	_make_grips()
	_build_rider()
	add_to_group("fp_hide")
	_build_mirrors()


## Spots on the handlebar grips (they turn with the bars), for the rider's hands.
var _grips: Array[Node3D] = []


func _make_grips() -> void:
	for side: float in [-1.0, 1.0]:
		var g := Node3D.new()
		g.name = "GripL" if side < 0.0 else "GripR"
		_fork.add_child(g)
		# grip middle in the scooter's space (from tools/blender/make_scooter.py), into the fork's space
		var model_pos := Vector3(side * 0.3, 1.025, -0.388)
		var fork_xf := _rel_to(_fork, _lean_pivot)
		g.transform = Transform3D(Basis.IDENTITY, fork_xf.affine_inverse() * model_pos)
		_grips.append(g)


static func _rel_to(n: Node3D, root: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	while n != null and n != root:
		t = n.transform * t
		n = n.get_parent() as Node3D
	return t


## The player sitting on the motor (same look as the player on foot).
func _build_rider() -> void:
	_rider = CharacterModel.new()
	_rider.name = "Rider"
	_lean_pivot.add_child(_rider)
	_rider.build_look(CharacterModel.rider_look(GameState.player_female))
	_rider.pose_sit()
	# the detailed model has shorter arms: sit closer to the handlebar so the hands reach
	_rider.position = Vector3(0, -0.1, 0.14 if _rider.has_skin() else 0.3)
	_rider.visible = is_ridden
	_rider.set_first_person(_fp_hidden)
	_rider.hand_targets = {"l": _grips[0], "r": _grips[1]}   # hands hold the grips (detailed model)


## Rebuild the rider (after picking male / female).
func refresh_rider() -> void:
	_rider.free()
	_build_rider()


## Swap the model's materials by name: "Paint" gets the motor's color, the lights glow.
func _apply_model_materials(node: Node) -> void:
	var mi := node as MeshInstance3D
	if mi != null and mi.mesh != null:
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i)
			if m == null:
				continue
			match m.resource_name:
				"Paint":
					mi.set_surface_override_material(i, _paint)
				"HeadLight":
					mi.set_surface_override_material(i, LowPoly.glow(Color("#fff6d5"), 3.0))
				"TailLight":
					mi.set_surface_override_material(i, LowPoly.glow(Color("#ff2a2a"), 2.5))
				"Signal":
					mi.set_surface_override_material(i, LowPoly.glow(Color("#ff9a1a"), 0.6))
	for c in node.get_children():
		_apply_model_materials(c)


# --- Engine + horn sound, generated in code --------------------------------
# A small 4-stroke engine is a series of "putts" (one per firing). Each putt is a short
# burst (a low boom + some noise) that fades fast. Faster putts = higher revs.
# Scooters have automatic (CVT) gearboxes: revs jump up when you twist the throttle
# and then stay fairly high while the speed builds.

func _setup_audio() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = 0.15
	_audio = AudioStreamPlayer3D.new()
	_audio.stream = gen
	_audio.unit_size = 6.0
	_audio.bus = "SFX"
	add_child(_audio)
	_audio.play()
	_playback = _audio.get_stream_playback() as AudioStreamGeneratorPlayback


func _process(delta: float) -> void:
	_update_mirrors(delta)
	if _playback == null:
		return
	var frames := _playback.get_frames_available()
	if frames <= 0:
		return
	var horn_on := is_ridden and input_enabled and Input.is_action_pressed("horn")
	var running := is_ridden and fuel_liters > 0.0 and is_active
	var spd := clampf(absf(speed) / maxf(get_top_speed(), 1.0), 0.0, 1.0)
	var want := maxf(spd * 0.85, throttle_input * 0.55) + throttle_input * 0.15
	_rpm = lerpf(_rpm, want, minf(1.0, delta * (6.0 if want > _rpm else 2.5)))
	var fire_hz := 13.0 + _rpm * 62.0        # putts per second (idle ~800 rpm .. ~4500 rpm)
	var vol := (0.22 + throttle_input * 0.12) if running else 0.0
	var decay := exp(-1.0 / (MIX_RATE * (0.018 - _rpm * 0.008)))
	var tone := 1.0 - _rpm * 0.25
	var bright := 0.12 + throttle_input * 0.18 + _rpm * 0.1
	var buf := PackedVector2Array()
	buf.resize(frames)
	for i in frames:
		var s := 0.0
		if vol > 0.0:
			_pulse_phase += fire_hz / MIX_RATE
			if _pulse_phase >= _pulse_len:
				_pulse_phase -= _pulse_len
				_pulse_len = _noise.randf_range(0.93, 1.07)   # engines are never perfectly even
				_env = 1.0
			_body_phase = fmod(_body_phase + fire_hz * 2.6 * tone / MIX_RATE, 1.0)
			var raw := (sin(TAU * _body_phase) * 0.75 + _noise.randf_range(-1.0, 1.0) * 0.45) * _env
			_env *= decay
			_lp += bright * (raw - _lp)
			_lp2 += bright * (_lp - _lp2)
			s += _lp2 * vol * 2.2
		if horn_on:
			# scooter horn: two buzzy notes, softened by a filter
			_horn_phase_a = fmod(_horn_phase_a + 415.0 / MIX_RATE, 1.0)
			_horn_phase_b = fmod(_horn_phase_b + 520.0 / MIX_RATE, 1.0)
			var h := ((1.0 if _horn_phase_a < 0.5 else -1.0) + (1.0 if _horn_phase_b < 0.5 else -1.0)) * 0.12
			_horn_lp += 0.3 * (h - _horn_lp)
			s += _horn_lp
		buf[i] = Vector2(s, s)
	_playback.push_buffer(buf)
