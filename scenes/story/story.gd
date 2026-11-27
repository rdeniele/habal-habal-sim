class_name Story
extends Node
## The first-playthrough story / tutorial, written as one long script using `await`:
##   1. Intro at home with Nanay (choose: full tutorial or skip to the license)
##   2. Driving school: 4 lessons (accelerate, brake, turn, park) in the cone yard
##   3. Passenger training: Sir Jojo rides on the back, keep his comfort above 60%
##      (2 and 3 happen at the school's private TRAINING GROUND outside the city:
##       no traffic, no people walking through. A shuttle brings you back for the license.)
##   4. License at the Transport Office desk (enter your name, pay the fee, get your card)
##   5. Motor Shop: buy or rent your first motor
##   6. Day 1 begins at home
##
## Helpers: `_wait_until(func)` waits until a condition is true,
## `_wait_interact(pos, prompt)` waits until you press E there.

signal _cond_met
signal _interacted

const SCHOOL_YELLOW := Color("#f2c14e")
const GREEN := Color("#2ecc71")
const ORANGE := Color("#ff8c42")
const BLUE := Color("#4d9de0")
const INSTRUCTOR := "Sir Jojo"
const TRACK_RX := 11.6           # oval track between the two cone rings
const TRACK_RZ := 7.0
const YARD_LEAVE_DIST := 40.0    # leaving the yard during lessons resets you
const RING_RADIUS := 3.2
const ROUTE_RADIUS := 5.5
const PASS_COMFORT := 60.0

var active := false

var game: Node   # the main game script (for shop / respawn helpers)
var world: GameWorld
var player: Player
var motor: Motorcycle
var hud: HUD
var cam: FollowCamera
var booking: BookingSystem

var _marker: TargetMarker
var _sfx: AudioStreamPlayer
var _cond: Callable = Callable()
var _pending: Dictionary = {}
var _target := Vector3.ZERO
var _target_text := ""
var _target_color := GREEN
var _has_target := false
var _nanay: Passenger
var _jojo: Passenger
var _yard_c := Vector3.ZERO
var _ground: TrainingGround
var _yard_guard := false
var _training := false
var _crashed := false
var _comfort := 100.0
var _complain_cooldown := 0.0


func _ready() -> void:
	_marker = TargetMarker.new()
	add_child(_marker)
	_sfx = AudioStreamPlayer.new()
	_sfx.bus = "SFX"
	add_child(_sfx)


func setup(p_game: Node, p_world: GameWorld, p_player: Player, p_motor: Motorcycle, p_hud: HUD,
		p_cam: FollowCamera, p_booking: BookingSystem) -> void:
	game = p_game
	world = p_world
	player = p_player
	motor = p_motor
	hud = p_hud
	cam = p_cam
	booking = p_booking
	motor.bumped.connect(_on_bumped)


func start() -> void:
	active = true
	_run()


# --- The story, top to bottom ------------------------------------------------

func _run() -> void:
	GameState.reset_today()
	motor.set_active(false)   # no motor yet!
	_spawn_nanay()
	await _sleep(1.0)

	var skip := await _intro()
	if skip:
		var door: Vector3 = world.get_place("driving_school")["door"]
		await _travel("Nag-jeep ka pakadto sa Driving School...\n(You took a jeepney to the Driving School)", door, PI)
	else:
		await _driving_school()
		await _passenger_training()
	await _license()
	await _motor_shop()
	await _day_one()


func _intro() -> bool:
	var d := hud.dialog_box
	hud.set_objective("Prologue", "Your family needs money. Time to become a rider.")
	await d.say("Nanay", "Maayong aga, 'Nak! Mahal na gid ang tanan subong... bugas, kuryente, tubig.\n(Good morning! Everything is so expensive now... rice, power, water.)")
	await d.say("You", "Nay, ako na ang bahala. Mangin rider ko sang Sakay!\n(Leave it to me, Nay. I'll become a Sakay rider!)")
	var pick := await d.choose("Nanay", "Rider? Kabalo ka bala magmaneho sang motor?\n(Rider? Do you even know how to ride a motorcycle?)", [
		"Indi pa. Mag-driving school anay ko.  (Not yet, driving school first!)  - full tutorial",
		"Kabalo na ko, Nay!  (I already know how!)  - skip to the license",
	])
	if pick == 1:
		await d.say("Nanay", "Sige, pero kinahanglan mo gihapon sang lisensya!\n(Okay, but you still need a license!)")
	await d.say("Nanay", "May %s kita nga natipon. Gamita sing maayo, ha?\n(We saved up %s. Spend it wisely, okay?)" \
		% [Economy.format_peso(GameState.money), Economy.format_peso(GameState.money)])
	return pick == 1


