class_name Animals
extends Node3D
## Keeps stray dogs and cats on the sidewalks around you (spawned 15-90 m away, removed past
## 120 m) and makes them get out of the way of your motor.

const SPAWN_MIN := 15.0
const SPAWN_MAX := 90.0
const DESPAWN := 120.0
const SCARE_RIDING := 8.0      # meters: a moving motor this close sends them running
const SCARE_HORN := 18.0
const SPOOK_ON_FOOT := 3.5     # strays shy away if you walk or run this close...
const SNEAK_SPEED := 1.6       # ...faster than this (crouch to creep up)

var world: GameWorld
var player: Player
var motor: Motorcycle
var animals: Array[Animal] = []     # strays
var pets: Array[Animal] = []        # yours, waiting outside home
var _rng := RandomNumberGenerator.new()
var _tick := 0.0


func setup(p_world: GameWorld, p_player: Player, p_motor: Motorcycle) -> void:
	world = p_world
	player = p_player
	motor = p_motor
	_rng.randomize()
	for p: Dictionary in GameState.pets:
		var animal := Animal.new()
		add_child(animal)
		animal.setup(str(p["kind"]), Vector3.ZERO, Vector3.ZERO, int(p["seed"]))
		animal.pet = true
		send_home(animal)


func target_count() -> int:
	return {"low": 6, "medium": 11, "high": 18}.get(Settings.graphics, 11) as int


func _center() -> Vector3:
	return motor.global_position if player.state == Player.State.RIDING else player.global_position


func _physics_process(delta: float) -> void:
	if world == null:
		return
	var riding := player.state == Player.State.RIDING
	var center := _center()
	# your motor and horn scare them off
	var speed := motor.get_speed_kmh() if riding else 0.0
	var honking := riding and motor.input_enabled and Input.is_action_pressed("horn")
	for animal in animals:
		if not is_instance_valid(animal):
			continue
		var d := animal.global_position.distance_to(center)
		if (speed > 6.0 and d < SCARE_RIDING) or (honking and d < SCARE_HORN) or (riding and d < 2.0):
			animal.scare(center)
	if player.state == Player.State.ON_FOOT:
		var walk := Vector2(player.velocity.x, player.velocity.z).length()
		for animal in animals:
			var d := animal.global_position.distance_to(center)
			if d < SPOOK_ON_FOOT and walk > SNEAK_SPEED:
				animal.scare(center)
			elif d < SPOOK_ON_FOOT and player.crouching:
				animal.calm()
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.5
	for animal in animals.duplicate():
		if not is_instance_valid(animal):
			animals.erase(animal)
		elif animal.global_position.distance_to(center) > DESPAWN:
			animals.erase(animal)
			animal.queue_free()
	for i in 3:
		if animals.size() >= target_count():
			break
		spawn_near(center)


## Where the n-th pet waits: rows along the front of your house.
func home_spot(n: int) -> Vector3:
	var home := world.get_place("home")
	var door: Vector3 = home["door"]
	var front: Vector3 = home["front"]
	var side := Vector3(-front.z, 0, front.x)
	var spot := door - side * (2.0 + (n % 6) * 0.9) + front * (0.5 + int(n / 6.0) % 3 * 0.8)
	spot.y = 0.0
	return spot


## An adopted one goes (back) to wait outside home.
func send_home(animal: Animal) -> void:
	if animal.get_parent() != self:
		animal.reparent(self, false)
	animals.erase(animal)
	if not pets.has(animal):
		pets.append(animal)
	var front: Vector3 = world.get_place("home")["front"]
	var spot := home_spot(pets.find(animal))
	animal.settle(spot, spot, atan2(-front.x, -front.z))


## A stray put down: it hangs around from here.
func release(animal: Animal, at: Vector3, forward: Vector3) -> void:
	if animal.get_parent() != self:
		animal.reparent(self, false)
	var from := Vector3(at.x, 0, at.z)
	animal.settle(from, from + forward * 8.0, atan2(-forward.x, -forward.z))
	if not animals.has(animal):
		animals.append(animal)


## Put one on the sidewalk of a street near `center`.
func spawn_near(center: Vector3, min_distance: float = SPAWN_MIN) -> Animal:
	var g := world.road_graph
	var ids := g.point_ids_near(center, SPAWN_MAX)
	if ids.is_empty():
		return null
	for attempt in 6:
		var from_id: int = ids[_rng.randi() % ids.size()]
		var neighbors := g.neighbors(from_id)
		if neighbors.is_empty():
			continue
		var to_id: int = neighbors[_rng.randi() % neighbors.size()]
		var a := g.get_point(from_id)
		var b := g.get_point(to_id)
		var length := a.distance_to(b)
		if length < 8.0:
			continue
		var dir := (b - a) / length
		var right := Vector3(-dir.z, 0, dir.x)
		var side := 1.0 if _rng.randf() < 0.5 else -1.0
		var off := right * side * (g.road_width(from_id, to_id) * 0.5 + _rng.randf_range(0.9, 2.1))
		# stay clear of the corners
		var p0 := a + off + dir * 3.0
		var p1 := b + off - dir * 3.0
		p0.y = 0.0
		p1.y = 0.0
		if p0.distance_to(center) < min_distance and p1.distance_to(center) < min_distance:
			continue
		var animal := Animal.new()
		add_child(animal)
		animal.setup("dog" if _rng.randf() < 0.58 else "cat", p0, p1, _rng.randi())
		animals.append(animal)
		return animal
	return null
