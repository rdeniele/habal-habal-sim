extends Node3D
## Main gameplay scene.
## Connects the world, player, motorcycle, camera, HUD and the booking system:
## - F to get on/off the motor (only when close / stopped)
## - E to interact: refuel at a gas pump, enter places (shops open in Milestone 3)
## - Tab opens the Sakay phone, 1 / 2 accept / decline bookings
## - handles crashes (rider gets thrown off, passenger cancels)
## - runs the story/tutorial on a new game, and the Motor Shop (buy/rent/repair/sell)
## - day cycle: end the day at home (E at your door), rent, End of Day screen, auto-save
## - Esc pause menu: settings, save (at home), quit to menu

signal shop_purchased

const MOUNT_DISTANCE := 2.6
const INTERACT_DISTANCE := 3.2
const MAX_DISMOUNT_SPEED := 2.0   # m/s (~7 km/h)
const PUMP_RADIUS_RIDING := 4.5   # how close the motor must stop to the pump
const PUMP_MOTOR_RADIUS := 8.0    # on foot: motor must be parked this close to the pump
const HOME_MOTOR_RADIUS := 20.0   # motor must be parked this close to home to end the day / save
const PASS_OUT_HOUR := 26.0       # 2:00 AM (next day): you fall asleep wherever you are
const MAIN_MENU := "res://scenes/main_menu/main_menu.tscn"

@onready var world: TestCity = $World
@onready var player: Player = $Player
@onready var motor: Motorcycle = $Motorcycle
@onready var cam: FollowCamera = $CameraRig
@onready var hud: HUD = $HUD
@onready var booking: BookingSystem = $BookingSystem
@onready var story: Story = $Story

var day_cycle: DayCycle
var _sfx: AudioStreamPlayer
var _last_ui_open := false
var _ending_day := false


func _ready() -> void:
	player.camera = cam
	motor.setup(GameState.current_motor_id, GameState.motor_color_index)
	motor.set_active(GameState.has_motor())
	if GameState.motor_fuel >= 0.0:   # loaded from a save
		motor.fuel_liters = minf(GameState.motor_fuel, motor.get_tank_liters())
	motor.damage = GameState.motor_damage
	motor.crashed.connect(_on_motor_crashed)
	motor.ran_out_of_fuel.connect(_on_out_of_fuel)
	booking.setup(world, player, motor, hud, cam)
	hud.refuel_menu.amount_chosen.connect(_on_refuel_chosen)
	hud.shop.purchase.connect(_on_shop_purchase)
	hud.shop.repair_pressed.connect(_on_shop_repair)
	hud.shop.sell_pressed.connect(_on_shop_sell)
	story.setup(self, world, player, motor, hud, cam, booking)
	booking.final_ride_done.connect(_on_final_ride_done)
	hud.pause_menu.save_requested.connect(_on_save_requested)
	hud.pause_menu.quit_to_menu_requested.connect(_quit_to_menu)
	day_cycle = DayCycle.new()
	add_child(day_cycle)
	day_cycle.setup(world, motor, cam)
	_sfx = AudioStreamPlayer.new()
	_sfx.bus = "SFX"
	add_child(_sfx)
	respawn_at_home()
	_refresh_mouse(true)
	if not GameState.story_done:
		story.start()
		return
	hud.show_toast("DAY %d · Maayong aga, %s!\nGet on your motor (F), then Tab and GO ONLINE." % [GameState.day, GameState.player_name], 7.0)


