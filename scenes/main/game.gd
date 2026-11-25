extends Node3D
## Main gameplay scene.
## Connects the world, player, motorcycle, camera, HUD and the booking system:
## - F to get on/off the motor (only when close / stopped)
## - E to interact: refuel at a gas pump, enter places (shops open in Milestone 3)
## - Tab opens the Sakay phone, 1 / 2 accept / decline bookings
## - handles crashes (rider gets thrown off, passenger cancels)

const MOUNT_DISTANCE := 2.6
const INTERACT_DISTANCE := 3.2
const MAX_DISMOUNT_SPEED := 2.0   # m/s (~7 km/h)
const PUMP_RADIUS_RIDING := 4.5   # how close the motor must stop to the pump
const PUMP_MOTOR_RADIUS := 8.0    # on foot: motor must be parked this close to the pump

@onready var world: TestCity = $World
@onready var player: Player = $Player
@onready var motor: Motorcycle = $Motorcycle
@onready var cam: FollowCamera = $CameraRig
@onready var hud: HUD = $HUD
@onready var booking: BookingSystem = $BookingSystem

var _sfx: AudioStreamPlayer


func _ready() -> void:
	player.camera = cam
	motor.setup(GameState.current_motor_id)
	motor.crashed.connect(_on_motor_crashed)
	motor.ran_out_of_fuel.connect(_on_out_of_fuel)
	booking.setup(world, player, motor, hud, cam)
	hud.refuel_menu.amount_chosen.connect(_on_refuel_chosen)
	hud.refuel_menu.closed.connect(_refresh_mouse)
	_sfx = AudioStreamPlayer.new()
	add_child(_sfx)
	_respawn_at_home()
	_refresh_mouse()
	hud.show_toast("Maayong aga, boss! Walk to your motor and press F.\nThen press Tab and GO ONLINE in the Sakay app.", 9.0)


func _physics_process(delta: float) -> void:
	GameState.advance_time(delta)
	if player.state == Player.State.RIDING:
		player.global_position = motor.global_position   # keep the player "with" the motor
	_update_prompt()
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
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
	elif event.is_action_pressed("pause") and hud.phone.is_open:
		hud.phone.close()
		_refresh_mouse()
	elif event.is_action_pressed("debug_respawn"):
		booking.abort_trip()
		_respawn_at_home()
		hud.show_toast("Respawned at home", 2.0)


# --- Phone & mouse -----------------------------------------------------------

## Tab: open the phone with the mouse free (to click), or close it.
func _toggle_phone() -> void:
	var phone := hud.phone
	if phone.is_open and phone.has_mouse:
		phone.close()
	else:
		phone.open(true)
	_refresh_mouse()


## Free the mouse while a clickable menu is open, lock it otherwise.
func _refresh_mouse() -> void:
	var ui_open := hud.refuel_menu.visible or (hud.phone.is_open and hud.phone.has_mouse)
	cam.ui_open = ui_open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if ui_open else Input.MOUSE_MODE_CAPTURED


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
	return player.global_position.distance_to(motor.global_position) < MOUNT_DISTANCE


# --- Crashes & fuel ----------------------------------------------------------

func _on_motor_crashed(impact: float, wall_normal: Vector3) -> void:
	if player.state != Player.State.RIDING:
		return
	booking.on_crash()   # passenger falls off and cancels (if any)
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
	if _can_refuel():
		_open_refuel_menu()
		return
	if player.state != Player.State.ON_FOOT:
		return
	var place := _nearest_place()
	if place.is_empty():
		return
	if place["id"] == "gas_station":
		hud.show_toast("Park your motor near the pump first (or ride in and stop at the pump).", 3.0)
		return
	hud.show_toast("%s\nSarado pa. Abi-abi lang! (Opens in a later milestone)" % place["name"], 3.0)


# --- Respawn & HUD -----------------------------------------------------------

func _respawn_at_home() -> void:
	var spawn := world.get_spawn()
	motor.set_ridden(false)
	player.set_riding(false)
	player.teleport(spawn["player_pos"])
	player.face_yaw(spawn["camera_yaw"])
	motor.place(spawn["motor_pos"], spawn["motor_heading"])
	cam.set_target(player, false)
	cam.snap_to(spawn["camera_yaw"])


func _update_prompt() -> void:
	var text := ""
	if hud.refuel_menu.visible:
		hud.set_prompt("")
		return
	if _can_refuel():
		text = "[E]  Magpagasolina  (Refuel)"
	else:
		match player.state:
			Player.State.ON_FOOT:
				if _near_motor():
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
	hud.update_vehicle(riding, motor.get_speed_kmh(), motor.get_fuel_ratio(), motor.get_display_name(), motor.damage)
	hud.update_health(not riding, player.health / Player.MAX_HEALTH)


static func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
