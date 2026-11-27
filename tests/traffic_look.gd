extends Node
## Photos of the traffic vehicles in the game: one close-up per kind (car, jeepney, tricycle,
## motorbike) plus a street view.   godot --path . res://tests/traffic_look.tscn
##   -> user://screenshots/traffic_*.png

var game: Node3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("user://screenshots")
	GameState.reset_new_game()
	GameState.debug_skip_story()
	GameState.time_hours = 8.5
	game = (load("res://scenes/main/game.tscn") as PackedScene).instantiate()
	add_child(game)
	_run()


func _run() -> void:
	await get_tree().create_timer(5.0).timeout
	game.day_cycle.set_process(false)
	var cam := Camera3D.new()
	cam.fov = 45.0
	game.add_child(cam)
	cam.current = true
	var done := {}
	var shots := 0
	for v: TrafficVehicle in game.traffic.vehicles:
		var kind: String = v.kind
		var count: int = done.get(kind, 0)
		if count >= (3 if kind == "car" else 1):
			continue
		done[kind] = count + 1
		v.process_mode = Node.PROCESS_MODE_DISABLED
		var b := v.global_transform.basis
		var fwd := -b.z
		var right := b.x
		var size: float = v.length
		cam.global_position = v.global_position + fwd * size * 0.9 + right * size * 0.75 + Vector3(0, size * 0.35 + 0.8, 0)
		cam.look_at(v.global_position + Vector3(0, 0.8, 0))
		await _shot("traffic_%s_%d" % [kind, count])
		v.process_mode = Node.PROCESS_MODE_INHERIT
		shots += 1
	print("kinds seen: ", done)
	get_tree().quit()


func _shot(n: String) -> void:
	for i in 6:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("user://screenshots/%s.png" % n)
	print("  saved ", n)
