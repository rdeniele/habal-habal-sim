extends Node
## Automated test of Milestone 4: day/night lighting, Last Ride, end of day, rent/debt,
## repossession, auto-save + load, pause-menu save rules, main menu.
## Uses save slot 3 and deletes it afterwards.
## Run:  godot --path . res://tests/day_test.tscn

const TEST_SLOT := 3

var game: Node3D
var booking: BookingSystem
var motor: Motorcycle
var player: Player
var hud: HUD
var _fails: Array[String] = []


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("user://screenshots")
	SaveManager.delete_slot(TEST_SLOT)
	GameState.reset_new_game()
	GameState.debug_skip_story()
	GameState.motor_mode = "rent"
	GameState.rental_out = true
	GameState.save_slot = TEST_SLOT
	game = (load("res://scenes/main/game.tscn") as PackedScene).instantiate()
	add_child(game)
	game.death_chance = 0.0   # (test) accidents never end the game
	game.traffic.can_hit_player = false
	booking = game.booking
	motor = game.motor
	player = game.player
	hud = game.hud
	_run()


func _run() -> void:
	await _wait(1.0)

	# --- Lighting -----------------------------------------------------------
	GameState.time_hours = 12.0
	game.day_cycle.update_now()
	_check(game.world.sun.light_energy > 1.0 and game.day_cycle.night_amount < 0.1, "noon is bright")
	await _wait(0.3)
	_shot("day_01_noon")
	GameState.time_hours = 18.0
	await _wait(0.3)
	_shot("day_02_sunset")
	GameState.time_hours = 21.0
	player.teleport(motor.global_position + Vector3(-1.2, 0.2, 0))
	game._toggle_ride()
	await _wait(0.3)
	_check(game.day_cycle.night_amount > 0.9, "night glow at 9 PM")
	_check(motor._headlight.visible, "headlight on at night while riding")
	_shot("day_03_night")
	GameState.time_hours = 23.5
	_check(booking.is_closed_hours(), "Sakay closed at 11:30 PM")
	GameState.time_hours = 15.0

	# --- Last Ride ----------------------------------------------------------
	booking.go_online_now()
	booking.request_last_ride()
	booking._next_request_in = 0.2
	await _until(func() -> bool: return booking.stage == BookingSystem.Stage.REQUEST, 5.0)
	var home: Vector3 = game.world.get_place("home")["door"]
	var drop_pos: Vector3 = booking._request["dropoff"]["pos"]
	_check(bool(booking._request["final"]), "request is marked final")
	_check(Story._flat(drop_pos, home) < BookingSystem.HOME_DROP_RADIUS, "final drop-off is near home (%d m)" % int(Story._flat(drop_pos, home)))
	booking.accept()
	_park_at(booking._request["pickup"])
	await _until(func() -> bool: return booking.stage == BookingSystem.Stage.TO_DROPOFF, 8.0)
	_park_at(booking._request["dropoff"])
	await _until(func() -> bool: return booking.stage == BookingSystem.Stage.OFFLINE, 5.0)
	_check(booking.stage == BookingSystem.Stage.OFFLINE, "offline after last ride")
	var fares_today := int(GameState.today["fares"])

	# --- Return the rental at the shop (pays the boundary) --------------------
	var money_before := GameState.money
	game._park_motor_at("motor_shop")
	game._on_shop_return()
	hud.shop.close_shop()
	_check(money_before - GameState.money == Economy.RENT_PER_DAY, "boundary of %d paid when returning" % Economy.RENT_PER_DAY)
	_check(not GameState.rental_out and not motor.is_active, "rental returned (motor gone)")

	# --- End of day ----------------------------------------------------------
	game.respawn_at_home()
	await _wait(0.3)
	game._try_end_day()
	await _until(func() -> bool: return hud.end_of_day.visible, 4.0)
	_check(hud.end_of_day.visible, "end of day screen shown")
	await _wait(0.6)
	_shot("day_04_summary")
	_check(int(GameState.today["rent_paid"]) == Economy.RENT_PER_DAY, "summary shows boundary paid")
	_check(fares_today > 0, "earned fares on day 1")
	hud.end_of_day._dismiss()
	await _until(func() -> bool: return not game._ending_day, 8.0)
	_check(GameState.day == 2, "now day 2")
	_check(SaveManager.has_save(TEST_SLOT), "auto-saved to slot %d" % TEST_SLOT)
	_check(int(SaveManager.read_slot(TEST_SLOT).get("day", 0)) == 2, "save says day 2")

	_check(not motor.is_active, "renter starts the morning without a motor")

	# --- Not returning the rental -> debt -> repossession -------------------
	for i in 3:
		GameState.rental_out = true   # rented again this morning...
		motor.set_active(true)
		GameState.money = 100
		await _end_day_quick()        # ...and never returned it
		print("  day %d: debt=%d unpaid=%d mode=%s" % [GameState.day, GameState.debt, GameState.rent_unpaid_days, GameState.motor_mode])
		if i < 2:
			_check(GameState.debt == Economy.RENT_PER_DAY * (i + 1), "debt grows (%d)" % GameState.debt)
	_check(GameState.motor_mode == "none" and not motor.is_active, "motor taken back after 3 unpaid days")

	# --- Load the save -------------------------------------------------------
	_check(SaveManager.load_game(TEST_SLOT), "load slot")
	_check(GameState.day == 5 and GameState.motor_mode == "none", "loaded day 5, no motor")

	# --- Pause menu save rules ----------------------------------------------
	GameState.motor_mode = "own"
	motor.set_active(true)
	game.respawn_at_home()
	await _wait(0.2)
	game._open_pause_menu()
	_check(hud.pause_menu.can_save, "can save at home")
	await _wait(0.2)
	_shot("day_05_pause")
	hud.pause_menu.close()
	player.teleport(player.global_position + Vector3(40, 0, 0))
	game._open_pause_menu()
	_check(not hud.pause_menu.can_save, "can't save away from home")
	hud.pause_menu.close()

	# --- Main menu -----------------------------------------------------------
	game.queue_free()
	await _wait(0.3)
	var menu := (load("res://scenes/main_menu/main_menu.tscn") as PackedScene).instantiate()
	add_child(menu)
	await _wait(1.5)
	_check(not menu._continue_btn.disabled, "Continue is enabled (a save exists)")
	_shot("day_06_main_menu")

	SaveManager.delete_slot(TEST_SLOT)
	print("DAY TEST DONE: %s" % ("ALL PASSED" if _fails.is_empty() else "FAILED: %s" % ", ".join(_fails)))
	get_tree().quit(0 if _fails.is_empty() else 1)


func _end_day_quick() -> void:
	game.respawn_at_home()
	game._end_day(false)
	await _until(func() -> bool: return hud.end_of_day.visible, 4.0)
	hud.end_of_day._shown_msec = 0
	hud.end_of_day._dismiss()
	await _until(func() -> bool: return not game._ending_day, 8.0)


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
	if DisplayServer.get_name() == "headless":
		return   # no screen to capture when running without a window
	get_viewport().get_texture().get_image().save_png("user://screenshots/%s.png" % shot_name)
