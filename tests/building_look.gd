extends Node
## Street photos of the buildings, day and night.  godot --path . res://tests/building_look.tscn
##   -> user://screenshots/buildings_*.png

var game: Node3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("user://screenshots")
	GameState.reset_new_game()
	GameState.debug_skip_story()
	GameState.time_hours = 10.0
	game = (load("res://scenes/main/game.tscn") as PackedScene).instantiate()
	add_child(game)
	_run()


func _run() -> void:
	await get_tree().create_timer(5.0).timeout
	game.day_cycle.set_process(false)
	var cam := Camera3D.new()
	cam.fov = 65.0
	cam.far = 1500.0
	game.add_child(cam)
	cam.current = true
	var p: Vector3 = game.player.global_position
	var g: RoadGraph = game.world.road_graph
	var near := g.point_ids_near(p, 120.0)
	var id: int = near[0] if not near.is_empty() else -1
	var dir := Vector3(0, 0, -1)
	var base := p
	if id >= 0:
		base = g.get_point(id)
		dir = (g.get_point(g.neighbors(id)[0]) - base).normalized()
	cam.global_position = base + Vector3(0, 2.2, 0)
	cam.look_at(base + dir * 20.0 + Vector3(0, 3.0, 0))
	await _shot("buildings_a_street")
	var side := Vector3(-dir.z, 0, dir.x)
	cam.look_at(base + dir * 6.0 + side * 9.0 + Vector3(0, 2.5, 0))
	await _shot("buildings_b_front")
	cam.global_position = base + Vector3(0, 28.0, 0) - dir * 30.0
	cam.look_at(base + dir * 25.0)
	await _shot("buildings_c_above")
	game.day_cycle.set_process(true)
	GameState.time_hours = 20.5
	await get_tree().create_timer(2.0).timeout
	cam.global_position = base + Vector3(0, 2.2, 0)
	cam.look_at(base + dir * 20.0 + Vector3(0, 3.0, 0))
	await _shot("buildings_d_night")
	get_tree().quit()


func _shot(n: String) -> void:
	for i in 10:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("user://screenshots/%s.png" % n)
	print("  saved ", n)