func _physics_process(delta: float) -> void:
	if not _ending_day:
		GameState.advance_time(delta)
	# Stayed out too late: you fall asleep and wake up at home.
	if GameState.story_done and GameState.time_hours >= PASS_OUT_HOUR and not _ending_day:
		_end_day(true)
	if player.state == Player.State.RIDING:
		player.global_position = motor.global_position   # keep the player "with" the motor
	# Freeze the player while a dialog / shop / license card is up.
	var blocked := hud.dialog_box.is_open or hud.license_card.visible or hud.shop.visible \
		or hud.refuel_menu.visible or hud.end_of_day.visible or _ending_day
	player.input_enabled = not blocked
	motor.input_enabled = not blocked
	_refresh_mouse()
	_update_prompt()
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if hud.dialog_box.is_open or hud.license_card.visible or hud.shop.visible \
			or hud.end_of_day.visible or _ending_day:
		return
	var menu := hud.refuel_menu
	# While the gas pump menu is open, it gets the keys first.
	if menu.visible:
		if event.is_action_pressed("option_1"):
			menu.choose(0)
		elif event.is_action_pressed("option_2"):
			menu.choose(1)
		elif event.is_action_pressed("option_3"):
			menu.choose(2)
		elif event.is_action_pressed("pause") or event.is_action_pressed("interact"):
			menu.close_menu()
		return

	if event.is_action_pressed("enter_exit"):
		_toggle_ride()
	elif event.is_action_pressed("interact"):
		_interact()
	elif event.is_action_pressed("toggle_help"):
		hud.toggle_help()
	elif event.is_action_pressed("phone"):
		_toggle_phone()
	elif event.is_action_pressed("option_1") and booking.has_request():
		booking.accept()
	elif event.is_action_pressed("option_2") and booking.has_request():
		booking.decline()
	elif event.is_action_pressed("pause"):
		if hud.phone.is_open:
			hud.phone.close()
			_refresh_mouse(true)
		else:
			_open_pause_menu()
	elif event.is_action_pressed("debug_respawn"):
		booking.abort_trip()
		respawn_at_home()
		hud.show_toast("Respawned at home", 2.0)


# --- Phone & mouse -----------------------------------------------------------

## Tab: open the phone with the mouse free (to click), or close it.
func _toggle_phone() -> void:
	var phone := hud.phone
	if phone.is_open and phone.has_mouse:
		phone.close()
	else:
		phone.open(true)
	_refresh_mouse(true)


## Free the mouse while a clickable menu is open, lock it when the menu closes.
## (Only changes the mouse when the menu state changes, so Esc can still free it.)
func _refresh_mouse(force: bool = false) -> void:
	var ui_open := hud.is_menu_open()
	cam.ui_open = ui_open
	if force or ui_open != _last_ui_open:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if ui_open else Input.MOUSE_MODE_CAPTURED
	_last_ui_open = ui_open


# --- Get on / get off --------------------------------------------------------

func _toggle_ride() -> void:
	match player.state:
		Player.State.ON_FOOT:
			if _near_motor():
				_mount()
		Player.State.RIDING:
			if absf(motor.speed) > MAX_DISMOUNT_SPEED:
				hud.show_toast("Hinay-hinay anay! (Stop first)", 2.0)
				return
			_dismount()


func _mount() -> void:
	player.set_riding(true)
	motor.set_ridden(true)
	cam.set_target(motor, true)


func _dismount() -> void:
	motor.set_ridden(false)
	player.set_riding(false)
	# Step off to the left; if blocked try the right, then behind.
	var b := motor.global_transform.basis
	var spot := motor.global_position + Vector3.UP * 0.3
	for offset: Vector3 in [Vector3(-0.95, 0, 0), Vector3(0.95, 0, 0), Vector3(0, 0, 1.5)]:
		var candidate := motor.global_position + b * offset + Vector3.UP * 0.3
		if player.is_spot_free(candidate):
			spot = candidate
			break
	player.teleport(spot)
	player.face_yaw(motor.heading)
	cam.set_target(player, false)


func _near_motor() -> bool:
	return motor.is_active and player.global_position.distance_to(motor.global_position) < MOUNT_DISTANCE


# --- Crashes & fuel ----------------------------------------------------------

func _on_motor_crashed(impact: float, wall_normal: Vector3) -> void:
	if player.state != Player.State.RIDING:
		return
	booking.on_crash()   # passenger falls off and cancels (if any)
	story.on_crash()     # fails passenger training (if running)
	motor.set_ridden(false)
	motor.fall_over()
	# Throw the rider away from the wall, a bit up in the air.
	var from := motor.global_position + wall_normal * 1.2 + Vector3.UP * 0.9
	player.knock_off(from, wall_normal * 3.0 + Vector3.UP * 3.5, impact)
	cam.set_target(player, false)
	hud.show_toast("Aray! Natumba ka! (You crashed)\nPress F near the motor to pick it up.", 3.5)


func _on_out_of_fuel() -> void:
	hud.show_toast("Wala na gasolina! (Out of gas)\nHold W to push it to a gas station.", 4.0)


# --- Gas station -------------------------------------------------------------

func _pump_position() -> Vector3:
	var gas := world.get_place("gas_station")
	return gas["door"] if not gas.is_empty() else Vector3(INF, 0, INF)


