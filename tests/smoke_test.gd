extends Node
## Automated smoke test: loads the game, gets on the motor, rides, steers, crashes,
## and saves screenshots to user://screenshots/. Prints results to the console.
## Run:  godot --path . res://tests/smoke_test.tscn

var game: Node3D
var _t := 0.0
var _step := 0
var _shots_dir := "user://screenshots"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(_shots_dir)
	GameState.debug_skip_story()   # tests start after the tutorial
	game = (load("res://scenes/main/game.tscn") as PackedScene).instantiate()
	add_child(game)


func _physics_process(delta: float) -> void:
	_t += delta
	var motor: Motorcycle = game.motor
	var player: Player = game.player
	match _step:
		0:
			if _t > 1.5:
				_shot("01_spawn")
				print("spawn player=", player.global_position, " motor=", motor.global_position,
					" dist=", player.global_position.distance_to(motor.global_position))
				# walk up to the motor (teleport for the test)
				player.teleport(motor.global_position + Vector3(-1.5, 0.2, 0))
				game._toggle_ride()
				print("mounted: ", player.state == Player.State.RIDING)
				Input.action_press("accelerate")
				_next()
		1:
			if _t > 4.0:
				print("after 4s gas: speed=", motor.get_speed_kmh(), " km/h pos=", motor.global_position)
				_shot("02_riding")
				Input.action_press("steer_left")
				_next()
		2:
			if _t > 1.0:
				print("turning: lean=", motor.get_node("LeanPivot").rotation.z, " heading=", motor.heading)
				_shot("03_turning")
				Input.action_release("steer_left")
				_next()
		3:
			# Keep riding straight until we hit something (or give up)
			if player.state != Player.State.RIDING:
				print("crashed after ", _t, "s, state=", player.state, " damage=", motor.damage)
				_next()
			elif _t > 12.0:
				print("no crash within 12s, speed=", motor.get_speed_kmh(), " pos=", motor.global_position)
				_next()
		4:
			if _t > 0.8:
				_shot("04_after_crash")
				Input.action_release("accelerate")
				_next()
		5:
			if _t > 3.0:
				print("player state after getting up: ", player.state, " health=", player.health)
				_shot("05_standing")
				print("SMOKE TEST DONE")
				get_tree().quit()


func _next() -> void:
	_step += 1
	_t = 0.0


func _shot(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_shots_dir, name]
	img.save_png(path)
	print("screenshot: ", ProjectSettings.globalize_path(path))
