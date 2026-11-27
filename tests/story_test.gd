extends Node
## Plays the whole story/tutorial automatically (Milestone 3):
## clicks through dialogs, teleports the motor to each lesson ring / checkpoint,
## gets the license, tries to buy a motor it can't afford, then buys one.
## Screenshots: user://screenshots/story_*.png
## Run:  godot --path . res://tests/story_test.tscn

const TIMEOUT := 150.0

var game: Node3D
var hud: HUD
var story: Story
var player: Player
var motor: Motorcycle
var _t := 0.0
var _cooldown := 0.0
var _shots := {}
var _tried_expensive := false
var _checked_ground := false
var _fails: Array[String] = []
var _done := false


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("user://screenshots")
	game = (load("res://scenes/main/game.tscn") as PackedScene).instantiate()
	add_child(game)
	game.death_chance = 0.0   # (test) accidents never end the game
	game.traffic.can_hit_player = false
	hud = game.hud
	story = game.story
	player = game.player
	motor = game.motor


func _physics_process(delta: float) -> void:
	if _done:
		return
	_t += delta
	_cooldown -= delta
	if _t > TIMEOUT:
		_fails.append("timed out at objective: " + hud._objective_text.text)
		_finish()
		return
	if _cooldown > 0.0:
		return
	_cooldown = 0.35

	# Story finished: Day 1 started -> go online ends the tutorial.
	if GameState.story_done and story.active and not hud.dialog_box.is_open:
		_shot_once("story_09_day1")
		game.booking.go_online_now()
		return
	if GameState.story_done and not story.active:
		_final_checks()
		return

	if hud.license_card.visible:
		_shot_once("story_06_license")
		hud.license_card._shown_msec = 0
		hud.license_card._dismiss()
		return

	if hud.shop.visible:
		_shot_once("story_07_shop")
		if not _tried_expensive:
			_tried_expensive = true
			var before := GameState.money
			hud.shop.purchase.emit("honda_beat", 0, "buy")   # too expensive after the license fee
			_check(hud.shop.visible and GameState.money == before, "can't buy a motor you can't afford")
		else:
			hud.shop.purchase.emit("honda_navi", 1, "buy")
		return

	var d := hud.dialog_box
	if d.is_open:
		match d._mode:
			"say":
				_shot_once("story_01_intro")
				d._finish()
				d.advanced.emit()
			"choose":
				d._pick(0)   # full tutorial
			"text":
				_shot_once("story_05_name")
				d._submit_text("Test Rider")
		return

	# Story wants us to press E somewhere
	if not story._pending.is_empty():
		if player.state == Player.State.RIDING:
			game._toggle_ride()
			return
		player.teleport(story._pending["pos"] + Vector3(0.5, 0.2, 0))
		game._interact()
		return

	if story._has_target:
		var objective: String = hud._objective_text.text.to_lower()
		var target: Vector3 = story._target
		if player.state != Player.State.RIDING:
			if objective.contains("get off"):
				return   # already off: wait for the story to notice
			# Get on the motor
			player.teleport(motor.global_position + Vector3(-1.2, 0.2, 0))
			game._toggle_ride()
			return
		if objective.contains("get off") and Story._flat(motor.global_position, target) < 1.0:
			game._toggle_ride()
			return
		if story._training:
			if not _checked_ground:
				_checked_ground = true
				_check(TrainingGround.contains(motor.global_position), "training happens at the private training ground")
				var near := 0
				for v in game.traffic.vehicles:
					if is_instance_valid(v) and v.global_position.distance_to(motor.global_position) < 300.0:
						near += 1
				for p in game.pedestrians.people:
					if is_instance_valid(p) and p.global_position.distance_to(motor.global_position) < 300.0:
						near += 1
				_check(near == 0, "no traffic or people at the training ground")
			_shot_once("story_04_training")
		elif objective.contains("lesson"):
			_shot_once("story_03_lesson")
		motor.place(target + Vector3(0, 0.2, 0), motor.heading)


func _final_checks() -> void:
	_shot_once("story_10_online")
	print("money=", GameState.money, " name=", GameState.player_name, " mode=", GameState.motor_mode,
		" motor=", GameState.current_motor_id, " color=", GameState.motor_color_index)
	_check(GameState.has_license, "has license")
	_check(GameState.player_name == "Test Rider", "name saved")
	_check(GameState.motor_mode == "own" and GameState.current_motor_id == "honda_navi", "owns a Honda Navi")
	_check(GameState.money == Economy.STARTING_MONEY - Economy.LICENSE_FEE - 56900, "paid license + motor")
	_check(motor.is_active, "motor is active")
	_check(game.booking.stage != BookingSystem.Stage.OFFLINE, "online after story")
	_finish()


func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		_fails.append(what)


func _finish() -> void:
	_done = true
	print("STORY TEST DONE in %.0fs: %s" % [_t, "ALL PASSED" if _fails.is_empty() else "FAILED: %s" % ", ".join(_fails)])
	get_tree().quit(0 if _fails.is_empty() else 1)


func _shot_once(shot_name: String) -> void:
	if _shots.has(shot_name):
		return
	_shots[shot_name] = true
	if DisplayServer.get_name() == "headless":
		return   # no screen to capture when running without a window
	get_viewport().get_texture().get_image().save_png("user://screenshots/%s.png" % shot_name)