func _driving_school() -> void:
	var d := hud.dialog_box
	_ground = TrainingGround.new()
	game.add_child(_ground)
	_yard_c = _ground.yard_center()
	var door := _ground.office_door()
	await _travel("Nag-jeep ka pakadto sa training ground sang Driving School...\n(You took a jeepney to the Driving School's training ground)", _ground.arrival_point(), 0.0)

	# Instructor waiting in the yard + the yellow school motor
	_jojo = Passenger.new()
	game.add_child(_jojo)
	_jojo.build_with_look(INSTRUCTOR, {
		"body": "male", "skin": Color("#c68c5a"), "hair": "short", "hair_color": Color("#1a1410"),
		"top": "polo", "top_color": Color("#3d5a80"), "bottom": "pants", "bottom_color": Color("#2d3047"),
		"helmet": Color("#f8f9fa")})
	_jojo.add_name_tag("Sir Jojo · Instructor")
	_jojo.global_position = _yard_c + Vector3(7.0, 0, -9.0)
	_jojo.face(door)
	motor.setup("honda_navi")
	motor.set_paint(SCHOOL_YELLOW)
	motor.set_active(true)
	motor.place(_track_point(90.0) + Vector3(0, 0.2, 0), PI * 0.5)

	hud.set_objective("Driving school", "Talk to Sir Jojo, your instructor (in the cone yard).")
	_set_target(_jojo.global_position, "Sir Jojo", GREEN)
	await _wait_interact(_jojo.global_position, "Istorya kay Sir Jojo  (Talk)")
	_clear_target()
	await d.say(INSTRUCTOR, "Welcome sa Driving School! Ako si Sir Jojo.\n(Welcome to Driving School! I'm Sir Jojo.)")
	await d.say(INSTRUCTOR, "Una, sakay sa dalag nga motor. Lapit kag pindota ang F.\n(First, get on the yellow motor. Walk up to it and press F.)")

	hud.set_objective("Lesson 1 of 4", "Get on the yellow school motor (F).")
	_set_target(motor.global_position, "School motor", SCHOOL_YELLOW)
	await _wait_until(func() -> bool: return player.state == Player.State.RIDING)
	_yard_guard = true

	await _ring("Lesson 1 of 4 · Accelerate", "Hold W to go. Ride into the green ring.", _track_point(150.0), false)
	await _ring("Lesson 2 of 4 · Brake", "Hold S to brake. STOP inside the ring.", _track_point(210.0), true)
	var turns := [270.0, 330.0, 30.0]
	for i in turns.size():
		await _ring("Lesson 3 of 4 · Turn", "Steer with A / D. Follow the rings around the cones (%d/3)." % (i + 1), _track_point(turns[i]), false)

	var spot := _track_point(90.0)
	hud.set_objective("Lesson 4 of 4 · Park", "Stop in the blue spot, then get off (F).")
	_set_target(spot, "PARK", BLUE)
	await _wait_until(func() -> bool:
		return player.state == Player.State.ON_FOOT and _flat(motor.global_position, spot) < RING_RADIUS \
			and absf(motor.speed) < 0.3)
	_yard_guard = false
	_clear_target()
	_ding()


func _passenger_training() -> void:
	var d := hud.dialog_box
	await d.say(INSTRUCTOR, "Nami! Next: passenger training. Ako ang pasahero mo.\n(Nice! Next is passenger training. I'll be your passenger.)")
	await d.say(INSTRUCTOR, "Indi pagbrake sing kusog kag indi magbangga. Kinahanglan labaw %d%% ang comfort ko.\n(No hard braking, no crashing. Keep my comfort above %d%%.)" % [int(PASS_COMFORT), int(PASS_COMFORT)])

	# Sir Jojo walks over and sits on the back.
	var side := motor.global_position + motor.global_transform.basis * Vector3(0.8, 0, 0.6)
	_jojo.walk_to_motor(side)
	await _jojo.reached_motor
	_seat_jojo()

	while true:
		hud.set_objective("Passenger training", "Get on the motor (F). Sir Jojo is riding with you.")
		_set_target(motor.global_position, "Motor", SCHOOL_YELLOW)
		await _wait_until(func() -> bool: return player.state == Player.State.RIDING)
		var result := await _training_run()
		if result == "pass":
			break
		await _sleep(1.5)
		if result == "crash":
			await d.say(INSTRUCTOR, "Aguy! Nagbangga kita! Liwat ta.\n(Ouch, we crashed! Let's try again.)")
		else:
			await d.say(INSTRUCTOR, "Comfort ko %d%% lang. Liwat ta, hinay-hinay lang.\n(My comfort was only %d%%. Again, nice and easy.)" % [int(_comfort), int(_comfort)])
		await _reset_training()

	await d.say(INSTRUCTOR, "Pasado ka! Comfort: %d%%. Ka-smooth sa imo!\n(You passed! So smooth!)" % int(_comfort))
	# Sir Jojo gets off and goes back inside.
	motor.detach_passenger()
	var off := motor.global_position + motor.global_transform.basis * Vector3(1.0, 0, 0.6)
	_jojo.get_off_and_leave(game, off, _ground.office_door())
	_jojo = null
	await d.say(INSTRUCTOR, "Kadto na sa Transport Office desk para sa lisensya mo.\n(Now go to the Transport Office desk for your license.)")


