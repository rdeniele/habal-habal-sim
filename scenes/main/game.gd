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
const STALL_RADIUS := 2.6         # how close to stand to a sari-sari store
const GPS_REFRESH := 0.4          # seconds between GPS route updates

@onready var world: TestCity = $World
@onready var player: Player = $Player
@onready var motor: Motorcycle = $Motorcycle
@onready var cam: FollowCamera = $CameraRig
@onready var hud: HUD = $HUD
@onready var booking: BookingSystem = $BookingSystem
@onready var story: Story = $Story

var day_cycle: DayCycle
var needs: Needs
var _gps_route := PackedVector3Array()
var _gps_timer := 0.0
var _gps_goal := ""               # "" / "home" / "shop": where the day-end GPS points
var _sfx: AudioStreamPlayer
var _last_ui_open := false
var _ending_day := false


func _ready() -> void:
	player.camera = cam
	motor.setup(GameState.current_motor_id, GameState.motor_color_index)
	motor.set_active(GameState.motor_available())
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
	hud.shop.return_pressed.connect(_on_shop_return)
	story.setup(self, world, player, motor, hud, cam, booking)
	booking.final_ride_done.connect(_on_final_ride_done)
	hud.pause_menu.save_requested.connect(_on_save_requested)
	hud.pause_menu.quit_to_menu_requested.connect(_quit_to_menu)
	day_cycle = DayCycle.new()
	add_child(day_cycle)
	day_cycle.setup(world, motor, cam)
	needs = Needs.new()
	add_child(needs)
	needs.setup(player, motor, hud)
	needs.fainted.connect(_on_fainted)
	hud.food_menu.item_chosen.connect(_on_food_chosen)
	hud.set_map_world(world)
	_sfx = AudioStreamPlayer.new()
	_sfx.bus = "SFX"
	add_child(_sfx)
	respawn_at_home()
	_refresh_mouse(true)
	if not GameState.story_done:
		story.start()
		return
	_morning_message()


## What to do this morning (renters first need to rent at the shop next door).
func _morning_message() -> void:
	if GameState.motor_mode == "rent" and not GameState.rental_out:
		hud.show_toast("DAY %d · Maayong aga, %s!\nRent a motor at the Motor Shop next door, then GO ONLINE." % [GameState.day, GameState.player_name], 7.0)
		hud.set_objective("Day %d" % GameState.day, "Rent today's motor at the Motor Shop (west of your house, E at its door).")
	elif not GameState.has_motor():
		hud.show_toast("DAY %d · You have no motor. Buy or rent one at the Motor Shop." % GameState.day, 7.0)
	else:
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
		or hud.refuel_menu.visible or hud.food_menu.visible or hud.end_of_day.visible or _ending_day
	needs.paused = _ending_day or story.active
	player.input_enabled = not blocked
	motor.input_enabled = not blocked
	_refresh_mouse()
	_update_prompt()
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if hud.dialog_box.is_open or hud.license_card.visible or hud.shop.visible \
			or hud.end_of_day.visible or _ending_day:
		return
	if hud.food_menu.visible:
		for i in 6:
			if event.is_action_pressed("option_%d" % (i + 1)):
				hud.food_menu.choose(i)
				return
		if event.is_action_pressed("pause") or event.is_action_pressed("interact"):
			hud.food_menu.close_menu()
		return
	if event.is_action_pressed("map"):
		hud.toggle_full_map()
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
	if _near_stall():
		hud.food_menu.open_menu()
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
		"rental_out": GameState.rental_out,
		"debt": GameState.debt,
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
	GameState.rental_out = mode == "rent"
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
	if mode == "rent":
		hud.set_objective("Rented for today", "Ride! Return it here and pay %s at the end of the day." % Economy.format_peso(Economy.RENT_PER_DAY))
	else:
		hud.set_objective("", "")
	shop_purchased.emit()


