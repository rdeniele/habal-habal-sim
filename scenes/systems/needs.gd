class_name Needs
extends Node
## Hunger, thirst and energy (stored in GameState so they can be saved/reset).
## - They go down over in-game time (riding tires you faster).
## - Standing still on foot = resting: energy comes back.
## - At 0 food or water you lose health; at 0 health or 0 energy you faint.
## - Low energy makes the motor drift a little (sleepy riding).
## Rates and food prices are in config/economy.gd.

signal fainted(reason: String)

const WARN_AT := 20.0
const STILL_TIME_TO_REST := 2.0

var player: Player
var motor: Motorcycle
var hud: HUD
var paused := false   # true during story / end of day / fainting

var _still := 0.0
var _warned := {}


func setup(p_player: Player, p_motor: Motorcycle, p_hud: HUD) -> void:
	player = p_player
	motor = p_motor
	hud = p_hud


func is_resting() -> bool:
	return _still >= STILL_TIME_TO_REST


func _physics_process(delta: float) -> void:
	if player == null:
		return
	hud.update_needs(player.health / Player.MAX_HEALTH, GameState.hunger / 100.0,
		GameState.thirst / 100.0, GameState.energy / 100.0, is_resting())
	if paused or not GameState.story_done:
		motor.drowsiness = 0.0
		return

	# Fainting is checked first (so resting can't "save" you at exactly 0).
	if player.health <= 0.0:
		fainted.emit("You were too hungry or thirsty and fainted.")
		return
	if GameState.energy <= 0.0:
		fainted.emit("You were too tired and fainted.")
		return

	var hours := delta * Settings.game_minutes_per_second() / 60.0
	var riding := player.state == Player.State.RIDING
	var moving := Vector2(player.velocity.x, player.velocity.z).length() > 0.2
	_still = _still + delta if (player.state == Player.State.ON_FOOT and not moving) else 0.0

	GameState.hunger = maxf(0.0, GameState.hunger - Economy.HUNGER_PER_HOUR * hours)
	GameState.thirst = maxf(0.0, GameState.thirst - Economy.THIRST_PER_HOUR * hours)
	if is_resting():
		GameState.energy = minf(100.0, GameState.energy + Economy.REST_ENERGY_PER_HOUR * hours)
	else:
		var drain := Economy.ENERGY_PER_HOUR + (Economy.ENERGY_RIDING_EXTRA if riding else 0.0)
		GameState.energy = maxf(0.0, GameState.energy - drain * hours)

	# Starving / dehydrated: health goes down. Fed and watered: it slowly comes back.
	if GameState.hunger <= 0.0 or GameState.thirst <= 0.0:
		player.health = maxf(0.0, player.health - Economy.STARVING_HEALTH_PER_SEC * delta)

	# Sleepy riding: the motor drifts a little when energy is low.
	motor.drowsiness = clampf((15.0 - GameState.energy) / 15.0, 0.0, 1.0) if riding else 0.0

	_warn("hunger", GameState.hunger, "Gutom na ko! (I'm hungry)\nBuy food at a sari-sari store (orange dots on the map).")
	_warn("thirst", GameState.thirst, "Uhaw na ko! (I'm thirsty)\nBuy a drink at a sari-sari store.")
	_warn("energy", GameState.energy, "Antok na ko... (I'm sleepy)\nTake a break: stand still on foot to rest, or have coffee.")


## Warn once when a meter drops below WARN_AT; re-arms when it goes back up.
func _warn(key: String, value: float, text: String) -> void:
	if value < WARN_AT and not _warned.get(key, false):
		_warned[key] = true
		hud.show_toast(text, 4.0)
	elif value > WARN_AT + 15.0:
		_warned[key] = false


## Eat/drink an item from Economy.FOOD_ITEMS.
func consume(item: Dictionary) -> void:
	GameState.hunger = clampf(GameState.hunger + float(item["hunger"]), 0.0, 100.0)
	GameState.thirst = clampf(GameState.thirst + float(item["thirst"]), 0.0, 100.0)
	GameState.energy = clampf(GameState.energy + float(item["energy"]), 0.0, 100.0)
	player.health = minf(Player.MAX_HEALTH, player.health + 10.0)
