class_name Fighter
extends Node3D
## A person who is in a fight with you (an angry driver, or someone you punched).
## Has health and a simple mind (mood):
##   HOSTILE  - comes at you and throws punches (with a wind-up you can see)
##   FLEEING  - runs away from you (you can chase them). More likely when hurt.
##   DOWN     - knocked down; gets up after a moment and runs off
##   RETURNING- walks back to their vehicle, which then drives off
## Combat (scenes/systems/combat.gd) owns the rules; this is the body + brain.

enum Mood { HOSTILE, FLEEING, DOWN, RETURNING }

const WALK := 2.4
const RUN := 4.6            # a bit slower than you running (5.8), so you can catch them
const PUNCH_RANGE := 1.7
const DAMAGE := 9.0
const LOSE_INTEREST := 35.0 # meters: hostile people give up if you get this far away
const FLEE_TIME := 14.0

var combat: Combat
var model: CharacterModel
var mood: Mood = Mood.HOSTILE
var hp := 100.0
var brave := 0.5            # 0..1 how likely to fight back instead of running
var home_vehicle: TrafficVehicle = null
var opponent: Fighter = null   # fighting another NPC instead of you
var display_name := "Stranger"

var _bubble: Label3D
var _bubble_time := 0.0
var _phase := 0.0
var _attack_timer := 1.0
var _windup := 0.0
var _punch_t := -1.0
var _block := 0.0
var _flinch := 0.0
var _mood_time := 0.0
var _rng := RandomNumberGenerator.new()


func build(look: Dictionary, existing: CharacterModel = null) -> void:
	_rng.randomize()
	if existing != null:
		# take over the body of the person on the street (no rebuild = no stutter)
		model = existing
		model.get_parent().remove_child(model)
		model.transform = Transform3D.IDENTITY
		add_child(model)
	else:
		model = CharacterModel.new()
		model.lod_distance = 120.0
		add_child(model)
		model.build_look(look)
	_bubble = Label3D.new()
	_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble.position.y = 2.35
	_bubble.font_size = 44
	_bubble.pixel_size = 0.007
	_bubble.outline_size = 12
	_bubble.modulate = Color("#ff8a80")
	_bubble.no_depth_test = true
	_bubble.visible = false
	add_child(_bubble)


func say(text: String, seconds: float = 3.0) -> void:
	_bubble.text = text
	_bubble.visible = true
	_bubble_time = seconds


func set_mood(m: Mood) -> void:
	mood = m
	_mood_time = 0.0
	_windup = 0.0
	_punch_t = -1.0
	if m == Mood.DOWN:   # knocked out: crumple, shoved back a little
		var back := model.global_transform.basis.z.normalized()
		model.start_ragdoll(back * 2.2 + Vector3.UP * 1.2, back * 1.8)
	else:
		if model.is_ragdoll():
			var at := model.ragdoll_ground_position()
			model.stop_ragdoll()
			global_position = Vector3(at.x, global_position.y, at.z)
		model.rotation.x = 0.0
		model.position.y = 0.0


## Angry at YOU (not busy fighting someone else).
func is_hostile() -> bool:
	return mood == Mood.HOSTILE and (opponent == null or not is_instance_valid(opponent))


func _target_position() -> Vector3:
	if opponent != null and is_instance_valid(opponent):
		return opponent.global_position
	return combat.player_position()


func is_blocking() -> bool:
	return _block > 0.0


func _physics_process(delta: float) -> void:
	if combat == null:
		return
	_mood_time += delta
	if _bubble_time > 0.0:
		_bubble_time -= delta
		_bubble.visible = _bubble_time > 0.0
	_block = maxf(0.0, _block - delta)
	_flinch = maxf(0.0, _flinch - delta)
	var target := _target_position() if mood == Mood.HOSTILE else combat.player_position()
	var to := target - global_position
	to.y = 0.0
	var dist := to.length()
	match mood:
		Mood.HOSTILE:
			_hostile(delta, target, dist)
		Mood.FLEEING:
			var away := -to.normalized() if dist > 0.01 else Vector3.FORWARD
			_move(global_position + away * 5.0, RUN, 0.0, delta)
			if _mood_time > FLEE_TIME or dist > 60.0:
				combat.remove_fighter(self)
		Mood.DOWN:
			if not model.is_ragdoll():
				model.rotation.x = lerpf(model.rotation.x, -1.45, 1.0 - exp(-10.0 * delta))
				model.position.y = lerpf(model.position.y, 0.18, 1.0 - exp(-10.0 * delta))
			if _mood_time > 2.6:
				set_mood(Mood.RETURNING if home_vehicle != null else Mood.FLEEING)
				say("Sige na, sige na! (Okay, okay!)", 2.5)
		Mood.RETURNING:
			if home_vehicle == null or not is_instance_valid(home_vehicle):
				set_mood(Mood.FLEEING)
			elif _move(home_vehicle.global_position, WALK + 0.8, 1.4, delta):
				home_vehicle.stopped_for_rage = false
				combat.remove_fighter(self)
	model.rotation.x = model.rotation.x if mood == Mood.DOWN else _flinch * 0.8


