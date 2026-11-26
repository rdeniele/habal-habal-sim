class_name DayCycle
extends Node
## Changes the lighting with the in-game clock: morning -> afternoon -> sunset -> night.
## Moves the sun across the sky, blends sky/fog colors, makes windows and street lamps
## glow at night, and turns on the motor headlight after dark.
## Also applies the graphics preset (shadows, fog, draw distance).

## Keyframes by hour: sun energy, sun color, sky top, sky horizon, ambient energy, night glow (0-1).
const KEYS := [
	[0.0, 0.22, "#9fb4ff", "#0b1026", "#1b2440", 0.25, 1.0],
	[5.0, 0.22, "#9fb4ff", "#141c3a", "#33406a", 0.30, 1.0],
	[6.0, 0.60, "#ffb070", "#4a6fa5", "#f4a261", 0.50, 0.6],
	[7.5, 1.25, "#fff0d8", "#4f9fe0", "#cfe8f5", 0.90, 0.0],
	[16.5, 1.25, "#fff4e0", "#4f9fe0", "#cfe8f5", 0.90, 0.0],
	[18.0, 0.70, "#ff9050", "#3d5a99", "#f08a5d", 0.55, 0.5],
	[18.8, 0.08, "#ff9050", "#1c2650", "#5a4a70", 0.35, 0.9],
	[19.2, 0.22, "#9fb4ff", "#141c3a", "#2c3560", 0.30, 1.0],
	[24.0, 0.22, "#9fb4ff", "#0b1026", "#1b2440", 0.25, 1.0],
]
const SUNRISE := 5.6
const SUNSET := 19.0

var world: GameWorld
var motor: Motorcycle
var cam: FollowCamera
var night_amount := 0.0   # 0 = day, 1 = night (other systems can read this)


func setup(p_world: GameWorld, p_motor: Motorcycle, p_cam: FollowCamera) -> void:
	world = p_world
	motor = p_motor
	cam = p_cam
	Settings.changed.connect(_apply_graphics)
	_apply_graphics()
	update_now()


func _process(_delta: float) -> void:
	if world != null:
		update_now()


func update_now() -> void:
	var h := GameState.hour_of_day()
	var k := _sample(h)
	var sun := world.sun
	sun.light_energy = k[0]
	sun.light_color = k[1]
	world.sky_material.sky_top_color = k[2]
	world.sky_material.sky_horizon_color = k[3]
	world.sky_material.ground_horizon_color = k[3]
	world.environment.ambient_light_energy = k[4]
	world.environment.fog_light_color = (k[3] as Color).lerp(Color("#cfe3ee"), 0.3)
	night_amount = k[5]
	world.set_night_glow(night_amount)
	# bloom: lamps, windows and headlights get a soft glow after dark (not on Low)
	var env := world.environment
	env.glow_enabled = Settings.graphics != "low" and night_amount > 0.02
	env.glow_intensity = 0.9 * night_amount

	if h >= SUNRISE and h < SUNSET:
		# Sun: rises in the east (+X), sets in the west, highest at noon.
		var t := (h - 6.0) / 12.0
		var elevation := maxf(4.0, sin(clampf(t, 0.0, 1.0) * PI) * 65.0)
		sun.rotation_degrees = Vector3(-elevation, 90.0 - t * 180.0, 0.0)
	else:
		sun.rotation_degrees = Vector3(-45.0, -30.0, 0.0)   # moonlight

	if motor != null:
		motor.set_headlight(night_amount > 0.4 and motor.is_ridden)


## Linear blend between the two keyframes around `h`.
func _sample(h: float) -> Array:
	for i in range(1, KEYS.size()):
		var b: Array = KEYS[i]
		if h <= float(b[0]):
			var a: Array = KEYS[i - 1]
			var t := inverse_lerp(float(a[0]), float(b[0]), h)
			return [
				lerpf(a[1], b[1], t),
				Color(str(a[2])).lerp(Color(str(b[2])), t),
				Color(str(a[3])).lerp(Color(str(b[3])), t),
				Color(str(a[4])).lerp(Color(str(b[4])), t),
				lerpf(a[5], b[5], t),
				lerpf(a[6], b[6], t),
			]
	var last: Array = KEYS[KEYS.size() - 1]
	return [last[1], Color(str(last[2])), Color(str(last[3])), Color(str(last[4])), last[5], last[6]]


## Graphics preset: shadows, fog thickness, how far you can see.
func _apply_graphics() -> void:
	if world == null:
		return
	world.sun.shadow_enabled = Settings.shadows_enabled()
	world.sun.directional_shadow_max_distance = 160.0 if Settings.graphics == "high" else 100.0
	world.environment.fog_density = 0.0045 if Settings.graphics == "low" else 0.0018
	var env := world.environment
	# glow (bloom) settings; only bright things (lamps/windows/lights) glow
	env.glow_hdr_threshold = 1.1
	env.glow_bloom = 0.04
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	# a bit warmer and richer colors: sunny tropical look
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.04
	# soft shadows in corners and under things (only on High: costs some speed)
	env.ssao_enabled = Settings.graphics == "high"
	env.ssao_radius = 1.6
	env.ssao_intensity = 1.4
	world.sun.shadow_blur = 1.5
	if cam != null:
		cam.camera.far = Settings.draw_distance()
