extends Node
## Close-up photos of the player's scooter in the game (day, handlebar turned, night).
##   godot --path . res://tests/scooter_check.tscn   -> user://screenshots/scooter_*.png

var game: Node3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("user://screenshots")
	GameState.reset_new_game()
	GameState.debug_skip_story()
	GameState.time_hours = 9.5
	Settings.camera_view = 0   # third person so the rider shows (not saved)
	game = (load("res://scenes/main/game.tscn") as PackedScene).instantiate()
	add_child(game)
	game.death_chance = 0.0   # (test) accidents never end the game
	game.traffic.can_hit_player = false
	_run()


func _run() -> void:
	var motor: Motorcycle = game.motor
	# use the motor's own parking spot; move the player out of the picture
	game.player.teleport(motor.global_position + Vector3(0, 0.3, 12))
	await get_tree().create_timer(2.0).timeout
	print("motor at ", motor.global_position, " on floor: ", motor.is_on_floor())
	motor.set_physics_process(false)
	game.day_cycle.set_process(false)
	var cam := Camera3D.new()
	cam.fov = 40.0
	game.add_child(cam)
	cam.current = true
	var p := motor.global_position
	var fwd := motor.get_forward()
	var right := fwd.cross(Vector3.UP)
	cam.global_position = p + fwd * 2.2 + right * 1.6 + Vector3(0, 1.1, 0)
	cam.look_at(p + Vector3(0, 0.55, 0))
	await _shot("scooter_a_front")
	cam.global_position = p - fwd * 2.4 - right * 1.4 + Vector3(0, 1.3, 0)
	cam.look_at(p + Vector3(0, 0.55, 0))
	await _shot("scooter_b_rear")
	game.call("_mount")
	await get_tree().create_timer(0.5).timeout
	motor.set_physics_process(false)
	motor.get_node("LeanPivot/Scooter").find_child("Fork", true, false).rotation.y = 0.4
	cam.global_position = p + right * 2.6 + fwd * 0.6 + Vector3(0, 1.0, 0)
	cam.look_at(p + Vector3(0, 0.7, 0))
	await _shot("scooter_c_rider_steer")
	# the female rider (as if picked at the license desk)
	GameState.player_female = true
	game.player.refresh_look()
	motor.refresh_rider()
	await _shot("scooter_c2_rider_female")
	cam.global_position = p + fwd * 2.4 - right * 1.2 + Vector3(0, 1.5, 0)
	cam.look_at(p + Vector3(0, 1.0, 0))
	await _shot("scooter_c3_rider_front")
	# first person: the camera at the rider's eyes, the body and hands stay visible
	for female: bool in [true, false]:
		GameState.player_female = female
		game.player.refresh_look()
		motor.refresh_rider()
		motor.set_fp_hidden(true)
		for i in 3:
			await get_tree().process_frame
		var eye := motor.get_head_position()
		cam.fov = 75.0
		cam.global_position = eye
		cam.look_at(eye + fwd * 2.0 + Vector3(0, -0.9, 0))
		await _shot("scooter_e_fp_%s" % ("female" if female else "male"))
		motor.set_fp_hidden(false)
		cam.fov = 40.0
	GameState.time_hours = 20.5
	game.day_cycle.set_process(true)
	motor.set_headlight(true)
	cam.global_position = p + fwd * 3.0 + right * 1.2 + Vector3(0, 1.3, 0)
	cam.look_at(p + Vector3(0, 0.6, 0))
	await get_tree().create_timer(1.5).timeout
	await _shot("scooter_d_night")
	get_tree().quit()


func _shot(n: String) -> void:
	for i in 10:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("user://screenshots/%s.png" % n)
	print("  saved ", n)
