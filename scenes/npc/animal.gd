class_name Animal
extends Node3D
signal ran_off          # finished tumbling and running after a crash
## A street dog (aspin) or cat. Hangs around its stretch of sidewalk: walks, stands, sits,
## lies down, barks or meows now and then, and darts out of the way when you ride close or
## honk. They always get away: no collision, nobody hurts them.
## You can creep up and pick one up (see scenes/systems/pet_care.gd); adopted ones are `pet`s.
## Model parts come from tools/blender/make_animals.py and are moved here (no skeleton).

enum Mood { IDLE, WALK, SIT, LIE, FLEE }

const MODELS := {"dog": "res://assets/animals/dog.glb", "cat": "res://assets/animals/cat.glb"}
## [coat, patch, muzzle]
const COATS := {
	"dog": [["#c08a52", "#e9dcc4", "#e3cfae"], ["#2d2826", "#d8cfc2", "#8a6a4c"], ["#e8dfcd", "#b98a58", "#f2ead9"],
		["#7a5234", "#d9c4a2", "#c7a77e"], ["#8f8a84", "#e6e1da", "#d2ccc4"]],
	"cat": [["#d38a3e", "#f1e2c8", "#f1e2c8"], ["#77706a", "#3f3a36", "#e6e1da"], ["#262322", "#f1ede4", "#f1ede4"],
		["#efeae0", "#d38a3e", "#f5f1e8"]],
}

var kind := "dog"
var look_seed := 0              # same seed = same coat (saved for pets)
var pet := false                # yours: waits at home, never runs from you
var held := ""                 # "" free, "arms", "board" or "lap"
var _happy := 0.0               # being petted
var _vel := Vector3.ZERO        # tumbling after a crash
var _ground := 0.0
var _landed := false
var _down_left := 0.0
var _run_left := 0.0
var mood: Mood = Mood.IDLE
var a := Vector3.ZERO          # the stretch of sidewalk it lives on
var b := Vector3.ZERO
var _along := 0.0              # meters from a toward b
var _goal := 0.0
var _mood_left := 2.0
var _voice_left := 8.0
var _phase := 0.0
var _body: Node3D
var _head: Node3D
var _tail: Node3D
var _legs: Array[Node3D] = []  # FL, FR, BL, BR
var _rest: Dictionary = {}     # node -> rest position
var _audio: AudioStreamPlayer3D
var _rng := RandomNumberGenerator.new()
static var _materials: Dictionary = {}


func setup(p_kind: String, p_a: Vector3, p_b: Vector3, seed_value: int) -> void:
	kind = p_kind
	a = p_a
	b = p_b
	_rng.seed = seed_value
	look_seed = seed_value
	var model := (load(MODELS[kind]) as PackedScene).instantiate() as Node3D
	add_child(model)
	_body = model.find_child("Body", true, false) as Node3D
	_head = model.find_child("Head", true, false) as Node3D
	_tail = model.find_child("Tail", true, false) as Node3D
	for n: String in ["LegFL", "LegFR", "LegBL", "LegBR"]:
		_legs.append(model.find_child(n, true, false) as Node3D)
	for n: Node3D in [_body, _head, _tail] + _legs:
		_rest[n] = n.position
	var coats: Array = COATS[kind]
	var coat: Array = coats[_rng.randi() % coats.size()]
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mi.visibility_range_end = 90.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i)
			var k := ["Coat", "Patch", "Muzzle"].find(m.resource_name) if m != null else -1
			if k >= 0:
				mi.set_surface_override_material(i, _coat_material(str(coat[k])))
	scale = Vector3.ONE * _rng.randf_range(0.9, 1.08)
	_audio = AudioStreamPlayer3D.new()
	_audio.bus = "SFX"
	_audio.unit_size = 5.0
	_audio.max_distance = 45.0
	add_child(_audio)
	_along = _rng.randf() * a.distance_to(b)
	_goal = _along
	global_position = _spot()
	rotation.y = _rng.randf() * TAU
	_phase = _rng.randf() * TAU
	_voice_left = _rng.randf_range(4.0, 30.0)


static func _coat_material(hex: String) -> StandardMaterial3D:
	if not _materials.has(hex):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(hex)
		m.roughness = 0.9
		_materials[hex] = m
	return _materials[hex]


func _spot() -> Vector3:
	return a + (b - a).normalized() * _along


## Something scary at `from` (your motor, a horn): run the other way along the sidewalk.
func scare(from: Vector3) -> void:
	if pet or held != "":
		return
	var length := a.distance_to(b)
	var dir := (b - a) / maxf(length, 0.01)
	var side := 1.0 if (global_position - from).dot(dir) >= 0.0 else -1.0
	_goal = clampf(_along + side * _rng.randf_range(5.0, 9.0), 0.0, length)
	if absf(_goal - _along) < 1.0:   # cornered at the end: dash back the other way
		_goal = clampf(_along - side * 8.0, 0.0, length)
	if mood != Mood.FLEE and _rng.randf() < 0.7:
		speak()
	mood = Mood.FLEE
	_mood_left = 4.0


