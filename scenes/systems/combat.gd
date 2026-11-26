class_name Combat
extends Node
## Open-world fist fighting (in the style of early-2000s open-world games).
##
## On foot, anytime:  Left mouse / J = punch (alternating, up to a 3-hit combo)
##                    Right mouse / K (hold) = block      L = dodge back
## Punch...
##   - a person on the street: they fight back or run away (more likely to run when hurt);
##     you can chase them down.
##   - a vehicle: the driver may get out angry (road rage) or just honk.
## Bumping a vehicle with your motor (or cutting one off) can also make the driver come out.
## Knock someone down: +1 Respect. Get knocked out yourself: you wake up at the clinic.
## Enforcers who see you fighting will fine you (see police.gd).

signal fight_lost
signal assault(where: Vector3)   # you hit a person (for traffic enforcers / police)

const PUNCH_RANGE := 1.8
const COMBO_DAMAGE := [0.0, 8.0, 10.0, 16.0]
const BUMP_RAGE_CHANCE := 0.55
const CUT_OFF_RAGE_CHANCE := 0.2
const CAR_PUNCH_RAGE_CHANCE := 0.7
const STANCE_TIME := 3.0          # stay in fighting stance this long after punching
const BYSTANDER_RADIUS := 15.0    # people this close see the fight
const JOIN_CHANCE := 0.2          # ...and might jump in (max 2 at a time)
const FLEE_CHANCE := 0.75         # ...or run away
const DRIVER_LINES := ["Hoy! Wala ka mata?! (Hey! Are you blind?!)", "Ano problema mo, ha?! (What's your problem?!)",
	"Gusto mo away?! (You want a fight?!)", "Bayaran mo na! (You'll pay for that!)", "Panaog dira! (Get down here!)"]

var game: Node
var player: Player
var motor: Motorcycle
var hud: HUD
var booking: BookingSystem
var traffic: Traffic
var pedestrians: Pedestrians
var fighters: Array[Fighter] = []
var focus: Fighter = null         # whose health bar is shown

var _rng := RandomNumberGenerator.new()
var _combo := 0
var _combo_window := 0.0
var _punch_t := -1.0
var _punch_right := true
var _hit_pending := false
var _dodge := 0.0
var _flinch := 0.0
var _stance := 0.0
var _focus_time := 0.0
var _rage_cooldown := 0.0
var _fight_noted := false
var _calm_time := 0.0
var _lost := false
var _alert_cooldown := 0.0
var _sfx: AudioStreamPlayer


func setup(p_game: Node, p_player: Player, p_motor: Motorcycle, p_hud: HUD, p_booking: BookingSystem,
		p_traffic: Traffic, p_pedestrians: Pedestrians) -> void:
	game = p_game
	player = p_player
	motor = p_motor
	hud = p_hud
	booking = p_booking
	traffic = p_traffic
	pedestrians = p_pedestrians
	_rng.randomize()
	_sfx = AudioStreamPlayer.new()
	_sfx.bus = "SFX"
	add_child(_sfx)


func player_position() -> Vector3:
	return motor.global_position if player.state == Player.State.RIDING else player.global_position


func player_on_foot() -> bool:
	return player.state == Player.State.ON_FOOT


func has_hostile() -> bool:
	for f in fighters:
		if is_instance_valid(f) and f.is_hostile():
			return true
	return false


func is_in_combat() -> bool:
	return _stance > 0.0 or has_hostile()


# --- Input ---------------------------------------------------------------------

func _can_fight() -> bool:
	return player_on_foot() and player.input_enabled and not hud.is_menu_open() \
		and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if not _can_fight():
		return
	if event.is_action_pressed("punch"):
		get_viewport().set_input_as_handled()
		player_punch()
	elif event.is_action_pressed("dodge"):
		get_viewport().set_input_as_handled()
		player_dodge()


func player_punch() -> void:
	if _punch_t >= 0.0 or _dodge > 0.0 or not player_on_foot():
		return
	_combo = mini(_combo + 1, 3) if _combo_window > 0.0 else 1
	_combo_window = 0.75
	_punch_t = 0.0
	_punch_right = not _punch_right
	_hit_pending = true
	_stance = STANCE_TIME


