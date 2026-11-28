class_name PetCare
extends Node
## Hands-on with dogs and cats.
##   E  lift the one beside you, then E again to caress it
##   1  adopt (it's yours: it waits outside home)     2  put it down (a pet goes home)
##   F  by your motor with your cat in your arms: it rides in the front, where the food goes,
##      and now and then climbs onto your lap. Dogs don't ride.
## Picking up a stray can get you bitten (Economy.BITE_CHANCE).

const REACH := 1.6
const STROKE_SECONDS := 1.8
## spots on the motor (in its leaning frame): in the food basket on the footboard, and your lap
const BOARD := Vector3(0.0, 0.6, -0.13)
const LAP := Vector3(0.0, 0.92, -0.14)

var game: Node
var animals: Animals
var held: Animal = null        # in your arms
var cat: Animal = null         # riding on the motor
var on_lap := false
var bite_chance := Economy.BITE_CHANCE   # tests set this
var _stroke_left := 0.0
var _lap_left := 8.0
var _basket: Node3D
var _rng := RandomNumberGenerator.new()


func setup(p_game: Node, p_animals: Animals) -> void:
	game = p_game
	animals = p_animals
	_rng.randomize()


## The animal within arm's reach (on foot), or null.
func nearest() -> Animal:
	var player: Player = game.player
	if player.state != Player.State.ON_FOOT:
		return null
	var best: Animal = null
	var best_d := REACH
	var around: Array = animals.animals + animals.pets
	if cat != null:
		around.append(cat)
	for animal: Animal in around:
		if not is_instance_valid(animal) or animal == held:
			continue
		var d := Vector2(animal.global_position.x - player.global_position.x,
			animal.global_position.z - player.global_position.z).length()
		if d < best_d:
			best_d = d
			best = animal
	return best


func prompt() -> String:
	var player: Player = game.player
	if held != null:
		var text := "[E]  Haplos (Pet)"
		if not held.pet:
			text += "     [1]  Adopt     [2]  Put down"
		else:
			text += "     [2]  Send home" if _far_from_home() else "     [2]  Put down"
			if held.kind == "cat" and game._near_motor() and cat == null:
				text += "     [F]  Ride together"
		return text
	if player.state == Player.State.RIDING:
		if cat != null and on_lap and absf(game.motor.speed) < 0.5:
			return "[E]  Haplos (Pet your cat)     [F]  Panaog  (Get off)"
		return ""
	var animal := nearest()
	if animal == null:
		return ""
	return "[E]  Lift your %s" % animal.kind if animal.pet else "[E]  Lift the stray %s  (it might bite)" % animal.kind


## E. Returns true when it was about an animal.
func try_interact() -> bool:
	if held != null:
		caress()
		return true
	if game.player.state == Player.State.RIDING:
		if cat != null and on_lap and absf(game.motor.speed) < 0.5:
			cat.caress()
			return true
		return false
	var animal := nearest()
	if animal == null or game.combat.is_in_combat():
		return false
	lift(animal)
	return true


func lift(animal: Animal) -> void:
	if not animal.pet and _rng.randf() < bite_chance:
		animal.scare(game.player.global_position)
		game.on_bitten(animal.kind)
		return
	if animal == cat:
		cat = null
	animals.animals.erase(animal)
	held = animal
	game.player.carrying = true
	_carry()
	animal.caress()


func caress() -> void:
	if held == null or _stroke_left > 0.0:
		return
	_stroke_left = STROKE_SECONDS
	held.caress()


## Seconds of petting left (drives the stroking hand), 0 when not petting.
func stroking() -> float:
	return _stroke_left if held != null else 0.0


func adopt() -> void:
	if held == null or held.pet:
		return
	held.pet = true
	GameState.pets.append({"kind": held.kind, "seed": held.look_seed})
	held.caress()
	var more := "\nStand by your motor and press F to ride with it." if held.kind == "cat" else "\nDogs can't ride: press 2 and it waits at home."
	game.hud.show_toast("Imo na ina! (Your %s now)%s" % [held.kind, more], 4.0)


func put_down() -> void:
	if held == null:
		return
	var animal := held
	var far := _far_from_home()
	_let_go()
	if animal.pet:
		animals.send_home(animal)
		if far:
			game.hud.show_toast("Your %s is waiting for you at home." % animal.kind, 3.0)
	else:
		var yaw: float = game.player.get_facing_yaw()
		var forward := Vector3(-sin(yaw), 0, -cos(yaw))
		animals.release(animal, game.player.global_position + forward * 0.8, forward)


