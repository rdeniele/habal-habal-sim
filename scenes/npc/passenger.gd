class_name Passenger
extends Node3D
## A passenger: waits on the sidewalk waving, walks to the motor, sits on the back,
## then gets off and walks away. Movement is simple (no physics) since it's short and slow.

signal reached_motor

enum State { WAITING, WALKING_TO_MOTOR, READY, ON_BIKE, LEAVING }

const WALK_SPEED := 1.7
const LEAVE_TIMEOUT := 8.0
const JACKETS := ["#ef476f", "#ffd166", "#06d6a0", "#118ab2", "#f4f1de", "#8338ec", "#fb5607", "#3a86ff"]
const PANTS := ["#2d3047", "#3d405b", "#6b4f3a", "#1d3557", "#4a4e69"]
const HELMETS := ["#f8f9fa", "#ffbe0b", "#e63946", "#212529", "#90e0ef"]

var display_name := ""
var state: State = State.WAITING
var model: CharacterModel

var _target := Vector3.ZERO
var _t := 0.0
var _phase := 0.0


## Builds a random-looking passenger.
const FEMALE_NAMES := ["Maria", "Bea", "Nening", "Joy", "Angel", "Kristine", "Ella", "Gina", "Jessa",
	"Liza", "Inday", "Cha-cha", "Rosa", "Mae", "Tess"]
const MALE_NAMES := ["Jun-jun", "Carlo", "Mark", "Paolo", "Rommel", "Tonton", "Dodong", "Migs",
	"Jomar", "Ben", "Rey", "Nonoy", "Kiko"]


## Is this passenger type a woman, a man, or either (random)?
static func is_female_for(kind: String, rng: RandomNumberGenerator) -> bool:
	match kind:
		"tita", "lola":
			return true
		"worker", "seaman":
			return false
	return rng.randf() < 0.5


static func random_name(female: bool, rng: RandomNumberGenerator) -> String:
	var names: Array = FEMALE_NAMES if female else MALE_NAMES
	return names[rng.randi() % names.size()]


## Builds a passenger who looks like their type (kind = personality id, e.g. "lola").
var _down := 0.0   # > 0 while lying on the ground after a crash

func build(rng: RandomNumberGenerator, passenger_name: String, kind: String = "", female: bool = false) -> void:
	display_name = passenger_name
	name = "Passenger_" + passenger_name
	model = CharacterModel.new()
	add_child(model)
	var look := CharacterModel.random_look(rng, female, kind)
	look["helmet"] = Color(HELMETS[rng.randi() % HELMETS.size()])
	model.build_look(look)
	model.set_helmet(false)   # the rider hands them a spare helmet when they get on


## Build with specific colors (story characters like the instructor or Nanay).
## Pass helmet with alpha 0 for no helmet.
func build_with_colors(person_name: String, jacket: Color, pants: Color, helmet: Color) -> void:
	display_name = person_name
	name = "NPC_" + person_name.replace(" ", "_")
	model = CharacterModel.new()
	add_child(model)
	model.build(jacket, pants, helmet)


## Build a story character from a full look (see CharacterModel.random_look for keys).
func build_with_look(person_name: String, look: Dictionary) -> void:
	display_name = person_name
	name = "NPC_" + person_name.replace(" ", "_")
	model = CharacterModel.new()
	add_child(model)
	model.build_look(look)


## Floating name tag above the head.
func add_name_tag(text: String) -> void:
	LowPoly.label(self, text, Vector3(0, 2.35, 0), 0.32)


func _physics_process(delta: float) -> void:
	_t += delta
	match state:
		State.WAITING:
			# Wave at the rider
			model.pose_wave()
		State.WALKING_TO_MOTOR, State.LEAVING:
			if _down > 0.0:
				_down -= delta
				if _down <= 0.0 and model.is_ragdoll():
					global_position = model.ragdoll_ground_position()
					model.stop_ragdoll()
				_t = 0.0
				return
			_walk_step(delta)


## Thrown off in a crash: flop for a moment, then get up and walk off. Call after
## get_off_and_leave().
func fall(velocity: Vector3) -> void:
	_down = 2.2
	model.pose_sit(0.7)
	model.start_ragdoll(velocity, velocity * 0.3 + Vector3.UP)


func _walk_step(delta: float) -> void:
	var to := _target - global_position
	to.y = 0.0
	var dist := to.length()
	var timed_out := state == State.LEAVING and _t > LEAVE_TIMEOUT
	if dist < 0.15 or timed_out:
		if state == State.WALKING_TO_MOTOR:
			model.pose_stand()
			state = State.READY
			reached_motor.emit()
		else:
			queue_free()
		return
	global_position += to / dist * minf(dist, WALK_SPEED * delta)
	rotation.y = atan2(-to.x, -to.z)
	_phase += delta * WALK_SPEED * 2.4
	model.walk(_phase, 0.6)


## Turn to look at a point (yaw only).
func face(point: Vector3) -> void:
	var to := point - global_position
	if Vector2(to.x, to.z).length() > 0.01:
		rotation.y = atan2(-to.x, -to.z)


func walk_to_motor(point: Vector3) -> void:
	_target = point
	_t = 0.0
	state = State.WALKING_TO_MOTOR


## Go back to waiting (e.g. the rider drove off while we were walking over).
func wait_again(point: Vector3) -> void:
	global_position = point
	state = State.WAITING


## Sit on the motor's back seat. `mount` is the motor's lean pivot.
func sit_on(mount: Node3D, seat: Vector3) -> void:
	reparent(mount, false)
	position = seat
	rotation = Vector3.ZERO
	model.pose_sit(0.7)
	model.set_helmet(true, true)   # pop! helmet on
	state = State.ON_BIKE


## Get off the motor at `at` (world position) and walk to `walk_target`, then disappear.
func get_off_and_leave(new_parent: Node, at: Vector3, walk_target: Vector3) -> void:
	reparent(new_parent, true)
	global_position = at
	rotation = Vector3.ZERO
	model.pose_stand()
	model.set_helmet(false)   # gives the helmet back
	_target = walk_target
	_t = 0.0
	state = State.LEAVING