## Riding: stopped at the pump. On foot: standing at the pump with the motor parked close.
func _can_refuel() -> bool:
	var pump := _pump_position()
	match player.state:
		Player.State.RIDING:
			return absf(motor.speed) < 0.6 and _flat_dist(motor.global_position, pump) < PUMP_RADIUS_RIDING
		Player.State.ON_FOOT:
			return _flat_dist(player.global_position, pump) < INTERACT_DISTANCE \
				and _flat_dist(motor.global_position, pump) < PUMP_MOTOR_RADIUS
	return false


func _open_refuel_menu() -> void:
	hud.refuel_menu.open_menu(motor.fuel_liters, motor.get_tank_liters(), GameState.money)
	_refresh_mouse()


func _on_refuel_chosen(liters: float) -> void:
	var price := float(Economy.GAS_PRICE_PER_LITER)
	# If you can't afford it all, buy what your wallet allows.
	var affordable := minf(liters, GameState.money / price)
	if affordable < 0.05:
		hud.show_toast("Kulang ang kwarta! (Not enough money)", 2.5)
		return
	var added := motor.refuel(affordable)
	var cost := int(ceil(added * price))
	GameState.add_money(-cost)
	GameState.today["gas_spent"] = int(GameState.today["gas_spent"]) + cost
	_sfx.stream = Sfx.cash()
	_sfx.play()
	hud.show_toast("Nagpagasolina: %.1f L · -%s" % [added, Economy.format_peso(cost)], 3.0)


# --- Interact with places ----------------------------------------------------

func _nearest_place() -> Dictionary:
	var best: Dictionary = {}
	var best_dist := INTERACT_DISTANCE
	for place: Dictionary in world.places:
		var door: Vector3 = place["door"]
		var d := player.global_position.distance_to(door)
		if d < best_dist:
			best_dist = d
			best = place
	return best


func _interact() -> void:
	if story.try_interact():
		return
	if motor.is_active and _can_refuel():
		_open_refuel_menu()
		return
	if player.state != Player.State.ON_FOOT:
		return
	var place := _nearest_place()
	if place.is_empty():
		return
	match str(place["id"]):
		"gas_station":
			hud.show_toast("Park your motor near the pump first (or ride in and stop at the pump).", 3.0)
		"motor_shop":
			if story.active:
				hud.show_toast("Finish what you're doing first.", 2.0)
			else:
				open_shop(false)
		"home":
			_try_end_day()
		_:
			hud.show_toast("%s\nSarado pa. Abi-abi lang! (Opens later)" % place["name"], 3.0)


# --- Motor Shop --------------------------------------------------------------

func open_shop(tutorial: bool) -> void:
	var shop_door: Vector3 = world.get_place("motor_shop")["door"]
	var near := motor.is_active and _flat_dist(motor.global_position, shop_door) < 20.0
	hud.shop.open_shop({
		"money": GameState.money,
		"mode": GameState.motor_mode,
		"current_id": GameState.current_motor_id,
		"color_index": GameState.motor_color_index,
		"damage": motor.damage if motor.is_active else 0.0,
		"motor_near": near,
		"tutorial": tutorial,
	})


## Trade-in value of the motor you own (0 if renting / none).
func _trade_in_value() -> int:
	if GameState.motor_mode != "own":
		return 0
	return int(int(Motors.get_motor(GameState.current_motor_id)["price"]) * Economy.SELL_BACK_RATIO)


func _on_shop_purchase(motor_id: String, color_index: int, mode: String) -> void:
	if booking.is_busy():
		hud.show_toast("Finish your trip first!", 2.0)
		return
	var info := Motors.get_motor(motor_id)
	var trade_in := _trade_in_value()
	if mode == "buy":
		var net := int(info["price"]) - trade_in
		if net > GameState.money:
			_play(Sfx.error())
			hud.show_toast("Kulang ang kwarta! (Not enough money)", 2.5)
			return
		GameState.add_money(-net)
	else:
		GameState.add_money(trade_in)   # renting: sell the old one if you owned it
	GameState.motor_mode = "own" if mode == "buy" else "rent"
	GameState.current_motor_id = motor_id
	GameState.motor_color_index = color_index
	if player.state == Player.State.RIDING:
		_dismount()
	motor.setup(motor_id, color_index)
	motor.set_active(true)
	_park_motor_at("motor_shop")
	hud.shop.close_shop()
	_play(Sfx.cash())
	var bought := mode == "buy"
	hud.show_toast("%s ang %s! (You %s it)\nIt's parked outside the shop." \
		% ["Nabakal mo" if bought else "Gin-rentahan mo", info["name"], "bought" if bought else "rented"], 4.0)
	shop_purchased.emit()


