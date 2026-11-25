class_name Motors
extends RefCounted
## The list of motorcycles you can buy or rent, with their stats.
## Prices are real Philippine SRPs (Nov 2026). Stats are tuned for fun, not exact.
##
## top_speed_kmh  - max speed on flat road
## acceleration   - meters per second^2 (bigger = faster pickup)
## handling       - steering multiplier (1.0 = normal, bigger = turns tighter)
## tank_liters    - fuel tank size
## km_per_liter   - fuel efficiency (see Economy.FUEL_USE_MULTIPLIER)
## colors         - body color options (hex). First one is the default.

const DEFAULT_MOTOR_ID: String = "honda_beat"

const LIST: Array = [
	{
		"id": "honda_navi", "name": "Honda Navi", "price": 56900, "tier": "Starter",
		"top_speed_kmh": 85.0, "acceleration": 3.6, "handling": 1.15,
		"tank_liters": 3.5, "km_per_liter": 59.0,
		"colors": ["#d64545", "#3a7d44", "#f2f2f2"],
	},
	{
		"id": "suzuki_smash", "name": "Suzuki Smash FI", "price": 67400, "tier": "Starter",
		"top_speed_kmh": 100.0, "acceleration": 3.8, "handling": 1.0,
		"tank_liters": 4.3, "km_per_liter": 50.0,
		"colors": ["#1f4e9c", "#c62828", "#222222"],
	},
	{
		"id": "honda_beat", "name": "Honda BeAT", "price": 72400, "tier": "Starter",
		"top_speed_kmh": 88.0, "acceleration": 3.7, "handling": 1.1,
		"tank_liters": 4.2, "km_per_liter": 60.0,
		"colors": ["#e63946", "#2a9d8f", "#f4f1de"],
	},
	{
		"id": "yamaha_mio_i125", "name": "Yamaha Mio i 125", "price": 77900, "tier": "Mid",
		"top_speed_kmh": 98.0, "acceleration": 4.1, "handling": 1.05,
		"tank_liters": 4.2, "km_per_liter": 50.0,
		"colors": ["#3d5a80", "#ee6c4d", "#e0e0e0"],
	},
	{
		"id": "honda_click_125i", "name": "Honda Click 125i", "price": 81900, "tier": "Mid",
		"top_speed_kmh": 100.0, "acceleration": 4.3, "handling": 1.0,
		"tank_liters": 5.5, "km_per_liter": 53.0,
		"colors": ["#111111", "#b00020", "#0077b6"],
	},
	{
		"id": "yamaha_aerox", "name": "Yamaha Aerox", "price": 125900, "tier": "Dream",
		"top_speed_kmh": 120.0, "acceleration": 5.2, "handling": 0.95,
		"tank_liters": 5.5, "km_per_liter": 44.0,
		"colors": ["#1d3557", "#ffb703", "#6a040f"],
	},
]


## Returns the stats dictionary for a motor id (falls back to the first motor).
static func get_motor(id: String) -> Dictionary:
	for m: Dictionary in LIST:
		if m["id"] == id:
			return m
	return LIST[0]