## Give back today's rental and pay the boundary (+ any old debt).
func _on_shop_return() -> void:
	if booking.is_busy():
		hud.show_toast("Finish your trip first!", 2.0)
		return
	if player.state == Player.State.RIDING:
		_dismount()
	booking.go_offline()
	var due := Economy.RENT_PER_DAY + GameState.debt
	if GameState.money >= due:
		GameState.add_money(-due)
		GameState.today["rent_paid"] = int(GameState.today["rent_paid"]) + due
		GameState.debt = 0
		GameState.rent_unpaid_days = 0
		_play(Sfx.cash())
		hud.show_toast("Motor returned. Boundary paid: -%s\nSalamat, boss! Walk home and rest (E at your door)." % Economy.format_peso(due), 4.0)
	else:
		_add_unpaid_day()
		_play(Sfx.error())
		hud.show_toast("Motor returned, but you couldn't pay! Debt: %s" % Economy.format_peso(GameState.debt), 4.0)
	GameState.rental_out = false
	_sync_motor_to_state()
	motor.set_active(false)
	hud.set_objective("Day done", "Walk home and press E at your door to end the day.")
	_gps_goal = "home"
	open_shop(false)


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
	_gps_goal = "shop" if GameState.motor_mode == "rent" else "home"
	if GameState.motor_mode == "rent":
		hud.set_objective("Last ride done", "Return the motor to the Motor Shop and pay the boundary, then walk home (E at your door).")
	else:
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
		"repairs": t["repairs"], "food": t.get("food", 0), "money": GameState.money, "debt": GameState.debt,
		"rating": GameState.rating, "notes": notes,
	}
	await hud.end_of_day.show_summary(summary)

	# Next morning
	_gps_goal = ""
	GameState.wake_up_needs()
	player.health = Player.MAX_HEALTH
	GameState.day += 1
	GameState.time_hours = Economy.DAY_START_HOUR
	GameState.reset_today()
	respawn_at_home()
	_sync_motor_to_state()
	var saved := SaveManager.save_game(maxi(GameState.save_slot, 1))
	await hud.show_caption("DAY %d" % GameState.day)
	await get_tree().create_timer(1.2).timeout
	await hud.fade_in(0.7)
	_ending_day = false
	_morning_message()
	if saved:
		hud.show_toast("Day %d · Auto-saved" % GameState.day, 2.5)


## Renters who didn't return the motor today: the boundary becomes debt.
## Returns notes for the summary screen.
func _pay_rent() -> Array[String]:
	var notes: Array[String] = []
	if GameState.motor_mode != "rent" or not GameState.rental_out:
		return notes
	notes.append("You didn't return the rented motor! Today's boundary (%s) was added to your debt." % Economy.format_peso(Economy.RENT_PER_DAY))
	var taken := _add_unpaid_day()
	if taken:
		notes.append("Gin-kuha na ang motor! You couldn't pay the boundary for %d days, so the motor was taken back. Rent or buy another at the Motor Shop." % Economy.RENT_MAX_UNPAID_DAYS)
	else:
		notes.append("Debt is now %s. %d more unpaid day(s) and the motor gets taken back." \
			% [Economy.format_peso(GameState.debt), Economy.RENT_MAX_UNPAID_DAYS - GameState.rent_unpaid_days])
	return notes


## One more unpaid boundary. Returns true if the motor got taken back (3 unpaid days).
func _add_unpaid_day() -> bool:
	GameState.debt += Economy.RENT_PER_DAY
	GameState.rent_unpaid_days += 1
	if GameState.rent_unpaid_days < Economy.RENT_MAX_UNPAID_DAYS:
		return false
	GameState.motor_mode = "none"
	GameState.rental_out = false
	GameState.debt = 0
	GameState.rent_unpaid_days = 0
	motor.set_active(false)
	return true


## Copy the motor's fuel and damage into GameState (so they get saved).
func _sync_motor_to_state() -> void:
	GameState.motor_fuel = motor.fuel_liters if motor.is_active else -1.0
	GameState.motor_damage = motor.damage if motor.is_active else 0.0


# --- Food, fainting ---------------------------------------------------------

func _near_stall() -> bool:
	if player.state != Player.State.ON_FOOT:
		return false
	for s in world.food_stalls:
		if _flat_dist(player.global_position, s) < STALL_RADIUS:
			return true
	return false


func _on_food_chosen(item: Dictionary) -> void:
	var price := int(item["price"])
	if not GameState.spend(price):
		_play(Sfx.error())
		return
	GameState.today["food"] = int(GameState.today.get("food", 0)) + price
	needs.consume(item)
	_play(Sfx.tones([660.0, 880.0], 0.07))
	hud.show_toast("Namit! %s  -%s" % [item["name"], Economy.format_peso(price)], 2.0)


