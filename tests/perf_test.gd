extends Node
## Performance check: rides through Bacolod with traffic and people, V-Sync off,
## and reports frame times (average, slowest 5%, worst), draw calls and object counts.
## Run:  godot --path . res://tests/perf_test.tscn

const RIDE_SECONDS := 20.0

var game: Node3D
var motor: Motorcycle
var player: Player
var _times: Array[float] = []


func _ready() -> void:
	GameState.reset_new_game()
	GameState.debug_skip_story()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	game = (load("res://scenes/main/game.tscn") as PackedScene).instantiate()
	add_child(game)
	game.death_chance = 0.0   # (test) accidents never end the game
	game.traffic.can_hit_player = false
	motor = game.motor
	player = game.player
	_run()


func _run() -> void:
	GameState.time_hours = 8.0   # rush hour = the most traffic
	await get_tree().create_timer(3.0).timeout
	player.teleport(motor.global_position + Vector3(-1.2, 0.2, 0))
	game._toggle_ride()
	# simple autopilot toward the plaza along the GPS route
	var route: PackedVector3Array = game.world.road_graph.route(motor.global_position, Vector3.ZERO)
	var idx := 1
	var t := 0.0
	var draw_calls := 0
	var objects := 0
	while t < RIDE_SECONDS:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		t += dt
		_times.append(dt * 1000.0)
		if dt * 1000.0 > 18.0:
			print("  slow frame %.1f ms at t=%.1f s  (vehicles %d, people %d, chunks %d, building tasks %d)" % [
				dt * 1000.0, t, game.traffic.vehicles.size(), game.pedestrians.people.size(),
				game.world._loaded.size(), game.world._tasks.size()])
		draw_calls = maxi(draw_calls, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		objects = maxi(objects, int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)))
		# steer toward the next route point
		while idx < route.size() - 1 and Vector2(route[idx].x - motor.global_position.x, route[idx].z - motor.global_position.z).length() < 6.0:
			idx += 1
		var to := route[idx] - motor.global_position
		var want := atan2(-to.x, -to.z)
		var diff := wrapf(want - motor.heading, -PI, PI)
		Input.action_release("steer_left")
		Input.action_release("steer_right")
		if diff > 0.08:
			Input.action_press("steer_left")
		elif diff < -0.08:
			Input.action_press("steer_right")
		Input.action_press("accelerate")
		if player.state != Player.State.RIDING:
			player.teleport(motor.global_position + Vector3(-1.2, 0.2, 0))
			game._toggle_ride()
	Input.action_release("accelerate")
	_times.sort()
	var n := _times.size()
	var avg := 0.0
	for x in _times:
		avg += x
	avg /= n
	print("PERF: %d frames in %.0f s  |  avg %.1f ms (%.0f fps)  |  slowest 5%%: %.1f ms  |  worst %.1f ms" % [
		n, RIDE_SECONDS, avg, 1000.0 / avg, _times[int(n * 0.95)], _times[n - 1]])
	print("PERF: max draw calls %d, max objects %d, nodes %d, vehicles %d, people %d, chunks %d" % [
		draw_calls, objects, Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		game.traffic.vehicles.size(), game.pedestrians.people.size(), game.world._loaded.size()])
	get_tree().quit()
