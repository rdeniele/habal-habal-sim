extends Node3D
## Character "photo studio": lines up the new characters and saves screenshots.
## Run:  godot --path . res://tests/character_test.tscn

const KINDS := ["student", "tita", "office", "worker", "tourist", "nurse", "lola", "teen", "seaman", "vendor"]

var cam: Camera3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("user://screenshots")
	# Simple studio: ground, sun, sky
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#9ec9e6")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.78, 0.82)
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 150, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	add_child(sun)
	LowPoly.box(self, Vector3(40, 0.1, 40), Color("#c9c5bb"), Vector3(0, -0.05, 0))
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	cs.shape = box
	cs.position = Vector3(0, -0.5, 0)
	floor_body.add_child(cs)
	add_child(floor_body)

	cam = Camera3D.new()
	cam.fov = 40
	add_child(cam)
	cam.current = true
	_run()


func _run() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	# 1) Lineup of passenger types (they face -Z, so the camera stands at -Z looking +Z)
	for i in KINDS.size():
		var kind: String = KINDS[i]
		var p := Passenger.new()
		add_child(p)
		var female := Passenger.is_female_for(kind, rng) if kind in ["tita", "lola", "worker", "seaman"] else i % 2 == 0
		p.build(rng, kind, kind, female)
		p.position = Vector3(-4.5 + i * 1.0, 0, 0)
		p.state = Passenger.State.READY
	cam.position = Vector3(0, 1.3, -9.0)
	cam.look_at(Vector3(0, 0.95, 0))
	await _wait(0.4)
	_shot("char_01_lineup")

	# 2) Face close-up of two people
	cam.fov = 25
	cam.position = Vector3(-3.5, 1.66, -1.1)
	cam.look_at(Vector3(-3.5, 1.6, 0))
	await _wait(0.2)
	_shot("char_02_faces")

	# 3) Walking pose + rider and passenger on a motor
	for c in get_children():
		if c is Passenger:
			c.queue_free()
	await _wait(0.1)
	var walker := CharacterModel.new()
	add_child(walker)
	walker.build_look(CharacterModel.random_look(rng, true, "teen"))
	walker.position = Vector3(-2.0, 0, 0)
	walker.walk(1.2, 1.0)
	var walker2 := CharacterModel.new()
	add_child(walker2)
	walker2.build_look(CharacterModel.random_look(rng, false, "worker"))
	walker2.position = Vector3(-1.0, 0, 0)
	walker2.walk(4.0, 1.0)
	var motor := (load("res://scenes/player/motorcycle.tscn") as PackedScene).instantiate() as Motorcycle
	add_child(motor)
	motor.set_ridden(true)
	motor.place(Vector3(1.2, 0, 0), PI * 0.5)   # side view
	var pas := Passenger.new()
	add_child(pas)
	pas.build(rng, "Maria", "tita", true)
	pas.sit_on(motor.get_seat_mount(), Motorcycle.PASSENGER_SEAT)
	cam.fov = 40
	cam.position = Vector3(0, 1.4, -6.5)
	cam.look_at(Vector3(0, 0.9, 0))
	await _wait(0.6)
	_shot("char_03_walk_and_ride")
	print("CHARACTER TEST DONE")
	get_tree().quit()


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _shot(n: String) -> void:
	get_viewport().get_texture().get_image().save_png("user://screenshots/%s.png" % n)
