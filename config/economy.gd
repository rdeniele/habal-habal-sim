class_name Economy
extends RefCounted
## ALL money numbers, prices, fares and rates live here so they're easy to tweak.
## Use them anywhere like: Economy.STARTING_MONEY
## (Most are placeholders until we balance the game.)

# --- Wallet ---------------------------------------------------------------
const STARTING_MONEY: int = 60000

# --- Motor shop (Buy vs Rent) ----------------------------------------------
const RENT_PER_DAY: int = 350            # daily "boundary" when renting
const RENT_MAX_UNPAID_DAYS: int = 3      # after this many unpaid days the motor is taken back
const SELL_BACK_RATIO: float = 0.6       # owned motors sell back at 60% of price

# --- Gas -------------------------------------------------------------------
const GAS_PRICE_PER_LITER: int = 62      # regular gasoline, approx. Nov 2026
## Real scooters do ~50-60 km/L, so a tank would last forever in a small city.
## This multiplies fuel use so gas actually matters in-game. 1.0 = realistic.
const FUEL_USE_MULTIPLIER: float = 8.0

# --- Fares -----------------------------------------------------------------
const BASE_FARE: int = 0               # fare = BASE_FARE + PER_KM * km ...
const PER_KM: int = 40                 # habal-habal rates: about ₱120 for 3 km
const MIN_FARE: int = 20              # ...but never less than this (nearest rides pay ₱20)
const SURGE_MULTIPLIER: float = 1.3      # rush hours (7-9 AM, 5-7 PM) and rain
const SURGE_HOURS: Array = [[7.0, 9.0], [17.0, 19.0]]   # rush hours (24h clock)
const TIP_CHANCE_5_STAR: float = 0.25
const TIP_MIN: int = 10
const TIP_MAX: int = 50

# --- Bookings --------------------------------------------------------------
const BOOKING_ACCEPT_SECONDS: float = 15.0
## Seconds between booking requests when your rating is 5.0 (random in this range).
const BOOKING_INTERVAL_MIN: float = 6.0
const BOOKING_INTERVAL_MAX: float = 14.0
## Each star below 5.0 makes you wait this much longer (0.8 = +80% per star).
const BOOKING_LOW_RATING_SLOWDOWN: float = 0.8

# --- Accidents -------------------------------------------------------------
## Chance of dying (game over) in a motor crash, when a car hits you, or when you lose a
## fist fight. People you hit and your passenger in a crash have the same chance of dying. Never during the tutorial. 0.0 = nobody dies.
## Chance a stray bites when you pick it up (a bite can kill: DEATH_CHANCE).
const BITE_CHANCE: float = 0.2
const DEATH_CHANCE: float = 0.5

# --- Other costs -----------------------------------------------------------
const LICENSE_FEE: int = 585
const CLINIC_FEE: int = 500
const REPAIR_COST_PER_DAMAGE_POINT: int = 40   # damage is 0-100

# --- Traffic fines (from traffic enforcers) --------------------------------
## Based on Philippine rules (LTO Joint Administrative Order 2014-01 / RA 4136).
## Amounts change over time and some cities have their own ordinances: tweak as needed.
const FINE_RED_LIGHT: int = 1000            # Disregarding traffic signs / signals
const FINE_RECKLESS: Array = [2000, 3000, 10000]   # Reckless driving: 1st, 2nd, 3rd+ offense
const FINE_FIGHTING: int = 5000             # Fighting in public / alarms and scandals (approx.)
## Getting BUSTED by the police (after a chase): days in jail and bail/fines per wanted star.
## You earn nothing while in jail, and your wallet can go deep into the negative.
const JAIL_DAYS_PER_STAR: int = 2
const BAIL_PER_STAR: int = 5000
## RA 4136 speed limit for motorcycles on city through-streets is 40 km/h.
# No speeding tickets: speed is up to you (and how your passenger feels about it).

# --- Food & drinks (sari-sari stores) -------------------------------------
## hunger / thirst / energy = how much each meter goes up (meters are 0-100).
const FOOD_ITEMS: Array = [
	{"name": "Mineral water", "price": 20, "hunger": 0, "thirst": 45, "energy": 0},
	{"name": "Softdrinks", "price": 25, "hunger": 0, "thirst": 30, "energy": 5},
	{"name": "3-in-1 coffee", "price": 15, "hunger": 0, "thirst": 5, "energy": 25},
	{"name": "Pandesal (5 pcs)", "price": 15, "hunger": 15, "thirst": -5, "energy": 0},
	{"name": "Piaya", "price": 20, "hunger": 20, "thirst": -5, "energy": 5},
	{"name": "Rice + ulam (meal)", "price": 80, "hunger": 60, "thirst": 0, "energy": 10},
]

# --- Body needs (per in-game hour) -----------------------------------------
const HUNGER_PER_HOUR: float = 6.0
const THIRST_PER_HOUR: float = 9.0      # Bacolod is hot!
const ENERGY_PER_HOUR: float = 4.0
const ENERGY_RIDING_EXTRA: float = 2.5  # riding tires you faster
const REST_ENERGY_PER_HOUR: float = 35.0  # standing still on foot = resting
const STARVING_HEALTH_PER_SEC: float = 2.0  # health lost per real second at 0 food or water

# --- Time ------------------------------------------------------------------
const DAY_START_HOUR: float = 7.0
## How many in-game minutes pass per real second.
const GAME_MINUTES_PER_SECOND: float = 1.0


## True during rush hour (fares get the surge multiplier).
static func is_surge(hour: float) -> bool:
	for range_pair: Array in SURGE_HOURS:
		if hour >= float(range_pair[0]) and hour < float(range_pair[1]):
			return true
	return false


## Fare for a trip of `km` kilometers starting at `hour`.
static func calc_fare(km: float, hour: float) -> int:
	var fare := BASE_FARE + PER_KM * km
	if is_surge(hour):
		fare *= SURGE_MULTIPLIER
	return maxi(MIN_FARE, int(round(fare)))


## Formats an amount like "₱60,000" (or "-₱350").
static func format_peso(amount: int) -> String:
	var digits := str(absi(amount))
	var out := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-₱" if amount < 0 else "₱") + out
