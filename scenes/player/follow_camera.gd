class_name FollowCamera
extends Node3D
## Third-person camera: Rig (yaw) -> PitchPivot (pitch) -> SpringArm3D -> Camera3D.
## The SpringArm pulls the camera closer when a wall is between it and the target,
## so the camera never goes inside buildings.
## On the motor, the camera swings behind you automatically when you stop moving the mouse.
##
## First person (the default; C cycles views, and the game remembers your choice): the camera sits at your eyes.
## On the motor, the mouse turns/tilts your HEAD (look over your shoulder, check the
## side mirrors); it slowly turns back to the front while you ride.

const PRESETS: Array = [
	{"length": 4.2, "height": 1.6},   # normal
	{"length": 6.5, "height": 2.0},   # far
	{"length": 2.4, "height": 1.45},  # close
	{"fp": true},                     # first person
]
const HEAD_YAW_MAX := 1.75     # ~100 degrees each way
const HEAD_PITCH_MIN := -0.9
const HEAD_PITCH_MAX := 0.6
const PITCH_MIN := -1.2
const PITCH_MAX := 0.35

## Mouse sensitivity and invert Y come from Settings (settings menu).
@export var stick_sensitivity := 2.6

var target: Node3D
var follow_heading := false   # auto-rotate behind the motor
var ui_open := false          # a clickable menu is open: don't grab the mouse on click
var camera: Camera3D

var _yaw := 0.0
var _pitch := -0.28
var _preset := 0
var _idle_look_time := 10.0
var _pitch_pivot: Node3D
var _arm: SpringArm3D
var _length := 4.2
var _head_yaw := 0.0      # first person on the motor: head turn relative to the bike
var _head_pitch := -0.1
var _was_fp := false


func _ready() -> void:
	top_level = true   # move freely, not attached to a parent's transform
	_pitch_pivot = Node3D.new()
	add_child(_pitch_pivot)

	_arm = SpringArm3D.new()
	_arm.collision_mask = 1   # only the world blocks the camera
	_arm.margin = 0.2
	var sphere := SphereShape3D.new()
	sphere.radius = 0.25
	_arm.shape = sphere
	_arm.spring_length = _length
	_pitch_pivot.add_child(_arm)

	_preset = clampi(Settings.camera_view, 0, PRESETS.size() - 1)
	camera = Camera3D.new()
	camera.fov = 70.0
	camera.far = 2500.0
	_arm.add_child(camera)
	camera.current = true


func set_target(node: Node3D, follow: bool) -> void:
	target = node
	follow_heading = follow


## Jump straight to the target with a given yaw (used on spawn/respawn).
func snap_to(yaw: float) -> void:
	_yaw = yaw
	if target != null:
		global_position = target.global_position + Vector3.UP * float((PRESETS[_preset] as Dictionary).get("height", 1.62))
	rotation = Vector3(0, _yaw, 0)
	reset_physics_interpolation()


## Yaw used for walking direction / minimap. In first person on the motor: where your head looks.
func get_yaw() -> float:
	if is_first_person() and target is Motorcycle:
		return (target as Motorcycle).heading + _head_yaw
	return _yaw


func is_first_person() -> bool:
	return bool((PRESETS[_preset] as Dictionary).get("fp", false))


func _unhandled_input(event: InputEvent) -> void:
	# Click the game window to lock the mouse. Esc frees it (pause menu comes in Milestone 4).
	if event is InputEventMouseButton and event.pressed and not ui_open and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		var y_sign := -1.0 if Settings.invert_y else 1.0
		if is_first_person() and target is Motorcycle:
			_head_yaw = clampf(_head_yaw - motion.relative.x * Settings.mouse_sensitivity, -HEAD_YAW_MAX, HEAD_YAW_MAX)
			_head_pitch = clampf(_head_pitch - motion.relative.y * Settings.mouse_sensitivity * y_sign, HEAD_PITCH_MIN, HEAD_PITCH_MAX)
		else:
			_yaw -= motion.relative.x * Settings.mouse_sensitivity
			_pitch = clampf(_pitch - motion.relative.y * Settings.mouse_sensitivity * y_sign, PITCH_MIN, PITCH_MAX)
		_idle_look_time = 0.0
	elif event.is_action_pressed("camera_change"):
		set_view((_preset + 1) % PRESETS.size())


