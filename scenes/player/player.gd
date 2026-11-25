class_name Player
extends CharacterBody3D
## The rider when on foot: walk, run, get knocked down after a crash.
## While riding, this node is hidden and the Motorcycle shows its own rider model.

enum State { ON_FOOT, RIDING, KNOCKED_DOWN }

const WALK_SPEED := 2.4
const RUN_SPEED := 5.8
const ACCEL := 14.0
const GRAVITY := 22.0
const TURN_SPEED := 12.0
const KNOCKDOWN_TIME := 2.4
const MAX_HEALTH := 100.0

## Collision layers (bit values): 1 = world, 2 = player, 4 = motorcycles
const LAYER_PLAYER := 2
const MASK_ON_FOOT := 1 | 4

## Rider look (Sakay app colors: teal jacket + helmet)
const JACKET_COLOR := Color("#14a39a")
const PANTS_COLOR := Color("#2d3047")
const HELMET_COLOR := Color("#14a39a")

var state: State = State.ON_FOOT
var camera: FollowCamera
var health: float = MAX_HEALTH
var input_enabled := true

var _yaw_pivot: Node3D
var _model: CharacterModel
var _anim_phase := 0.0
var _knock_time := 0.0


func _ready() -> void:
	collision_layer = LAYER_PLAYER
	collision_mask = MASK_ON_FOOT
	floor_snap_length = 0.3

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.8
	shape.shape = capsule
	shape.position.y = 0.9
	add_child(shape)

	_yaw_pivot = Node3D.new()
	add_child(_yaw_pivot)
	_model = CharacterModel.new()
	_yaw_pivot.add_child(_model)
	_model.build(JACKET_COLOR, PANTS_COLOR, HELMET_COLOR)


func _physics_process(delta: float) -> void:
	match state:
		State.RIDING:
			return
		State.KNOCKED_DOWN:
			_process_knockdown(delta)
		State.ON_FOOT:
			_process_walk(delta)
	# Slow health regen, but only when you've eaten and had water.
	if GameState.hunger > 20.0 and GameState.thirst > 20.0:
		health = minf(MAX_HEALTH, health + 1.5 * delta)


func _process_walk(delta: float) -> void:
	var input := Vector2.ZERO
	if input_enabled:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	# Move relative to where the camera is looking.
	var yaw: float = camera.get_yaw() if camera != null else 0.0
	var dir := Basis(Vector3.UP, yaw) * Vector3(input.x, 0.0, input.y)
	var running := Input.is_action_pressed("run")
	var target_speed := (RUN_SPEED if running else WALK_SPEED) * minf(1.0, input.length())

	var flat := Vector3(velocity.x, 0, velocity.z).move_toward(dir.normalized() * target_speed, ACCEL * delta)
	velocity.x = flat.x
	velocity.z = flat.z
	_apply_gravity(delta)
	move_and_slide()

	# Turn the body to face where we're walking.
	if dir.length() > 0.1:
		var target_yaw := atan2(-dir.x, -dir.z)
		_yaw_pivot.rotation.y = lerp_angle(_yaw_pivot.rotation.y, target_yaw, 1.0 - exp(-TURN_SPEED * delta))

	var speed := Vector2(velocity.x, velocity.z).length()
	_anim_phase += delta * speed * 2.2
	_model.walk(_anim_phase, clampf(speed / RUN_SPEED * 1.4, 0.0, 1.0))


func _process_knockdown(delta: float) -> void:
	_knock_time += delta
	_apply_gravity(delta)
	var friction := 6.0 if is_on_floor() else 0.5
	var flat := Vector3(velocity.x, 0, velocity.z).move_toward(Vector3.ZERO, friction * delta)
	velocity.x = flat.x
	velocity.z = flat.z
	move_and_slide()

	# Fall flat on the ground, stay a moment, then stand back up.
	var lying := _knock_time < KNOCKDOWN_TIME - 0.6
	var k := 1.0 - exp(-10.0 * delta)
	_model.rotation.x = lerpf(_model.rotation.x, -1.45 if lying else 0.0, k)
	_model.position.y = lerpf(_model.position.y, 0.18 if lying else 0.0, k)
	_model.walk(0.0, 0.0)
	if _knock_time >= KNOCKDOWN_TIME:
		_model.rotation.x = 0.0
		_model.position.y = 0.0
		state = State.ON_FOOT


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta


# --- Called by the game ------------------------------------------------------

## Hide/disable the on-foot body while riding (the motor shows a rider model).
func set_riding(on: bool) -> void:
	state = State.RIDING if on else State.ON_FOOT
	visible = not on
	collision_layer = 0 if on else LAYER_PLAYER
	collision_mask = 0 if on else MASK_ON_FOOT
	velocity = Vector3.ZERO
	_model.rotation = Vector3.ZERO
	_model.position = Vector3.ZERO


## Instantly move somewhere (no smoothing between the old and new spot).
func teleport(pos: Vector3) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	reset_physics_interpolation()


func get_facing_yaw() -> float:
	return _yaw_pivot.rotation.y


func face_yaw(yaw: float) -> void:
	_yaw_pivot.rotation.y = yaw


## Thrown off the motor in a crash.
func knock_off(from_pos: Vector3, launch: Vector3, impact: float) -> void:
	set_riding(false)
	teleport(from_pos)
	velocity = launch
	state = State.KNOCKED_DOWN
	_knock_time = 0.0
	health = maxf(5.0, health - impact * 2.5)
	if Vector2(launch.x, launch.z).length() > 0.1:
		_yaw_pivot.rotation.y = atan2(-launch.x, -launch.z)


## True when a spot is free for the player's capsule (used when getting off).
func is_spot_free(pos: Vector3) -> bool:
	return not test_move(Transform3D(Basis.IDENTITY, pos), Vector3(0, 0.05, 0))
