class_name BookingSystem
extends Node
## The ride-hailing loop (the "Sakay" app logic):
##   OFFLINE -> (go online) -> SEARCHING -> REQUEST (15 s to accept)
##   -> TO_PICKUP -> BOARDING (passenger walks to the motor) -> TO_DROPOFF -> paid + rated
##   -> back to SEARCHING
##
## While a passenger is on board we track a "comfort" score (0-100). Hard braking,
## bumping into things and going too fast lower it. Comfort + trip time = star rating.

signal trip_completed(fare: int, tip: int, stars: int)
signal final_ride_done   # the "Last Ride" trip is finished: time to go home

## Sakay doesn't send bookings late at night (hours, 24h clock).
const CLOSED_FROM := 23.0
const OPEN_FROM := 5.0
## The final "Last Ride" booking drops off within this distance of home.
const HOME_DROP_RADIUS := 150.0

enum Stage { OFFLINE, SEARCHING, REQUEST, TO_PICKUP, BOARDING, TO_DROPOFF, BREAK }

const DIALOG_PATH := "res://data/dialog/passengers.json"

const PICKUP_RADIUS := 7.5        # how close the motor must stop to the passenger (m)
const DROPOFF_RADIUS := 8.5
const STOP_SPEED := 1.6           # "stopped" = slower than this (m/s)
const BOARD_ABORT_DISTANCE := 3.0 # rider drives off while passenger walks over
const PICKUP_MIN_M := 80.0        # distances are "city block" distances (|dx| + |dz|)
const PICKUP_MAX_M := 450.0
const TRIP_MIN_M := 150.0
const TRIP_MAX_M := 800.0
const EXPECTED_SPEED := 7.0       # m/s used to judge if a trip was "late" (~25 km/h)

# Comfort penalties
const HARD_BRAKE_DECEL := 8.5     # m/s^2 counts as a hard brake
const HARD_BRAKE_PENALTY := 30.0  # comfort per second of hard braking
const SCARY_SPEED_KMH := 70.0
const SCARY_SPEED_PENALTY := 4.0  # comfort per second above scary speed
const BUMP_PENALTY := 3.0         # comfort per m/s of impact

const PICKUP_COLOR := Color("#2ecc71")
const DROPOFF_COLOR := Color("#ff8c42")

var stage: Stage = Stage.OFFLINE
var last_ride := false   # player pressed "Last Ride": next booking ends near home
var _closed_shown := false

var world: TestCity
var player: Player
var motor: Motorcycle
var hud: HUD
var phone: Phone
var cam: FollowCamera

var _rng := RandomNumberGenerator.new()
var _names: Array = []
var _personalities: Array = []
var _personality_bag: Array = []   # shuffled; refilled when empty (no repeats in a row)
var _next_request_in := 0.0
var _request: Dictionary = {}
var _request_time_left := 0.0
var _peeked := false               # phone popped up by itself for this request
var _passenger: Passenger
var _marker: TargetMarker
var _sfx: AudioStreamPlayer
var _comfort := 100.0
var _pickup_time := 0.0
var _trip_time := 0.0
var _complain_cooldown := 0.0
var _said_ride_line := false
var _board_start := Vector3.ZERO


func _ready() -> void:
	_rng.randomize()
	_marker = TargetMarker.new()
	add_child(_marker)
	_sfx = AudioStreamPlayer.new()
	_sfx.bus = "SFX"
	add_child(_sfx)
	_load_dialog()


## Called once by the game with references to everything we need.
func setup(p_world: TestCity, p_player: Player, p_motor: Motorcycle, p_hud: HUD, p_cam: FollowCamera) -> void:
	world = p_world
	player = p_player
	motor = p_motor
	hud = p_hud
	cam = p_cam
	phone = hud.phone
	phone.online_toggled.connect(_on_online_toggled)
	phone.accept_pressed.connect(accept)
	phone.decline_pressed.connect(decline)
	phone.cancel_pressed.connect(cancel_trip)
	phone.last_ride_pressed.connect(request_last_ride)
	phone.break_pressed.connect(toggle_break)
	motor.bumped.connect(_on_bumped)


