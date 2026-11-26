class_name Sfx
extends RefCounted
## All game sounds are made in code (no sound files, no licenses to worry about).
## Each sound is "synthesized" once into an AudioStreamWAV and cached.
## Tricks used: noise (hiss/crunch), sine/sawtooth waves (tones), envelopes (fade in/out),
## a simple low-pass filter (makes things sound softer/further away) and Karplus-Strong
## (a classic trick that makes a burst of noise ring like a plucked guitar string).
## Real recordings can replace any of these later: just return a loaded .ogg/.wav instead.

const RATE := 22050

static var _cache: Dictionary = {}


# --- Helpers ---------------------------------------------------------------------------

## Turns float samples (-1..1) into a playable sound.
static func _to_wav(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = samples.size()
	return wav


## One-pole low-pass filter, in place. `amount` 0..1 (smaller = more muffled).
static func _lowpass(s: PackedFloat32Array, amount: float) -> void:
	var y := 0.0
	for i in s.size():
		y += amount * (s[i] - y)
		s[i] = y


## Mixes `src` into `dst` starting at sample `at`, multiplied by `gain`.
static func _mix(dst: PackedFloat32Array, src: PackedFloat32Array, at: int, gain := 1.0) -> void:
	var n := mini(src.size(), dst.size() - at)
	for i in n:
		dst[at + i] += src[i] * gain


## Scale so the loudest sample is `peak` (no clipping/distortion).
static func _normalize(s: PackedFloat32Array, peak: float) -> void:
	var m := 0.0
	for v in s:
		m = maxf(m, absf(v))
	if m > 0.0001:
		var k := peak / m
		for i in s.size():
			s[i] *= k


## Short fade at both ends so sounds don't click.
static func _fade_edges(s: PackedFloat32Array, fade_sec := 0.01) -> void:
	var f := int(RATE * fade_sec)
	for i in mini(f, s.size()):
		s[i] *= float(i) / f
		s[s.size() - 1 - i] *= float(i) / f


## A horn-like tone: sawtooth chord (all `freqs` at once), low-passed so it's not harsh.
static func _horn_tone(freqs: Array, seconds: float, volume: float, muffle := 0.25) -> PackedFloat32Array:
	var n := int(RATE * seconds)
	var s := PackedFloat32Array()
	s.resize(n)
	for f: float in freqs:
		var ph := 0.0
		for i in n:
			ph = fmod(ph + f / RATE, 1.0)
			s[i] += (ph * 2.0 - 1.0) * volume / freqs.size()
	_lowpass(s, muffle)
	_lowpass(s, muffle * 1.6)
	_fade_edges(s, 0.015)
	return s


# --- Simple beeps (UI) ----------------------------------------------------------------

## A short sequence of soft "beeps", one per frequency (Hz). 0 = a short silence.
static func tones(freqs: Array, note_len: float = 0.1, volume: float = 0.35) -> AudioStreamWAV:
	var key := "%s|%s|%s" % [str(freqs), note_len, volume]
	if _cache.has(key):
		return _cache[key]
	var per_note := int(RATE * note_len)
	var s := PackedFloat32Array()
	s.resize(per_note * freqs.size())
	var idx := 0
	for f: float in freqs:
		for i in per_note:
			var t := float(i) / RATE
			var env := minf(1.0, float(i) / (RATE * 0.005)) * exp(-t * 9.0 / maxf(note_len * 6.0, 0.3))
			# sine plus a little 2nd harmonic = a rounder "marimba-ish" beep
			s[idx] = (sin(TAU * f * t) + 0.25 * sin(TAU * 2.0 * f * t)) * volume * env
			idx += 1
	_fade_edges(s, 0.004)
	var wav := _to_wav(s)
	_cache[key] = wav
	return wav


## Phone notification: two quick high beeps.
static func ping() -> AudioStreamWAV:
	return tones([1320.0, 0.0, 1760.0], 0.08)


## Cash register-ish rising notes.
static func cash() -> AudioStreamWAV:
	return tones([880.0, 1175.0, 1568.0], 0.09)


static func error() -> AudioStreamWAV:
	return tones([330.0, 220.0], 0.14)


# --- Street sounds ----------------------------------------------------------------------

## Vehicle horn by kind: "car", "jeepney", "tricycle", "motorbike".
static func horn(kind: String) -> AudioStreamWAV:
	var key := "horn_" + kind
	if _cache.has(key):
		return _cache[key]
	var s := PackedFloat32Array()
	match kind:
		"jeepney":
			# big jeepney air horn: three rising notes
			s.resize(int(RATE * 1.05))
			_mix(s, _horn_tone([233.0, 294.0], 0.28, 0.55, 0.3), 0)
			_mix(s, _horn_tone([262.0, 330.0], 0.28, 0.55, 0.3), int(RATE * 0.32))
			_mix(s, _horn_tone([311.0, 392.0], 0.4, 0.55, 0.3), int(RATE * 0.64))
		"tricycle":
			# thin little "meep meep"
			s.resize(int(RATE * 0.42))
			_mix(s, _horn_tone([560.0, 600.0], 0.15, 0.4, 0.35), 0)
			_mix(s, _horn_tone([560.0, 600.0], 0.18, 0.4, 0.35), int(RATE * 0.22))
		"motorbike":
			s = _horn_tone([415.0, 520.0], 0.3, 0.42, 0.3)
		_:
			# car: classic two-tone "beep-beeeep"
			s.resize(int(RATE * 0.8))
			_mix(s, _horn_tone([350.0, 440.0], 0.18, 0.5, 0.22), 0)
			_mix(s, _horn_tone([350.0, 440.0], 0.5, 0.5, 0.22), int(RATE * 0.26))
	var wav := _to_wav(s)
	_cache[key] = wav
	return wav


## Car crash: crunch of noise + metal clangs + a low thump.
static func crash() -> AudioStreamWAV:
	if _cache.has("crash"):
		return _cache["crash"]
	var n := int(RATE * 0.9)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var y := 0.0
	for i in n:
		var t := float(i) / RATE
		y += 0.35 * (rng.randf_range(-1.0, 1.0) - y)            # muffled crunch noise
		var v := y * 1.4 * exp(-t * 7.0)
		v += sin(TAU * (90.0 - t * 60.0) * t) * 0.6 * exp(-t * 14.0)   # thump
		for p: Vector2 in [Vector2(523.0, 9.0), Vector2(1187.0, 12.0), Vector2(1913.0, 16.0)]:
			v += sin(TAU * p.x * t) * 0.12 * exp(-t * p.y)       # metal ring
		# a second smaller crunch (glass/plastic bits) a moment later
		if t > 0.18:
			v += rng.randf_range(-1.0, 1.0) * 0.25 * exp(-(t - 0.18) * 18.0)
		s[i] = v * 0.6
	_fade_edges(s, 0.003)
	var wav := _to_wav(s)
	_cache["crash"] = wav
	return wav


## Punch landing (blocked = duller, softer).
static func punch(blocked: bool) -> AudioStreamWAV:
	var key := "punch_%s" % blocked
	if _cache.has(key):
		return _cache[key]
	var n := int(RATE * 0.16)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		ph += (140.0 - t * 500.0) / RATE                       # pitch drops fast = "thud"
		var v := sin(TAU * ph) * exp(-t * 30.0)
		v += rng.randf_range(-1.0, 1.0) * exp(-t * (90.0 if not blocked else 140.0)) * 0.7   # slap
		s[i] = v * (0.75 if not blocked else 0.4)
	if blocked:
		_lowpass(s, 0.3)
	_fade_edges(s, 0.002)
	var wav := _to_wav(s)
	_cache[key] = wav
	return wav


## Enforcer's whistle (two sharp tweets).
static func whistle() -> AudioStreamWAV:
	if _cache.has("whistle"):
		return _cache["whistle"]
	var s := PackedFloat32Array()
	s.resize(int(RATE * 0.55))
	var rng := RandomNumberGenerator.new()
	for start: float in [0.0, 0.25]:
		var n := int(RATE * 0.2)
		for i in n:
			var t := float(i) / RATE
			# a whistle "trills": the pitch wobbles fast, plus a little breath noise
			var f := 2800.0 + sin(TAU * 32.0 * t) * 180.0
			var env := minf(1.0, t / 0.01) * minf(1.0, (0.2 - t) / 0.03)
			s[int(start * RATE) + i] += (sin(TAU * f * t) * 0.3 + rng.randf_range(-1, 1) * 0.04) * env
	var wav := _to_wav(s)
	_cache["whistle"] = wav
	return wav


## Looping police siren (smooth wail up and down).
static func siren() -> AudioStreamWAV:
	if _cache.has("siren"):
		return _cache["siren"]
	var frames := int(RATE * 1.6)
	var s := PackedFloat32Array()
	s.resize(frames)
	var phase := 0.0
	for i in frames:
		var t := float(i) / frames
		var f := 650.0 + 450.0 * (0.5 - 0.5 * cos(t * TAU))   # 650 -> 1100 -> 650 Hz
		phase = fmod(phase + f / RATE, 1.0)
		# rounded square wave (fundamental + 3rd + 5th harmonics) = less harsh than a pure square
		var x := TAU * phase
		s[i] = (sin(x) + sin(3.0 * x) / 3.0 + sin(5.0 * x) / 5.0) * 0.28
	var wav := _to_wav(s, true)
	_cache["siren"] = wav
	return wav


# --- Long sounds (made on a background thread, see BackgroundAudio) ----------------------

## City background: distant traffic rumble, far-away horns and the odd rooster/bird.
## 12-second loop.
static func city_ambience() -> AudioStreamWAV:
	var seconds := 12.0
	var n := int(RATE * seconds)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1903
	# brown noise = deep rumble of far traffic
	var b := 0.0
	var y := 0.0
	for i in n:
		b = clampf(b + rng.randf_range(-1.0, 1.0) * 0.02, -1.0, 1.0)
		y += 0.05 * (b - y)
		var t := float(i) / RATE
		var swell := 0.75 + 0.25 * sin(TAU * t / seconds * 2.0)   # traffic comes and goes (loops cleanly)
		s[i] = y * 0.9 * swell
	# far-away horns (quiet and muffled)
	for k in 5:
		var kinds := ["car", "car", "tricycle", "jeepney", "motorbike"]
		var h := _horn_far(kinds[k] as String, rng)
		_mix(s, h, int(rng.randf_range(0.2, seconds - 1.4) * RATE), rng.randf_range(0.12, 0.22))
	# birds chirping now and then
	for k in 4:
		_mix(s, _chirp(rng), int(rng.randf_range(0.2, seconds - 0.6) * RATE), 0.06)
	# make the loop seamless: blend the last half second into the start
	var xf := int(RATE * 0.5)
	for i in xf:
		var w := float(i) / xf
		s[i] = s[i] * w + s[n - xf + i] * (1.0 - w)
	s.resize(n - xf)
	_normalize(s, 0.7)
	return _to_wav(s, true)


static func _horn_far(kind: String, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var f := rng.randf_range(0.9, 1.1)
	match kind:
		"jeepney":
			return _horn_tone([233.0 * f, 294.0 * f], 0.5, 1.0, 0.08)
		"tricycle":
			return _horn_tone([560.0 * f, 600.0 * f], 0.2, 1.0, 0.1)
		"motorbike":
			return _horn_tone([415.0 * f, 520.0 * f], 0.25, 1.0, 0.08)
	return _horn_tone([350.0 * f, 440.0 * f], 0.35, 1.0, 0.08)


static func _chirp(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	s.resize(int(RATE * 0.5))
	var base := rng.randf_range(3000.0, 4200.0)
	for c in 3:
		var at := int(c * RATE * 0.13)
		var ph := 0.0
		for i in int(RATE * 0.07):
			var t := float(i) / RATE
			ph += (base + t * 9000.0) / RATE
			s[at + i] += sin(TAU * ph) * sin(PI * t / 0.07)
	return s


## Background music: a laid-back acoustic guitar loop (like a radio in a carinderia).
## Original tune, made from scratch: G - D - Em - C, 92 BPM, 8 bars (~21 s), loops.
static func music_loop() -> AudioStreamWAV:
	var bpm := 92.0
	var beat := 60.0 / bpm
	var bars := 8
	var n := int(RATE * beat * 4.0 * bars)
	var s := PackedFloat32Array()
	s.resize(n + RATE * 2)   # 2 s extra for ringing notes (folded back to the start below)
	# chord notes (Hz): bass note + three guitar notes
	var chords := [
		[98.0, [196.0, 247.0, 294.0, 392.0]],    # G
		[146.8, [220.0, 294.0, 370.0, 440.0]],   # D
		[82.4, [196.0, 247.0, 330.0, 392.0]],    # Em
		[130.8, [196.0, 262.0, 330.0, 392.0]],   # C
	]
	# 8th-note picking pattern (index into the chord's guitar notes)
	var pattern := [0, 2, 1, 3, 2, 1, 3, 2]
	var plucks: Dictionary = {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 2003
	for bar in bars:
		var chord: Array = chords[bar % 4]
		var bar_start := bar * 4.0 * beat
		# bass on beats 1 and 3
		for b in [0, 2]:
			var bass_f: float = chord[0] * (1.0 if b == 0 else 1.5)
			_mix(s, _bass(bass_f, beat * 1.8), int((bar_start + b * beat) * RATE), 0.42)
		# guitar 8th notes
		var notes: Array = chord[1]
		for e in 8:
			var f: float = notes[pattern[e]]
			if bar % 2 == 1 and e == 7:
				f = notes[3] * 1.122   # a little passing note at the end of every 2nd bar
			if not plucks.has(f):
				plucks[f] = _pluck(f, 1.4, rng)
			var swing := 0.06 * beat if e % 2 == 1 else 0.0   # lazy swing feel
			_mix(s, plucks[f], int((bar_start + e * beat * 0.5 + swing) * RATE), 0.3 if e % 2 == 0 else 0.22)
		# soft shaker on the off-beats
		for e in 4:
			_mix(s, _shaker(rng), int((bar_start + (e + 0.5) * beat) * RATE), 0.05)
	# the tail of the last notes wraps around to the start so the loop is seamless
	for i in range(n, s.size()):
		s[i - n] += s[i]
	s.resize(n)
	_normalize(s, 0.8)
	return _to_wav(s, true)


## Karplus-Strong plucked string.
static func _pluck(f: float, seconds: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var period := maxi(2, int(RATE / f))
	var buf := PackedFloat32Array()
	buf.resize(period)
	for i in period:
		buf[i] = rng.randf_range(-1.0, 1.0)
	var n := int(RATE * seconds)
	var s := PackedFloat32Array()
	s.resize(n)
	var idx := 0
	for i in n:
		var nxt := (idx + 1) % period
		var v := buf[idx]
		s[i] = v
		buf[idx] = (v + buf[nxt]) * 0.5 * 0.996
		idx = nxt
	_lowpass(s, 0.45)
	_fade_edges(s, 0.004)
	return s


static func _bass(f: float, seconds: float) -> PackedFloat32Array:
	var n := int(RATE * seconds)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		s[i] = (sin(TAU * f * t) + 0.3 * sin(TAU * 2.0 * f * t)) * exp(-t * 2.2) * minf(1.0, t / 0.01)
	_fade_edges(s, 0.02)
	return s


static func _shaker(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(RATE * 0.08)
	var s := PackedFloat32Array()
	s.resize(n)
	var prev := 0.0
	for i in n:
		var w := rng.randf_range(-1.0, 1.0)
		s[i] = (w - prev) * sin(PI * float(i) / n)   # high-passed noise = "tss"
		prev = w
	return s
