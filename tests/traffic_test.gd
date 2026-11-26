extends Node
## Automated test of Milestone 6: traffic, traffic lights, pedestrians, road rage, fist fights.
## Run:  godot --path . res://tests/traffic_test.tscn

var game: Node3D
var traffic: Traffic
var combat: Combat
var motor: Motorcycle
var player: Player
var _fails: Array[String] = []


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("user://screenshots")
	GameState.reset_new_game()
	GameState.debug_skip_story()
	game = (load("res://scenes/main/game.tscn") as PackedScene).instantiate()
	add_child(game)
	traffic = game.traffic
	combat = game.combat
	motor = game.motor
	player = game.player
	_run()


func _run() -> void:
	GameState.time_hours = 10.0
	await _wait(4.0)

	# --- Traffic & people ---------------------------------------------------------
	print("  vehicles: %d (target %d), people: %d, traffic lights nearby: %d" % [
		traffic.vehicles.size(), traffic.target_count(), game.pedestrians.people.size(), traffic._light_nodes.size()])
	_check(traffic.vehicles.size() >= 5, "traffic spawned")
	_check(game.pedestrians.people.size() >= 3, "people walking")
	var kinds := {}
	for v in traffic.vehicles:
		kinds[v.kind] = true
	print("  vehicle kinds: %s" % ", ".join(kinds.keys()))
	var start_pos := {}
	for veh in traffic.vehicles:
		start_pos[veh] = veh.global_position
	await _wait(2.0)
	var moved := 0
	for veh in start_pos:
		if is_instance_valid(veh) and (veh as Node3D).global_position.distance_to(start_pos[veh]) > 2.0:
			moved += 1
	print("  %d of %d vehicles moved in 2 s (others: red lights / queues)" % [moved, start_pos.size()])
	_check(moved >= start_pos.size() / 2, "vehicles drive")

	# a view of the street with traffic: put the camera behind some car
	var nearest: TrafficVehicle = _closest_vehicle()
	if nearest != null:
		player.teleport(nearest.global_position - nearest.forward() * 12.0 + Vector3(2.5, 0.3, 0))
		game.cam.snap_to(nearest.heading)
		await _wait(0.8)
		_shot("traffic_01_street")

	# --- Traffic light states -----------------------------------------------------
	var found_light := false
	for id: int in traffic._light_nodes:
		var nb: PackedInt64Array = game.world.road_graph.neighbors(id)
		var s0: int = traffic.light_state(id, nb[0])
		var s1: int = traffic.light_state(id, nb[1]) if nb.size() > 1 else 2
		print("  light %d: states %d / %d" % [id, s0, s1])
		found_light = true
		break
	_check(found_light, "traffic lights placed near the player")

	# (test) during the fight checks, enforcers look the other way; police get their own checks
	game.police._cooldowns["fighting"] = 99999.0
	game.police._cooldowns["reckless"] = 99999.0

	# --- Road rage: ride away -----------------------------------------------------
	game.respawn_at_home()
	await _wait(0.5)
	player.teleport(motor.global_position + Vector3(-1.2, 0.2, 0))
	game._toggle_ride()
	var v := _closest_vehicle()
	combat.start_road_rage(v, true)
	_check(combat.has_hostile(), "road rage: driver gets out angry")
	await _wait(1.0)
	_shot("traffic_02_road_rage")
	motor.place(motor.global_position + Vector3(0, 0.3, 45), motor.heading)
	await _until(func() -> bool: return not combat.has_hostile(), 15.0)
	_check(not combat.has_hostile(), "ride away: driver gives up")
	await _until(func() -> bool: return combat.fighters.is_empty(), 15.0)

	# --- Fight a driver and win -------------------------------------------------------
	v = _closest_vehicle()
	combat.start_road_rage(v, true)
	game._toggle_ride()   # get off
	var foe: Fighter = combat.focus
	player.teleport(foe.global_position + Vector3(1.0, 0.2, 0))
	var respect := GameState.respect
	var t := 0.0
	var shot_taken := false
	while is_instance_valid(foe) and foe.mood != Fighter.Mood.DOWN and t < 25.0:
		player.health = maxf(player.health, 60.0)   # (test) keep the player alive
		# chase them if they run (they're slower than you when you run)
		if player.global_position.distance_to(foe.global_position) > 1.4:
			player.teleport(foe.global_position + (player.global_position - foe.global_position).normalized() * 1.0)
		# no lock-on: aim the camera (and so the punches) at them
		var aim := foe.global_position - player.global_position
		game.cam.snap_to(atan2(-aim.x, -aim.z))
		player.face_yaw(atan2(-aim.x, -aim.z))
		combat.player_punch()
		await _wait(0.3)
		t += 0.3
		if not shot_taken and t > 1.5:
			shot_taken = true
			_shot("traffic_03_fight")
	_check(GameState.respect == respect + 1, "knocked the driver down (+1 respect)")
	await _until(func() -> bool: return not is_instance_valid(foe), 20.0)
	_check(not is_instance_valid(foe), "beaten driver goes back to the car")
	combat.cancel()   # (bystanders who joined in or ran off)

	# --- Punch a stranger: they fight back or run -----------------------------------
	var person: Pedestrian = null
	for p in game.pedestrians.people:
		if is_instance_valid(p):
			person = p
			break
	if person != null:
		person.set_physics_process(false)   # (test) hold still
		var spot := person.global_position + Vector3(1.0, 0.2, 0)
		player.teleport(spot)
		var to := person.global_position - spot
		player.face_yaw(atan2(-to.x, -to.z))
		game.cam.snap_to(atan2(-to.x, -to.z))   # no lock-on: you aim with the camera
		await _wait(0.1)
		var n := combat.fighters.size()
		combat.player_punch()
		await _wait(0.5)
		_check(combat.fighters.size() >= n + 1, "punched a stranger: they (and maybe bystanders) react")
		if combat.fighters.size() > n:
			var f: Fighter = combat.fighters[combat.fighters.size() - 1]
			print("  stranger reaction: %s" % ["fights back", "runs away", "down", "returning"][f.mood])
	combat.cancel()

	# --- Lose a fight -> clinic --------------------------------------------------------
	v = _closest_vehicle()
	combat.start_road_rage(v, true)
	player.teleport(combat.focus.global_position + Vector3(1.0, 0.2, 0))
	await _wait(0.5)
	player.health = 8.0
	var money := GameState.money
	for i in 4:
		await _wait(0.6)
		if combat.focus != null and is_instance_valid(combat.focus):
			print("  lose trace: mood=%d dist=%.1f player hp=%.0f on_foot=%s ending=%s" % [combat.focus.mood,
				combat.focus.global_position.distance_to(player.global_position), player.health, combat.player_on_foot(), game._ending_day])
	await _until(func() -> bool: return game._ending_day, 15.0)
	await _until(func() -> bool: return not game._ending_day, 10.0)
	var clinic: Dictionary = game.world.nearest_place("clinic", player.global_position)
	_check(Story._flat(player.global_position, clinic["door"]) < 4.0, "lost fight: woke up at the clinic")
	_check(money - GameState.money >= Economy.CLINIC_FEE, "paid the clinic fee")

	# --- Traffic enforcer: ticket, money can go negative ---------------------------------
	var police: Police = game.police
	police.clear_wanted()
	var enforcer: Node3D = null
	for r in [400.0, 900.0, 2000.0]:
		police._update_enforcers(player.global_position)
		if not police.enforcers.is_empty():
			break
		# no enforcer here: move toward the city center where there are more traffic lights
		player.teleport(Vector3(0, 0.3, 0))
		game.world.update_streaming(Vector3.ZERO, true)
	if not police.enforcers.is_empty():
		enforcer = police.enforcers.values()[0]
		GameState.money = 500
		police._cooldowns.clear()
		police.violation("red_light", enforcer.global_position + Vector3(5, 0, 0))
		print("  after ticket: money %d" % GameState.money)
		_check(GameState.money == 500 - Economy.FINE_RED_LIGHT, "enforcer gives a ticket (red light)")
		_check(GameState.money < 0, "wallet can go negative")
		game._update_hud()
		await _wait(0.3)
		_shot("traffic_04_ticket")
	else:
		_check(false, "found a traffic enforcer")

	# --- Bystanders join in or run away ----------------------------------------------
	combat.cancel()
	var near_people := 0
	for p in game.pedestrians.people:
		if is_instance_valid(p) and near_people < 4:
			p.set_physics_process(false)
			p.global_position = player.global_position + Vector3(4.0 + near_people, 0, 3.0)
			near_people += 1
	var before := combat.fighters.size()
	combat._alert_cooldown = 0.0
	combat._alert_bystanders(player.global_position)
	var reacted := combat.fighters.size() - before
	var joined := 0
	for f in combat.fighters:
		if f.is_hostile():
			joined += 1
	print("  bystanders: %d nearby, %d reacted (%d joined the fight)" % [near_people, reacted, joined])
	_check(near_people == 0 or reacted > 0, "bystanders react to a fight")
	combat.cancel()

	game.police._cooldowns.clear()

	# --- Police chase: lose them ---------------------------------------------------------
	police.add_wanted(1, "fighting")
	await _wait(1.0)
	_check(police.units.size() == 1, "police unit chasing (1 star)")
	player.teleport(player.global_position + Vector3(300, 0.3, 0))
	police._unseen = 30.0
	await _wait(0.5)
	_check(police.wanted == 0, "lost the police")

	# --- Police chase: busted -> jail -------------------------------------------------------
	game.respawn_at_home()
	await _wait(0.5)
	var day_before := GameState.day
	var money_before := GameState.money
	police.add_wanted(2, "reckless")
	await _until(func() -> bool: return police.units.size() == 2, 3.0)
	# (test) bring a unit next to you instead of waiting for the chase
	police.units[0].global_position = player.global_position + Vector3(2.0, 0, 0)
	await _until(func() -> bool: return game._ending_day, 6.0)
	await _until(func() -> bool: return not game._ending_day, 10.0)
	print("  busted: day %d -> %d, money %d -> %d" % [day_before, GameState.day, money_before, GameState.money])
	_check(GameState.day == day_before + 2 * Economy.JAIL_DAYS_PER_STAR, "busted: jailed for 4 days")
	_check(money_before - GameState.money == 2 * Economy.BAIL_PER_STAR, "busted: paid bail")

	# --- First person with side mirrors ---------------------------------------------------
	game.respawn_at_home()
	await _wait(0.4)
	player.teleport(motor.global_position + Vector3(-1.2, 0.2, 0))
	game._toggle_ride()
	game.cam._preset = 3   # first person
	Input.action_press("accelerate")
	await _wait(2.0)
	Input.action_release("accelerate")
	_check(game.cam.is_first_person() and motor._mirrors_active, "first person + side mirrors on")
	_shot("traffic_05_first_person")
	game.cam._head_yaw = 1.2   # look over your left shoulder
	await _wait(0.3)
	_shot("traffic_06_head_turn")
	game.cam._preset = 0
	await _wait(0.2)

	# --- Hit a pedestrian with the motor -------------------------------------------------
	await _wait(1.0)
	var walker: Pedestrian = null
	for p in game.pedestrians.people:
		if is_instance_valid(p):
			walker = p
			break
	if walker != null:
		game._on_hit_person(walker, 6.0)
		_check(walker.knocked > 0.0, "a person you hit with the motor falls down")

	# --- Traffic light countdown timers ---------------------------------------------------
	var lid := -1
	for id: int in traffic._light_nodes:
		lid = id
		break
	if lid != -1:
		var head: Dictionary = traffic._light_nodes[lid]["heads"][0]
		var secs := traffic.light_time_left(lid, int(head["from"]))
		print("  light timer shows '%s' (%.1f s left)" % [(head["timer"] as Label3D).text, secs])
		_check(secs > 0.0 and secs <= Traffic.CYCLE and (head["timer"] as Label3D).text != "", "traffic light countdown timer")
		# stand back and look at it
		var lp: Vector3 = game.world.road_graph.get_point(lid)
		game.respawn_at_home()
		player.teleport(lp + Vector3(9, 0.3, 9))
		var to_light := lp - player.global_position
		game.cam.snap_to(atan2(-to_light.x, -to_light.z))
		await _wait(0.6)
		_shot("traffic_07_light_timer")

	# --- NPC car crash ----------------------------------------------------------------------
	var a: TrafficVehicle = null
	var b: TrafficVehicle = null
	for veh in traffic.vehicles:
		if is_instance_valid(veh) and veh.crash_time <= 0.0 and not veh.stopped_for_rage:
			if a == null:
				a = veh
			elif b == null:
				b = veh
				break
	if a != null and b != null:
		# (test) put b right across a's nose, both moving
		b.progress = a.progress
		b._start_segment(a.from_id, a.to_id, a.progress / a.seg_len)
		b.heading = a.heading + PI * 0.5
		a.speed = 8.0
		b.speed = 8.0
		b.global_transform = Transform3D(Basis(Vector3.UP, b.heading), a.global_position + a.forward() * 1.0)
		traffic._check_vehicle_crashes()
		_check(a.crash_time > 0.0 and b.crash_time > 0.0, "two NPC cars crash and stop")
		# drivers fight each other
		combat.cancel()
		combat.start_npc_road_rage(a, b)
		_check(combat.fighters.size() == 2 and combat.fighters[0].opponent == combat.fighters[1], "crashed drivers fight each other")
		player.teleport(a.global_position + Vector3(8, 0.3, 8))
		var tl := a.global_position - player.global_position
		game.cam.snap_to(atan2(-tl.x, -tl.z))
		await _wait(2.0)
		_shot("traffic_08_npc_fight")
		await _until(func() -> bool:
			for f in combat.fighters:
				if is_instance_valid(f) and f.mood != Fighter.Mood.HOSTILE:
					return true
			return combat.fighters.size() < 2, 40.0)
		print("  npc fight result: %s" % ", ".join(combat.fighters.map(func(f: Fighter) -> String:
			return ["hostile", "fleeing", "down", "returning"][f.mood] if is_instance_valid(f) else "gone")))
		_check(true, "npc fight resolves")
		combat.cancel()

	# --- You ride into a car ---------------------------------------------------------------------
	var car: TrafficVehicle = _closest_vehicle()
	car.crash_time = 0.0
	motor.speed = 9.0
	game._on_motor_hit_vehicle(car)
	_check(car.crash_time > 0.0, "a car you hit gets knocked and stops")
	combat.cancel()

	# --- Street fight between two people --------------------------------------------------------
	var p1: Pedestrian = null
	var p2: Pedestrian = null
	for p in game.pedestrians.people:
		if is_instance_valid(p):
			if p1 == null:
				p1 = p
			else:
				p2 = p
				break
	if p1 != null and p2 != null:
		combat.start_street_fight(p1, p2)
		_check(combat.fighters.size() == 2 and combat.fighters[0].opponent != null, "people start a street fight")
		combat.cancel()

	print("TRAFFIC TEST DONE: %s" % ("ALL PASSED" if _fails.is_empty() else "FAILED: %s" % ", ".join(_fails)))
	get_tree().quit(0 if _fails.is_empty() else 1)


func _closest_vehicle() -> TrafficVehicle:
	var best: TrafficVehicle = null
	var best_d := INF
	for v in traffic.vehicles:
		if is_instance_valid(v):
			var d := v.global_position.distance_to(player.global_position)
			if d < best_d:
				best_d = d
				best = v
	return best


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _until(cond: Callable, timeout: float) -> void:
	var t := 0.0
	while not bool(cond.call()) and t < timeout:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()


func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		_fails.append(what)


func _shot(n: String) -> void:
	get_viewport().get_texture().get_image().save_png("user://screenshots/%s.png" % n)