func player_dodge() -> void:
	if _dodge > 0.0:
		return
	_dodge = 0.45
	var back := Vector3(sin(player.get_facing_yaw()), 0, cos(player.get_facing_yaw()))
	player.velocity += back * 7.0
	_stance = STANCE_TIME


# --- Every frame -----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if player == null:
		return
	_rage_cooldown = maxf(0.0, _rage_cooldown - delta)
	_combo_window = maxf(0.0, _combo_window - delta)
	_dodge = maxf(0.0, _dodge - delta)
	_stance = maxf(0.0, _stance - delta)
	_focus_time = maxf(0.0, _focus_time - delta)
	_alert_cooldown = maxf(0.0, _alert_cooldown - delta)
	for f in fighters.duplicate():
		if not is_instance_valid(f):
			fighters.erase(f)

	# Fighting stance while someone angry is close (no lock-on: you aim with the camera)
	var nearest := _nearest_hostile(8.0)
	if nearest != null:
		_stance = maxf(_stance, 0.5)
		_calm_time = 0.0
	else:
		_calm_time += delta
		if _calm_time > 10.0:
			_fight_noted = false

	if player_on_foot():
		_update_punch(delta)
		if _stance > 0.0:
			_pose_player(delta)

	# Health bars
	if focus != null and is_instance_valid(focus) and (focus.is_hostile() or _focus_time > 0.0):
		hud.show_fight(player.health / Player.MAX_HEALTH, focus.hp / 100.0)
	else:
		hud.hide_fight()

	player.in_combat = is_in_combat()   # no health regen mid-fight


func _update_punch(delta: float) -> void:
	if _punch_t < 0.0:
		return
	_punch_t += delta / 0.32
	if _hit_pending and _punch_t >= 0.45:
		_hit_pending = false
		_resolve_hit()
	if _punch_t >= 1.0:
		_punch_t = -1.0


func _pose_player(delta: float) -> void:
	var pm := player.get_model()
	var blocking := Input.is_action_pressed("block") and _punch_t < 0.0
	if _punch_t >= 0.0:
		pm.pose_punch(_punch_right, _punch_t)
	elif blocking:
		pm.pose_block()
	else:
		pm.pose_guard()
	_flinch = maxf(0.0, _flinch - delta)
	pm.rotation.x = _flinch * 0.8


## What did that punch hit? A fighter, a person on the street, or a vehicle.
func _resolve_hit() -> void:
	var me := player.global_position
	var fwd := Vector3(-sin(player.get_facing_yaw()), 0, -cos(player.get_facing_yaw()))
	var dmg: float = COMBO_DAMAGE[_combo]
	# 1) someone already fighting / fleeing
	var best: Fighter = null
	var best_d := PUNCH_RANGE
	for f in fighters:
		if not is_instance_valid(f) or f.mood == Fighter.Mood.DOWN:
			continue
		var to := f.global_position - me
		to.y = 0.0
		if to.length() < best_d and to.normalized().dot(fwd) > 0.3:
			best_d = to.length()
			best = f
	if best != null:
		_hit_fighter(best, dmg)
		return
	# 2) a person walking by
	if pedestrians != null:
		for p in pedestrians.people:
			if not is_instance_valid(p):
				continue
			var to := p.global_position - me
			to.y = 0.0
			if to.length() < PUNCH_RANGE and to.normalized().dot(fwd) > 0.3:
				var f := _convert_pedestrian(p)
				_hit_fighter(f, dmg)
				f.react_to_attack()
				return
	# 3) a vehicle
	if traffic != null:
		for v in traffic.vehicles:
			if is_instance_valid(v) and _near_vehicle(v, me, 1.0):
				_play_hit(true)
				car_punched(v)
				return


func _hit_fighter(f: Fighter, dmg: float) -> void:
	f.opponent = null   # you hit them: now they're angry at you
	var dealt := f.take_hit(dmg)
	focus = f
	_focus_time = 4.0
	_play_hit(dealt < dmg * 0.5)
	_note_fight()
	assault.emit(f.global_position)
	_alert_bystanders(f.global_position)
	if f.mood == Fighter.Mood.DOWN and f.hp <= 0.0:
		GameState.respect += 1
		hud.show_toast("Panalo ka! Knocked them down.  +1 Respect (%d)" % GameState.respect, 3.0)
		player.get_model().pose_victory()


