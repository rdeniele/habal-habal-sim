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
const TIP_CHANCE_5_STAR: float = 0.25
const BOOKING_ACCEPT_SECONDS: float = 15.0

# --- Other costs -----------------------------------------------------------
const LICENSE_FEE: int = 585
const CLINIC_FEE: int = 500
const REPAIR_COST_PER_DAMAGE_POINT: int = 40   # damage is 0-100

# --- Time ------------------------------------------------------------------
const DAY_START_HOUR: float = 7.0
## How many in-game minutes pass per real second.
const GAME_MINUTES_PER_SECOND: float = 1.0


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
