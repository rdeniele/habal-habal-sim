# Habal-Habal Simulator

A low-poly 3D motorcycle-taxi (ride-hailing rider) simulator for PC, set in **Bacolod City, Negros Occidental**.
Ride around, pick up passengers on the **Sakay** rider app (our own fictional app), earn pesos, and get home before the day ends.

Made with **Godot 4** (GDScript).

## Play the game (Windows .exe)

Build it once (needs Godot + its export templates), then just double-click the `.exe`:

```powershell
godot --headless --path . --export-release "Windows Desktop" builds/windows/HabalHabalSimulator.exe
```

The result is one file, `builds\windows\HabalHabalSimulator.exe` (~115 MB, map and all included).
Copy it to any 64-bit Windows PC and run it, no install needed. Saves go to
`%APPDATA%\Godotpp_userdata\Habal-Habal Simulator\`.
Export templates: in the Godot editor, **Editor → Manage Export Templates → Download and Install**.

## How to run (for development)

1. Download **Godot 4.5 or newer** (the latest 4.x stable, *standard* version, not ".NET"): https://godotengine.org/download/windows/
   It's a single `.exe`, no installer. Unzip it anywhere, e.g. `C:\Tools\Godot\`.
2. Open Godot → **Import** → pick this folder's `project.godot` → **Import & Edit**.
   (The first open takes a moment while Godot scans the project.)
3. Press **F5** (or the ▶ Play button, top right) to run the game. It opens on the **main menu**:
   New Game (pick one of 3 save slots), Continue, Load Game, Settings, Credits, Quit.

Optional: rename the exe to `godot.exe` and add its folder to your PATH, so this works in a terminal:

```powershell
godot --path . 
```

## How to play (so far)

A new game starts with the story: talk with Nanay, go to driving school (4 lessons + passenger
training with Sir Jojo), get your license, then buy or rent your first motor at the Motor Shop.
The lessons happen at the school's private **training ground** outside the city (a fenced lot with a
cone yard and a practice loop), so no traffic or people get in the way. A shuttle brings you back.
Already know how to ride? Pick "Kabalo na ko!" at the start to skip straight to the license.

Then every day:

1. Walk to your motor and press **F** to get on.
2. Press **Tab** to open the **Sakay** rider app and click **GO ONLINE**.
3. A booking pops up: press **1** to accept (or **2** to decline) within 15 seconds.
4. Follow the **GPS**: the blue route on the minimap (bottom-left), the arrow at the top, and the green beam.
   The minimap always shows **H = home**, G = gas, M = motor shop, + = clinic, S = driving school,
   orange dots = sari-sari stores. Press **M** for the full city map. Stop next to the passenger.
5. They hop on. Ride smoothly to the orange beam: hard braking and bumps make them uncomfortable.
   Speed is up to you: a late student or a nurse wants you to hurry, Lola wants you to take it slow.
6. Stop at the drop-off: you get paid and rated (1-5 stars). Good ratings = more bookings.
7. Visit the **Motor Shop** (E at its door) anytime to buy/rent another motor, repair damage, or sell yours.
8. Ready to stop? Tap **LAST RIDE** in the app: your next booking drops off near home.
   Then ride home, park, and press **E at your front door** to end the day.
   You'll see the **End of Day** summary (fares, gas, rent, net earnings), then the game **auto-saves**.
   Renting? Rent your motor each morning at the Motor Shop (next to your house). At the end of the day,
   **return it there and pay the ₱350 boundary**. Not returned / can't pay = debt; 3 unpaid days = it's taken back.
   Stay out past 2 AM and you fall asleep on the road. Sakay sends no bookings 11 PM - 5 AM.
9. Watch your **food, water and energy** (bottom-left). Buy food and drinks at sari-sari stores (E at the
   orange dots) or the gas station. Stand still on foot to rest. Need a pause? Tap **TAKE A BREAK** in the app.
   Let a meter hit zero and you faint and wake up at the clinic (₱500).
10. **Traffic is real**: cars, jeepneys, tricycles and motorbikes drive on the right, stop at red lights
    and honk if you block them. People walk the sidewalks and cross the streets: don't hit them!
    Traffic lights only stand at the big main-road crossings (at least 350 m apart). Each one stands on the **far corner** of the crossing, facing you, with a **countdown timer**
    only your lane can see; the speedometer shows "LIGHT AHEAD: RED 12s". **Right turn anytime** is allowed.
    Some drivers are careless: cars can **crash** into each other (or into you), and the drivers may
    get out and fight each other. People on the street sometimes start fights too.
11. **Open-world fighting**: on foot, left click punches anyone (combos), right click blocks, L dodges.
    No lock-on: you aim with the camera, and you can fight several people at once.
    Punch a person and they fight back or run (more likely to run when hurt; chase them!).
    Punch or bump a vehicle and the driver may get out angry ("Galit ang driver!"): no buttons, you
    decide: ride away or get off and fight. People who see a fight join in or run.
    Knock someone down = +1 Respect. Get knocked out = clinic (₱500).
    A passenger on board gets scared and cancels if a fight starts.
12. **Traffic enforcers** stand at some intersections (yellow-green dots on the minimap). Only the enforcer
    at THAT crossing can catch you beating the red light. He blows his whistle and waves you over:
    **pull over** next to him and pay the ticket (real LTO amounts), or **run for it** and get 1 wanted star.
    No speeding tickets. Your wallet can go **negative (red)**: keep working to get back out.
    Hitting or even bumping a pedestrian, or fighting, where enforcers/police (or people on the street) see it
    = **WANTED ★**: police motorbikes chase you. Your stars and offenses show at the top middle of the screen.
    Lose them (stay out of sight) or get **BUSTED**: 2 days in jail per star, ₱5,000 bail per star, no income.
13. The game starts in **first person** (press **C** to change; it remembers your choice). On the motor the
    mouse turns your head and the **side mirrors** show the traffic behind you. On foot, your **fists** show
    when you punch or block.
14. **Explore**: open the full map (**M**), **left click** to drop a **pin** (click near SM City, Ayala,
    the Cathedral, the Plaza, the Capitol or the Lagoon to pick it), and the GPS takes you there.
    Right click removes the pin. When you're not working (offline or on a break), the GPS shows the way HOME.
15. Low on gas? Ride into the **Gasolinahan**, stop at the pump and press **E**. Out of gas? Hold W to push.
16. **Sounds & music**: a putt-putt scooter engine, horns for every vehicle type, crashes, punches, the
    enforcer's whistle, city noise, and a laid-back guitar tune that plays like a radio while you ride.
    All made in code (no sound files). Volumes in **Settings** (Music / Sound effects).
17. Passengers have several lines for every moment (getting on, chatting, thanks, complaints), so rides
    don't repeat. All in Hiligaynon, Bisaya, Tagalog and English.
- **Sky**: drifting painted-style clouds (different weather every day, clear to cloudy), orange
   sunsets, a moon and twinkling stars at night. Made in code (`scenes/world/sky.gdshader`); preview it
   without the game: `python tools/sky_preview.py sky.png`.
18. **Graphics → Low** is made for weak laptops: no shadows, and the 3D world is drawn at a lower
    resolution and sharpened back up (FSR). **High** adds soft corner shadows (SSAO). Night lights glow.
19. **Controller**: plug in an Xbox-style gamepad. Menus work too: press any button to highlight one,
    D-pad to move, A to press.

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
| Full map (left click: pin, right click: remove pin) | M | LB |
| Fight: punch / block / dodge | J or left mouse / K or right mouse (hold) / L | X / B / RB |
| Change camera | C | R3 |
| Controls help | F1 | |
| Pause menu (settings, save at home, quit) | Esc | Start |
| Menus | Mouse | D-pad + A |
| Respawn at home (debug) | F8 | |

## Project layout

```
project.godot          Godot project settings
config/economy.gd      ALL prices, fares, rates (tweak here)
config/motors.gd       motorcycle list + stats
autoload/              always-loaded scripts: InputSetup (controls), GameState (wallet, day...)
scenes/main/           the main game scene that connects everything
scenes/world/          Bacolod City (from OpenStreetMap), the old test city, road graph, textures
scenes/player/         on-foot player, motorcycle, follow camera
scenes/common/         low-poly model helpers (boxes, character model)
scenes/story/          story / tutorial script (intro, driving school, license, first motor)
scenes/systems/        booking system (Sakay app logic), GPS target marker
scenes/npc/            passengers, traffic vehicles, people walking, angry drivers
scenes/ui/             HUD, Sakay phone app, gas pump menu, dialog box, license card, motor shop
data/dialog/           passenger personalities + lines (Hiligaynon, Bisaya, Tagalog, English)
data/map/bacolod/      converted map: meta.json, graph.json (roads), chunks/*.json (200 m tiles)
tools/                 osm_download.sh (get OSM data), osm_convert.py (make the game map),
                       make_icon.gd + make_ico.py (app icon from icon.svg)
icon.svg / icon.ico    the app icon (original)
assets/characters/     character_kit.glb (body parts the game uses) + character_kit.blend (open in Blender)
tools/blender/         make_character_kit.py (builds the parts), preview_character.py / render_glb.py (previews)
export_presets.cfg     Windows .exe export settings
tests/                 automated tests (see below)
```

## The Bacolod map

The city is real: roads, buildings, parks, rivers and the coastline come from OpenStreetMap
(© OpenStreetMap contributors, ODbL). The world origin (0, 0) is the Public Plaza.
Landmarks: San Sebastian Cathedral, Public Plaza, Provincial Capitol, SM City, Ayala Capitol Central.
Where OSM has no buildings mapped, the converter adds simple "filler" houses and stores so streets
aren't empty. Buildings that a road runs through (like covered walkways over a street) are removed,
and buildings whose corners poke into a lane are trimmed back to the curb. To rebuild the map (e.g. after OSM updates), in Git Bash:

```powershell
bash tools/osm_download.sh
```

```powershell
python tools/osm_convert.py
```

## Characters (Blender)

People are built from a kit of body parts modeled in **Blender** (original, early-2000s low-poly style):
head with jaw, nose and ears; chest and shoulders; arms with real fists; legs with knees and calves;
sneakers and tsinelas; 8 hairstyles; slim / average / heavy bodies. Faces (stubble, mustache, goatee,
glasses, wrinkles) and clothes (jeans seams, polo buttons, jacket zipper, dress pleats) are pixel
textures painted by the game in any skin, hair and clothing color.

Animations are original and made in code (`scenes/common/character_model.gd`), in an early-2000s
style: a weighty walk with hip sway and shoulder twist, a leaning run with the back foot kicking up,
idle breathing / weight shifts / looking around, a bouncy fighting stance, punches that turn the whole
body, blocking, flinching, sitting on the motor (riders lean into the handlebar), waving and cheering.

To see the animations without opening the game, pose a row of characters and render them:

```powershell
godot --headless --path . -s res://tests/pose_export.gd
```

```powershell
& "D:\Tools\Blenderlender-5.3.0-windows-x64lender.exe" -b -P tools/blender/render_glb.py -- "$env:APPDATA\Godotpp_userdata\Habal-Habal Simulator\pose_preview.glb" poses.png
```

To change the shapes: edit `tools/blender/make_character_kit.py` (or open `assets/characters/character_kit.blend`
in Blender, but the script overwrites it), then rebuild the kit and render a preview, no window needed:

```powershell
& "D:\Tools\Blenderlender-5.3.0-windows-x64lender.exe" -b -P tools/blender/make_character_kit.py
```

```powershell
& "D:\Tools\Blenderlender-5.3.0-windows-x64lender.exe" -b -P tools/blender/preview_character.py -- preview.png
```

## Automated tests

Godot can run the game by itself and check that things work (it also saves screenshots to
`%APPDATA%\Godot\app_userdata\Habal-Habal Simulator\screenshots`). Add `--headless` to run a test
without opening a window (no screenshots then), e.g. while you're using the PC for something else:

```powershell
godot --path . res://tests/smoke_test.tscn
```

```powershell
godot --path . res://tests/ride_test.tscn
```

```powershell
godot --path . res://tests/story_test.tscn
```

```powershell
godot --path . res://tests/day_test.tscn
```

```powershell
godot --path . res://tests/feedback_test.tscn
```

```powershell
godot --path . res://tests/map_test.tscn
```

```powershell
godot --path . res://tests/character_test.tscn
```

```powershell
godot --path . res://tests/traffic_test.tscn
```

```powershell
godot --path . res://tests/perf_test.tscn
```

The sound test runs without a window and also saves every sound as a `.wav` in
`%APPDATA%\Godotpp_userdata\Habal-Habal Simulator\sounds` so you can listen to them:

```powershell
godot --headless --path . -s res://tests/audio_test.gd
```

Saves and settings live in `%APPDATA%\Godot\app_userdata\Habal-Habal Simulator\` (`saves/slot_1.json` ... and `settings.cfg`).

Most models are built from code (boxes/cylinders) as placeholders, so everything is plain text and easy to change.

## Milestones

1. ✅ Foundation – test city, on-foot player, arcade motorcycle, get on/off, third-person camera
2. ✅ Ride-hailing loop – Sakay app, bookings, passengers, fares, ratings, fuel, gas stations
3. ✅ Story & economy – intro, driving school, license, motor shop (buy/rent)
4. ✅ Day cycle & saves – time of day, last ride, end-of-day summary, saves, menus, settings
4.5 ✅ Playtest fixes – GPS + minimap, ₱20 minimum fare, passenger helmets, 11 passenger types, daily rental
    return, hunger/thirst/energy + sari-sari stores, break mode, day length setting
5. ✅ Real Bacolod map from OpenStreetMap (roads, landmarks, GPS on real streets) + early-2000s textured low-poly look
   + new early-2000s style characters: tapered limbs with elbows/knees, painted pixel faces,
     hairstyles, outfits by passenger type (lola, nurse, student, worker...), Filipino skin tones
6. ✅ Traffic, traffic lights, people walking around, road rage & fist fights (on the real roads)
7. ✅ Polish & Windows export – code-made sounds and music, more passenger lines, lighting pass,
   gamepad menus, low-end graphics mode, app icon, one-file Windows .exe

## Credits

See [CREDITS.md](CREDITS.md).
