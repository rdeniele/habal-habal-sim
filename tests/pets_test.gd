extends Node
## Crouch, sneaking up, lifting, petting, adopting, bites, the cat on the scooter.
## Photos -> user://screenshots/pets_*.png      godot --path . res://tests/pets_test.tscn

var game: Node3D
var care: PetCare
var player: Player
var _fails: Array[String] = []
var _spawn: Vector3


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("user://screenshots")
	GameState.reset_new_game()
	GameState.debug_skip_story()
	GameState.time_hours = 9.5
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


## A stray sitting `ahead` meters in front of the spawn point (toward the road).
func _stray(kind: String, ahead: float, coat: int = 3) -> Animal:
	var a := Animal.new()
	game.animals.add_child(a)
	var front: Vector3 = game.world.get_place("home")["front"]
	var p := player.global_position + front * ahead
	p.y = 0.0
	a.setup(kind, p, p, coat)
	a.settle(p, p + front * 10.0, atan2(front.x, front.z))
	a._mood_left = 100.0
	game.animals.animals.append(a)
	return a


## Stand at the spawn point looking toward the road.
func _stand() -> void:
	player.teleport(_spawn)
	var front: Vector3 = game.world.get_place("home")["front"]
	var yaw := atan2(-front.x, -front.z)
	player.face_yaw(yaw)
	game.cam.snap_to(yaw)


func _clear_strays() -> void:
	for a: Animal in game.animals.animals:
		a.queue_free()
	game.animals.animals.clear()


func _run() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await _wait(3.0)
	care = game.pet_care
	player = game.player
	care.bite_chance = 0.0
	game.animals.set_physics_process(true)
	_spawn = player.global_position + (game.world.get_place("home")["front"] as Vector3) * 1.5
	_stand()
	await _wait(0.5)
	_clear_strays()

	# --- crouch ---
	var eye: float = game.cam.global_position.y
	Input.action_press("crouch")
	Input.action_press("move_forward")
	await _wait(0.8)
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	Input.action_release("move_forward")
	_check(player.crouching and speed < 1.4, "Ctrl crouches and creeps (%.1f m/s)" % speed)
	_check(game.cam.global_position.y < eye - 0.3, "camera comes down")
	await _wait(0.5)
	await _shot("pets_1_crouch")

	# --- sneaking up ---
	_stand()
	_clear_strays()
	var cat := _stray("cat", 2.8)
	await _wait(0.4)
	Input.action_press("move_forward")
	await _wait(0.9)
	Input.action_release("move_forward")
	_check(cat.mood != Animal.Mood.FLEE, "stray stays when you creep up")
	Input.action_release("crouch")
	await _wait(0.6)
	_stand()
	_clear_strays()
	var shy := _stray("dog", 3.0)
	await _wait(0.2)
	Input.action_press("move_forward")
	await _wait(0.5)
	Input.action_release("move_forward")
	_check(shy.mood == Animal.Mood.FLEE, "stray runs when you walk up to it")

	# --- lift, pet, adopt a dog ---
	await _wait(0.5)
	_stand()
	_clear_strays()
	var dog := _stray("dog", 1.0, 1)
	await _wait(0.4)
	_check(game.hud._prompt_label.text.contains("Lift the stray dog"), "prompt to lift")
	game._interact()
	_check(care.held == dog and player.carrying, "lifted the stray")
	await _wait(2.2)
	care.caress()
	await _wait(0.5)
	await _shot("pets_2_hold_dog")
	care.adopt()
	_check(dog.pet and GameState.pets.size() == 1, "adopted")
	game._toggle_ride()
	player.teleport(game.motor.global_position + Vector3(-1.0, 0.2, 0))
	care.held = dog
	care.ride_with_held()
	_check(player.state == Player.State.ON_FOOT, "a dog can't ride")
	care.put_down()
	_check(game.animals.pets.has(dog) and dog.global_position.distance_to(game.animals.home_spot(0)) < 0.2, "dog waits outside home")

	# --- a cat: first person, then on the scooter ---
	_stand()
	_clear_strays()
	var kitty := _stray("cat", 1.0, 0)
	await _wait(0.3)
	game.cam.set_view(3)
	care.lift(kitty)
	care.adopt()
	game.cam._pitch = -0.45
	await _wait(0.5)
	await _shot("pets_3_hold_cat_fp")
	# take the motor a little way up the street, away from home
	var front: Vector3 = game.world.get_place("home")["front"]
	var side := Vector3(-front.z, 0, front.x)
	game.motor.place(game.motor.global_position + side * 18.0, atan2(-side.x, -side.z))
	player.teleport(game.motor.global_position + front * 1.2 + Vector3(0, 0.2, 0))
	await _wait(0.3)
	care.ride_with_held()
	await _wait(0.8)
	_check(player.state == Player.State.RIDING and care.cat == kitty and kitty.held == "board", "cat rides in front")
	game.cam._head_pitch = -0.75
	await _wait(0.3)
	game.cam._head_pitch = -0.75
	await _shot("pets_4_cat_board_fp")
	care.on_lap = true
	care._lap_left = 100.0
	await _wait(0.5)
	_check(kitty.held == "lap", "cat on the lap")
	game.cam._head_pitch = -0.85
	await _shot("pets_5_cat_lap_fp")
	game.cam.set_view(2)
	await _wait(0.8)
	game.cam._yaw = game.motor.heading + 1.9
	game.cam._pitch = -0.3
	await _wait(0.4)
	await _shot("pets_6_cat_lap")
	care.on_lap = false
	await _wait(0.5)
	await _shot("pets_7_cat_board")
	Input.action_press("accelerate")
	await _wait(1.2)
	Input.action_release("accelerate")
	_check(care.cat == kitty, "cat stays on while riding")
	game.motor.place(game.world.get_spawn()["motor_pos"], game.world.get_spawn()["motor_heading"])
	game._toggle_ride()
	await _wait(0.5)
	_check(care.cat == null and game.animals.pets.has(kitty), "cat hops off at home")

	# --- pets are saved and come back ---
	var data: Dictionary = JSON.parse_string(JSON.stringify(GameState.to_dict()))
	GameState.from_dict(data)
	_check(GameState.pets.size() == 2 and int(GameState.pets[0]["seed"]) == 1, "pets are saved")
	game.cam.set_view(0)
	player.teleport(game.animals.home_spot(0) + front * 3.2 + Vector3(0, 0.2, 0))
	var look := atan2(front.x, front.z)
	player.face_yaw(look)
	game.cam.snap_to(look)
	await _wait(1.0)
	await _shot("pets_8_home")

	# --- bites ---
	_stand()
	_clear_strays()
	var biter := _stray("dog", 1.0)
	await _wait(0.3)
	care.bite_chance = 1.0
	var health := player.health
	care.lift(biter)
	_check(care.held == null and player.health < health - 10.0 and not game.is_dead, "a bite hurts")
	care.lift(game.animals.pets[0])
	_check(care.held != null, "your own pet never bites")
	care.put_down()
	game.death_chance = 1.0
	_stand()
	var deadly := _stray("cat", 1.0)
	care.lift(deadly)
	_check(game.is_dead, "a bite can kill")
	await _wait(2.6)
	await _shot("pets_9_game_over")
	print("PETS TEST DONE: %s" % ("ALL PASSED" if _fails.is_empty() else "FAILED: " + ", ".join(_fails)))
	get_tree().paused = false
	get_tree().quit()


func _shot(n: String) -> void:
	for i in 4:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("user://screenshots/%s.png" % n)
