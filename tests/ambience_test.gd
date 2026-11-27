extends Node
## Checks the in-game sound: no music, nature layers fade by time / speed / the sea,
## and birds / roosters / dogs / geckos really play.   godot --path . res://tests/ambience_test.tscn

var game: Node3D
var _fails: Array[String] = []


func _ready() -> void:
	GameState.reset_new_game()
	GameState.debug_skip_story()
	GameState.time_hours = 6.5
	game = (load("res://scenes/main/game.tscn") as PackedScene).instantiate()
	add_child(game)
	_run()


func _check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_fails.append(what)


func _db(amb: Ambience, layer: String) -> float:
	return (amb.get("_layers")[layer] as BackgroundAudio).target_db


func _run() -> void:
	await get_tree().create_timer(3.0).timeout
	var amb: Ambience = game.get("_ambience")
	_check(amb != null, "ambience is running")
	var music := 0
	for n in game.find_children("*", "AudioStreamPlayer", true, false):
		if (n as AudioStreamPlayer).bus == "Music" and (n as AudioStreamPlayer).playing:
			music += 1
	_check(music == 0, "no music in the game")
	var night_morning := _db(amb, "night")
	_check(night_morning < -40.0, "no crickets in the morning (%.0f dB)" % night_morning)
	var wind_still := _db(amb, "wind")
	# count one-shots for a while in the morning
	var played := 0
	var shots: Array = amb.get("_shots")
	for i in 40:
		await get_tree().create_timer(0.25).timeout
		for p: AudioStreamPlayer3D in shots:
			if p.playing:
				played += 1
	_check(played > 0, "birds / roosters heard in the morning")
	# riding fast: wind up
	game.call("_mount")
	game.motor.speed = 16.0
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_db(amb, "wind") > wind_still + 8.0, "wind louder when riding fast (%.0f -> %.0f dB)" % [wind_still, _db(amb, "wind")])
	# night
	GameState.time_hours = 22.0
	await get_tree().create_timer(0.3).timeout
	_check(_db(amb, "night") > -20.0, "crickets at night (%.0f dB)" % _db(amb, "night"))
	_check(_db(amb, "city") < -18.0, "city quieter at night (%.0f dB)" % _db(amb, "city"))
	var sea: PackedVector2Array = game.world.get_sea_polygon()
	if sea.size() >= 3:
		var c := Vector3(sea[0].x, 0, sea[0].y)
		var d: float = amb.call("_distance_to_sea", c + Vector3(0, 0, 0))
		_check(d < 5.0, "the sea is found at the coast (%.1f m)" % d)
	print("  sea distance %.0f m, sea %.0f dB" % [amb.get("_sea_dist"), _db(amb, "sea")])
	print("AMBIENCE TEST DONE: %s" % ("ALL PASSED" if _fails.is_empty() else "FAILED: " + ", ".join(_fails)))
	get_tree().quit()
