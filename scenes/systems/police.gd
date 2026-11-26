class_name Police
extends Node3D
## Traffic enforcers standing at some busy intersections (every 3rd traffic light).
## Most lights have NO enforcer: you only get in trouble if the enforcer at THAT crossing
## sees you beat the red light (right turns on red are allowed, like "right turn anytime").
## No speeding tickets: how fast you ride is between you and your passenger.
##
## When an enforcer catches you he blows the whistle and waves you over. Your choice:
##   - pull over next to him (stop within a few meters) -> pay the ticket
##   - ride away                                        -> "evading" = 1 WANTED star
## The fine comes straight out of your wallet, which can go negative (work it back up).
## Amounts: config/economy.gd (based on LTO JAO 2014-01 / RA 4136).
##
## Serious stuff (hitting a pedestrian, fighting in public) gives you a WANTED level (stars)
## instead: police motorbikes chase you. Lose them (stay out of their sight) and the stars
## fade. Get caught = BUSTED: jail days + bail (handled by the game).

signal ticketed(reason: String, fine: int)
signal busted(stars: int)
signal wanted_changed(stars: int)

const SIGHT := 70.0             # enforcers/police see serious stuff (hitting people, fights) this far
const LIGHT_SIGHT := 40.0       # an enforcer only notices a red light at his own crossing
const PULL_OVER_TIME := 12.0    # seconds to stop next to the enforcer before it counts as evading
const PULL_OVER_DIST := 12.0
const EVADE_DIST := 75.0
const WITNESS_DIST := 25.0      # people on the street who see you hit someone may call the police
const ENFORCER_RADIUS := 230.0
const SPEED_WATCH := 45.0
const COOLDOWN := 20.0          # same violation can't be ticketed again for this long
const REASONS := {
	"red_light": "Disregarding traffic signal (beating the red light)",
	"reckless": "Reckless driving (hit a pedestrian)",
	"bump": "Bumped a pedestrian",
	"fighting": "Fighting in public / alarms and scandals",
	"evading": "Evading a traffic enforcer",
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
var offenses: Array[String] = []   # what you're wanted for (shown under the stars)
var pull_over := {}                 # enforcer waiting for you to stop: {"enforcer", "reason", "time"}
var _red_entry := {}                # entered a crossing on red: decide when we leave (right turn = ok)


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
	_update_pull_over(delta)
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


## Red lights: when we ENTER a crossing on red we remember how we came in; when we LEAVE
## it we check where we went. Turning right on red is fine; straight or left = violation.
func _check_red_light() -> void:
	var here := motor.global_position
	var current := -1
	for id in world.road_graph.point_ids_near(here, 6.0):
		if traffic.is_signal(id):
			current = id
			break
	if current != -1 and current != _inside_signal and absf(motor.speed) > 2.0:
		var from := _approach(current, motor.get_forward())
		if from != -1 and traffic.light_state(current, from) == 2:
			_red_entry = {"id": current, "fwd": motor.get_forward(), "pos": here}
	if current == -1 and _inside_signal != -1 and not _red_entry.is_empty():
		if not is_right_turn(_red_entry["fwd"], motor.get_forward()):
			violation("red_light", _red_entry["pos"], int(_red_entry["id"]))
		_red_entry = {}
	_inside_signal = current


## Which road did we come in on? The neighbor behind us.
func _approach(id: int, fwd: Vector3) -> int:
	var g := world.road_graph
	var best := -1
	var best_dot := -2.0
	for n in g.neighbors(id):
		var dot := (g.get_point(id) - g.get_point(n)).normalized().dot(fwd)
		if dot > best_dot:
			best_dot = dot
			best = n
	return best


## Right turn = we now face roughly 90 degrees clockwise (seen from above) from how we came in.
static func is_right_turn(f_in: Vector3, f_out: Vector3) -> bool:
	var cross_y := f_in.z * f_out.x - f_in.x * f_out.z
	return cross_y < -0.5 and f_in.dot(f_out) < 0.6


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
## `at_signal` = the traffic light crossing (red lights: only that crossing's enforcer counts).
func violation(reason: String, pos: Vector3, at_signal: int = -1) -> void:
	if float(_cooldowns.get(reason, 0.0)) > 0.0:
		return
	var e: Node3D = null
	if reason == "red_light":
		if enforcers.has(at_signal) and (enforcers[at_signal] as Node3D).global_position.distance_to(pos) < LIGHT_SIGHT:
			e = enforcers[at_signal]
	else:
		e = _nearest_enforcer(pos, SIGHT)
	var police_saw := _nearest_unit(pos, 60.0) != null
	if reason == "reckless" or reason == "bump" or reason == "fighting":
		var stars: int = {"reckless": 2, "bump": 1, "fighting": 1}[reason]
		if e == null and not police_saw:
			# no enforcer around... but people on the street saw it and may call the police
			if reason == "fighting" or not _witnessed(pos) or _rng.randf() > (0.6 if reason == "reckless" else 0.3):
				return
			stars = 1
			hud.show_toast("May nakakita! Someone saw that and called the police!", 3.0)
		_cooldowns[reason] = 6.0
		_whistle()
		add_wanted(stars, reason)
		return
	if e == null or not pull_over.is_empty():
		return
	_cooldowns[reason] = COOLDOWN
	_whistle()
	e.look_at(Vector3(pos.x, e.global_position.y, pos.z), Vector3.UP)
	pull_over = {"enforcer": e, "reason": reason, "time": PULL_OVER_TIME}
	hud.show_toast("PRRT! An enforcer saw you %s!\nPull over next to him to take the ticket (%s)... or run for it!" % [
		"beat the red light" if reason == "red_light" else str(REASONS[reason]).to_lower(), Economy.format_peso(_fine_for(reason))], 4.5)


## Waiting for you to pull over: stop near the enforcer = ticket; ride off = evading (1 star).
func _update_pull_over(delta: float) -> void:
	if pull_over.is_empty():
		return
	var e: Node3D = pull_over["enforcer"]
	if not is_instance_valid(e):
		pull_over = {}
		return
	pull_over["time"] = float(pull_over["time"]) - delta
	var me := traffic.player_pos()
	var d := e.global_position.distance_to(me)
	if d > 0.5:
		e.look_at(Vector3(me.x, e.global_position.y, me.z), Vector3.UP)
	var my_speed := absf(motor.speed) if player.state == Player.State.RIDING else 0.0
	if d < PULL_OVER_DIST and my_speed < 1.5:
		_give_ticket(pull_over["reason"])
		pull_over = {}
	elif d > EVADE_DIST or float(pull_over["time"]) <= 0.0:
		pull_over = {}
		_whistle()
		add_wanted(1, "evading")


func _give_ticket(reason: String) -> void:
	var fine := _fine_for(reason)
	GameState.add_money(-fine)   # can go below zero: that's debt you work off
	GameState.today["fines"] = int(GameState.today.get("fines", 0)) + fine
	GameState.tickets += 1
	hud.show_toast("TICKET: %s  -%s\nSalamat sa kooperasyon! (Thanks for cooperating)%s" % [REASONS[reason], Economy.format_peso(fine),
		"\nYour wallet is negative: keep working to pay it off!" if GameState.money < 0 else ""], 4.5)
	ticketed.emit(reason, fine)


## Seconds left to pull over (0 = no enforcer waiting). For the HUD.
func pull_over_time() -> float:
	return float(pull_over.get("time", 0.0))


## Was anyone walking nearby to see it?
func _witnessed(pos: Vector3) -> bool:
	if traffic.pedestrians == null:
		return false
	for p in traffic.pedestrians.people:
		if is_instance_valid(p) and p.global_position.distance_to(pos) < WITNESS_DIST and p.knocked <= 0.0:
			return true
	return false


## Enforcer positions for the minimap.
func enforcer_positions() -> PackedVector3Array:
	var out := PackedVector3Array()
	for id: int in enforcers:
		out.append((enforcers[id] as Node3D).global_position)
	return out


func _whistle() -> void:
	_sfx.stream = Sfx.whistle()
	_sfx.play()


# --- Wanted level & police chase ----------------------------------------------------

func add_wanted(stars: int, reason: String) -> void:
	var before := wanted
	wanted = mini(3, maxi(wanted + 1, stars) if wanted > 0 else stars)
	_unseen = 0.0
	var text: String = REASONS.get(reason, reason)
	if not offenses.has(text):
		offenses.append(text)
	if wanted != before:
		wanted_changed.emit(wanted)
		hud.show_toast("WANTED %s  -  %s!
Police are coming. Lose them, or you'll be jailed." % [
			"★".repeat(wanted), text], 4.0)
	else:
		wanted_changed.emit(wanted)   # same stars, maybe a new offense: refresh the list


func clear_wanted() -> void:
	wanted = 0
	offenses.clear()
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
		"fighting":
			return Economy.FINE_FIGHTING
		"bump":
			var bump_fines: Array = Economy.FINE_RECKLESS
			return bump_fines[0]
		"reckless":
			var fines: Array = Economy.FINE_RECKLESS
			var f: int = fines[mini(GameState.reckless_count, fines.size() - 1)]
			GameState.reckless_count += 1
			return f
	return 0
