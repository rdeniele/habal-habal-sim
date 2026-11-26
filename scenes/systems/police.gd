class_name Police
extends Node3D
## Traffic enforcers standing at some busy intersections. If one SEES you break a rule
## (within ~70 m) they blow the whistle and you get a ticket - the fine comes straight out
## of your wallet, which can go negative (you'll have to work it back up).
##
## Violations:  running a red light, speeding (> limit + tolerance, near an enforcer),
##              hitting a pedestrian (reckless driving), fighting in public.
## Amounts: config/economy.gd (based on LTO JAO 2014-01 / RA 4136).
##
## Serious stuff (hitting a pedestrian, fighting in public) gives you a WANTED level (stars)
## instead: police motorbikes chase you. Lose them (stay out of their sight) and the stars
## fade. Get caught = BUSTED: jail days + bail (handled by the game).

signal ticketed(reason: String, fine: int)
signal busted(stars: int)
signal wanted_changed(stars: int)

const SIGHT := 70.0
const ENFORCER_RADIUS := 230.0
const SPEED_WATCH := 45.0
const COOLDOWN := 20.0          # same violation can't be ticketed again for this long
const REASONS := {
	"red_light": "Disregarding traffic signal (beating the red light)",
	"speeding": "Over the speed limit",
	"reckless": "Reckless driving (hit a pedestrian)",
	"fighting": "Fighting in public / alarms and scandals",
}

var world: GameWorld
var player: Player
var motor: Motorcycle
var hud: HUD
var traffic: Traffic

var enforcers := {}             # traffic-light point id -> CharacterModel holder (Node3D)
var wanted := 0                 # 0-3 stars
var units: Array[PoliceUnit] = []
var _unseen := 0.0              # seconds no police has had eyes on you
var _catch := 0.0               # seconds a unit has been right next to you while you're slow
var _cooldowns := {}
var _tick := 0.0
var _inside_signal := -1        # the traffic light intersection we're currently crossing
var _sfx: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()
var _t := 0.0


func setup(p_world: GameWorld, p_player: Player, p_motor: Motorcycle, p_hud: HUD, p_traffic: Traffic) -> void:
	world = p_world
	player = p_player
	motor = p_motor
	hud = p_hud
	traffic = p_traffic
	_rng.randomize()
	_sfx = AudioStreamPlayer.new()
	_sfx.bus = "SFX"
	add_child(_sfx)


func _physics_process(delta: float) -> void:
	if world == null or not GameState.story_done:
		return
	_t += delta
	for k: String in _cooldowns.keys():
		_cooldowns[k] = float(_cooldowns[k]) - delta
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.5
		_update_enforcers(traffic.player_pos())
	_animate_enforcers()
	if player.state == Player.State.RIDING:
		_check_red_light()
		_check_speeding()
	_update_chase(delta)


## Enforcers stand at every third traffic-light intersection near you.
func _update_enforcers(center: Vector3) -> void:
	var g := world.road_graph
	var near := {}
	for id in g.point_ids_near(center, ENFORCER_RADIUS):
		if id % 3 == 0 and traffic.is_signal(id):
			near[id] = true
			if not enforcers.has(id):
				enforcers[id] = _spawn_enforcer(id)
	for id: int in enforcers.keys():
		if not near.has(id):
			(enforcers[id] as Node3D).queue_free()
			enforcers.erase(id)


func _spawn_enforcer(id: int) -> Node3D:
	var g := world.road_graph
	var p := g.get_point(id)
	var nb := g.neighbors(id)
	var d := (p - g.get_point(nb[0])).normalized()
	var right := Vector3(-d.z, 0, d.x)
	var w := g.road_width(id, nb[0])
	var holder := Node3D.new()
	add_child(holder)
	holder.global_position = p - right * (w * 0.5 + 1.8) - d * (w * 0.5 + 1.5)
	holder.rotation.y = atan2(-right.x, -right.z)   # facing the road
	var female := _rng.randf() < 0.3
	var m := CharacterModel.make_look("enforcer_%s" % female, {
		"body": "female" if female else "male", "skin": Color("#b97d4f"),
		"hair": "short", "hair_color": Color("#1a1410"),
		"top": "polo", "top_color": Color("#9cc3e6"), "bottom": "pants", "bottom_color": Color("#1d3557"),
		"helmet": Color("#1d3557"),   # uniform cap
	}, 150.0)
	holder.add_child(m)
	LowPoly.box(holder, Vector3(0.44, 0.34, 0.33), Color("#d4ff3a"), Vector3(0, 1.28, 0))   # reflective vest
	LowPoly.label(holder, "Traffic Enforcer", Vector3(0, 2.35, 0), 0.28)
	holder.set_meta("model", m)
	return holder


## Enforcers wave traffic along with one arm.
func _animate_enforcers() -> void:
	for id: int in enforcers:
		var m: CharacterModel = (enforcers[id] as Node3D).get_meta("model")
		m.arm_r.rotation = Vector3(0, 0, 1.4 + sin(_t * 3.0 + id) * 0.5)


## Did we just enter a traffic-light intersection while our light was red?
func _check_red_light() -> void:
	var here := motor.global_position
	var current := -1
	for id in world.road_graph.point_ids_near(here, 6.0):
		if traffic.is_signal(id):
			current = id
			break
	if current != -1 and current != _inside_signal and absf(motor.speed) > 2.0:
		# which road did we come in on? the neighbor behind us
		var g := world.road_graph
		var fwd := motor.get_forward()
		var best := -1
		var best_dot := -2.0
		for n in g.neighbors(current):
			var dot := (g.get_point(current) - g.get_point(n)).normalized().dot(fwd)
			if dot > best_dot:
				best_dot = dot
				best = n
		if best != -1 and traffic.light_state(current, best) == 2:
			violation("red_light", here)
	_inside_signal = current


