extends Node
## Global game data that every scene can read: wallet, day, time, motor, stats.
## Access it anywhere as `GameState.money`, `GameState.day`, etc.
## (SaveManager in Milestone 4 will save/load these values.)

signal money_changed(new_amount: int)

var money: int = Economy.STARTING_MONEY
var day: int = 1
var time_hours: float = Economy.DAY_START_HOUR   # 0.0 - 24.0
var current_motor_id: String = Motors.DEFAULT_MOTOR_ID
var rating: float = 5.0
var respect: int = 0


func add_money(amount: int) -> void:
	money += amount
	money_changed.emit(money)


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