func _on_shop_repair() -> void:
	var cost := int(ceil(motor.damage)) * Economy.REPAIR_COST_PER_DAMAGE_POINT
	if cost <= 0 or not GameState.spend(cost):
		_play(Sfx.error())
		return
	motor.damage = 0.0
	GameState.today["repairs"] = int(GameState.today["repairs"]) + cost
	_play(Sfx.cash())
	hud.show_toast("Naayo na! (Repaired)  -%s" % Economy.format_peso(cost), 3.0)
	open_shop(false)


func _on_shop_sell() -> void:
	if booking.is_busy():
		hud.show_toast("Finish your trip first!", 2.0)
		return
	var value := _trade_in_value()
	if value <= 0:
		return
	if player.state == Player.State.RIDING:
		_dismount()
	booking.go_offline()
	GameState.add_money(value)
	GameState.motor_mode = "none"
	motor.set_active(false)
	_play(Sfx.cash())
	hud.show_toast("Nabaligya mo ang motor (+%s).\nBuy or rent another one to keep working." % Economy.format_peso(value), 4.0)
	open_shop(false)


func _park_motor_at(place_id: String) -> void:
	var place := world.get_place(place_id)
	var door: Vector3 = place["door"]
	var fz: float = place["front_z"]
	motor.place(door + Vector3(2.5, 0.2, fz * 3.2), -PI * 0.5)


func _play(stream: AudioStream) -> void:
	_sfx.stream = stream
	_sfx.play()


# --- End of day, rent, saving ----------------------------------------------

func _on_final_ride_done() -> void:
	hud.set_objective("Last ride done", "Ride home, park your motor, and press E at your door to end the day.")


func _motor_at_home() -> bool:
	var door: Vector3 = world.get_place("home")["door"]
	return not motor.is_active or _flat_dist(motor.global_position, door) < HOME_MOTOR_RADIUS


func _player_at_home() -> bool:
	var door: Vector3 = world.get_place("home")["door"]
	return player.state == Player.State.ON_FOOT and _flat_dist(player.global_position, door) < INTERACT_DISTANCE


## E at your front door.
func _try_end_day() -> void:
	if not GameState.story_done:
		return
	if booking.is_busy():
		hud.show_toast("You still have a passenger / trip! Finish it first.", 2.5)
		return
	if not _motor_at_home():
		hud.show_toast("Park your motor at home first (it's not here).", 2.5)
		return
	_end_day(false)


## Ends the day: pay rent, show the summary, auto-save, start the next morning.
## `passed_out` = you stayed out past 2 AM and fell asleep.
func _end_day(passed_out: bool) -> void:
	_ending_day = true
	booking.abort_trip()
	booking.go_offline()
	hud.phone.close()
	hud.set_objective("", "")
	if player.state == Player.State.RIDING:
		_dismount()
	await hud.fade_out(0.7)

	var notes: Array[String] = []
	if passed_out:
		notes.append("Nakatulog ka sa dalan! You stayed out past 2 AM and fell asleep. Your motor was brought home.")
	notes.append_array(_pay_rent())

	var t: Dictionary = GameState.today
	var summary := {
		"day": GameState.day, "rides": t["rides"], "fares": t["fares"], "tips": t["tips"],
		"gas_spent": t["gas_spent"], "rent_paid": t["rent_paid"], "clinic": t["clinic"],
		"repairs": t["repairs"], "money": GameState.money, "debt": GameState.debt,
		"rating": GameState.rating, "notes": notes,
	}
	await hud.end_of_day.show_summary(summary)

	# Next morning
	GameState.day += 1
	GameState.time_hours = Economy.DAY_START_HOUR
	GameState.reset_today()
	respawn_at_home()
	_sync_motor_to_state()
	var saved := SaveManager.save_game(maxi(GameState.save_slot, 1))
	await hud.show_caption("DAY %d" % GameState.day)
	await get_tree().create_timer(1.2).timeout
	await hud.fade_in(0.7)
	hud.show_toast("Maayong aga! Day %d.%s" % [GameState.day, "  (Auto-saved)" if saved else ""], 4.0)
	_ending_day = false