## Too hungry / thirsty / tired: you wake up at the clinic and pay the fee.
func _on_fainted(reason: String) -> void:
	if _ending_day:
		return
	_ending_day = true
	booking.abort_trip()
	if player.state == Player.State.RIDING:
		motor.set_ridden(false)
		player.set_riding(false)
	await hud.fade_out(0.6)
	await hud.show_caption("Nakuyapan ka!\n(You fainted)")
	var clinic: Dictionary = world.get_place("clinic")
	var door: Vector3 = clinic["door"]
	player.teleport(door + Vector3(0, 0.2, 0))
	cam.set_target(player, false)
	if motor.is_active:
		_park_motor_at("clinic")
	var fee := mini(Economy.CLINIC_FEE, maxi(GameState.money, 0))
	GameState.add_money(-fee)
	GameState.today["clinic"] = int(GameState.today["clinic"]) + fee
	GameState.hunger = maxf(GameState.hunger, 50.0)
	GameState.thirst = maxf(GameState.thirst, 50.0)
	GameState.energy = maxf(GameState.energy, 50.0)
	player.health = 60.0
	GameState.time_hours += 2.0   # lost time at the clinic
	await get_tree().create_timer(1.5).timeout
	await hud.fade_in(0.6)
	hud.show_toast("%s\nThe clinic took care of you: -%s. Eat, drink and rest!" % [reason, Economy.format_peso(fee)], 5.0)
	_ending_day = false


# --- GPS & map ---------------------------------------------------------------

## Where the GPS should point: trip target, story target, or home/shop at day end.
func _gps_target() -> Dictionary:
	var bt := booking.get_target()
	if not bt.is_empty():
		return bt
	if story.active and story._has_target:
		return {"pos": story._target, "color": story._target_color, "label": story._target_text}
	if _gps_goal == "shop" and GameState.rental_out:
		return {"pos": world.get_place("motor_shop")["door"], "color": Color("#8338ec"), "label": "MOTOR SHOP (return)"}
	if _gps_goal != "" or (GameState.story_done and GameState.hour_of_day() >= 22.0):
		return {"pos": world.get_place("home")["door"], "color": Color("#ffd166"), "label": "HOME"}
	return {}


func _update_gps() -> void:
	var me := motor.global_position if player.state == Player.State.RIDING else player.global_position
	var facing := motor.heading if player.state == Player.State.RIDING else player.get_facing_yaw()
	var target := _gps_target()
	_gps_timer -= get_physics_process_delta_time()
	if target.is_empty():
		_gps_route = PackedVector3Array()
	elif _gps_timer <= 0.0:
		_gps_timer = GPS_REFRESH
		_gps_route = world.road_graph.route(me, target["pos"])
	var has_target := not target.is_empty()
	hud.update_map(me, cam.get_yaw(), facing, _gps_route, has_target,
		target["pos"] if has_target else Vector3.ZERO, target["color"] if has_target else Color.WHITE)
	# The top arrow for home/shop (bookings and the story set their own).
	if has_target and target.has("label") and booking.get_target().is_empty() and not story._has_target:
		var to: Vector3 = target["pos"] - me
		var rel := wrapf(atan2(-to.x, -to.z) - cam.get_yaw(), -PI, PI)
		var left := RoadGraph.path_length(_gps_route) if _gps_route.size() > 1 else Vector2(to.x, to.z).length()
		hud.set_nav("%s   %d m" % [target["label"], int(left)], target["color"], rel)
	elif not has_target and booking.get_target().is_empty() and not story._has_target:
		hud.hide_nav()


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
	motor.set_active(GameState.motor_available())
	cam.set_target(player, false)
	cam.snap_to(spawn["camera_yaw"])


func _update_prompt() -> void:
	var text := ""
	if hud.refuel_menu.visible or hud.food_menu.visible or hud.dialog_box.is_open or hud.shop.visible or hud.license_card.visible:
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
				elif _near_stall():
					text = "[E]  Sari-sari store  (food & drinks)"
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
	_update_gps()


static func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
