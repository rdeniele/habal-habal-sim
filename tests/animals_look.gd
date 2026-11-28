extends Node
## Stray dogs and cats: they spawn, walk / sit / lie, and run from the motor. Photos ->
## user://screenshots/animals_*.png      godot --path . res://tests/animals_look.tscn

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
	game.death_chance = 0.0
	game.traffic.can_hit_player = false
	_run()


func _check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_fails.append(what)


func _run() -> void:
	await get_tree().create_timer(5.0).timeout
	var animals: Animals = game.animals
	_check(animals.animals.size() >= 4, "dogs and cats around (%d)" % animals.animals.size())
	var kinds := {}
	for a in animals.animals:
		kinds[a.kind] = int(kinds.get(a.kind, 0)) + 1
	print("  ", kinds)
	# a line-up next to the player: standing, sitting, lying, walking
	var base: Vector3 = game.player.global_position
	var row: Array[Animal] = []
	var moods := [Animal.Mood.IDLE, Animal.Mood.SIT, Animal.Mood.LIE, Animal.Mood.WALK]
	for i in 8:
		var a := Animal.new()
		animals.add_child(a)
		var p := base + Vector3(-2.8 + (i % 4) * 1.5, 0, -2.5 - (i / 4) * 1.3)
		p.y = 0.0
		a.setup("dog" if i < 4 else "cat", p, p + Vector3(6, 0, 0), 100 + i)
		a._along = 0.0
		a.mood = moods[i % 4]
		a._goal = 6.0 if a.mood == Animal.Mood.WALK else 0.0
		a._mood_left = 100.0
		a.rotation.y = -PI * 0.5
		row.append(a)
	await get_tree().create_timer(1.2).timeout
	game.player.visible = false
	game.motor.visible = false
	for other in animals.animals:
		other.visible = false
	var cam := Camera3D.new()
	cam.fov = 40.0
	game.add_child(cam)
	cam.current = true
	cam.global_position = base + Vector3(-0.4, 1.4, 1.8)
	cam.look_at(base + Vector3(-0.4, 0.25, -3.0))
	await _shot("animals_a_poses")
	var dog := row[0]
	var before := dog.global_position
	dog.scare(before - Vector3(2, 0, 0))
	await get_tree().create_timer(1.0).timeout
	_check(dog.global_position.distance_to(before) > 2.0, "runs away when scared (%.1f m)" % dog.global_position.distance_to(before))
	# the real triggers: get on the motor, honk, then ride past
	game.player.visible = true
	game.motor.visible = true
	game.player.teleport(game.motor.global_position + Vector3(-1.5, 0.2, 0))
	game._toggle_ride()
	await get_tree().create_timer(1.0).timeout
	var cat := _place(animals, "cat", 12.0)
	await get_tree().create_timer(0.5).timeout
	_check(cat.mood != Animal.Mood.FLEE, "stays put while you wait quietly")
	Input.action_press("horn")
	await get_tree().create_timer(0.3).timeout
	Input.action_release("horn")
	_check(cat.mood == Animal.Mood.FLEE, "runs from the horn")
	Input.action_press("accelerate")
	await get_tree().create_timer(1.5).timeout
	var near := _place(animals, "dog", 6.0)
	await get_tree().create_timer(0.2).timeout
	var kmh: float = game.motor.get_speed_kmh()
	_check(near.mood == Animal.Mood.FLEE, "runs from a moving motor (%.0f km/h)" % kmh)
	Input.action_release("accelerate")
	print("ANIMALS TEST DONE: %s" % ("ALL PASSED" if _fails.is_empty() else "FAILED: " + ", ".join(_fails)))
	get_tree().quit()


## A sitting animal on a clear stretch, `away` meters beside the motor.
func _place(animals: Animals, kind: String, away: float) -> Animal:
	var a := Animal.new()
	animals.add_child(a)
	var p: Vector3 = game.motor.global_position + game.motor.global_basis.x * away
	p.y = 0.0
	a.setup(kind, p, p + game.motor.global_basis.x * 10.0, 7)
	a._along = 0.0
	a._goal = 0.0
	a.global_position = p
	a.mood = Animal.Mood.SIT
	a._mood_left = 100.0
	animals.animals.append(a)
	return a


func _shot(n: String) -> void:
	for i in 4:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("user://screenshots/%s.png" % n)