## You're creeping up slowly: it stops and sits to look at you.
func calm() -> void:
	if pet or held != "" or mood == Mood.FLEE or mood == Mood.LIE:
		return
	mood = Mood.SIT
	_goal = _along
	_mood_left = maxf(_mood_left, 3.0)


## Live here from now on (a stretch of sidewalk, or one spot when p_a == p_b).
func settle(p_a: Vector3, p_b: Vector3, yaw: float) -> void:
	held = ""
	a = p_a
	b = p_b
	_along = 0.0
	_goal = 0.0
	rotation = Vector3(0, yaw, 0)
	global_position = a
	mood = Mood.SIT
	_mood_left = _rng.randf_range(3.0, 8.0)
	reset_physics_interpolation()


## Carried or riding: stick to `parent` at `local` (call every frame).
func hold_in(parent: Node3D, local: Transform3D, how: String) -> void:
	held = how
	var moved := get_parent() != parent
	if moved:
		reparent(parent, false)
	transform = Transform3D(local.basis.scaled(Vector3.ONE * scale.x), local.origin)
	if moved:
		reset_physics_interpolation()
	mood = Mood.SIT if how == "board" else Mood.LIE


## Thrown off in a crash: flies, flops with loose legs, gets up and bolts. Never hurt.
## Emits `ran_off` when it's gone far enough. Must already be a child of a world-space node.
func tumble(launch: Vector3, ground: float) -> void:
	held = "tumble"
	_vel = launch
	_ground = ground
	_landed = false
	_down_left = 1.0
	_run_left = 2.2
	rotation = Vector3(0, rotation.y, 0)
	reset_physics_interpolation()
	speak()


func _tumble_step(delta: float) -> void:
	if not _landed:
		_vel.y -= 14.0 * delta
		global_position += _vel * delta
		rotation.x += 9.0 * delta
		rotation.z += 6.0 * delta
		_flail(delta, 1.3)
		if global_position.y <= _ground:
			global_position.y = _ground
			if _vel.y < -2.5:       # bounce once
				_vel = Vector3(_vel.x * 0.5, -_vel.y * 0.35, _vel.z * 0.5)
			else:
				_vel.y = 0.0
				_landed = true
	elif _down_left > 0.0:
		_down_left -= delta
		rotation.x = 0.0
		rotation.z = PI * 0.5       # flat on its side
		global_position.y = _ground + (0.08 if kind == "cat" else 0.12)
		_flail(delta, 0.25)
	else:
		var away := Vector3(_vel.x, 0, _vel.z)
		away = away.normalized() if away.length() > 0.1 else -global_basis.z.normalized()
		rotation = Vector3(0, atan2(-away.x, -away.z), 0)
		global_position.y = _ground
		global_position += away * 5.0 * delta
		mood = Mood.FLEE
		_animate(delta, 5.0)
		_run_left -= delta
		if _run_left <= 0.0:
			held = ""
			ran_off.emit()


## Legs, head and tail flapping about.
func _flail(delta: float, amount: float) -> void:
	_phase += delta * 17.0
	for i in 4:
		_legs[i].rotation.x = sin(_phase + i * 1.9) * amount
	_head.rotation.x = sin(_phase * 0.7) * amount * 0.5
	_tail.rotation.y = sin(_phase * 1.3) * amount


## A caress: head up, tail going, a purr or a pant, and a little heart.
func caress() -> void:
	_happy = 1.8
	if not _audio.playing:
		_audio.stream = NatureSfx.purr() if kind == "cat" else NatureSfx.pant()
		_audio.volume_db = -6.0
		_audio.pitch_scale = 1.0
		_audio.play()
	var heart := Label3D.new()
	heart.text = "\u2665"
	heart.modulate = Color("#ff5d7a")
	heart.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	heart.pixel_size = 0.0016 if held == "" else 0.0007   # smaller up close
	heart.font_size = 96
	heart.position = Vector3(0, 0.55 if kind == "cat" else 0.8, 0)
	add_child(heart)
	var t := heart.create_tween()
	t.tween_property(heart, "position:y", heart.position.y + 0.3, 0.9)
	t.tween_callback(heart.queue_free)


func speak() -> void:
	if _audio.playing:
		return
	_audio.stream = NatureSfx.dog(_rng.randi() % 4) if kind == "dog" else NatureSfx.meow(_rng.randi() % 4)
	_audio.volume_db = -4.0
	_audio.pitch_scale = _rng.randf_range(0.92, 1.12)
	_audio.play()


