extends Node
## Global game data that every scene can read: wallet, day, time, motor, stats.
## Access it anywhere as `GameState.money`, `GameState.day`, etc.
## (SaveManager in Milestone 4 will save/load these values.)

signal money_changed(new_amount: int)

const RATING_HISTORY := 30   # average rating uses the last N rides

var money: int = Economy.STARTING_MONEY
var day: int = 1
var time_hours: float = Economy.DAY_START_HOUR   # 0.0 - 24.0
var current_motor_id: String = Motors.DEFAULT_MOTOR_ID
var respect: int = 0

## Star ratings from passengers (newest last). Starts with a few 5s so you begin at 5.0.
var ratings: Array[int] = [5, 5, 5, 5, 5]
var rating: float = 5.0

## Passenger language: "hil" Hiligaynon, "ceb" Bisaya, "tl" Tagalog, "en" English, "mixed"
var passenger_language: String = "mixed"

## Today's numbers, shown on the End of Day screen (Milestone 4).
var today: Dictionary = {}


func _ready() -> void:
	reset_today()


func reset_today() -> void:
	today = {"rides": 0, "fares": 0, "tips": 0, "gas_spent": 0, "cancelled": 0}


func add_money(amount: int) -> void:
	money += amount
	money_changed.emit(money)


## Pay for something. Returns false (and pays nothing) if you can't afford it.
func spend(amount: int) -> bool:
	if amount > money:
		return false
	add_money(-amount)
	return true


func add_rating(stars: int) -> void:
	ratings.append(clampi(stars, 1, 5))
	while ratings.size() > RATING_HISTORY:
		ratings.pop_front()
	var total := 0
	for r in ratings:
		total += r
	rating = float(total) / ratings.size()


## Moves the in-game clock forward. Called every physics frame by the game.
func advance_time(delta: float) -> void:
	time_hours += delta * Economy.GAME_MINUTES_PER_SECOND / 60.0
	if time_hours >= 24.0:
		time_hours -= 24.0


## Returns the clock as text, e.g. "7:05 AM".
func get_time_string() -> String:
	var total_minutes := int(time_hours * 60.0)
	var h := int(time_hours) % 24
	var m := total_minutes % 60
	var suffix := "AM" if h < 12 else "PM"
	var h12 := h % 12
	if h12 == 0:
		h12 = 12
	return "%d:%02d %s" % [h12, m, suffix]
