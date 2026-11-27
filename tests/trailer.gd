extends Node
## Trailer "director": plays the game by itself (scripted shots, captions, title) while Godot's
## Movie Maker records every frame at a steady 30 fps (slow PCs still give smooth video).
## Fast cut: ~24 s of 1.5-2.5 s shots with flash cuts and punchy captions.
## Record (opens a window for a couple of minutes):
##   godot --path . --write-movie builds/trailer/trailer.avi --fixed-fps 30 res://tests/trailer.tscn
## Then add the music and encode to MP4: python tools/trailer_music.py + ffmpeg (see README).

const FPS := 30.0
const CATHEDRAL := Vector3(-126, 0, -5)
const PLAZA := Vector3(-190, 0, 138)

var game: Node3D
var motor: Motorcycle
var player: Player
var hud: HUD
var cam: FollowCamera
var cine: Camera3D          # free "film" camera for the cinematic shots

var _layer: CanvasLayer
var _black: ColorRect
var _flash: ColorRect
var _title: Label
var _sub: Label
var _caption: Label
var _route := PackedVector3Array()
var _route_idx := 1
var _passenger: Passenger
var _spot := {}
var _street := {}
var _next_punch := 0.0
var _vw := 1280.0           # video width (text sizes follow it)

## Captions. The global cut (default) leads with what anyone understands; the local cut names
## Bacolod up front. Pick the local one with:  ... res://tests/trailer.tscn -- --local
const GLOBAL := {
	"open": "THE PHILIPPINES", "ride": "MOTORCYCLE TAXI LIFE", "side": "PICK UP PASSENGERS",
	"front": "BEAT THE TRAFFIC", "fp": "EARN YOUR PESOS", "enforcer": "PRRT! MIND THE ENFORCERS",
	"fight": "ROAD RAGE? FIGHT BACK", "sunset": "A REAL CITY: BACOLOD", "night": "RIDE ALL NIGHT",
	"sub": "A motorcycle taxi life in the Philippines  ·  PC",
}
const LOCAL := {
	"open": "BACOLOD CITY", "ride": "BE A HABAL-HABAL RIDER", "side": "PICK UP PASSENGERS",
	"front": "BEAT THE TRAFFIC", "fp": "EARN YOUR PESOS", "enforcer": "PRRT! MIND THE ENFORCERS",
	"fight": "ROAD RAGE? FIGHT BACK", "sunset": "", "night": "RIDE ALL NIGHT",
	"sub": "A motorcycle taxi life in Bacolod City  ·  PC",
}
var T: Dictionary = GLOBAL


func _ready() -> void:
	GameState.reset_new_game()
	GameState.debug_skip_story()
	GameState.time_hours = 7.4
	Settings.graphics = "high"       # best look for the video (not saved)
	Settings.apply()
	game = (load("res://scenes/main/game.tscn") as PackedScene).instantiate()
	add_child(game)
	game.death_chance = 0.0   # (test) accidents never end the game
	game.traffic.can_hit_player = false
	motor = game.motor
	player = game.player
	hud = game.hud
	cam = game.cam
	cine = Camera3D.new()
	cine.fov = 62.0
	cine.far = 2500.0
	game.add_child(cine)
	_vw = get_viewport().get_visible_rect().size.x
	if OS.get_cmdline_user_args().has("--local"):
		T = LOCAL
	_build_overlay()
	_direct()


func _process(_delta: float) -> void:
	# music is added afterwards (faster beat); keep the in-game radio off while filming
	if is_instance_valid(game) and game._radio.playing:
		game._radio.stop()
	# clean frame: no "press F" prompts or pop-up messages
	if is_instance_valid(hud):
		hud._prompt_panel.visible = false
		hud._toast_label.visible = false


# --- The trailer -------------------------------------------------------------------------

