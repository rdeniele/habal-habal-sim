extends Node
## Global game data that every scene can read: wallet, day, time, motor, stats.
## Access it anywhere as `GameState.money`, `GameState.day`, etc.
## SaveManager saves/loads this with to_dict() / from_dict().

signal money_changed(new_amount: int)

const RATING_HISTORY := 30   # average rating uses the last N rides

var money: int = Economy.STARTING_MONEY
var day: int = 1
var time_hours: float = Economy.DAY_START_HOUR   # 0.0 - 24.0+ (goes past 24 after midnight)
var current_motor_id: String = Motors.DEFAULT_MOTOR_ID
var motor_color_index: int = 0
## "none" = no motor yet, "rent" = renting (pays boundary daily), "own" = bought
var motor_mode: String = "none"
var motor_fuel: float = -1.0     # liters, -1 = full tank (used when loading a save)
var motor_damage: float = 0.0
var debt: int = 0                # unpaid rent (boundary)
var rent_unpaid_days: int = 0
var respect: int = 0

# --- Story / tutorial ---
var player_name: String = ""
var has_license: bool = false
var story_done: bool = false

## Star ratings from passengers (newest last). Starts with a few 5s so you begin at 5.0.
var ratings: Array[int] = [5, 5, 5, 5, 5]
var rating: float = 5.0

## Today's numbers, shown on the End of Day screen.
var today: Dictionary = {}

## Which save slot this game uses (1-3), 0 = not saved yet.
var save_slot: int = 0


func _ready() -> void:
	reset_today()


## Everything back to a fresh new game.
func reset_new_game() -> void:
	money = Economy.STARTING_MONEY
	day = 1
	time_hours = Economy.DAY_START_HOUR
	current_motor_id = Motors.DEFAULT_MOTOR_ID
	motor_color_index = 0
	motor_mode = "none"
	motor_fuel = -1.0
	motor_damage = 0.0
	debt = 0
	rent_unpaid_days = 0
	respect = 0
	player_name = ""
	has_license = false
	story_done = false
	ratings = [5, 5, 5, 5, 5]
	rating = 5.0
	save_slot = 0
	reset_today()


func reset_today() -> void:
	today = {"rides": 0, "fares": 0, "tips": 0, "gas_spent": 0, "cancelled": 0,
		"rent_paid": 0, "clinic": 0, "repairs": 0}


func add_money(amount: int) -> void:
	money += amount
	money_changed.emit(money)


## Pay for something. Returns false (and pays nothing) if you can't afford it.
func spend(amount: int) -> bool:
	if amount > money:
		return false
	add_money(-amount)
	return true


func has_motor() -> bool:
	return motor_mode != "none"


## Set up a "finished tutorial" state (used by tests and debug skip).
func debug_skip_story() -> void:
	story_done = true
	has_license = true
	if player_name == "":
		player_name = "Juan Dela Cruz"
	if motor_mode == "none":
		motor_mode = "own"
		current_motor_id = Motors.DEFAULT_MOTOR_ID


func add_rating(stars: int) -> void:
	ratings.append(clampi(stars, 1, 5))
	while ratings.size() > RATING_HISTORY:
		ratings.pop_front()
	var total := 0
	for r in ratings:
		total += r
	rating = float(total) / ratings.size()


## Moves the in-game clock forward. Called every physics frame by the game.
## The clock keeps counting past 24:00 (25.5 = 1:30 AM) until you end the day.
func advance_time(delta: float) -> void:
	time_hours += delta * Economy.GAME_MINUTES_PER_SECOND / 60.0


## Hour of the day 0-24 (for lighting, surge, etc.)
func hour_of_day() -> float:
	return fmod(time_hours, 24.0)


## Returns the clock as text, e.g. "7:05 AM".
func get_time_string() -> String:
	var h := int(hour_of_day())
	var m := int(time_hours * 60.0) % 60
	var suffix := "AM" if h < 12 else "PM"
	var h12 := h % 12
	if h12 == 0:
		h12 = 12
	return "%d:%02d %s" % [h12, m, suffix]


# --- Save data ---------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"money": money, "day": day, "debt": debt, "rent_unpaid_days": rent_unpaid_days,
		"current_motor_id": current_motor_id, "motor_color_index": motor_color_index,
		"motor_mode": motor_mode, "motor_fuel": motor_fuel, "motor_damage": motor_damage,
		"respect": respect, "player_name": player_name, "has_license": has_license,
		"story_done": story_done, "ratings": ratings.duplicate(),
	}


func from_dict(d: Dictionary) -> void:
	reset_new_game()
	money = int(d.get("money", money))
	day = int(d.get("day", day))
	debt = int(d.get("debt", 0))
	rent_unpaid_days = int(d.get("rent_unpaid_days", 0))
	current_motor_id = str(d.get("current_motor_id", current_motor_id))
	motor_color_index = int(d.get("motor_color_index", 0))
	motor_mode = str(d.get("motor_mode", "none"))
	motor_fuel = float(d.get("motor_fuel", -1.0))
	motor_damage = float(d.get("motor_damage", 0.0))
	respect = int(d.get("respect", 0))
	player_name = str(d.get("player_name", ""))
	has_license = bool(d.get("has_license", false))
	story_done = bool(d.get("story_done", false))
	ratings.clear()
	for r in d.get("ratings", [5, 5, 5, 5, 5]):
		ratings.append(int(r))
	if ratings.is_empty():
		ratings = [5, 5, 5, 5, 5]
	add_rating(ratings.pop_back())   # recompute the average
	# A loaded game always starts in the morning at home.
	time_hours = Economy.DAY_START_HOUR
	reset_today()