## They hit you.
func damage_player(dmg: float, from: Fighter) -> void:
	if _dodge > 0.0 or not player_on_foot():
		return
	var blocking := Input.is_action_pressed("block") and _punch_t < 0.0
	player.health = maxf(0.0, player.health - dmg * (0.2 if blocking else 1.0))
	if player.health <= 0.0 and not _lost:
		_lost = true
		fight_lost.emit()
		return
	_flinch = 0.0 if blocking else 0.3
	focus = from
	_focus_time = 4.0
	_stance = STANCE_TIME
	_play_hit(blocking)
	_note_fight()
	_alert_bystanders(player.global_position)


## People who see a fight: a few jump in against you, most run away, some don't care.
func _alert_bystanders(where: Vector3) -> void:
	if _alert_cooldown > 0.0 or pedestrians == null:
		return
	_alert_cooldown = 2.0
	var joined := 0
	for p in pedestrians.people.duplicate():
		if not is_instance_valid(p) or p.knocked > 0.0:
			continue
		if p.global_position.distance_to(where) > BYSTANDER_RADIUS:
			continue
		var roll := _rng.randf()
		if roll < JOIN_CHANCE and joined < 2:
			joined += 1
			var f := _convert_pedestrian(p)
			f.brave = 0.9
			f.set_mood(Fighter.Mood.HOSTILE)
			f.say(["Hoy! Ngaa ginabakol mo siya?! (Why are you hitting them?!)", "Bulig ta! (Let's help!)",
				"Tama na ina! (Stop that!)"][_rng.randi() % 3], 3.0)
		elif roll < JOIN_CHANCE + FLEE_CHANCE:
			var f := _convert_pedestrian(p)
			f.set_mood(Fighter.Mood.FLEEING)
			if _rng.randf() < 0.5:
				f.say(["Tabang! (Help!)", "Dalagan! (Run!)", "Ay, may away! (A fight!)"][_rng.randi() % 3], 2.0)


## A fight just started near your motor: a passenger on board gets scared and leaves.
func _note_fight() -> void:
	if not _fight_noted:
		_fight_noted = true
		booking.on_fight_started()


# --- Vehicles & road rage ----------------------------------------------------------

func on_vehicle_hit(v: TrafficVehicle) -> void:
	if _rng.randf() < BUMP_RAGE_CHANCE:
		start_road_rage(v)
	elif is_instance_valid(v):
		v.honk()


func on_cut_off(v: TrafficVehicle) -> void:
	if _rng.randf() < CUT_OFF_RAGE_CHANCE:
		start_road_rage(v)
	elif is_instance_valid(v):
		v.honk()


func car_punched(v: TrafficVehicle) -> void:
	if v.stopped_for_rage:
		return
	if _rng.randf() < CAR_PUNCH_RAGE_CHANCE:
		start_road_rage(v, true)
	else:
		v.honk()


## Two NPC drivers crashed: sometimes they get out and fight each other.
func start_npc_road_rage(a: TrafficVehicle, b: TrafficVehicle) -> void:
	if not is_instance_valid(a) or not is_instance_valid(b) or a.stopped_for_rage or b.stopped_for_rage:
		return
	if fighters.size() > 6:
		return
	var fa := _driver_out(a)
	var fb := _driver_out(b)
	fa.opponent = fb
	fb.opponent = fa
	fa.say(DRIVER_LINES[_rng.randi() % DRIVER_LINES.size()], 3.5)
	fb.say(["Ikaw ang wala mata! (YOU are the blind one!)", "Ano?! Away ta?! (What?! Want to fight?!)"][_rng.randi() % 2], 3.5)