func _check_speeding() -> void:
	if motor.get_speed_kmh() < Economy.SPEED_LIMIT_KMH + Economy.SPEED_TOLERANCE_KMH:
		return
	if _nearest_enforcer(motor.global_position, SPEED_WATCH) != null:
		violation("speeding", motor.global_position)


func _nearest_enforcer(pos: Vector3, radius: float) -> Node3D:
	var best: Node3D = null
	var best_d := radius
	for id: int in enforcers:
		var e: Node3D = enforcers[id]
		var d := e.global_position.distance_to(pos)
		if d < best_d:
			best_d = d
			best = e
	return best


## A rule was broken at `pos`. If an enforcer (or police) saw it: ticket, or wanted stars.
func violation(reason: String, pos: Vector3) -> void:
	if float(_cooldowns.get(reason, 0.0)) > 0.0:
		return
	var e := _nearest_enforcer(pos, SIGHT)
	var police_saw := _nearest_unit(pos, 60.0) != null
	if e == null and not police_saw:
		return   # nobody saw it...
	if reason == "reckless" or reason == "fighting":
		_cooldowns[reason] = 6.0
		_whistle()
		add_wanted(2 if reason == "reckless" else 1, reason)
		return
	if e == null:
		return
	_cooldowns[reason] = COOLDOWN
	var fine := _fine_for(reason)
	GameState.add_money(-fine)   # can go below zero: that's debt you work off
	GameState.today["fines"] = int(GameState.today.get("fines", 0)) + fine
	GameState.tickets += 1
	_whistle()
	var holder := e
	holder.look_at(Vector3(pos.x, holder.global_position.y, pos.z), Vector3.UP)
	hud.show_toast("PRRT! TICKET from a traffic enforcer\n%s: -%s%s" % [REASONS[reason], Economy.format_peso(fine),
		"\nYour wallet is negative: keep working to pay it off!" if GameState.money < 0 else ""], 4.5)
	ticketed.emit(reason, fine)


func _whistle() -> void:
	_sfx.stream = Sfx.whistle()
	_sfx.play()


# --- Wanted level & police chase ----------------------------------------------------

func add_wanted(stars: int, reason: String) -> void:
	var before := wanted
	wanted = mini(3, maxi(wanted + 1, stars) if wanted > 0 else stars)
	_unseen = 0.0
	if wanted != before:
		wanted_changed.emit(wanted)
		hud.show_toast("WANTED %s  -  %s!
Police are coming. Lose them, or you'll be jailed." % [
			"★".repeat(wanted), REASONS.get(reason, reason)], 4.0)


func clear_wanted() -> void:
	wanted = 0
	_unseen = 0.0
	_catch = 0.0
	for u in units:
		if is_instance_valid(u):
			u.queue_free()
	units.clear()
	wanted_changed.emit(0)


func _nearest_unit(pos: Vector3, radius: float) -> PoliceUnit:
	var best: PoliceUnit = null
	var best_d := radius
	for u in units:
		if is_instance_valid(u):
			var d := u.global_position.distance_to(pos)
			if d < best_d:
				best_d = d
				best = u
	return best


func _update_chase(delta: float) -> void:
	if wanted <= 0:
		return
	var me := traffic.player_pos()
	# one unit per star, coming from 120-200 m away on the roads
	units = units.filter(func(u: PoliceUnit) -> bool: return is_instance_valid(u))
	while units.size() < wanted:
		var u := _spawn_unit(me)
		if u == null:
			break
		units.append(u)
	# out of sight long enough -> lost them
	var nearest := _nearest_unit(me, 70.0)
	if nearest == null:
		_unseen += delta
		if _unseen > 12.0 + 6.0 * wanted:
			hud.show_toast("Nawala ka na sa pulis! (You lost the police.)", 3.0)
			clear_wanted()
			return
	else:
		_unseen = 0.0
	# caught: a unit right next to you while you're slow / stopped / on foot
	var my_speed := absf(motor.speed) if player.state == Player.State.RIDING else Vector2(player.velocity.x, player.velocity.z).length()
	var close := _nearest_unit(me, 4.0)
	if close != null and my_speed < 4.0:
		_catch += delta
		if _catch > 1.5:
			var stars := wanted
			clear_wanted()
			busted.emit(stars)
	else:
		_catch = maxf(0.0, _catch - delta)


func _spawn_unit(me: Vector3) -> PoliceUnit:
	var g := world.road_graph
	var ids := g.point_ids_near(me, 200.0)
	for attempt in 10:
		if ids.is_empty():
			return null
		var p := g.get_point(ids[_rng.randi() % ids.size()])
		if p.distance_to(Vector3(me.x, 0, me.z)) < 120.0:
			continue
		var u := PoliceUnit.new()
		add_child(u)
		u.global_position = p
		u.setup(g, func() -> Vector3: return traffic.player_pos())
		return u
	return null


func _fine_for(reason: String) -> int:
	match reason:
		"red_light":
			return Economy.FINE_RED_LIGHT
		"speeding":
			return Economy.FINE_SPEEDING
		"fighting":
			return Economy.FINE_FIGHTING
		"reckless":
			var fines: Array = Economy.FINE_RECKLESS
			var f: int = fines[mini(GameState.reckless_count, fines.size() - 1)]
			GameState.reckless_count += 1
			return f
	return 0
