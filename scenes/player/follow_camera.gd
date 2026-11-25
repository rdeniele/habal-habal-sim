class_name FollowCamera
extends Node3D
## Third-person camera: Rig (yaw) -> PitchPivot (pitch) -> SpringArm3D -> Camera3D.
## The SpringArm pulls the camera closer when a wall is between it and the target,
## so the camera never goes inside buildings.
## On the motor, the camera swings behind you automatically when you stop moving the mouse.

const PRESETS: Array = [
	{"length": 4.2, "height": 1.6},   # normal
	{"length": 6.5, "height": 2.0},   # far
	{"length": 2.4, "height": 1.45},  # close
]
const PITCH_MIN := -1.2
const PITCH_MAX := 0.35

@export var mouse_sensitivity := 0.0025
@export var stick_sensitivity := 2.6
@export var invert_y := false

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
		global_position = target.global_position + Vector3.UP * float(PRESETS[_preset]["height"])
	rotation = Vector3(0, _yaw, 0)
	reset_physics_interpolation()


func get_yaw() -> float:
	return _yaw


func _unhandled_input(event: InputEvent) -> void:
	# Click the game window to lock the mouse. Esc frees it (pause menu comes in Milestone 4).
	if event is InputEventMouseButton and event.pressed and not ui_open and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		_yaw -= motion.relative.x * mouse_sensitivity
		var y_sign := -1.0 if invert_y else 1.0
		_pitch = clampf(_pitch - motion.relative.y * mouse_sensitivity * y_sign, PITCH_MIN, PITCH_MAX)
		_idle_look_time = 0.0
	elif event.is_action_pressed("camera_change"):
		_preset = (_preset + 1) % PRESETS.size()


func _physics_process(delta: float) -> void:
	# Gamepad right stick look
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look.length() > 0.0:
		_yaw -= look.x * stick_sensitivity * delta
		var y_sign := -1.0 if invert_y else 1.0
		_pitch = clampf(_pitch - look.y * stick_sensitivity * delta * y_sign, PITCH_MIN, PITCH_MAX)
		_idle_look_time = 0.0
	_idle_look_time += delta

	if target == null:
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