func _direct() -> void:
	hud.visible = false
	game.police.set_physics_process(false)
	game.police._cooldowns["fighting"] = 9999.0
	hud.set_objective("", "")
	cam._preset = 0
	_black.color.a = 1.0
	_haze(true)

	# load the plaza area + start the ride there, so traffic is already around when we cut in
	_mount_with_passenger()
	_route = game.world.road_graph.route(motor.global_position, Vector3(288, 0, -682))
	_route_idx = 1
	_release_keys()
	await _frames(2.0)    # (black) let the city and traffic load

	# 1) BACOLOD CITY: fast aerial dive toward the cathedral
	cine.current = true
	_black.color.a = 0.0
	await _shot(2.2, _s_dive, T["open"])

	# 2) the ride, filmed from many angles (one continuous ride)
	_haze(false)
	await _cut()
	cine.current = false
	cam.camera.current = true
	cam.snap_to(motor.heading)
	hud.visible = true
	await _shot(2.0, _s_ride, T["ride"])
	await _cut()
	cine.current = true
	hud.visible = false
	await _shot(1.8, _s_side, T["side"])
	await _cut()
	await _shot(1.6, _s_front, T["front"])
	await _cut()
	cam.camera.current = true
	cam._preset = 3
	hud.visible = true
	await _shot(1.8, _s_ride, T["fp"])
	cam._preset = 0
	_release_keys()

	# 3) the enforcer whistle
	await _cut()
	_spot = _enforcer_crossing()
	cam.camera.current = true
	await _shot(2.0, _s_enforcer, T["enforcer"])
	game.police.pull_over = {}

	# 4) road rage fight
	await _cut()
	hud.visible = false
	if _stage_fight():
		await _shot(2.6, _fight_step, T["fight"])
	game.combat.cancel()

	# 5) sunset to night, fast timelapse over the rooftops
	await _cut()
	_street = _main_road_spot()
	cine.current = true
	_haze(true)
	await _shot(2.2, _s_sunset, T["sunset"])

	# 6) night ride with the headlight on
	await _cut()
	_haze(false)
	_night_ride_setup()
	await _shot(2.0, _s_night_side, T["night"])
	_release_keys()

	# 7) title
	await _cut()
	_haze(true)
	_stage_player(PLAZA + Vector3(20, 0, 0))
	cine.current = true
	await _shot(4.0, _s_title, "")
	await _fade_out(0.5)
	await _frames(0.3)
	get_tree().quit()


# --- Shot steps (t: 0 -> 1 during the shot) -----------------------------------------------

func _s_dive(t: float) -> void:
	var e := t * t * (3.0 - 2.0 * t)
	var a := lerpf(-1.3, -0.3, e)
	var r := lerpf(150.0, 45.0, e)
	cine.global_position = CATHEDRAL + Vector3(cos(a) * r, lerpf(85.0, 22.0, e), sin(a) * r)
	cine.look_at(CATHEDRAL + Vector3(0, 10, 0))
	_autopilot()   # the ride is already going (we cut to it next)


func _s_ride(_t: float) -> void:
	_autopilot()


func _s_side(t: float) -> void:
	_autopilot()
	var side := motor.global_transform.basis.x
	var fwd := -motor.global_transform.basis.z
	cine.global_position = motor.global_position + side * 2.6 + fwd * lerpf(3.0, -1.0, t) + Vector3.UP * 0.8
	cine.look_at(motor.global_position + Vector3.UP * 0.9)


func _s_front(t: float) -> void:
	_autopilot()
	var fwd := -motor.global_transform.basis.z
	var side := motor.global_transform.basis.x
	cine.global_position = motor.global_position + fwd * lerpf(6.0, 4.5, t) + side * 0.8 + Vector3.UP * 1.1
	cine.look_at(motor.global_position + Vector3.UP * 1.0)


func _s_enforcer(t: float) -> void:
	if t > 0.05 and game.police.pull_over.is_empty() and _spot.get("enforcer") != null:
		game.police._cooldowns.clear()
		game.police._cooldowns["fighting"] = 9999.0
		game.police.violation("red_light", (_spot["enforcer"] as Node3D).global_position + Vector3(4, 0, 0), int(_spot["id"]))
	game.police._animate_enforcers()


func _s_sunset(t: float) -> void:
	GameState.time_hours = lerpf(17.6, 20.4, t)
	var pos: Vector3 = _street["pos"]
	var dir: Vector3 = _street["dir"]
	cine.global_position = pos - dir * lerpf(30.0, 10.0, t) + Vector3.UP * lerpf(24.0, 30.0, t)
	cine.look_at(pos + dir * 260.0 + Vector3.UP * 12.0)


func _s_night_side(t: float) -> void:
	_autopilot()
	var side := motor.global_transform.basis.x
	var fwd := -motor.global_transform.basis.z
	cine.global_position = motor.global_position - side * 2.8 + fwd * lerpf(2.5, -1.5, t) + Vector3.UP * 1.0
	cine.look_at(motor.global_position + Vector3.UP * 0.9)


func _s_title(t: float) -> void:
	var a := lerpf(0.4, 0.75, t)
	cine.global_position = PLAZA + Vector3(cos(a) * 140.0, 75.0, sin(a) * 140.0)
	cine.look_at(PLAZA)
	var pop := clampf(t * 5.0, 0.0, 1.0)
	_title.modulate.a = pop
	_title.pivot_offset = _title.size * 0.5
	_title.scale = Vector2.ONE * lerpf(1.35, 1.0, pop * pop * (3.0 - 2.0 * pop))
	_sub.modulate.a = clampf((t - 0.25) * 4.0, 0.0, 1.0)