## F while holding one: only your own cat gets to ride.
func ride_with_held() -> void:
	if game.player.state != Player.State.ON_FOOT or not game._near_motor():
		return
	if held.kind == "dog":
		game.hud.show_toast("Dogs can't ride! Put your dog down first (2).", 2.5)
	elif not held.pet:
		game.hud.show_toast("Adopt the cat first (1), or put it down (2).", 2.5)
	elif cat != null:
		game.hud.show_toast("One cat at a time on the motor.", 2.5)
	else:
		var animal := held
		_let_go()
		cat = animal
		on_lap = false
		_lap_left = _rng.randf_range(6.0, 14.0)
		game._toggle_ride()
		_seat_cat()
		cat.speak()


## Everyone out of your arms and off the motor (crash, end of day, death...).
func release_all() -> void:
	if held != null:
		put_down()
	if cat != null:
		var animal := cat
		cat = null
		animals.send_home(animal)


func _let_go() -> void:
	held = null
	_stroke_left = 0.0
	game.player.carrying = false
	game.player.stroke = 0.0


func _far_from_home() -> bool:
	var door: Vector3 = game.world.get_place("home")["door"]
	return game.player.global_position.distance_to(door) > 25.0


func _physics_process(delta: float) -> void:
	if game == null:
		return
	var player: Player = game.player
	var motor: Motorcycle = game.motor
	# knocked down, day over, no motor any more: everyone gets to safety
	var trouble: bool = player.state == Player.State.KNOCKED_DOWN or game._ending_day or game.is_dead
	if held != null and (trouble or player.state == Player.State.RIDING):
		put_down()
	if cat != null and (trouble or not motor.is_active or motor.is_fallen):
		var scared := cat
		cat = null
		animals.send_home(scared)
		if not game.is_dead:
			game.hud.show_toast("Your cat jumped off and ran home.", 3.0)
	if held != null:
		_stroke_left = maxf(0.0, _stroke_left - delta)
		player.stroke = sin(_stroke_left * 7.0) * 0.25 if _stroke_left > 0.0 else 0.0
		_carry()
	_show_basket(cat != null)
	if cat == null:
		return
	if player.state == Player.State.RIDING:
		_lap_left -= delta
		if _lap_left <= 0.0:
			var was := on_lap
			on_lap = not on_lap and _rng.randf() < 0.6
			_lap_left = _rng.randf_range(8.0, 18.0)
			if on_lap and not was:
				cat.speak()
				game.hud.show_toast("Your cat climbed onto your lap.", 2.5)
		_seat_cat()
	else:
		on_lap = false
		_seat_cat()
		# parked at home: it hops off and joins the others
		var door: Vector3 = game.world.get_place("home")["door"]
		if motor.global_position.distance_to(door) < 12.0:
			var animal := cat
			cat = null
			animals.send_home(animal)


## The food basket on the footboard (only there while your cat rides along).
func _show_basket(on: bool) -> void:
	if _basket == null:
		if not on:
			return
		_basket = Node3D.new()
		game.motor.get_seat_mount().add_child(_basket)
		LowPoly.box(_basket, Vector3(0.21, 0.21, 0.2), Color("#9c6b3c"), Vector3(0, 0.485, -0.13))
		LowPoly.box(_basket, Vector3(0.235, 0.028, 0.225), Color("#c99a62"), Vector3(0, 0.59, -0.13))
		for y: float in [0.44, 0.52]:
			LowPoly.box(_basket, Vector3(0.222, 0.016, 0.212), Color("#7a5030"), Vector3(0, y, -0.13))
	_basket.visible = on


func _seat_cat() -> void:
	var spot := LAP if on_lap else BOARD
	# on the lap it curls up sideways; in front it sits looking at the road
	var turn := Basis(Vector3.UP, PI * 0.5) if on_lap else Basis.IDENTITY
	cat.hold_in(game.motor.get_seat_mount(), Transform3D(turn, spot), "lap" if on_lap else "board")


## Keep the held one in your arms (in first person: in front of your eyes).
func _carry() -> void:
	var player: Player = game.player
	var dog := held.kind == "dog"
	if game.cam.is_first_person():
		var low := Vector3(0.0, -0.78 if dog else -0.52, -0.95 if dog else -0.7)
		held.hold_in(game.cam.camera, Transform3D(Basis(Vector3.UP, PI * 0.5), low), "arms")
	else:
		var turn := Basis(Vector3.UP, player.get_facing_yaw())
		var up := (0.99 if dog else 1.1) - (0.45 if player.crouching else 0.0)
		held.hold_in(player, Transform3D(turn * Basis(Vector3.UP, PI * 0.5), turn * Vector3(0, up, -0.34)), "arms")
