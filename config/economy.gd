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
const BASE_FARE: int = 50
const PER_KM: int = 12
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

# --- Other costs -----------------------------------------------------------
const LICENSE_FEE: int = 585
const CLINIC_FEE: int = 500
const REPAIR_COST_PER_DAMAGE_POINT: int = 40   # damage is 0-100

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
	return int(round(fare))


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