## One attempt at the route. Returns "pass", "crash" or "low".
func _training_run() -> String:
	_training = true
	_crashed = false
	_comfort = 100.0
	var route := _training_route()
	for i in route.size():
		var last := i == route.size() - 1
		var p := route[i]
		if last:
			hud.set_objective("Passenger training", "Back to the yard: stop on the blue spot.")
			_set_target(p, "STOP", BLUE)
		else:
			hud.set_objective("Passenger training", "Ride through the checkpoints (%d/%d). Smooth and steady!" % [i + 1, route.size() - 1])
			_set_target(p, "CHECKPOINT", ORANGE)
		var radius := RING_RADIUS if last else ROUTE_RADIUS
		await _wait_until(func() -> bool:
			return _crashed or (player.state == Player.State.RIDING and _flat(motor.global_position, p) < radius \
				and (not last or absf(motor.speed) < 0.4)))
		if _crashed:
			break
		_ding()
	_training = false
	_clear_target()
	hud.set_objective_meter("", -1.0)
	if _crashed:
		return "crash"
	return "pass" if _comfort >= PASS_COMFORT else "low"


func _license() -> void:
	var d := hud.dialog_box
	var door: Vector3 = world.get_place("driving_school")["door"]
	if _ground != null:
		# back to the city: the school shuttle drops you at the office (the school motor stays)
		await _travel("Ginhatod ka sang school shuttle balik sa siyudad...\n(The school shuttle took you back to the city office)", door, PI)
		motor.set_active(false)
		_ground.queue_free()
		_ground = null
	hud.set_objective("License", "Go to the Transport Office desk at the front of the school (E).")
	_set_target(door, "TRANSPORT OFFICE", GREEN)
	await _wait_interact(door, "Transport Office desk")
	_clear_target()
	var player_name := await d.ask_text("Clerk", "Maayong aga! Ano ang imo bug-os nga ngalan?\n(Good morning! What's your full name?)", "Juan Dela Cruz")
	GameState.player_name = player_name
	var g := await d.choose("Clerk", "Lalaki ka ukon babaye?\n(Are you male or female?)", ["Lalaki (Male)", "Babaye (Female)"])
	GameState.player_female = g == 1
	player.refresh_look()
	motor.refresh_rider()
	await d.say("Clerk", "Salamat, %s. Ang license fee %s.\n(Thank you. The license fee is %s.)" \
		% [player_name, Economy.format_peso(Economy.LICENSE_FEE), Economy.format_peso(Economy.LICENSE_FEE)])
	GameState.add_money(-Economy.LICENSE_FEE)
	GameState.has_license = true
	_play(Sfx.cash())
	var number := "G07-26-%06d" % (randi() % 1000000)
	await hud.license_card.show_card(player_name, number)
	await d.say("Clerk", "Congrats! Next, kuha ka motor sa Motor Shop. Buy ukon rent, ikaw bahala.\n(Next, get a motor at the Motor Shop. Buy or rent, it's up to you.)")


func _motor_shop() -> void:
	var d := hud.dialog_box
	motor.set_active(false)   # the school keeps its motor
	var shop_place := world.get_place("motor_shop")
	var door: Vector3 = shop_place["door"]
	await _travel("Nag-jeep ka pakadto sa Motor Shop...\n(You took a jeepney to the Motor Shop)", door, PI)
	hud.set_objective("Your first motor", "Enter the Motor Shop (E). Buy or rent your first motor.")
	_set_target(door, "MOTOR SHOP", GREEN)
	await _wait_interact(door, "Motor Shop")
	_clear_target()
	await d.say("Shop owner", "Maayo nga pag-abot, boss! Buy ukon rent? Kung rent, %s kada adlaw ang boundary.\n(Welcome! Buy or rent? Renting costs %s a day.)" \
		% [Economy.format_peso(Economy.RENT_PER_DAY), Economy.format_peso(Economy.RENT_PER_DAY)])
	game.open_shop(true)
	await game.shop_purchased
	await d.say("Shop owner", "Salamat, boss! Ingat sa dalan!\n(Thanks, boss! Ride safe!)")