## Daily boundary for renters. Returns notes for the summary screen.
func _pay_rent() -> Array[String]:
	var notes: Array[String] = []
	if GameState.motor_mode != "rent":
		return notes
	var due := Economy.RENT_PER_DAY + GameState.debt
	if GameState.money >= due:
		GameState.add_money(-due)
		GameState.today["rent_paid"] = due
		GameState.debt = 0
		GameState.rent_unpaid_days = 0
		return notes
	# Can't pay: it becomes debt.
	GameState.debt += Economy.RENT_PER_DAY
	GameState.rent_unpaid_days += 1
	if GameState.rent_unpaid_days >= Economy.RENT_MAX_UNPAID_DAYS:
		notes.append("Gin-kuha na ang motor! You couldn't pay the boundary for %d days, so the motor was taken back. Rent or buy another at the Motor Shop." % GameState.rent_unpaid_days)
		GameState.motor_mode = "none"
		GameState.debt = 0
		GameState.rent_unpaid_days = 0
		motor.set_active(false)
	else:
		notes.append("Kulang ang kwarta for the boundary! Debt is now %s. %d more unpaid day(s) and the motor gets taken back." \
			% [Economy.format_peso(GameState.debt), Economy.RENT_MAX_UNPAID_DAYS - GameState.rent_unpaid_days])
	return notes


## Copy the motor's fuel and damage into GameState (so they get saved).
func _sync_motor_to_state() -> void:
	GameState.motor_fuel = motor.fuel_liters if motor.is_active else -1.0
	GameState.motor_damage = motor.damage if motor.is_active else 0.0


# --- Pause menu --------------------------------------------------------------

func _open_pause_menu() -> void:
	var pm := hud.pause_menu
	pm.can_save = GameState.story_done and _player_at_home() and _motor_at_home() and not booking.is_busy()
	if not GameState.story_done:
		pm.save_hint = "You can save after the tutorial."
	elif not _player_at_home():
		pm.save_hint = "You can only save at home (stand at your front door)."
	elif not _motor_at_home():
		pm.save_hint = "Park your motor at home to save."
	else:
		pm.save_hint = "Finish your trip first."
	pm.open()


func _on_save_requested() -> void:
	_sync_motor_to_state()
	var slot := maxi(GameState.save_slot, 1)
	if SaveManager.save_game(slot):
		hud.pause_menu.show_info("Saved to slot %d!" % slot)
	else:
		hud.pause_menu.show_info("Could not save!")


func _quit_to_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU)


# --- Respawn & HUD -----------------------------------------------------------

func respawn_at_home() -> void:
	var spawn := world.get_spawn()
	motor.set_ridden(false)
	player.set_riding(false)
	player.teleport(spawn["player_pos"])
	player.face_yaw(spawn["camera_yaw"])
	motor.place(spawn["motor_pos"], spawn["motor_heading"])
	motor.set_active(GameState.has_motor())
	cam.set_target(player, false)
	cam.snap_to(spawn["camera_yaw"])


func _update_prompt() -> void:
	var text := ""
	if hud.refuel_menu.visible or hud.dialog_box.is_open or hud.shop.visible or hud.license_card.visible:
		hud.set_prompt("")
		return
	var story_prompt := story.get_prompt()
	if story_prompt != "":
		text = story_prompt
	elif motor.is_active and _can_refuel():
		text = "[E]  Magpagasolina  (Refuel)"
	else:
		match player.state:
			Player.State.ON_FOOT:
				if GameState.story_done and _player_at_home() and not _near_motor():
					text = "[E]  Matulog  (End the day)"
				elif _near_motor():
					text = "[F]  Sakay sa motor  (Get on)"
				else:
					var place := _nearest_place()
					if not place.is_empty():
						text = "[E]  %s" % place["name"]
			Player.State.RIDING:
				if booking.has_request():
					text = "[1]  Accept booking     [2]  Decline"
				elif absf(motor.speed) < 0.5:
					text = "[F]  Panaog  (Get off)"
	hud.set_prompt(text)


func _update_hud() -> void:
	var riding := player.state == Player.State.RIDING
	hud.set_money(GameState.money)
	hud.set_clock(GameState.day, GameState.get_time_string())
	hud.update_vehicle(riding and motor.is_active, motor.get_speed_kmh(), motor.get_fuel_ratio(), motor.get_display_name(), motor.damage)
	hud.update_health(not riding, player.health / Player.MAX_HEALTH)


static func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
