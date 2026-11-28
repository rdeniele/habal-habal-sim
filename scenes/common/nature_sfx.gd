class_name NatureSfx
extends RefCounted
## Real-life background sounds, made in code (no files, no licenses): no music in the game,
## just what you'd hear riding around Bacolod.
##
## Loops (long, seamless, made on a background thread by BackgroundAudio):
##   "city"    far traffic rumble and the odd far horn
##   "wind"    gusty wind (the game turns it up and pitches it up when you ride fast)
##   "leaves"  rustling trees in the breeze
##   "sea"     waves rolling in and washing out
##   "night"   crickets and far frogs
## One-shots (played now and then at a random spot around you, so nothing repeats on a loop):
##   bird("sparrow" / "dove" / "myna"), rooster(), dog(), gecko(), meow()  -- a few variants each.

const RATE := Sfx.RATE

static var _shots: Dictionary = {}   # "kind_variant" -> AudioStreamWAV


## A long looping background layer.
static func loop(kind: String) -> AudioStreamWAV:
	match kind:
		"city":
			return _city()
		"wind":
			return _wind()
		"leaves":
			return _leaves()
		"sea":
			return _sea()
		"night":
			return _night()
	return Sfx.music_loop()   # "music" (the menu)


# --- helpers ----------------------------------------------------------------------------

## Blend the end into the start so the loop has no seam, then make it playable.
static func _finish_loop(s: PackedFloat32Array, peak: float) -> AudioStreamWAV:
	var n := s.size()
	var xf := int(RATE * 0.6)
	for i in xf:
		var w := float(i) / xf
		s[i] = s[i] * w + s[n - xf + i] * (1.0 - w)
	s.resize(n - xf)
	Sfx._normalize(s, peak)
	return Sfx._to_wav(s, true)


static func _empty(seconds: float) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	s.resize(int(RATE * seconds))
	return s


