class_name Ambience
extends Node3D
## In-game background sound: no music, just the world (see NatureSfx for the sounds).
##
## Layers that always loop, faded up and down by what's around you:
##   city traffic  louder at rush hour, quiet late at night
##   wind          soft when standing; loud and higher when riding fast (wind past the helmet)
##   leaves        breezy rustle by day, softer at night
##   sea           only near the coast (louder the closer you are)
##   night         crickets and frogs after dark
## Now-and-then sounds at a random spot 15-60 m around you (so they come from somewhere):
##   birds (all day, most in the morning), roosters (dawn, and now and then all day, it's
##   the Philippines), dogs (mostly at night), the tuko gecko (night).

const SHOT_PLAYERS := 4

var world: GameWorld
var motor: Motorcycle
var player: Player

var _layers := {}              # name -> BackgroundAudio
var _shots: Array[AudioStreamPlayer3D] = []
var _next := {}                # one-shot kind -> seconds until it may play again
var _rng := RandomNumberGenerator.new()
var _sea_dist := 9999.0
var _sea_timer := 0.0


func setup(p_world: GameWorld, p_player: Player, p_motor: Motorcycle) -> void:
	world = p_world
	player = p_player
	motor = p_motor


func _ready() -> void:
	_rng.randomize()
	for layer: String in ["city", "wind", "leaves", "sea", "night"]:
		var b := BackgroundAudio.create(layer, "SFX", -80.0)
		add_child(b)
		_layers[layer] = b
	for i in SHOT_PLAYERS:
		var p := AudioStreamPlayer3D.new()
		p.bus = "SFX"
		p.unit_size = 18.0
		p.max_distance = 120.0
		p.attenuation_filter_cutoff_hz = 6000.0   # far sounds get a bit muffled
		add_child(p)
		_shots.append(p)
	for k: String in ["bird", "rooster", "dog", "gecko"]:
		_next[k] = _rng.randf_range(1.0, 6.0)


func _process(delta: float) -> void:
	var listener := _listener_pos()
	var h := GameState.hour_of_day()
	var night := _night_amount(h)            # 0 day .. 1 night (smooth at dusk / dawn)
	var riding := player != null and player.state == Player.State.RIDING
	var speed := motor.get_speed_kmh() if (riding and motor != null) else 0.0
	var speed_k := clampf(speed / 60.0, 0.0, 1.0)

	# city: rush hours louder, night quieter
	var rush := 1.0 if Economy.is_surge(h) else 0.0
	_set_layer("city", lerpf(-13.0, -23.0, night) + rush * 2.5)
	# wind: rises with speed, and its pitch too
	_set_layer("wind", lerpf(-25.0, -7.0, speed_k))
	(_layers["wind"] as BackgroundAudio).pitch_scale = lerpf(0.9, 1.5, speed_k)
	_set_layer("leaves", lerpf(-24.0, -32.0, night) - speed_k * 6.0)
	_set_layer("night", lerpf(-60.0, -14.0, night))
	# sea: check the distance twice a second
	_sea_timer -= delta
	if _sea_timer <= 0.0:
		_sea_timer = 0.5
		_sea_dist = _distance_to_sea(listener)
	_set_layer("sea", lerpf(-8.0, -60.0, clampf(_sea_dist / 450.0, 0.0, 1.0)))

	_update_shots(delta, h, night, listener)


func _set_layer(layer: String, db: float) -> void:
	(_layers[layer] as BackgroundAudio).target_db = db


## 0 in the day, 1 at night, smooth around 18:00-19:30 and 4:30-6:00.
static func _night_amount(h: float) -> float:
	if h >= 12.0:
		return smoothstep(18.0, 19.5, h)
	return 1.0 - smoothstep(4.5, 6.0, h)


func _listener_pos() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		return cam.global_position
	return player.global_position if player != null else Vector3.ZERO


func _distance_to_sea(p: Vector3) -> float:
	if world == null:
		return 9999.0
	var sea := world.get_sea_polygon()
	if sea.size() < 3:
		return 9999.0
	var q := Vector2(p.x, p.z)
	if Geometry2D.is_point_in_polygon(q, sea):
		return 0.0
	var best := 9999.0
	for i in sea.size():
		var a := sea[i]
		var b := sea[(i + 1) % sea.size()]
		best = minf(best, q.distance_to(Geometry2D.get_closest_point_to_segment(q, a, b)))
	return best


# --- now-and-then sounds ----------------------------------------------------------------

func _update_shots(delta: float, h: float, night: float, listener: Vector3) -> void:
	for k: String in _next.keys():
		_next[k] = float(_next[k]) - delta
	var morning := 1.0 - smoothstep(8.0, 10.0, h) if h >= 5.0 else 0.0
	var dawn := smoothstep(4.0, 5.0, h) * (1.0 - smoothstep(7.0, 8.0, h))
	# birds: busy in the morning, calmer at noon, none at night
	if _next["bird"] <= 0.0:
		if night < 0.5:
			var kind: String = ["sparrow", "sparrow", "myna", "dove"][_rng.randi() % 4]
			_play(NatureSfx.bird(kind, _rng.randi() % 4), listener, -10.0 + morning * 3.0, _rng.randf_range(0.9, 1.15))
		_next["bird"] = _rng.randf_range(1.5, 4.0) if morning > 0.3 else _rng.randf_range(4.0, 10.0)
	# roosters: lots at dawn, but they crow all day here
	if _next["rooster"] <= 0.0:
		if night < 0.8 or dawn > 0.0:
			_play(NatureSfx.rooster(_rng.randi() % 3), listener, -12.0, _rng.randf_range(0.92, 1.08))
		_next["rooster"] = _rng.randf_range(15.0, 35.0) if dawn > 0.3 else _rng.randf_range(60.0, 150.0)
	# dogs: mostly at night
	if _next["dog"] <= 0.0:
		_play(NatureSfx.dog(_rng.randi() % 4), listener, -11.0, _rng.randf_range(0.9, 1.1))
		_next["dog"] = _rng.randf_range(12.0, 35.0) if night > 0.5 else _rng.randf_range(40.0, 100.0)
	# the tuko gecko: night only
	if _next["gecko"] <= 0.0:
		if night > 0.7:
			_play(NatureSfx.gecko(_rng.randi() % 3), listener, -9.0, 1.0)
		_next["gecko"] = _rng.randf_range(35.0, 90.0)


## Play a sound at a random spot 15-60 m around the listener, on a free player.
func _play(stream: AudioStream, around: Vector3, db: float, pitch: float) -> void:
	for p in _shots:
		if not p.playing:
			var a := _rng.randf() * TAU
			var d := _rng.randf_range(15.0, 60.0)
			p.global_position = around + Vector3(cos(a) * d, _rng.randf_range(2.0, 8.0), sin(a) * d)
			p.stream = stream
			p.volume_db = db
			p.pitch_scale = pitch
			p.play()
			return
