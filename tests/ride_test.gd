extends Node
## Automated test of the ride-hailing loop (Milestone 2).
## Teleports the motor between stops instead of driving, then checks money, rating,
## refueling and pushing with no gas. Screenshots go to user://screenshots/ride_*.png
## Run:  godot --path . res://tests/ride_test.tscn

var game: Node3D
var booking: BookingSystem
var motor: Motorcycle
var player: Player
var _t := 0.0
var _step := 0
var _money_before := 0
var _fails: Array[String] = []


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("user://screenshots")
	GameState.debug_skip_story()   # tests start after the tutorial
	game = (load("res://scenes/main/game.tscn") as PackedScene).instantiate()
	add_child(game)
	booking = game.booking
	motor = game.motor
	player = game.player


func _physics_process(delta: float) -> void:
	_t += delta
	match _step:
		0:
			if _t > 1.0:
				player.teleport(motor.global_position + Vector3(-1.5, 0.2, 0))
				game._toggle_ride()
				_check(player.state == Player.State.RIDING, "mounted")
				booking.go_online_now()
				booking._next_request_in = 0.5
				_next()
		1:
			if booking.stage == BookingSystem.Stage.REQUEST and _t > 1.0:
				var r := booking._request
				print("request: ", r["name"], " pickup=", r["pickup"]["label"], " drop=", r["dropoff"]["label"],
					" trip=", int(r["trip_m"]), "m fare=", r["fare"])
				_shot("ride_01_request")
				booking.accept()
				_check(booking.stage == BookingSystem.Stage.TO_PICKUP, "accepted -> TO_PICKUP")
				_next()
			elif _t > 10.0:
				_fail("no booking request within 10s")
		2:
			if _t > 0.5:
				_shot("ride_02_gps")
				_park_at(booking._request["pickup"])
				_next()
		3:
			if booking.stage == BookingSystem.Stage.TO_DROPOFF:
				print("passenger on board after ", snappedf(_t, 0.1), "s")
				Input.action_press("accelerate")
				_next()
			elif _t > 1.0 and _t < 1.1:
				_shot("ride_03_boarding")
			elif _t > 10.0:
				_fail("passenger never boarded, stage=%d" % booking.stage)
		4:
			if _t > 2.0:
				Input.action_release("accelerate")
				_shot("ride_04_with_passenger")
				_money_before = GameState.money
				_park_at(booking._request["dropoff"])
				_next()
		5:
			if booking.stage == BookingSystem.Stage.SEARCHING:
				var earned := GameState.money - _money_before
				print("trip done: earned ", earned, " rating=", GameState.rating, " today=", GameState.today)
				_check(earned > 0, "got paid")
				_check(int(GameState.today["rides"]) == 1, "ride counted")
				_next()
			elif _t > 5.0:
				_fail("drop-off never completed, stage=%d" % booking.stage)
		6:
			if _t > 0.6:
				_shot("ride_05_dropoff")
				# Refuel test: nearly empty tank, park at the pump
				motor.fuel_liters = 0.5
				var pump: Vector3 = game._pump_position()
				motor.place(pump + Vector3(0, 0.2, 0), -PI * 0.5)
				_next()
		7:
			if _t > 0.5:
				_check(game._can_refuel(), "can refuel at pump")
				game._interact()
				_check(game.hud.refuel_menu.visible, "refuel menu opened")
				_shot("ride_06_refuel_menu")
				var money := GameState.money
				game.hud.refuel_menu.choose(2)   # full tank
				print("refuel: fuel=", motor.fuel_liters, " paid=", money - GameState.money)
				_check(absf(motor.fuel_liters - motor.get_tank_liters()) < 0.01, "tank is full")
				_check(GameState.money < money, "paid for gas")
				# Out of gas: pushing should be slow
				motor.fuel_liters = 0.0
				motor.place(motor.global_position + Vector3(0, 0, 12), -PI * 0.5)
				Input.action_press("accelerate")
				_next()
		8:
			if _t > 3.0:
				Input.action_release("accelerate")
				print("pushing speed: ", motor.get_speed_kmh(), " km/h")
				_check(motor.get_speed_kmh() > 3.0 and motor.get_speed_kmh() < 7.0, "push speed ~6 km/h")
				_finish()


## Stop the motor on the road right next to an address point.
func _park_at(point: Dictionary) -> void:
	var pos: Vector3 = point["pos"]
	var road_dir: Vector3 = point["road_dir"]
	var along_x := absf(road_dir.z) > 0.5     # east-west road
	var heading := -PI * 0.5 if along_x else 0.0
	motor.place(pos + road_dir * 3.4 + Vector3(0, 0.2, 0), heading)


func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		_fails.append(what)


func _fail(msg: String) -> void:
	_fails.append(msg)
	print("  FAIL  " + msg)
	_finish()


func _finish() -> void:
	print("RIDE TEST DONE: %s" % ("ALL PASSED" if _fails.is_empty() else "FAILED: %s" % ", ".join(_fails)))
	get_tree().quit(0 if _fails.is_empty() else 1)


func _next() -> void:
	_step += 1
	_t = 0.0


func _shot(shot_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return   # no screen to capture when running without a window
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://screenshots/%s.png" % shot_name)