func _day_one() -> void:
	await hud.fade_out(0.8)
	await hud.show_caption("DAY 1\n%s, Sakay rider" % GameState.player_name)
	GameState.day = 1
	GameState.time_hours = Economy.DAY_START_HOUR
	GameState.reset_today()
	GameState.story_done = true
	game.respawn_at_home()
	game._sync_motor_to_state()
	SaveManager.save_game(maxi(GameState.save_slot, 1))   # first save: Day 1 morning
	await _sleep(2.0)
	await hud.fade_in(0.8)
	hud.set_objective("Day 1", "Get on your motor (F), press Tab and GO ONLINE in the Sakay app.")
	await _wait_until(func() -> bool: return booking.stage != BookingSystem.Stage.OFFLINE)
	hud.set_objective("", "")
	active = false


# --- Training helpers --------------------------------------------------------

func _seat_jojo() -> void:
	_jojo.sit_on(motor.get_seat_mount(), Motorcycle.PASSENGER_SEAT)
	motor.attach_passenger(_jojo)


func _reset_training() -> void:
	await hud.fade_out(0.4)
	motor.place(_track_point(90.0) + Vector3(0, 0.2, 0), PI * 0.5)
	if player.state == Player.State.RIDING:
		motor.set_ridden(false)
	player.set_riding(false)
	player.teleport(motor.global_position + motor.global_transform.basis * Vector3(-1.0, 0.2, 0))
	cam.set_target(player, false)
	await _sleep(0.3)
	await hud.fade_in(0.4)


## Once around the training ground's practice loop, then back to the yard.
## (Without the training ground: a loop on the real roads around the school.)
func _training_route() -> Array[Vector3]:
	if _ground != null:
		var loop := _ground.route_points()
		loop.append(_track_point(90.0))
		return loop
	var by_quadrant := {}
	for p in world.road_graph.points_near(_yard_c, 200.0):
		var d := _flat(p, _yard_c)
		if d < 90.0:
			continue
		var ang := atan2(p.z - _yard_c.z, p.x - _yard_c.x)
		var q := int(floor((ang + PI) / (PI * 0.5))) % 4
		if not by_quadrant.has(q) or absf(d - 140.0) < absf(_flat(by_quadrant[q], _yard_c) - 140.0):
			by_quadrant[q] = p
	var route: Array[Vector3] = []
	for q in [2, 3, 0, 1]:   # go around the yard
		if by_quadrant.has(q):
			route.append(by_quadrant[q])
	route.append(_track_point(90.0))
	return route


func _track_point(degrees: float) -> Vector3:
	var a := deg_to_rad(degrees)
	return _yard_c + Vector3(cos(a) * TRACK_RX, 0, sin(a) * TRACK_RZ)


func _ring(title: String, text: String, pos: Vector3, need_stop: bool) -> void:
	hud.set_objective(title, text)
	_set_target(pos, "STOP HERE" if need_stop else "GO", GREEN)
	await _wait_until(func() -> bool:
		return player.state == Player.State.RIDING and _flat(motor.global_position, pos) < RING_RADIUS \
			and (not need_stop or absf(motor.speed) < 0.4))
	_ding()


func _on_bumped(impact: float) -> void:
	if _training:
		_comfort = maxf(0.0, _comfort - impact * BookingSystem.BUMP_PENALTY)
		_jojo_complain()


## Called by the game when the rider crashes.
func on_crash() -> void:
	if _training:
		_crashed = true
		_comfort = 0.0


func _jojo_complain() -> void:
	if _complain_cooldown > 0.0:
		return
	_complain_cooldown = 5.0
	var lines := ["Hinay lang! (Easy!)", "Ay! Ang akon likod! (Ow, my back!)", "Indi pagbrake sing kusog! (Don't brake so hard!)"]
	hud.show_dialog(INSTRUCTOR, lines[randi() % lines.size()], 3.0)