func _hostile(delta: float, target: Vector3, dist: float) -> void:
	var vs_npc := opponent != null and is_instance_valid(opponent)
	if opponent != null and not vs_npc:
		opponent = null
	if vs_npc and opponent.mood != Mood.HOSTILE:
		# the other one is down or ran: we won this one
		say(["Ayan! (Take that!)", "Kabalo ka na?! (Got it now?!)"][_rng.randi() % 2], 2.5)
		opponent = null
		set_mood(Mood.RETURNING if home_vehicle != null else Mood.FLEEING)
		return
	if not vs_npc and (dist > LOSE_INTEREST or _mood_time > 60.0):
		say("Duwag! (Coward!)", 2.5)
		set_mood(Mood.RETURNING if home_vehicle != null else Mood.FLEEING)
		return
	if not vs_npc and not combat.player_on_foot():
		# You're on the motor: they chase and shout but can't fight you
		_move(target, WALK + 0.6, 1.8, delta)
		model.pose_guard()
		return
	if dist > 1.35:
		_move(target, RUN * 0.75, 1.2, delta)
	else:
		_face(target)
	# attack: wind-up (telegraph) -> punch
	if _windup > 0.0:
		_windup -= delta
		model.pose_windup(true)
		if _windup <= 0.0:
			_punch_t = 0.0
			if dist < PUNCH_RANGE:
				if vs_npc:
					opponent.take_hit(DAMAGE * _rng.randf_range(0.8, 1.3))
				else:
					combat.damage_player(DAMAGE, self)
	elif _punch_t >= 0.0:
		_punch_t += delta / 0.3
		model.pose_punch(true, _punch_t)
		if _punch_t >= 1.0:
			_punch_t = -1.0
	else:
		if _block > 0.0:
			model.pose_block()
		else:
			model.pose_guard()
		_attack_timer -= delta
		if _attack_timer <= 0.0 and dist < 2.2:
			_windup = 0.42
			_attack_timer = _rng.randf_range(0.9, 1.7)


## You hit them. Returns the damage actually dealt.
func take_hit(dmg: float) -> float:
	if mood == Mood.DOWN:
		return 0.0
	if _block > 0.0:
		dmg *= 0.25
	hp -= dmg
	_flinch = 0.3
	_windup = 0.0
	if hp <= 0.0:
		hp = 0.0
		set_mood(Mood.DOWN)
		return dmg
	match mood:
		Mood.HOSTILE:
			if hp < 35.0 and _rng.randf() < 0.6:
				set_mood(Mood.FLEEING)
				say(["Tabang! (Help!)", "Tama na! (Enough!)", "Ayaw na! (Stop!)"][_rng.randi() % 3], 2.5)
			elif _rng.randf() < 0.25:
				_block = 0.7
		Mood.FLEEING, Mood.RETURNING:
			# cornered: sometimes they turn and fight back
			if hp > 50.0 and _rng.randf() < brave * 0.5:
				set_mood(Mood.HOSTILE)
				say("Ikaw ha! (You asked for it!)", 2.0)
	return dmg


## First hit from you while they were minding their own business: fight back or run?
func react_to_attack() -> void:
	if _rng.randf() < brave * (hp / 100.0):
		set_mood(Mood.HOSTILE)
		say(["Ano ka?! (What's your problem?!)", "Gusto mo away?! (You want a fight?!)"][_rng.randi() % 2], 2.5)
	else:
		set_mood(Mood.FLEEING)
		say(["Tabang! (Help!)", "Ay! Buang! (You're crazy!)"][_rng.randi() % 2], 2.5)


func _face(point: Vector3) -> void:
	var to := point - global_position
	if Vector2(to.x, to.z).length() > 0.05:
		rotation.y = atan2(-to.x, -to.z)


## Step toward `point`, stopping `stop_at` meters away. Returns true when there.
func _move(point: Vector3, speed: float, stop_at: float, delta: float) -> bool:
	var to := point - global_position
	to.y = 0.0
	var d := to.length()
	_face(point)
	if d <= stop_at + 0.05:
		return true
	global_position += to / d * minf(speed * delta, d - stop_at)
	_phase += delta * speed * 2.4
	model.walk(_phase, clampf(speed / 3.0, 0.4, 1.0))
	return false


## (kept for older callers)
func walk_toward(point: Vector3, speed: float, stop_at: float, delta: float) -> bool:
	return _move(point, speed, stop_at, delta)


func face(point: Vector3) -> void:
	_face(point)