## Switch camera view (0 normal, 1 far, 2 close, 3 first person) and remember it.
func set_view(index: int) -> void:
	_preset = clampi(index, 0, PRESETS.size() - 1)
	if Settings.camera_view != _preset:
		Settings.camera_view = _preset
		Settings.save()


func _physics_process(delta: float) -> void:
	# Gamepad right stick look
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look.length() > 0.0:
		_yaw -= look.x * stick_sensitivity * delta
		var y_sign := -1.0 if Settings.invert_y else 1.0
		_pitch = clampf(_pitch - look.y * stick_sensitivity * delta * y_sign, PITCH_MIN, PITCH_MAX)
		_idle_look_time = 0.0
	_idle_look_time += delta

	if target == null:
		return
	var fp := is_first_person()
	if fp != _was_fp:
		_set_body_hidden(fp)
		_was_fp = fp
	if fp:
		_first_person(delta)
		return

	var speed_ratio := 0.0
	if target is Motorcycle:
		var bike := target as Motorcycle
		speed_ratio = clampf(bike.get_speed_kmh() / 100.0, 0.0, 1.0)
		# Swing behind the motor when the player isn't steering the camera.
		if follow_heading and _idle_look_time > 1.2 and absf(bike.speed) > 2.0:
			_yaw = lerp_angle(_yaw, bike.heading, 1.0 - exp(-2.5 * delta))
			_pitch = lerpf(_pitch, -0.22, 1.0 - exp(-1.5 * delta))

	var preset: Dictionary = PRESETS[_preset]
	# Pull back a bit and widen the view at speed (feels faster).
	_length = lerpf(_length, float(preset["length"]) + speed_ratio * 1.2, 1.0 - exp(-6.0 * delta))
	_arm.spring_length = _length
	camera.fov = lerpf(camera.fov, 70.0 + speed_ratio * 12.0, 1.0 - exp(-4.0 * delta))

	var goal := target.global_position + Vector3.UP * float(preset["height"])
	global_position = global_position.lerp(goal, 1.0 - exp(-14.0 * delta))
	rotation = Vector3(0, _yaw, 0)
	_pitch_pivot.rotation = Vector3(_pitch, 0, 0)


# --- First person ------------------------------------------------------------------

func _first_person(delta: float) -> void:
	_arm.spring_length = 0.0
	camera.near = 0.04
	camera.fov = lerpf(camera.fov, 75.0, 1.0 - exp(-4.0 * delta))
	if target is Motorcycle:
		var bike := target as Motorcycle
		# The head slowly turns back to the front while riding and not looking around.
		if _idle_look_time > 1.5 and absf(bike.speed) > 2.0:
			_head_yaw = lerpf(_head_yaw, 0.0, 1.0 - exp(-2.0 * delta))
			_head_pitch = lerpf(_head_pitch, -0.1, 1.0 - exp(-2.0 * delta))
		global_position = bike.get_head_position()
		# yaw = bike + head turn; the head also tilts with the bike's lean
		rotation = Vector3(0, bike.heading + _head_yaw, bike.get_lean() * 0.7)
		_pitch_pivot.rotation = Vector3(_head_pitch, 0, 0)
		bike.set_mirrors_active(true)
	else:
		global_position = target.global_position + Vector3.UP * 1.62
		rotation = Vector3(0, _yaw, 0)
		_pitch_pivot.rotation = Vector3(clampf(_pitch, -1.2, 1.0), 0, 0)


## Hide your own body (and the rider) so it doesn't block the first-person view.
func _set_body_hidden(hidden: bool) -> void:
	camera.near = 0.04 if hidden else 0.05
	for n in get_tree().get_nodes_in_group("fp_hide"):
		if n.has_method("set_fp_hidden"):
			n.set_fp_hidden(hidden)
	if not hidden:
		_arm.spring_length = _length
