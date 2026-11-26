extends Node
## Checks the real Bacolod map (Milestone 5): loads, streams chunks, GPS routes on real
## roads, landmarks render, leaving the city turns you around. Saves screenshots + FPS.
## Run:  godot --path . res://tests/map_test.tscn

var game: Node3D
var world: BacolodCity
var motor: Motorcycle
var player: Player
var cam: FollowCamera
var _fails: Array[String] = []


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("user://screenshots")
	GameState.reset_new_game()
	GameState.debug_skip_story()
	var t0 := Time.get_ticks_msec()
	game = (load("res://scenes/main/game.tscn") as PackedScene).instantiate()
	add_child(game)
	print("  game + map loaded in %d ms" % (Time.get_ticks_msec() - t0))
	world = game.world
	motor = game.motor
	player = game.player
	cam = game.cam
	_run()


func _run() -> void:
	await _wait(1.0)
	GameState.time_hours = 10.0
	print("  road graph: %d points, %d segments; %d places, %d addresses, %d food stalls" % [
		world.road_graph.point_count(), world.road_graph.segments.size(), world.places.size(),
		world.address_points.size(), world.food_stalls.size()])
	_check(world.road_graph.segments.size() > 1000, "real road network loaded")
	_check(world.address_points.size() > 200, "pickup/drop-off spots loaded")
	_check(not world.get_place("home").is_empty() and not world.get_place("motor_shop").is_empty()
		and not world.get_place("driving_school").is_empty(), "home, shop and school placed")
	_check(world._loaded.size() > 0, "chunks loaded around home (%d)" % world._loaded.size())

	# Home view
	await _wait(0.5)
	_shot("map_01_home")
	print("  FPS at home: %d" % Engine.get_frames_per_second())

	# GPS route across town
	var plaza := Vector3.ZERO
	var route: PackedVector3Array = world.road_graph.route(player.global_position, plaza)
	var length := RoadGraph.path_length(route)
	var straight := Vector2(player.global_position.x, player.global_position.z).length()
	print("  GPS home -> plaza: %d m along roads (%d m straight), %d points" % [int(length), int(straight), route.size()])
	_check(route.size() > 5 and length > straight and length < straight * 2.5, "GPS route follows real roads")

	# Visit landmarks
	var i := 2
	for lm: Dictionary in world.landmarks:
		var pos := Vector3(float(lm["x"]), 0, float(lm["z"]))
		var view_from := pos + Vector3(55, 30, 55)
		player.teleport(pos + Vector3(40, 0.3, 40))
		world.update_streaming(pos, true)
		# a temporary "drone" camera looking down at the landmark
		var drone := Camera3D.new()
		drone.far = 2000.0
		add_child(drone)
		drone.global_position = view_from
		drone.look_at(pos + Vector3(0, 8, 0))
		drone.current = true
		await _wait(0.6)
		_shot("map_%02d_%s" % [i, lm["id"]])
		drone.queue_free()
		cam.camera.current = true
		i += 1

	# Ride around downtown for a few seconds and measure chunk streaming + FPS
	game.respawn_at_home()
	await _wait(0.3)
	player.teleport(motor.global_position + Vector3(-1.2, 0.2, 0))
	game._toggle_ride()
	Input.action_press("accelerate")
	var frames := 0
	var t := 0.0
	var min_fps := 999
	while t < 6.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		frames += 1
		if t > 1.0:
			min_fps = mini(min_fps, Engine.get_frames_per_second())
	Input.action_release("accelerate")
	print("  riding: avg %.0f fps over %d frames, lowest %d fps, chunks loaded %d" % [frames / t, frames, min_fps, world._loaded.size()])
	_shot("map_08_riding")

	# Full map
	game.hud.toggle_full_map()
	await _wait(0.4)
	_shot("map_09_full_map")
	game.hud.toggle_full_map()

	# Leaving the city
	var r := world.get_map_rect()
	motor.place(Vector3(r.position.x - 200, 0.3, r.get_center().y), 0.0)
	await _until(func() -> bool: return game._returning, 2.0)
	_check(game._returning, "leaving the city is detected")
	await _until(func() -> bool: return not game._returning, 5.0)
	_check(world.is_in_bounds(motor.global_position), "put back inside the city")

	print("MAP TEST DONE: %s" % ("ALL PASSED" if _fails.is_empty() else "FAILED: %s" % ", ".join(_fails)))
	get_tree().quit(0 if _fails.is_empty() else 1)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _until(cond: Callable, timeout: float) -> void:
	var t := 0.0
	while not bool(cond.call()) and t < timeout:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()


func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		_fails.append(what)


func _shot(shot_name: String) -> void:
	get_viewport().get_texture().get_image().save_png("user://screenshots/%s.png" % shot_name)