## Two people on the street start fighting each other.
func start_street_fight(p1: Pedestrian, p2: Pedestrian) -> void:
	if fighters.size() > 6:
		return
	var f1 := _convert_pedestrian(p1)
	var f2 := _convert_pedestrian(p2)
	f1.opponent = f2
	f2.opponent = f1
	f1.set_mood(Fighter.Mood.HOSTILE)
	f2.set_mood(Fighter.Mood.HOSTILE)
	f1.say(["Ano imo ginatan-aw?! (What are you looking at?!)", "Utang mo! (Pay your debt!)"][_rng.randi() % 2], 3.0)
	f2.say(["Gusto mo away?! (You want a fight?!)", "Halika! (Come on!)"][_rng.randi() % 2], 3.0)


func _driver_out(v: TrafficVehicle) -> Fighter:
	v.stopped_for_rage = true
	var f := _spawn_fighter(CharacterModel.random_look(_rng, _rng.randf() < 0.2, "worker"))
	var side := Vector3(-v.forward().z, 0, v.forward().x)
	f.global_position = v.global_position - side * 1.6
	f.home_vehicle = v
	f.brave = 0.8
	f.set_mood(Fighter.Mood.HOSTILE)
	return f


## The driver stops and gets out angry.
func start_road_rage(v: TrafficVehicle, force: bool = false) -> void:
	if not is_instance_valid(v) or v.stopped_for_rage or not GameState.story_done:
		return
	if _rage_cooldown > 0.0 and not force:
		return
	_rage_cooldown = 20.0
	v.stopped_for_rage = true
	v.honk()
	var f := _spawn_fighter(CharacterModel.random_look(_rng, _rng.randf() < 0.2, "worker"))
	var side := Vector3(-v.forward().z, 0, v.forward().x)
	f.global_position = v.global_position - side * 1.6
	f.home_vehicle = v
	f.brave = 0.8
	f.display_name = "Driver"
	f.set_mood(Fighter.Mood.HOSTILE)
	f.say(DRIVER_LINES[_rng.randi() % DRIVER_LINES.size()], 4.0)
	focus = f
	# Just a heads-up: you decide whether to ride off or get off and fight.
	hud.show_toast("Galit ang driver! (The driver wants a fight)", 3.0)


## Rough distance check from a point to a vehicle's box.
func _near_vehicle(v: TrafficVehicle, p: Vector3, max_d: float) -> bool:
	var local := v.to_local(p)
	var dx := maxf(absf(local.x) - v.box.x * 0.5, 0.0)
	var dz := maxf(absf(local.z) - v.box.z * 0.5, 0.0)
	return Vector2(dx, dz).length() < max_d


# --- Fighters ---------------------------------------------------------------------

func _spawn_fighter(look: Dictionary, existing: CharacterModel = null) -> Fighter:
	var f := Fighter.new()
	game.add_child(f)
	f.build(look, existing)
	f.combat = self
	f.brave = _rng.randf_range(0.2, 0.85)
	fighters.append(f)
	return f


## A person on the sidewalk becomes a fighter (same look, same spot).
func _convert_pedestrian(p: Pedestrian) -> Fighter:
	var f := _spawn_fighter(p.model.get_look(), p.model)
	f.global_transform = p.global_transform
	pedestrians.people.erase(p)
	p.queue_free()
	return f


func remove_fighter(f: Fighter) -> void:
	fighters.erase(f)
	if f == focus:
		focus = null
	if is_instance_valid(f.home_vehicle):
		f.home_vehicle.stopped_for_rage = false
	f.queue_free()


func _nearest_hostile(radius: float) -> Fighter:
	var best: Fighter = null
	var best_d := radius
	for f in fighters:
		if is_instance_valid(f) and f.is_hostile():
			var d := f.global_position.distance_to(player.global_position)
			if d < best_d:
				best_d = d
				best = f
	return best


## Stop all fights right away (end of day, clinic, respawn...).
func cancel() -> void:
	for f in fighters.duplicate():
		if is_instance_valid(f):
			remove_fighter(f)
	fighters.clear()
	focus = null
	_lost = false
	_stance = 0.0
	_punch_t = -1.0
	player.fight_target = null
	hud.hide_fight()


func _play_hit(blocked: bool) -> void:
	_sfx.stream = Sfx.tones([140.0, 90.0], 0.05, 0.5) if not blocked else Sfx.tones([260.0], 0.05, 0.3)
	_sfx.play()
