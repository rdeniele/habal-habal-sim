extends Node3D
## Main gameplay scene (Milestone 1).
## Connects the world, player, motorcycle, camera and HUD:
## - F to get on/off the motor (only when close / stopped)
## - E to interact with places (shops open in later milestones)
## - handles crashes (rider gets thrown off)

const MOUNT_DISTANCE := 2.6
const INTERACT_DISTANCE := 3.2
const MAX_DISMOUNT_SPEED := 2.0   # m/s (~7 km/h)

@onready var world: TestCity = $World
@onready var player: Player = $Player
@onready var motor: Motorcycle = $Motorcycle
@onready var cam: FollowCamera = $CameraRig
@onready var hud: HUD = $HUD


func _ready() -> void:
	player.camera = cam
	motor.setup(GameState.current_motor_id)
	motor.crashed.connect(_on_motor_crashed)
	motor.ran_out_of_fuel.connect(_on_out_of_fuel)
	_respawn_at_home()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.show_toast("Maayong aga, boss! Lakat sa motor mo kag pindota ang F.\n(Good morning! Walk to your motor and press F.)", 8.0)


func _physics_process(delta: float) -> void:
	GameState.advance_time(delta)
	if player.state == Player.State.RIDING:
		player.global_position = motor.global_position   # keep the player "with" the motor
	_update_prompt()
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("enter_exit"):
		_toggle_ride()
	elif event.is_action_pressed("interact"):
		_interact()
	elif event.is_action_pressed("toggle_help"):
		hud.toggle_help()
	elif event.is_action_pressed("phone"):
		hud.show_toast("Sakay rider app: coming in Milestone 2!", 2.5)
	elif event.is_action_pressed("debug_respawn"):
		_respawn_at_home()
		hud.show_toast("Respawned at home", 2.0)


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
	motor.set_ridden(false)
	motor.fall_over()
	# Throw the rider away from the wall, a bit up in the air.
	var from := motor.global_position + wall_normal * 1.2 + Vector3.UP * 0.9
	player.knock_off(from, wall_normal * 3.0 + Vector3.UP * 3.5, impact)
	cam.set_target(player, false)
	hud.show_toast("Aray! Natumba ka! (You crashed)\nPress F near the motor to pick it up.", 3.5)


func _on_out_of_fuel() -> void:
	hud.show_toast("Wala na gasolina! (Out of gas)\nGas stations open in Milestone 2. Press F8 to reset.", 4.0)


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
	if player.state != Player.State.ON_FOOT:
		return
	var place := _nearest_place()
	if place.is_empty():
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
	match player.state:
		Player.State.ON_FOOT:
			if _near_motor():
				text = "[F]  Sakay sa motor  (Get on)"
			else:
				var place := _nearest_place()
				if not place.is_empty():
					text = "[E]  %s" % place["name"]
		Player.State.RIDING:
			if absf(motor.speed) < 0.5:
				text = "[F]  Panaog  (Get off)"
	hud.set_prompt(text)


func _update_hud() -> void:
	var riding := player.state == Player.State.RIDING
	hud.set_money(GameState.money)
	hud.set_clock(GameState.day, GameState.get_time_string())
	hud.update_vehicle(riding, motor.get_speed_kmh(), motor.get_fuel_ratio(), motor.get_display_name(), motor.damage)
	hud.update_health(not riding, player.health / Player.MAX_HEALTH)
