extends Node
## Crash with a customer and your cat aboard: both go limp, run away, one-star review,
## the cat ends up home. Photos -> user://screenshots/crash_*.png
##   godot --path . res://tests/crash_riders_test.tscn

var game: Node3D
var _fails: Array[String] = []


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("user://screenshots")
	GameState.reset_new_game()
	GameState.debug_skip_story()
	GameState.time_hours = 9.5
	GameState.pets = [{"kind": "cat", "seed": 0}]
	Settings.camera_view = 0   # (not saved)
	game = (load("res://scenes/main/game.tscn") as PackedScene).instantiate()
	add_child(game)
	game.death_chance = 0.0
	game.traffic.can_hit_player = false
	_run()


func _check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_fails.append(what)


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _run() -> void:
	await _wait(3.0)
	var player: Player = game.player
	var motor: Motorcycle = game.motor
	var care: PetCare = game.pet_care
	var booking: BookingSystem = game.booking
	var home: Dictionary = game.world.get_place("home")
	var front: Vector3 = home["front"]
	var side := Vector3(-front.z, 0, front.x)
	motor.place((home["door"] as Vector3) + front * 5.0 + side * 22.0 + Vector3(0, 0.2, 0), atan2(-side.x, -side.z))
	player.teleport(motor.global_position + front * 1.2)
	await _wait(0.5)
	var kitty: Animal = game.animals.pets[0]
	care.lift(kitty)
	care.ride_with_held()
	# a customer on the back seat
	booking.go_online_now()
	booking._next_request_in = 0.1
	await _wait(1.0)
	booking.accept()
	await _wait(0.3)
	booking._start_boarding()
	booking._on_passenger_reached_motor()
	var rider: Passenger = booking._passenger
	await _wait(0.5)
	var rating := GameState.rating
	_check(care.cat == kitty and motor.passenger == rider, "customer and cat aboard")

	motor.speed = 12.0
	game.call("_on_motor_crashed", 12.0, motor.global_transform.basis.z)
	await _wait(0.3)
	_check(rider.model.is_ragdoll(), "customer goes limp")
	_check(kitty.held == "tumble" and care.cat == null, "cat goes flying")
	var start := kitty.global_position
	var cam := Camera3D.new()
	cam.fov = 55.0
	game.add_child(cam)
	cam.current = true
	var focus := motor.global_position
	cam.global_position = focus + front * 5.5 + Vector3(0, 2.6, 0)
	cam.look_at(focus + Vector3(0, 0.4, 0))
	await _shot("crash_1_flying")
	await _wait(0.9)
	_check(kitty.global_position.y < 0.35 and kitty.global_position.distance_to(start) > 0.5, "cat lands")
	await _shot("crash_2_down")
	await _wait(1.9)
	var at := rider.global_position
	await _shot("crash_3_running")
	await _wait(0.5)
	_check(rider.fleeing and not rider.model.is_ragdoll() and rider.global_position.distance_to(at) > 1.5,
		"customer gets up and runs (%.1f m in 0.5 s)" % rider.global_position.distance_to(at))
	_check(game.hud._toast_label.text.contains("left a review"), "review shown: " + game.hud._toast_label.text.replace("\n", " "))
	_check(GameState.rating < rating, "rating went down (%.2f -> %.2f)" % [rating, GameState.rating])
	cam.current = false
	game.cam.camera.current = true
	await _shot("crash_4_review")
	await _wait(3.0)
	_check(kitty.held == "" and kitty.global_position.distance_to(game.animals.home_spot(0)) < 0.3, "cat ran home")
	print("CRASH RIDERS TEST DONE: %s" % ("ALL PASSED" if _fails.is_empty() else "FAILED: " + ", ".join(_fails)))
	get_tree().quit()


func _shot(n: String) -> void:
	for i in 3:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("user://screenshots/%s.png" % n)