# --- Generic helpers ---------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not active:
		return
	_complain_cooldown = maxf(0.0, _complain_cooldown - delta)

	if _training:
		var before := _comfort
		if motor.last_accel < -BookingSystem.HARD_BRAKE_DECEL:
			_comfort -= BookingSystem.HARD_BRAKE_PENALTY * delta
		if motor.get_speed_kmh() > BookingSystem.SCARY_SPEED_KMH:
			_comfort -= BookingSystem.SCARY_SPEED_PENALTY * delta
		_comfort = maxf(0.0, _comfort)
		if _comfort < before:
			_jojo_complain()
		hud.set_objective_meter("Sir Jojo's comfort: %d%%  (need %d%%)" % [int(_comfort), int(PASS_COMFORT)], _comfort / 100.0)

	# Leaving the yard during the lessons puts you back at the start.
	if _yard_guard and _flat(motor.global_position, _yard_c) > YARD_LEAVE_DIST:
		motor.place(_track_point(90.0) + Vector3(0, 0.2, 0), PI * 0.5)
		hud.show_toast("Balik sa yard! (Stay inside the school yard)", 2.5)

	if _has_target:
		var from := motor.global_position if player.state == Player.State.RIDING else player.global_position
		var to := _target - from
		var rel := wrapf(atan2(-to.x, -to.z) - cam.get_yaw(), -PI, PI)
		var dist := Vector2(to.x, to.z).length()
		hud.set_nav("%s   %d m" % [_target_text, int(dist)], _target_color, rel)

	if _cond.is_valid() and bool(_cond.call()):
		_cond = Callable()
		_cond_met.emit()


func _wait_until(cond: Callable) -> void:
	_cond = cond
	await _cond_met


func _wait_interact(pos: Vector3, prompt: String, radius: float = 3.2) -> void:
	_pending = {"pos": pos, "prompt": prompt, "radius": radius}
	await _interacted


## The game calls this when E is pressed. Returns true if the story used it.
func try_interact() -> bool:
	if not active or _pending.is_empty() or not _is_near_pending():
		return false
	_pending = {}
	_interacted.emit()
	return true


## Prompt text for the HUD when standing at a story interaction ("" if none).
func get_prompt() -> String:
	if not active or _pending.is_empty() or not _is_near_pending():
		return ""
	return "[E]  %s" % _pending["prompt"]


func _is_near_pending() -> bool:
	return player.state == Player.State.ON_FOOT \
		and _flat(player.global_position, _pending["pos"]) < float(_pending["radius"])


func _set_target(pos: Vector3, text: String, color: Color) -> void:
	_target = pos
	_target_text = text
	_target_color = color
	_has_target = true
	_marker.show_at(pos, color, text)


func _clear_target() -> void:
	_has_target = false
	_marker.hide_marker()
	hud.hide_nav()


## Fade out, show a caption, move the player, fade back in.
func _travel(caption: String, pos: Vector3, yaw: float) -> void:
	_clear_target()
	await hud.fade_out(0.6)
	await hud.show_caption(caption)
	if player.state == Player.State.RIDING:
		motor.set_ridden(false)
		player.set_riding(false)
	world.update_streaming(pos, true)
	player.teleport(pos + Vector3(0, 0.2, 0))
	player.face_yaw(yaw)
	cam.set_target(player, false)
	cam.snap_to(yaw)
	await _sleep(1.6)
	await hud.fade_in(0.6)


func _spawn_nanay() -> void:
	var home := world.get_place("home")
	var door: Vector3 = home["door"]
	var front: Vector3 = home["front"]
	var side := Vector3(-front.z, 0, front.x)
	_nanay = Passenger.new()
	game.add_child(_nanay)
	_nanay.build_with_look("Nanay", {
		"body": "female", "skin": Color("#b97d4f"), "hair": "bun", "hair_color": Color("#6b6b6b"),
		"top": "dress", "top_color": Color("#e07a9b"), "bottom": "skirt", "bottom_color": Color("#e07a9b"),
		"age": "old", "helmet": Color(0, 0, 0, 0),
		"model": "res://assets/characters/npc/nanay.glb"})   # tools/blender/make_apose.py
	_nanay.add_name_tag("Nanay")
	# Nanay stands a couple of steps away; you face her and the camera looks from the side
	# so both of you are in view.
	var nanay_pos := door + side * 2.2 + front * 0.6
	_nanay.global_position = nanay_pos
	_nanay.face(player.global_position)
	var to_nanay := nanay_pos - player.global_position
	var yaw := atan2(-to_nanay.x, -to_nanay.z)
	player.face_yaw(yaw)
	cam.snap_to(yaw + 0.7)


func _sleep(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _ding() -> void:
	_play(Sfx.tones([1046.0, 1568.0], 0.08))


func _play(stream: AudioStream) -> void:
	_sfx.stream = stream
	_sfx.play()


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