func _physics_process(delta: float) -> void:
	_happy = maxf(0.0, _happy - delta)
	if held == "tumble":
		_tumble_step(delta)
		return
	if held != "":
		_animate(delta, 0.0)
		return
	_mood_left -= delta
	_voice_left -= delta
	if _voice_left <= 0.0:
		_voice_left = _rng.randf_range(12.0, 45.0)
		if mood != Mood.LIE:
			speak()
	if _mood_left <= 0.0 and (mood != Mood.FLEE or absf(_goal - _along) < 0.1):
		_pick_mood()
	var speed := 0.0
	if (mood == Mood.WALK or mood == Mood.FLEE) and absf(_goal - _along) > 0.05:
		speed = (4.5 if kind == "dog" else 5.0) if mood == Mood.FLEE else (0.8 if kind == "dog" else 0.55)
		var way := signf(_goal - _along)
		_along = move_toward(_along, _goal, speed * delta)
		var dir := (b - a).normalized() * way
		rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), 1.0 - exp(-10.0 * delta))
	elif mood == Mood.WALK or mood == Mood.FLEE:
		mood = Mood.IDLE
		_mood_left = _rng.randf_range(1.0, 3.0)
	global_position = _spot()
	_animate(delta, speed)


func _pick_mood() -> void:
	var r := _rng.randf()
	if r < 0.4:
		mood = Mood.WALK
		_goal = clampf(_along + _rng.randf_range(-7.0, 7.0), 0.0, a.distance_to(b))
		_mood_left = 12.0
	elif r < 0.65:
		mood = Mood.IDLE
		_mood_left = _rng.randf_range(2.0, 6.0)
	elif r < 0.85:
		mood = Mood.SIT
		_mood_left = _rng.randf_range(5.0, 14.0)
	else:
		mood = Mood.LIE
		_mood_left = _rng.randf_range(8.0, 25.0)


## Legs swing when moving; sitting tips the body back; lying sinks to the ground.
func _animate(delta: float, speed: float) -> void:
	var k := 1.0 - exp(-9.0 * delta)
	_phase += delta * (3.0 + speed * (4.5 if kind == "dog" else 6.0))
	var h: float = (_rest[_legs[2]] as Vector3).y   # hip height
	var body_tilt := 0.0
	var drop := 0.0
	var rear_drop := 0.0
	var legs := [0.0, 0.0, 0.0, 0.0]
	var tail := sin(_phase * 0.6) * (0.25 if kind == "dog" else 0.15)
	var head_pitch := sin(_phase * 0.23) * 0.1
	if _happy > 0.0:
		tail = sin(_happy * (14.0 if kind == "dog" else 5.0)) * (0.6 if kind == "dog" else 0.3)
		head_pitch = 0.22 + sin(_happy * 6.0) * 0.06
	match mood:
		Mood.WALK, Mood.FLEE:
			if speed > 0.0:
				var swing := 0.75 if mood == Mood.FLEE else 0.45
				var gallop := mood == Mood.FLEE
				for i in 4:
					# walk: diagonal pairs; run: front pair then back pair
					var offset := (0.0 if i < 2 else PI) if gallop else (0.0 if i == 0 or i == 3 else PI)
					legs[i] = sin(_phase + offset) * swing
				drop = -absf(cos(_phase)) * (0.04 if gallop else 0.012) * h * 2.0
		Mood.SIT:
			body_tilt = 0.55
			rear_drop = h * 0.62
			legs = [0.0, 0.0, 1.25, 1.25]
		Mood.LIE:
			drop = h * 0.68
			legs = [1.45, 1.45, 1.5, 1.5]
			head_pitch = head_pitch if _happy > 0.0 else -0.1
	# Godot: forward is -Z, so tipping back to sit = rotate about X
	var pivot_z: float = (_rest[_legs[0]] as Vector3).z   # the front legs stay on the ground
	var tip := Basis(Vector3.RIGHT, body_tilt)
	for n: Node3D in [_body, _head, _tail] + _legs:
		var rest: Vector3 = _rest[n]
		var pos := rest + Vector3(0, -drop, 0)
		if body_tilt != 0.0:
			var from := rest - Vector3(0, h, pivot_z)
			pos = tip * from + Vector3(0, h, pivot_z)
			if n == _legs[0] or n == _legs[1]:
				pos = rest
			elif n == _legs[2] or n == _legs[3]:
				pos = Vector3(rest.x, h - rear_drop, rest.z)
		n.position = n.position.lerp(pos, k)
	var targets := {_body: body_tilt, _tail: -0.5 if mood == Mood.LIE or mood == Mood.SIT else 0.0,
		_head: head_pitch, _legs[0]: legs[0], _legs[1]: legs[1], _legs[2]: legs[2], _legs[3]: legs[3]}
	for n: Node3D in targets:
		n.rotation.x = lerpf(n.rotation.x, targets[n], k)
	_tail.rotation.y = tail