func _load_dialog() -> void:
	var text := FileAccess.get_file_as_string(DIALOG_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		_names = parsed.get("names", [])
		_personalities = parsed.get("personalities", [])
	if _names.is_empty():
		_names = ["Juan"]
	if _personalities.is_empty():
		push_warning("No passenger personalities loaded from %s" % DIALOG_PATH)


## Current GPS target for the trip ({} when there's none).
func get_target() -> Dictionary:
	match stage:
		Stage.TO_PICKUP, Stage.BOARDING:
			return {"pos": _request["pickup"]["pos"], "color": PICKUP_COLOR}
		Stage.TO_DROPOFF:
			return {"pos": _request["dropoff"]["pos"], "color": DROPOFF_COLOR}
	return {}


func is_busy() -> bool:
	return stage in [Stage.TO_PICKUP, Stage.BOARDING, Stage.TO_DROPOFF]


func has_request() -> bool:
	return stage == Stage.REQUEST


# --- Main loop ---------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if world == null:
		return
	var t: Dictionary = GameState.today
	phone.set_stats(int(t["fares"]) + int(t["tips"]), int(t["rides"]), GameState.rating)
	_complain_cooldown = maxf(0.0, _complain_cooldown - delta)

	match stage:
		Stage.SEARCHING:
			_next_request_in -= delta
			if is_closed_hours():
				if not _closed_shown:
					_closed_shown = true
					phone.show_message("Sakay is resting", "No bookings from 11 PM to 5 AM. Go home and sleep!")
				_next_request_in = maxf(_next_request_in, 2.0)
			else:
				if _closed_shown:
					_closed_shown = false
					phone.show_message("Looking for passengers...", "Stay near the roads. Bookings come faster when your rating is high.")
				if _next_request_in <= 0.0:
					_make_request()
		Stage.REQUEST:
			_request_time_left -= delta
			phone.update_request_timer(_request_time_left / Economy.BOOKING_ACCEPT_SECONDS)
			if _request_time_left <= 0.0:
				decline()
				hud.show_toast("Booking expired", 2.0)
		Stage.TO_PICKUP:
			_pickup_time += delta
			var pickup_pos: Vector3 = _request["pickup"]["pos"]
			_update_nav(pickup_pos, "PICKUP · %s" % _request["name"], PICKUP_COLOR)
			if _motor_stopped_near(pickup_pos, PICKUP_RADIUS):
				_start_boarding()
		Stage.BOARDING:
			if _flat_dist(motor.global_position, _board_start) > BOARD_ABORT_DISTANCE:
				# Rider drove away: passenger goes back and keeps waiting.
				_passenger.wait_again(_request["pickup"]["pos"])
				stage = Stage.TO_PICKUP
				hud.show_dialog(str(_request["name"]), "Uy! Hulat anay! (Hey, wait!)")
		Stage.TO_DROPOFF:
			_trip_time += delta
			_track_comfort(delta)
			var drop_pos: Vector3 = _request["dropoff"]["pos"]
			_update_nav(drop_pos, "DROP-OFF · %s" % _request["dropoff"]["label"], DROPOFF_COLOR)
			if not _said_ride_line and _trip_time > 12.0:
				_said_ride_line = true
				_say("ride")
			if _motor_stopped_near(drop_pos, DROPOFF_RADIUS):
				_complete_trip()


# --- Going online / requests -------------------------------------------------

func _on_online_toggled(go_online: bool) -> void:
	if go_online:
		go_online_now()
	else:
		go_offline()


func go_online_now() -> void:
	if stage != Stage.OFFLINE:
		return
	if not GameState.has_license or not GameState.motor_available():
		phone.show_message("Can't go online yet", "You need a driver's license and a motor (bought, or rented for today at the Motor Shop).")
		hud.show_toast("You need a license and a motor first!", 2.5)
		return
	stage = Stage.SEARCHING
	last_ride = false
	_schedule_next_request(true)
	phone.set_online(true)
	_refresh_last_ride_button()
	phone.show_message("Looking for passengers...", "Stay near the roads. Bookings come faster when your rating is high.")


func go_offline() -> void:
	if is_busy():
		hud.show_toast("Finish your trip first!", 2.0)
		return
	stage = Stage.OFFLINE
	_request = {}
	last_ride = false
	phone.set_online(false)
	_refresh_last_ride_button()
	phone.show_message("You're offline", "Go online to start getting bookings from passengers around Bacolod.")
	_hide_nav()


## Wait time until the next booking. Lower rating = longer wait.
func _schedule_next_request(first: bool) -> void:
	var wait := _rng.randf_range(Economy.BOOKING_INTERVAL_MIN, Economy.BOOKING_INTERVAL_MAX)
	wait *= 1.0 + (5.0 - GameState.rating) * Economy.BOOKING_LOW_RATING_SLOWDOWN
	if first:
		wait *= 0.5
	_next_request_in = wait


func is_closed_hours() -> bool:
	var h := GameState.hour_of_day()
	return h >= CLOSED_FROM or h < OPEN_FROM


## "Last Ride" button: the next booking will be the final one, ending near home.
func request_last_ride() -> void:
	if stage == Stage.OFFLINE or last_ride:
		return
	last_ride = true
	_refresh_last_ride_button()
	hud.show_toast("Last Ride ON: your next booking drops off near home.", 3.0)
	if stage == Stage.REQUEST:
		decline()   # swap the current offer for a final one
		_next_request_in = 1.5


func _refresh_last_ride_button() -> void:
	phone.set_last_ride_state(stage != Stage.OFFLINE and stage != Stage.BREAK, last_ride)
	phone.set_break_state(stage != Stage.OFFLINE, stage == Stage.BREAK, not is_busy())


## Pause bookings for a break (eat, drink, rest) without going offline.
func toggle_break() -> void:
	if stage == Stage.BREAK:
		stage = Stage.SEARCHING
		_schedule_next_request(true)
		phone.set_status_text(" ● ONLINE ")
		phone.show_message("Looking for passengers...", "Break's over. Bookings are coming again.")
		hud.show_toast("Break over. Back to work!", 2.0)
	elif stage == Stage.SEARCHING or stage == Stage.REQUEST:
		if stage == Stage.REQUEST:
			decline()
		stage = Stage.BREAK
		phone.set_status_text(" ☕ ON BREAK ")
		phone.show_message("On break", "No bookings while you rest. Eat, drink, or stand still on foot to recover energy. Tap END BREAK when ready.")
		hud.show_toast("On break. Pahuway anay! (Rest a while)", 2.5)
	_refresh_last_ride_button()


func _make_request() -> void:
	var here := motor.global_position
	var pickup := _pick_point(here, PICKUP_MIN_M, PICKUP_MAX_M, {})
	var dropoff := {}
	if not pickup.is_empty():
		if last_ride:
			dropoff = _pick_near_home(pickup)
		else:
			dropoff = _pick_point(pickup["pos"], TRIP_MIN_M, TRIP_MAX_M, pickup)
	if pickup.is_empty() or dropoff.is_empty():
		_next_request_in = 3.0   # try again soon
		return
	var trip_m := _city_dist(pickup["pos"], dropoff["pos"])
	var lang := Settings.passenger_language
	if lang == "mixed":
		lang = ["hil", "ceb", "tl", "en"][_rng.randi() % 4]
	_request = {
		"name": _names[_rng.randi() % _names.size()],
		"rating": _rng.randf_range(4.3, 5.0),
		"personality": _next_personality(),
		"lang": lang,
		"pickup": pickup,
		"dropoff": dropoff,
		"pickup_m": _city_dist(here, pickup["pos"]),
		"trip_m": trip_m,
		"fare": Economy.calc_fare(trip_m / 1000.0, GameState.hour_of_day()),
		"surge": Economy.is_surge(GameState.hour_of_day()),
		"final": last_ride,
	}
	stage = Stage.REQUEST
	_request_time_left = Economy.BOOKING_ACCEPT_SECONDS
	phone.show_request(_request)
	_peeked = not phone.is_open
	if _peeked:
		phone.open(false)
	_play(Sfx.ping())


## Next passenger type from a shuffled bag, so every type shows up before any repeats.
func _next_personality() -> Dictionary:
	if _personalities.is_empty():
		return {}
	if _personality_bag.is_empty():
		_personality_bag = _personalities.duplicate()
		_personality_bag.shuffle()
	return _personality_bag.pop_back()


## A drop-off spot close to home (for the Last Ride).
func _pick_near_home(exclude: Dictionary) -> Dictionary:
	var home: Vector3 = world.get_place("home")["door"]
	var options: Array[Dictionary] = []
	for p in world.address_points:
		if p != exclude and _flat_dist(p["pos"], home) < HOME_DROP_RADIUS:
			options.append(p)
	if options.is_empty():
		return {}
	return options[_rng.randi() % options.size()]


## Random address point whose city-block distance from `from` is in [min_m, max_m].
func _pick_point(from: Vector3, min_m: float, max_m: float, exclude: Dictionary) -> Dictionary:
	var points := world.address_points
	for attempt in 60:
		var p: Dictionary = points[_rng.randi() % points.size()]
		if p == exclude:
			continue
		var d := _city_dist(from, p["pos"])
		if d >= min_m and d <= max_m:
			return p
	return {}


func accept() -> void:
	if stage != Stage.REQUEST:
		return
	stage = Stage.TO_PICKUP
	_refresh_last_ride_button()
	_pickup_time = 0.0
	# Spawn the passenger waiting on the sidewalk.
	_passenger = Passenger.new()
	get_parent().add_child(_passenger)
	_passenger.build(_rng, str(_request["name"]))
	var pickup: Dictionary = _request["pickup"]
	var pos: Vector3 = pickup["pos"]
	var road_dir: Vector3 = pickup["road_dir"]
	_passenger.global_position = pos
	_passenger.face(pos + road_dir)
	_passenger.reached_motor.connect(_on_passenger_reached_motor)
	_marker.show_at(pos, PICKUP_COLOR, "PICKUP: %s" % _request["name"])
	phone.show_trip("Pick up %s" % _request["name"], ["● %s" % pickup["label"], "Fare %s" % Economy.format_peso(int(_request["fare"]))], true)
	phone.set_toggle_enabled(false)
	if _peeked:
		_close_peek_later()


func decline() -> void:
	if stage != Stage.REQUEST:
		return
	stage = Stage.SEARCHING
	_request = {}
	_schedule_next_request(false)
	phone.show_message("Looking for passengers...", "Stay near the roads. Bookings come faster when your rating is high.")
	if _peeked:
		phone.close()


func cancel_trip() -> void:
	if stage != Stage.TO_PICKUP and stage != Stage.BOARDING:
		return
	if _passenger != null:
		_passenger.queue_free()
		_passenger = null
	GameState.today["cancelled"] = int(GameState.today["cancelled"]) + 1
	hud.show_toast("Trip cancelled", 2.0)
	_back_to_searching()


## Drop everything (used by debug respawn): passenger disappears, back to searching.
func abort_trip() -> void:
	if not is_busy():
		return
	motor.detach_passenger()
	if _passenger != null:
		_passenger.queue_free()
		_passenger = null
	_back_to_searching()


# --- Pickup ------------------------------------------------------------------

func _start_boarding() -> void:
	stage = Stage.BOARDING
	_board_start = motor.global_position
	# Walk to the right side of the motor, next to the back seat.
	var side := motor.global_position + motor.global_transform.basis * Vector3(0.8, 0, 0.6)
	_passenger.walk_to_motor(side)


func _on_passenger_reached_motor() -> void:
	if stage != Stage.BOARDING:
		return
	_passenger.sit_on(motor.get_seat_mount(), Motorcycle.PASSENGER_SEAT)
	motor.attach_passenger(_passenger)
	stage = Stage.TO_DROPOFF
	_trip_time = 0.0
	_comfort = 100.0
	_said_ride_line = false
	var drop: Dictionary = _request["dropoff"]
	_marker.show_at(drop["pos"], DROPOFF_COLOR, "DROP-OFF")
	phone.show_trip("Drop off %s" % _request["name"], ["● %s" % drop["label"], "Fare %s" % Economy.format_peso(int(_request["fare"]))], false)
	_say("greeting")


# --- During the ride ---------------------------------------------------------

func _track_comfort(delta: float) -> void:
	var before := _comfort
	if motor.last_accel < -HARD_BRAKE_DECEL:
		_comfort -= HARD_BRAKE_PENALTY * delta
	if motor.get_speed_kmh() > SCARY_SPEED_KMH:
		_comfort -= SCARY_SPEED_PENALTY * delta
	_comfort = maxf(0.0, _comfort)
	if _comfort < before and _comfort < 80.0:
		_maybe_complain()


func _on_bumped(impact: float) -> void:
	if stage != Stage.TO_DROPOFF:
		return
	_comfort = maxf(0.0, _comfort - impact * BUMP_PENALTY)
	_maybe_complain()


func _maybe_complain() -> void:
	if _complain_cooldown > 0.0:
		return
	_complain_cooldown = 6.0
	_say("complain")


## Called by the game when the rider crashes and falls off.
func on_crash() -> void:
	if stage != Stage.TO_DROPOFF or _passenger == null:
		return
	# Passenger falls off too, gets scared and cancels: no fare, 1 star.
	motor.detach_passenger()
	var off := motor.global_position + motor.global_transform.basis * Vector3(1.2, 0, 0.8)
	_passenger.get_off_and_leave(get_parent(), off + Vector3.UP * 0.05, _nearest_sidewalk(off))
	_say("complain")
	_passenger = null
	GameState.add_rating(1)
	GameState.today["cancelled"] = int(GameState.today["cancelled"]) + 1
	hud.show_toast("Passenger cancelled the trip!\nNo fare · ★☆☆☆☆", 3.5)
	_play(Sfx.error())
	_back_to_searching()


# --- Drop-off ----------------------------------------------------------------

func _complete_trip() -> void:
	var fare := int(_request["fare"])
	var stars := _calc_stars()
	var tip := 0
	if stars == 5 and _rng.randf() < Economy.TIP_CHANCE_5_STAR:
		tip = _rng.randi_range(Economy.TIP_MIN, Economy.TIP_MAX)

	motor.detach_passenger()
	var off := motor.global_position + motor.global_transform.basis * Vector3(1.0, 0, 0.6)
	var drop: Dictionary = _request["dropoff"]
	_passenger.get_off_and_leave(get_parent(), off + Vector3.UP * 0.05, drop["pos"])
	_passenger = null
	_say("thanks" if stars >= 3 else "complain")

	GameState.add_money(fare + tip)
	GameState.add_rating(stars)
	GameState.today["rides"] = int(GameState.today["rides"]) + 1
	GameState.today["fares"] = int(GameState.today["fares"]) + fare
	GameState.today["tips"] = int(GameState.today["tips"]) + tip

	var star_text := "★".repeat(stars) + "☆".repeat(5 - stars)
	var tip_text := "  (+%s tip!)" % Economy.format_peso(tip) if tip > 0 else ""
	hud.show_toast("+%s%s\n%s" % [Economy.format_peso(fare), tip_text, star_text], 3.5)
	_play(Sfx.cash())
	trip_completed.emit(fare, tip, stars)
	if bool(_request.get("final", false)):
		_finish_last_ride()
	else:
		_back_to_searching()


## After the final trip: go offline and head home.
func _finish_last_ride() -> void:
	_request = {}
	_marker.hide_marker()
	_hide_nav()
	phone.set_toggle_enabled(true)
	stage = Stage.OFFLINE
	last_ride = false
	phone.set_online(false)
	_refresh_last_ride_button()
	phone.show_message("That's it for today!", "Good work. Ride home, park, and press E at your door to end the day.")
	final_ride_done.emit()


## 5 stars, minus points for low comfort and slow pickup/trip.
func _calc_stars() -> int:
	var stars := 5
	if _comfort < 85.0:
		stars -= 1
	if _comfort < 65.0:
		stars -= 1
	if _comfort < 40.0:
		stars -= 1
	var expected_trip := float(_request["trip_m"]) / EXPECTED_SPEED + 20.0
	if _trip_time > expected_trip * 1.4:
		stars -= 1
	var expected_pickup := float(_request["pickup_m"]) / EXPECTED_SPEED + 30.0
	if _pickup_time > expected_pickup * 2.0:
		stars -= 1
	return clampi(stars, 1, 5)


func _back_to_searching() -> void:
	_request = {}
	_marker.hide_marker()
	_hide_nav()
	phone.set_toggle_enabled(true)
	stage = Stage.SEARCHING
	_refresh_last_ride_button()
	_schedule_next_request(false)
	phone.show_message("Looking for passengers...", "Stay near the roads. Bookings come faster when your rating is high.")


# --- Helpers -----------------------------------------------------------------

func _say(line_type: String) -> void:
	if _request.is_empty():
		return
	var person: Dictionary = _request["personality"]
	if person.is_empty():
		return
	var lines: Dictionary = person["lines"]
	var by_lang: Dictionary = lines.get(line_type, {})
	var text: String = by_lang.get(str(_request["lang"]), by_lang.get("en", ""))
	if text != "":
		hud.show_dialog(str(_request["name"]), text)


func _update_nav(target: Vector3, text: String, color: Color) -> void:
	var to := target - motor.global_position if player.state == Player.State.RIDING else target - player.global_position
	var target_yaw := atan2(-to.x, -to.z)
	var rel := wrapf(target_yaw - cam.get_yaw(), -PI, PI)
	var dist := Vector2(to.x, to.z).length()
	var dist_text := "%d m" % int(dist) if dist < 1000.0 else "%.1f km" % (dist / 1000.0)
	hud.set_nav("%s   %s" % [text, dist_text], color, rel)
	phone.set_trip_detail(dist_text)


func _hide_nav() -> void:
	hud.hide_nav()


func _motor_stopped_near(point: Vector3, radius: float) -> bool:
	return player.state == Player.State.RIDING \
		and absf(motor.speed) < STOP_SPEED \
		and _flat_dist(motor.global_position, point) < radius


func _nearest_sidewalk(from: Vector3) -> Vector3:
	var best := from
	var best_d := INF
	for p in world.address_points:
		var pos: Vector3 = p["pos"]
		var d := _flat_dist(from, pos)
		if d < best_d:
			best_d = d
			best = pos
	return best


func _close_peek_later() -> void:
	await get_tree().create_timer(2.5).timeout
	if not phone.has_mouse:
		phone.close()


func _play(stream: AudioStream) -> void:
	_sfx.stream = stream
	_sfx.play()


static func _city_dist(a: Vector3, b: Vector3) -> float:
	return absf(a.x - b.x) + absf(a.z - b.z)


static func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