## Smooth random noise between -1 and 1 that changes `speed` times per second.
static func _wobble(rng: RandomNumberGenerator, n: int, speed: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	var a := rng.randf_range(-1, 1)
	var b := rng.randf_range(-1, 1)
	var step := int(RATE / speed)
	for i in n:
		if i % step == 0:
			a = b
			b = rng.randf_range(-1, 1)
		var t := float(i % step) / step
		out[i] = lerpf(a, b, t * t * (3.0 - 2.0 * t))
	return out


# --- loops ------------------------------------------------------------------------------

## Far traffic: deep rumble that swells, a few far horns. (No birds: they're one-shots now.)
static func _city() -> AudioStreamWAV:
	var seconds := 16.0
	var s := _empty(seconds)
	var n := s.size()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1903
	var b := 0.0
	var y := 0.0
	var y2 := 0.0
	for i in n:
		b = clampf(b + rng.randf_range(-1.0, 1.0) * 0.02, -1.0, 1.0)
		y += 0.05 * (b - y)
		y2 += 0.3 * (rng.randf_range(-1.0, 1.0) * 0.05 - y2)     # faint tire hiss
		var t := float(i) / RATE
		var swell := 0.72 + 0.28 * sin(TAU * t / seconds * 3.0)
		s[i] = (y * 0.9 + y2) * swell
	for k in 4:
		var kinds := ["car", "jeepney", "tricycle", "motorbike"]
		var h := Sfx._horn_far(kinds[k] as String, rng)
		Sfx._mix(s, h, int(rng.randf_range(0.5, seconds - 1.5) * RATE), rng.randf_range(0.08, 0.16))
	return _finish_loop(s, 0.7)


## Wind: soft noise, low-passed, with slow gusts.
static func _wind() -> AudioStreamWAV:
	var seconds := 20.0
	var s := _empty(seconds)
	var n := s.size()
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var gust := _wobble(rng, n, 0.35)
	var fast := _wobble(rng, n, 2.0)
	var y := 0.0
	var y2 := 0.0
	for i in n:
		var g := 0.45 + 0.55 * (0.5 + 0.5 * gust[i])
		var cut := 0.02 + 0.05 * g          # stronger gusts sound brighter
		y += cut * (rng.randf_range(-1.0, 1.0) - y)
		y2 += cut * (y - y2)
		s[i] = y2 * g * (0.85 + 0.15 * fast[i])
	return _finish_loop(s, 0.6)


## Leaves: bright crackly noise in little bursts that follow the breeze.
static func _leaves() -> AudioStreamWAV:
	var seconds := 14.0
	var s := _empty(seconds)
	var n := s.size()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var breeze := _wobble(rng, n, 0.5)
	var flutter := _wobble(rng, n, 14.0)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var w := rng.randf_range(-1.0, 1.0)
		lp += 0.35 * (w - lp)
		lp2 += 0.04 * (lp - lp2)
		var hiss := lp - lp2                  # band-passed: no rumble, no harsh fizz
		var amt := clampf(0.5 + 0.5 * breeze[i], 0.0, 1.0)
		var crackle := maxf(0.0, flutter[i]) * amt
		s[i] = hiss * (0.25 * amt + crackle)
	return _finish_loop(s, 0.5)


## Sea: waves build, crash (brighter), wash out with a fizz. 4 waves in 26 s.
static func _sea() -> AudioStreamWAV:
	var seconds := 26.0
	var s := _empty(seconds)
	var n := s.size()
	var rng := RandomNumberGenerator.new()
	rng.seed = 555
	var b := 0.0
	var low := 0.0
	var hi := 0.0
	var hi2 := 0.0
	var period := seconds / 4.0
	for i in n:
		var t := float(i) / RATE
		var ph := fmod(t, period) / period          # 0..1 within one wave
		var build := smoothstep(0.0, 0.45, ph)
		var crash := exp(-pow((ph - 0.5) / 0.07, 2.0))
		var wash := 1.0 - smoothstep(0.5, 1.0, ph)
		var env := 0.25 + 0.55 * build * wash + 0.5 * crash
		b = clampf(b + rng.randf_range(-1.0, 1.0) * 0.03, -1.0, 1.0)
		low += 0.04 * (b - low)
		var w := rng.randf_range(-1.0, 1.0)
		hi += 0.5 * (w - hi)
		hi2 += 0.08 * (hi - hi2)
		var fizz := (hi - hi2) * (0.3 * crash + 0.15 * wash * smoothstep(0.5, 0.7, ph))
		s[i] = low * env * 1.4 + fizz
	return _finish_loop(s, 0.7)


## Night: a few crickets (each its own pitch and rhythm) and far frogs.
static func _night() -> AudioStreamWAV:
	var seconds := 12.0
	var s := _empty(seconds)
	var n := s.size()
	var rng := RandomNumberGenerator.new()
	rng.seed = 909
	for c in 5:
		var f := rng.randf_range(3800.0, 5200.0)
		var pulses_per_loop := rng.randi_range(14, 30)   # whole number of chirp groups per loop
		var group := float(n) / pulses_per_loop
		var gain := rng.randf_range(0.25, 0.6)
		var ph := 0.0
		for i in n:
			var gp := fmod(float(i), group) / group      # 0..1 within a chirp group
			var on := 0.0
			if gp < 0.3:
				var sub := fmod(gp / 0.3 * 3.0, 1.0)      # 3 quick pulses
				on = sin(PI * sub) if sub < 0.7 else 0.0
			ph += f / RATE
			s[i] += sin(TAU * ph) * on * gain * 0.3
	for k in 6:   # frogs: low "rrk" croaks
		var at := int(rng.randf_range(0.2, seconds - 0.6) * RATE)
		var f := rng.randf_range(260.0, 420.0)
		var ph := 0.0
		for i in int(RATE * 0.22):
			var t := float(i) / RATE
			ph += f / RATE
			var buzz := 0.5 + 0.5 * sin(TAU * 38.0 * t)
			var tone := sin(TAU * ph) + 0.4 * sin(TAU * ph * 2.0)
			if at + i < n:
				s[at + i] += tone * buzz * sin(PI * t / 0.22) * 0.12
	Sfx._lowpass(s, 0.7)
	return _finish_loop(s, 0.5)


# --- one-shots --------------------------------------------------------------------------

static func _shot(key: String, maker: Callable) -> AudioStreamWAV:
	if not _shots.has(key):
		var s: PackedFloat32Array = maker.call()
		Sfx._fade_edges(s)
		Sfx._normalize(s, 0.8)
		_shots[key] = Sfx._to_wav(s)
	return _shots[key]


## A bird call. kind: "sparrow" (quick chirps), "dove" (soft coo), "myna" (whistled notes).
static func bird(kind: String, variant: int) -> AudioStreamWAV:
	return _shot("bird_%s_%d" % [kind, variant], func() -> PackedFloat32Array:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(kind) + variant * 31
		match kind:
			"dove":
				return _dove(rng)
			"myna":
				return _myna(rng)
		return _sparrow(rng))


static func _sparrow(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var count := rng.randi_range(3, 7)
	var s := _empty(0.12 * count + 0.2)
	var base := rng.randf_range(3600.0, 5200.0)
	for c in count:
		var at := int((c * 0.12 + rng.randf_range(0.0, 0.03)) * RATE)
		var dur := rng.randf_range(0.04, 0.07)
		var sweep := rng.randf_range(-6000.0, 3000.0)
		var ph := 0.0
		for i in int(RATE * dur):
			var t := float(i) / RATE
			ph += (base + sweep * t / dur) / RATE
			if at + i < s.size():
				s[at + i] += sin(TAU * ph) * sin(PI * t / dur)
	return s


static func _dove(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var s := _empty(2.0)
	var f := rng.randf_range(430.0, 560.0)
	var notes := [[0.0, 0.25, 1.0], [0.45, 0.22, 0.85], [0.8, 0.6, 1.0]]   # hoo, hoo, hooo
	for nt: Array in notes:
		var at := int(float(nt[0]) * RATE)
		var dur: float = nt[1]
		var ph := 0.0
		for i in int(RATE * dur):
			var t := float(i) / RATE
			var bend := 1.0 + 0.06 * sin(PI * t / dur)
			ph += f * bend / RATE
			var env := sin(PI * t / dur) * float(nt[2])
			s[at + i] += (sin(TAU * ph) + 0.15 * sin(TAU * ph * 2.0)) * env
	Sfx._lowpass(s, 0.3)
	return s


static func _myna(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var count := rng.randi_range(2, 4)
	var s := _empty(0.3 * count + 0.2)
	for c in count:
		var at := int(c * 0.3 * RATE)
		var f0 := rng.randf_range(1400.0, 2600.0)
		var f1 := f0 * rng.randf_range(0.7, 1.5)
		var dur := rng.randf_range(0.12, 0.22)
		var ph := 0.0
		for i in int(RATE * dur):
			var t := float(i) / RATE
			var f := lerpf(f0, f1, t / dur) * (1.0 + 0.02 * sin(TAU * 30.0 * t))   # slide + warble
			ph += f / RATE
			s[at + i] += sin(TAU * ph) * sin(PI * t / dur)
	return s


## A rooster far away: "kuk-ku-ru-kuuuu" (a buzzy voice that rises and falls).
static func rooster(variant: int) -> AudioStreamWAV:
	return _shot("rooster_%d" % variant, func() -> PackedFloat32Array:
		var rng := RandomNumberGenerator.new()
		rng.seed = 3100 + variant
		var k := rng.randf_range(0.9, 1.12)
		var parts := [[0.12, 520.0, 600.0], [0.1, 600.0, 640.0], [0.14, 680.0, 760.0], [0.75, 820.0, 560.0]]
		var s := _empty(1.4)
		var at := 0
		var ph := 0.0
		for p: Array in parts:
			var dur: float = p[0]
			for i in int(RATE * dur):
				var t := float(i) / RATE
				var f := lerpf(float(p[1]), float(p[2]), t / dur) * k
				ph += f / RATE
				var x := fmod(ph, 1.0)
				var saw := 2.0 * x - 1.0
				var env := minf(1.0, t / 0.02) * (1.0 - smoothstep(dur * 0.7, dur, t))
				s[at + i] += saw * env
			at += int(RATE * (dur + 0.03))
		Sfx._lowpass(s, 0.18)
		Sfx._lowpass(s, 0.3)
		return s)


## A dog barking 1-3 times somewhere.
static func dog(variant: int) -> AudioStreamWAV:
	return _shot("dog_%d" % variant, func() -> PackedFloat32Array:
		var rng := RandomNumberGenerator.new()
		rng.seed = 7700 + variant
		var barks := rng.randi_range(1, 3)
		var f0 := rng.randf_range(280.0, 480.0)
		var s := _empty(0.35 * barks + 0.2)
		for b in barks:
			var at := int(b * rng.randf_range(0.28, 0.36) * RATE)
			var dur := 0.16
			var ph := 0.0
			for i in int(RATE * dur):
				var t := float(i) / RATE
				var f := f0 * (1.0 + 0.5 * t / dur) if t < 0.04 else f0 * (1.2 - 0.6 * (t - 0.04) / dur)
				ph += f / RATE
				var x := fmod(ph, 1.0)
				var voice := (2.0 * x - 1.0) * 0.7 + rng.randf_range(-1.0, 1.0) * 0.35
				var env := minf(1.0, t / 0.008) * exp(-t * 18.0)
				if at + i < s.size():
					s[at + i] += voice * env
		Sfx._lowpass(s, 0.25)
		return s)


## A cat: "mi-aaow", a voice that slides up then down.
static func meow(variant: int) -> AudioStreamWAV:
	return _shot("meow_%d" % variant, func() -> PackedFloat32Array:
		var rng := RandomNumberGenerator.new()
		rng.seed = 8800 + variant
		var f0 := rng.randf_range(520.0, 700.0)
		var dur := rng.randf_range(0.45, 0.8)
		var s := _empty(dur + 0.05)
		var ph := 0.0
		for i in int(RATE * dur):
			var t := float(i) / RATE
			var u := t / dur
			var f := f0 * (1.0 + 0.45 * sin(PI * minf(u * 1.6, 1.0)) - 0.25 * maxf(0.0, u - 0.6))
			ph += f * (1.0 + 0.012 * sin(TAU * 7.0 * t)) / RATE
			var voice := sin(TAU * ph) + 0.55 * sin(TAU * ph * 2.0) + 0.3 * sin(TAU * ph * 3.0) * (1.0 - u)
			s[i] = voice * minf(1.0, t / 0.05) * (1.0 - smoothstep(0.65, 1.0, u))
		Sfx._lowpass(s, 0.45)
		return s)


## A happy cat purring.
static func purr() -> AudioStreamWAV:
	return _shot("purr", func() -> PackedFloat32Array:
		var rng := RandomNumberGenerator.new()
		rng.seed = 8900
		var s := _empty(1.8)
		for i in s.size():
			var t := float(i) / RATE
			var pulse := pow(0.5 + 0.5 * sin(TAU * 26.0 * t), 3.0)
			var breath := 0.65 + 0.35 * sin(TAU * 1.1 * t)
			s[i] = (rng.randf_range(-1.0, 1.0) * 0.6 + sin(TAU * 52.0 * t)) * pulse * breath
		Sfx._lowpass(s, 0.12)
		return s)


## A happy dog panting.
static func pant() -> AudioStreamWAV:
	return _shot("pant", func() -> PackedFloat32Array:
		var rng := RandomNumberGenerator.new()
		rng.seed = 8950
		var s := _empty(1.6)
		for i in s.size():
			var t := float(i) / RATE
			s[i] = rng.randf_range(-1.0, 1.0) * pow(maxf(0.0, sin(TAU * 3.6 * t)), 2.0)
		Sfx._lowpass(s, 0.3)
		return s)


## The tuko gecko at night: a throaty buildup, then "to-KO, to-KO..." a few times.
static func gecko(variant: int) -> AudioStreamWAV:
	return _shot("gecko_%d" % variant, func() -> PackedFloat32Array:
		var rng := RandomNumberGenerator.new()
		rng.seed = 5150 + variant
		var calls := rng.randi_range(3, 6)
		var s := _empty(0.5 + calls * 0.7)
		var at := 0
		for i in int(RATE * 0.4):   # the rattle before it starts
			var t := float(i) / RATE
			s[i] += rng.randf_range(-1.0, 1.0) * (0.5 + 0.5 * sin(TAU * 25.0 * t)) * 0.25 * sin(PI * t / 0.4)
		at = int(RATE * 0.5)
		for c in calls:
			var fade := 1.0 - float(c) / (calls + 1) * 0.5    # later calls get quieter
			for syl: Array in [[0.12, 260.0, 0.7], [0.2, 520.0, 1.0]]:   # "to", "KO"
				var dur: float = syl[0]
				var ph := 0.0
				for i in int(RATE * dur):
					var t := float(i) / RATE
					ph += float(syl[1]) * (1.0 - 0.25 * t / dur) / RATE
					var throat := 0.55 + 0.45 * sin(TAU * 60.0 * t)
					var env := sin(PI * t / dur) * float(syl[2]) * fade
					if at + i < s.size():
						s[at + i] += (sin(TAU * ph) + 0.5 * sin(TAU * ph * 2.0)) * throat * env
				at += int(RATE * (dur + 0.06))
			at += int(RATE * 0.3)
		Sfx._lowpass(s, 0.35)
		return s)
