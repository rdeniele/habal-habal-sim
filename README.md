# Habal-Habal Simulator

A low-poly 3D motorcycle-taxi (ride-hailing rider) simulator for PC, set in **Bacolod City, Negros Occidental**.
Ride around, pick up passengers on the **Sakay** rider app (our own fictional app), earn pesos, and get home before the day ends.

Made with **Godot 4** (GDScript).

## How to run

1. Download **Godot 4.5 or newer** (the latest 4.x stable, *standard* version, not ".NET"): https://godotengine.org/download/windows/
   It's a single `.exe`, no installer. Unzip it anywhere, e.g. `C:\Tools\Godot\`.
2. Open Godot → **Import** → pick this folder's `project.godot` → **Import & Edit**.
   (The first open takes a moment while Godot scans the project.)
3. Press **F5** (or the ▶ Play button, top right) to run the game.

Optional: rename the exe to `godot.exe` and add its folder to your PATH, so this works in a terminal:

```powershell
godot --path . 
```

## How to play (so far)

1. Walk to your motor and press **F** to get on.
2. Press **Tab** to open the **Sakay** rider app and click **GO ONLINE**.
3. A booking pops up: press **1** to accept (or **2** to decline) within 15 seconds.
4. Follow the GPS arrow (top of the screen) and the green beam. Stop next to the passenger.
5. They hop on. Ride smoothly to the orange beam: hard braking, bumps and speeding make them uncomfortable.
6. Stop at the drop-off: you get paid and rated (1-5 stars). Good ratings = more bookings.
7. Low on gas? Ride into the **Gasolinahan**, stop at the pump and press **E**. Out of gas? Hold W to push.

## Controls

| Action | Keyboard / Mouse | Xbox gamepad |
|---|---|---|
| Walk / steer | WASD | Left stick |
| Run | Shift | L3 |
| Look | Mouse | Right stick |
| Gas / brake | W / S | RT / LT |
| Handbrake | Space | RB |
| Horn | H | L3 |
| Get on / off motor | F | Y |
| Interact / refuel at pump | E | A |
| Sakay phone | Tab | Back |
| Accept / decline booking | 1 / 2 | D-pad up / down |
| Change camera | C | R3 |
| Controls help | F1 | |
| Free the mouse | Esc | |
| Respawn at home (debug) | F8 | |

## Project layout

```
project.godot          Godot project settings
config/economy.gd      ALL prices, fares, rates (tweak here)
config/motors.gd       motorcycle list + stats
autoload/              always-loaded scripts: InputSetup (controls), GameState (wallet, day...)
scenes/main/           the main game scene that connects everything
scenes/world/          the test city (real Bacolod map comes in Milestone 6)
scenes/player/         on-foot player, motorcycle, follow camera
scenes/common/         low-poly model helpers (boxes, character model)
scenes/systems/        booking system (Sakay app logic), GPS target marker
scenes/npc/            passengers
scenes/ui/             HUD, Sakay phone app, gas pump menu
data/dialog/           passenger personalities + lines (Hiligaynon, Bisaya, Tagalog, English)
tests/                 automated tests (see below)
```

## Automated tests

Godot can run the game by itself and check that things work (it also saves screenshots to
`%APPDATA%\Godot\app_userdata\Habal-Habal Simulator\screenshots`):

```powershell
godot --path . res://tests/smoke_test.tscn
```

```powershell
godot --path . res://tests/ride_test.tscn
```

Most models are built from code (boxes/cylinders) as placeholders, so everything is plain text and easy to change.

## Milestones

1. ✅ Foundation – test city, on-foot player, arcade motorcycle, get on/off, third-person camera
2. ✅ Ride-hailing loop – Sakay app, bookings, passengers, fares, ratings, fuel, gas stations
3. Story & economy – intro, driving school, license, motor shop (buy/rent)
4. Day cycle & saves – time of day, last ride, end-of-day summary, saves, menus, settings
5. Traffic, road rage & fights
6. Real Bacolod map from OpenStreetMap
7. Polish & Windows export

## Credits

See [CREDITS.md](CREDITS.md).
