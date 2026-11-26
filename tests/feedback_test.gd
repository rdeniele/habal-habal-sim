extends Node
## Automated test of the playtest fixes (Milestone 4.5): min fare, passenger variety,
## helmet on boarding, GPS route + minimap, food stalls, break mode, fainting -> clinic.
## Run:  godot --path . res://tests/feedback_test.tscn

var game: Node3D
var booking: BookingSystem
var motor: Motorcycle
var player: Player
var hud: HUD
var _fails: Array[String] = []


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("user://screenshots")
	GameState.reset_new_game()
	GameState.debug_skip_story()
	game = (load("res://scenes/main/game.tscn") as PackedScene).instantiate()
	add_child(game)
	booking = game.booking
	motor = game.motor
	player = game.player
	hud = game.hud
	_run()


func _run() -> void:
	await _wait(1.0)
	GameState.time_hours = 10.0   # not rush hour

	# --- Fares ---------------------------------------------------------------
	_check(Economy.calc_fare(0.05, 10.0) == Economy.MIN_FARE, "shortest ride pays the minimum (%d)" % Economy.MIN_FARE)
	print("  fares: 0.3 km=%d  0.8 km=%d  1.5 km=%d" % [Economy.calc_fare(0.3, 10.0), Economy.calc_fare(0.8, 10.0), Economy.calc_fare(1.5, 10.0)])

	# --- Passenger variety ---------------------------------------------------
	var seen := {}
	for i in booking._personalities.size():
		seen[booking._next_personality()["id"]] = true
	_check(seen.size() == booking._personalities.size(), "every passenger type once before repeats (%d types)" % seen.size())

	# --- Helmet + GPS ----------------------------------------------------------
	player.teleport(motor.global_position + Vector3(-1.2, 0.2, 0))
	game._toggle_ride()
	booking.go_online_now()
	booking._next_request_in = 0.2
	await _until(func() -> bool: return booking.stage == BookingSystem.Stage.REQUEST, 5.0)
	booking.accept()
	var passenger: Passenger = booking._passenger
	_check(not passenger.model.has_helmet(), "waiting passenger has no helmet")
	await _wait(0.5)
	_check(game._gps_route.size() >= 3, "GPS route to pickup (%d points)" % game._gps_route.size())
	_shot("fb_01_gps_minimap")
	_park_at(booking._request["pickup"])
	await _until(func() -> bool: return booking.stage == BookingSystem.Stage.TO_DROPOFF, 8.0)
	_check(passenger.model.has_helmet(), "passenger puts on a helmet when riding")
	await _wait(0.4)
	_shot("fb_02_helmet_on")
	hud.toggle_full_map()
	await _wait(0.3)
	_shot("fb_03_full_map")
	hud.toggle_full_map()
	booking.abort_trip()

	# --- Break mode -------------------------------------------------------------
	booking.toggle_break()
	_check(booking.stage == BookingSystem.Stage.BREAK, "on break")
	booking._next_request_in = 0.0
	await _wait(1.0)
	_check(booking.stage == BookingSystem.Stage.BREAK, "no bookings during break")
	booking.toggle_break()
	_check(booking.stage == BookingSystem.Stage.SEARCHING, "break over, searching again")
	booking.go_offline()

	# --- GPS home -----------------------------------------------------------------
	game._gps_goal = "home"
	var t: Dictionary = game._gps_target()
	_check(t.get("label", "") == "HOME", "GPS points home at the end of the day")
	game._gps_goal = ""

	# --- Food stall ---------------------------------------------------------------
	game._dismount()
	var stall: Vector3 = game.world.food_stalls[0]
	player.teleport(stall + Vector3(0, 0.2, 0))
	await _wait(0.3)
	_check(game._near_stall(), "standing at a sari-sari store")
	GameState.thirst = 30.0
	var money := GameState.money
	game._interact()
	_check(hud.food_menu.visible, "food menu opens")
	await _wait(0.3)
	_shot("fb_04_food_menu")
	hud.food_menu.choose(0)   # mineral water
	_check(GameState.thirst > 70.0 and money - GameState.money == 20, "drank water (+thirst, -₱20)")
	hud.food_menu.close_menu()

	# --- Resting + fainting -------------------------------------------------------
	GameState.energy = 50.0
	await _wait(3.5)   # standing still
	_check(game.needs.is_resting() and GameState.energy > 50.0, "standing still rests (energy %.1f)" % GameState.energy)
	await _wait(0.2)
	_shot("fb_05_needs")
	money = GameState.money
	GameState.energy = 0.0
	await _until(func() -> bool: return game._ending_day, 3.0)
	await _until(func() -> bool: return not game._ending_day, 10.0)
	var clinic: Vector3 = game.world.nearest_place("clinic", player.global_position)["door"]
	_check(Story._flat(player.global_position, clinic) < 3.0, "woke up at the clinic")
	_check(money - GameState.money == Economy.CLINIC_FEE, "paid the clinic fee")

	print("FEEDBACK TEST DONE: %s" % ("ALL PASSED" if _fails.is_empty() else "FAILED: %s" % ", ".join(_fails)))
	get_tree().quit(0 if _fails.is_empty() else 1)


func _park_at(point: Dictionary) -> void:
	var pos: Vector3 = point["pos"]
	var road_dir: Vector3 = point["road_dir"]
	var heading := -PI * 0.5 if absf(road_dir.z) > 0.5 else 0.0
	motor.place(pos + road_dir * 3.4 + Vector3(0, 0.2, 0), heading)


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


func _shot(shot_name: String) -> void:
	get_viewport().get_texture().get_image().save_png("user://screenshots/%s.png" % shot_name)