# --- Staging helpers --------------------------------------------------------------------

func _haze(thin: bool) -> void:
	game.world.environment.fog_density = 0.0005 if thin else 0.0018


func _stage_player(pos: Vector3) -> void:
	if player.state == Player.State.RIDING:
		motor.speed = 0.0
		game._toggle_ride()
	game.world.update_streaming(pos, true)
	player.teleport(pos + Vector3(0, 0.3, 0))


## Motor on a road near the plaza with a passenger on the back; you're riding.
func _mount_with_passenger() -> void:
	var g: RoadGraph = game.world.road_graph
	var start := g.nearest_road_point(Vector3(-170, 0, 60))
	var heading := 0.0
	var near := g.point_ids_near(start, 30.0)
	if not near.is_empty() and not g.neighbors(near[0]).is_empty():
		var d := g.get_point(g.neighbors(near[0])[0]) - g.get_point(near[0])
		heading = atan2(-d.x, -d.z)
	game.world.update_streaming(start, true)
	motor.place(start + Vector3(0, 0.2, 0), heading)
	player.teleport(motor.global_position + Vector3(-1.2, 0.2, 0))
	game._toggle_ride()
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	_passenger = Passenger.new()
	game.add_child(_passenger)
	_passenger.build(rng, "Inday", "student", true)
	_passenger.sit_on(motor.get_seat_mount(), Motorcycle.PASSENGER_SEAT)
	motor.attach_passenger(_passenger)


## Simple autopilot along _route: steer toward the next point, keep ~40 km/h.
func _autopilot() -> void:
	if _route.size() < 2:
		return
	if player.state != Player.State.RIDING:
		player.teleport(motor.global_position + Vector3(-1.2, 0.2, 0))
		game._toggle_ride()
	while _route_idx < _route.size() - 1 and Vector2(_route[_route_idx].x - motor.global_position.x,
			_route[_route_idx].z - motor.global_position.z).length() < 7.0:
		_route_idx += 1
	var to := _route[_route_idx] - motor.global_position
	var diff := wrapf(atan2(-to.x, -to.z) - motor.heading, -PI, PI)
	Input.action_release("steer_left")
	Input.action_release("steer_right")
	if diff > 0.08:
		Input.action_press("steer_left")
	elif diff < -0.08:
		Input.action_press("steer_right")
	if motor.get_speed_kmh() < 40.0:
		Input.action_press("accelerate")
	else:
		Input.action_release("accelerate")


func _release_keys() -> void:
	for a: String in ["accelerate", "brake", "steer_left", "steer_right"]:
		Input.action_release(a)


## The enforcer crossing nearest to you: stop the motor just before it.
func _enforcer_crossing() -> Dictionary:
	var g: RoadGraph = game.world.road_graph
	var best := -1
	var best_d := INF
	for id: int in game.traffic._signals:
		if id % 2 != 0:
			continue
		var d: float = g.get_point(id).distance_to(motor.global_position)
		if d < best_d:
			best_d = d
			best = id
	if best == -1:
		return {}
	var p := g.get_point(best)
	var from := g.get_point(g.neighbors(best)[0])
	var dir := (p - from).normalized()
	var stop_at := p - dir * 16.0 + Vector3(-dir.z, 0, dir.x) * 1.5
	game.world.update_streaming(p, true)
	motor.speed = 0.0
	motor.place(stop_at + Vector3(0, 0.2, 0), atan2(-dir.x, -dir.z))
	game.traffic._update_lights(p)
	game.police._update_enforcers(p)
	cam.snap_to(atan2(-dir.x, -dir.z))
	hud.visible = true
	return {"id": best, "enforcer": game.police.enforcers.get(best)}


## On foot next to a car whose driver gets out angry. Returns false if no car was found.
func _stage_fight() -> bool:
	if player.state == Player.State.RIDING:
		motor.speed = 0.0
		game._toggle_ride()
	var car: TrafficVehicle = null
	var best := INF
	for v in game.traffic.vehicles:
		if is_instance_valid(v) and v.kind == "car":
			var d: float = v.global_position.distance_to(player.global_position)
			if d < best:
				best = d
				car = v
	if car == null:
		return false
	player.teleport(car.global_position + car.global_transform.basis.x * 3.0 + Vector3(0, 0.3, 0))
	game.combat.start_road_rage(car, true)
	# the driver is already out and close: no walking, straight to the action
	for f in game.combat.fighters:
		if is_instance_valid(f):
			f.global_position = player.global_position + (car.global_position - player.global_position).normalized() * 1.6
	cine.current = true
	return true


