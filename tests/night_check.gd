extends Node
## Night lighting check: the same aerial view at 20:30, saved with the night glow on and off
## (and with the moonlight off), to find what makes rooftops look too bright.
##   godot --path . res://tests/night_check.tscn

var game: Node3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("user://screenshots")
	GameState.reset_new_game()
	GameState.debug_skip_story()
	GameState.time_hours = 20.5
	game = (load("res://scenes/main/game.tscn") as PackedScene).instantiate()
	add_child(game)
	_run()


func _run() -> void:
	var plaza := Vector3(-190, 0, 138)
	game.world.update_streaming(plaza, true)
	game.player.teleport(plaza + Vector3(20, 0.3, 0))
	var cam := Camera3D.new()
	cam.far = 2500.0
	game.add_child(cam)
	cam.current = true
	cam.global_position = plaza + Vector3(100, 60, 100)
	cam.look_at(plaza)
	await get_tree().create_timer(4.0).timeout
	var env: Environment = game.world.environment
	print("night: sun energy %.2f, ambient %.2f, glow %s (intensity %.2f, bloom %.2f), fog %.4f" % [
		game.world.sun.light_energy, env.ambient_light_energy, env.glow_enabled, env.glow_intensity, env.glow_bloom, env.fog_density])
	await _shot("night_a_normal")
	game.day_cycle.set_process(false)
	env.glow_enabled = false
	await _shot("night_b_no_glow")
	env.glow_enabled = true
	game.world.sun.light_energy = 0.0
	await _shot("night_c_no_moonlight")
	game.world.sun.light_energy = 0.22
	env.ambient_light_energy = 0.0
	await _shot("night_d_no_ambient")
	env.ambient_light_energy = 0.29
	game.world.set_night_glow(0.0)
	await _shot("night_e_no_wall_glow")
	game.world.set_night_glow(1.0)
	var mw: StandardMaterial3D = game.world.get("_mat_wall")
	print("wall material: emission %s energy %.2f tex %s, albedo tex %s, vcolor %s" % [mw.emission, mw.emission_energy_multiplier,
		mw.emission_texture != null, mw.albedo_texture != null, mw.vertex_color_use_as_albedo])
	get_tree().quit()


func _shot(n: String) -> void:
	for i in 10:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("user://screenshots/%s.png" % n)
	print("  saved ", n)
