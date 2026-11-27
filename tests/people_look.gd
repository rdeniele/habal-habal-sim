extends Node3D
## Photo lineup of characters: the male and female rider (front, side, back) and a row of
## random street people (kids, teens, adults, elders).
##   godot --path . res://tests/people_look.tscn   -> user://screenshots/people_*.png

var cam: Camera3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("user://screenshots")
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("#9fb3c8")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("#c8d0da")
	env.environment.ambient_light_energy = 0.7
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	ground.mesh = pm
	ground.material_override = LowPoly.mat(Color("#8d8f88"))
	add_child(ground)
	cam = Camera3D.new()
	cam.fov = 35.0
	add_child(cam)
	_run()


func _run() -> void:
	# riders: male x3 (front, side, back) and female x3
	var x := -2.5
	for female: bool in [false, true]:
		for turn: float in [0.0, PI * 0.5, PI]:
			var m := CharacterModel.new()
			add_child(m)
			m.build_look(CharacterModel.rider_look(female))
			m.set_helmet(false)
			m.position = Vector3(x, 0, 0)
			m.rotation.y = PI + turn   # face the camera (+Z) first
			x += 1.0
	cam.position = Vector3(0, 1.1, 6.2)
	cam.look_at(Vector3(0, 0.9, 0))
	await _shot("people_riders")
	cam.position = Vector3(-2.0, 1.55, 1.6)
	cam.look_at(Vector3(-2.0, 1.45, 0))
	await _shot("people_rider_face")
	for c in get_children():
		if c is CharacterModel:
			c.queue_free()
	# the vendors (detailed NPC models) next to the sheet's pose
	x = -1.0
	for female: bool in [false, true]:
		var vl := CharacterModel.random_look(RandomNumberGenerator.new(), female, "vendor")
		var vm := CharacterModel.new()
		add_child(vm)
		vm.build_look(vl)
		vm.position = Vector3(x, 0, 0)
		vm.rotation.y = PI
		x += 0.9
	var walker := CharacterModel.make(RandomNumberGenerator.new(), false, "vendor", 0.0, true)   # a template copy
	add_child(walker)
	walker.position = Vector3(1.0, 0, 0)
	walker.rotation.y = PI * 0.5
	for i in 30:
		walker.walk(float(i) * 0.12, 0.5)
		await get_tree().process_frame
	var sitter := CharacterModel.make(RandomNumberGenerator.new(), false, "vendor", 0.0, true)
	add_child(sitter)
	sitter.position = Vector3(2.0, 0.45, 0)
	sitter.rotation.y = PI * 0.75
	sitter.pose_sit(0.7)   # like a passenger on the back seat
	cam.position = Vector3(0.5, 1.1, 4.6)
	cam.look_at(Vector3(0.5, 0.85, 0))
	await _shot("people_vendors")
	for c in get_children():
		if c is CharacterModel:
			c.queue_free()
	# Nanay (A-pose model): standing, walking, sitting
	for i in 3:
		var nm := CharacterModel.new()
		add_child(nm)
		nm.build_look({"body": "female", "hair": "bun", "age": "old", "height": 1.0, "helmet": Color(0, 0, 0, 0),
			"model": "res://assets/characters/npc/nanay.glb"})
		nm.position = Vector3(-1.1 + i * 1.1, 0.45 if i == 2 else 0.0, 0)
		nm.rotation.y = [PI, PI * 0.5, PI * 0.7][i]
		if i == 1:
			for k in 20:
				nm.walk(1.2, 0.45)
				await get_tree().process_frame
		elif i == 2:
			nm.pose_sit(0.7)
	cam.position = Vector3(0, 1.1, 4.2)
	cam.look_at(Vector3(0, 0.85, 0))
	await _shot("people_nanay")
	for c in get_children():
		if c is CharacterModel:
			c.queue_free()
	# random street people
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	x = -4.2
	var ages := {}
	for i in 12:
		var female := i % 2 == 1
		var look := CharacterModel.random_look(rng, female, "", true)
		ages[look["age"]] = int(ages.get(look["age"], 0)) + 1
		var m := CharacterModel.new()
		add_child(m)
		m.build_look(look)
		m.position = Vector3(x, 0, 0)
		m.rotation.y = PI
		x += 0.76
	print("ages: ", ages)
	cam.position = Vector3(0, 1.2, 8.2)
	cam.look_at(Vector3(0, 0.8, 0))
	await _shot("people_crowd")
	get_tree().quit()


func _shot(n: String) -> void:
	for i in 8:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("user://screenshots/%s.png" % n)
	print("  saved ", n)