func _fight_step(t: float) -> void:
	var foe: Fighter = null
	for f in game.combat.fighters:
		if is_instance_valid(f) and f.is_hostile():
			foe = f
			break
	var me := player.global_position
	if foe != null:
		var to := foe.global_position - me
		cam._yaw = atan2(-to.x, -to.z)
		player.face_yaw(cam._yaw)
		if to.length() < 2.2 and t > _next_punch:
			game.combat.player_punch()
			_next_punch = t + 0.05
		var mid := (me + foe.global_position) * 0.5
		var side := Vector3(-to.z, 0, to.x).normalized()
		cine.global_position = mid + side * 3.4 + Vector3.UP * 1.3 + to.normalized() * lerpf(-0.6, 0.6, t)
		cine.look_at(mid + Vector3.UP * 1.1)
	else:
		cine.global_position = me + Vector3(3.0, 1.5, 3.0)
		cine.look_at(me + Vector3.UP * 1.0)


## A main road near the plaza, looking west (for the sunset).
func _main_road_spot() -> Dictionary:
	var g: RoadGraph = game.world.road_graph
	for seg: Dictionary in g.segments:
		if seg.get("major", false):
			var a := g.get_point(int(seg["a"]))
			var b := g.get_point(int(seg["b"]))
			if a.distance_to(PLAZA) < 600.0 and a.distance_to(b) > 40.0:
				var dir := (b - a).normalized()
				if dir.x > 0.0:
					dir = -dir
				game.world.update_streaming(a, true)
				player.teleport(a + Vector3(0, 0.3, 0) - dir * 30.0)
				return {"pos": a, "dir": dir}
	return {"pos": PLAZA, "dir": Vector3(-1, 0, 0)}


## Back on the motor (night), riding on from a road near the plaza.
func _night_ride_setup() -> void:
	GameState.time_hours = 20.6
	if _passenger != null and is_instance_valid(_passenger):
		motor.detach_passenger()
		_passenger.queue_free()
		_passenger = null
	_mount_with_passenger()
	_route = game.world.road_graph.route(motor.global_position, Vector3(288, 0, -682))
	_route_idx = 1
	motor.speed = 9.0
	cine.current = true


# --- Timing, text and cuts --------------------------------------------------------------

func _frames(seconds: float) -> void:
	for i in int(seconds * FPS):
		await get_tree().process_frame


## Run `step(t)` every frame for `seconds`, with a caption that pops in.
func _shot(seconds: float, step: Callable, caption: String) -> void:
	_caption.text = caption
	var n := int(seconds * FPS)
	for i in n:
		var t := float(i) / float(maxi(n - 1, 1))
		step.call(t)
		if caption != "":
			var pop := clampf(t * 8.0, 0.0, 1.0)
			_caption.modulate.a = minf(pop, clampf((1.0 - t) * 10.0, 0.0, 1.0))
			_caption.pivot_offset = _caption.size * 0.5
			_caption.scale = Vector2.ONE * lerpf(1.4, 1.0, pop)
		else:
			_caption.modulate.a = 0.0
		await get_tree().process_frame
	_caption.text = ""


## Hard cut with a quick white flash (2 frames).
func _cut() -> void:
	_flash.color.a = 0.85
	await get_tree().process_frame
	_flash.color.a = 0.35
	await get_tree().process_frame
	_flash.color.a = 0.0


func _fade_out(seconds: float) -> void:
	var n := int(seconds * FPS)
	for i in n:
		_black.color.a = float(i + 1) / n
		await get_tree().process_frame


func _build_overlay() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 50
	add_child(_layer)
	_black = ColorRect.new()
	_black.color = Color(0, 0, 0, 1)
	_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_black)
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_flash)
	_caption = Label.new()
	_style(_caption, int(_vw * 0.05), Color("#ffe066"))
	_caption.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_caption.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_caption.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_caption.offset_bottom = -_vw * 0.11
	_layer.add_child(_caption)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", int(_vw * 0.01))
	_layer.add_child(box)
	_title = Label.new()
	_style(_title, int(_vw * 0.095), Color("#ffd166"))
	_title.text = "HABAL-HABAL\nSIMULATOR"    # two lines so it always fits
	_title.modulate.a = 0.0
	box.add_child(_title)
	_sub = Label.new()
	_style(_sub, int(_vw * 0.026), Color.WHITE)
	_sub.text = T["sub"]
	_sub.modulate.a = 0.0
	box.add_child(_sub)


func _style(l: Label, size: int, color: Color) -> void:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	l.add_theme_constant_override("outline_size", maxi(8, size / 5))
	l.add_theme_constant_override("line_spacing", -int(size * 0.15))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
