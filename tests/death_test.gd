extends Node
## Accidents can kill: crash, car hit and lost fight, each with a 100% and a 0% death chance.
##   godot --path . res://tests/death_test.tscn

var game: Node3D
var _fails: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute("user://screenshots")
	_run()


func _check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_fails.append(what)


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _new_game(chance: float) -> void:
	get_tree().paused = false
	if game != null:
		game.queue_free()
		await _wait(0.5)
	GameState.reset_new_game()
	GameState.debug_skip_story()
	GameState.time_hours = 9.5
	game = (load("res://scenes/main/game.tscn") as PackedScene).instantiate()
	game.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(game)
	game.death_chance = chance
	await _wait(2.5)


func _over() -> GameOver:
	for c in game.get_children():
		if c is GameOver:
			return c
	return null


func _crash() -> void:
	game.call("_mount")
	await _wait(0.4)
	game.call("_on_motor_crashed", 12.0, game.motor.global_transform.basis.z)


func _run() -> void:
	await _new_game(0.0)
	await _crash()
	await _wait(2.2)
	_check(not game.is_dead and _over() == null, "0% chance: you survive a crash")

	await _new_game(1.0)
	GameState.debt = 1050
	var shot_hud := get_viewport()
	for i in 5:
		await get_tree().process_frame
	shot_hud.get_texture().get_image().save_png("user://screenshots/gas_on_foot.png")
	await _crash()
	await _wait(2.6)
	_check(game.is_dead and _over() != null and get_tree().paused, "a deadly crash shows Game Over")
	_check("Your Nanay is left with your debt of ₱1,050." in GameOver.guilt_lines(), "debt is blamed on Nanay")
	await get_tree().create_timer(7.0).timeout
	get_viewport().get_texture().get_image().save_png("user://screenshots/game_over.png")

	await _new_game(1.0)
	var car: TrafficVehicle = null
	for v: TrafficVehicle in game.traffic.vehicles:
		if v.crash_time <= 0.0:
			car = v
			break
	_check(car != null, "found a car")
	if car != null:
		car.stopped_for_rage = false
		car.speed = 8.0
		game.player.teleport(car.global_position + car.forward() * (car.length * 0.5 + 0.3) + Vector3(0, 0.1, 0))
		game.traffic.check_hit_player(car)
		await _wait(2.4)
		_check(game.is_dead and _over() != null, "a car hitting you can kill you")

	await _new_game(1.0)
	game.combat.fight_lost.emit()
	await _wait(2.4)
	_check(game.is_dead and _over() != null, "losing a fist fight can kill you")

	for chance: float in [0.0, 1.0]:
		await _new_game(chance)
		await _wait(1.0)
		var people := game.find_children("*", "Pedestrian", true, false)
		_check(not people.is_empty(), "found a pedestrian")
		if people.is_empty():
			continue
		var ped := people[0] as Pedestrian
		game.player.teleport(ped.global_position + Vector3(3, 0.3, 3))
		game.call("_on_hit_person", ped, 9.0)
		await _wait(4.5)
		if chance == 0.0:
			_check(is_instance_valid(ped) and not ped.dead and ped.knocked <= 0.0, "0%: the pedestrian gets back up")
		else:
			_check(is_instance_valid(ped) and ped.dead and ped.model.is_ragdoll(), "a hit pedestrian can die and stays down")
			ped.knocked = 0.05
			await _wait(0.5)
			_check(not is_instance_valid(ped), "the body is cleared away later")

	var p := Passenger.new()
	game.add_child(p)
	p.build(RandomNumberGenerator.new(), "Test", "", false)
	p.get_off_and_leave(game, game.player.global_position + Vector3(2, 0, 0), game.player.global_position)
	p.fall(Vector3(2, 3, 0), true)
	await _wait(3.0)
	_check(is_instance_valid(p) and p.dead and p.model.is_ragdoll(), "a thrown passenger can die")

	await _new_game(1.0)
	game.story.active = true
	game.call("_on_fight_lost")
	_check(not game.is_dead, "nobody dies during the tutorial")
	get_tree().paused = false
	print("DEATH TEST DONE: %s" % ("ALL PASSED" if _fails.is_empty() else "FAILED: " + ", ".join(_fails)))
	get_tree().quit()
