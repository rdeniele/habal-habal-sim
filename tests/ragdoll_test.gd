extends Node
## Crash the motor and hit a pedestrian: the rider and the person go limp, stay above the
## ground, and get back up. Photos -> user://screenshots/ragdoll_*.png
##   godot --path . res://tests/ragdoll_test.tscn

var game: Node3D
var _fails: Array[String] = []


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("user://screenshots")
	GameState.reset_new_game()
	GameState.debug_skip_story()
	GameState.time_hours = 9.5
	Settings.camera_view = 0   # (not saved)
	game = (load("res://scenes/main/game.tscn") as PackedScene).instantiate()
	add_child(game)
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
	game.call("_mount")
	await _wait(0.5)
	motor.speed = 12.0
	game.call("_on_motor_crashed", 12.0, motor.global_transform.basis.z)
	var model := player.get_model()
	_check(model.is_ragdoll(), "rider goes limp in a crash")
	var start := model.ragdoll_ground_position()
	await _wait(0.35)
	await _shot("ragdoll_a_flying")
	await _wait(0.9)
	var points: Dictionary = model.ragdoll_points()
	var low := 999.0
	var high := -999.0
	for p: Vector3 in points.values():
		low = minf(low, p.y)
		high = maxf(high, p.y)
	var ground := model.ragdoll_ground_position().y
	_check(low > ground - 0.1, "nothing sinks into the ground (lowest %.2f above)" % (low - ground))
	_check(high - ground < 1.0, "the body ends up lying down (highest %.2f above)" % (high - ground))
	_check(model.ragdoll_ground_position().distance_to(start) > 0.3, "the body was thrown")
	await _shot("ragdoll_b_down")
	await _wait(2.0)
	_check(not model.is_ragdoll() and player.state == Player.State.ON_FOOT, "gets back up and can walk")
	_check(absf(model.position.y) < 0.02 and absf(model.rotation.x) < 0.05, "standing straight again")

	var person := Pedestrian.new()
	var near: Pedestrian = null
	for p in game.find_children("*", "Pedestrian", true, false):
		near = p as Pedestrian
		break
	person.free()
	if near != null:
		player.teleport(near.global_position + Vector3(3, 0.3, 3))
		await _wait(0.3)
		near.knock(8.0, Vector3(7, 0, 0))
		_check(near.model.is_ragdoll(), "a pedestrian goes limp when hit")
		await _wait(0.5)
		var cam := Camera3D.new()
		game.add_child(cam)
		cam.current = true
		cam.global_position = near.model.ragdoll_ground_position() + Vector3(2.5, 1.8, 2.5)
		cam.look_at(near.model.ragdoll_ground_position() + Vector3(0, 0.3, 0))
		await _shot("ragdoll_c_pedestrian")
		await _wait(4.5)
		_check(not near.model.is_ragdoll() and near.knocked <= 0.0, "the pedestrian gets back up")
	else:
		_check(false, "found a pedestrian")
	print("RAGDOLL TEST DONE: %s" % ("ALL PASSED" if _fails.is_empty() else "FAILED: " + ", ".join(_fails)))
	get_tree().quit()


func _shot(n: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("user://screenshots/%s.png" % n)
