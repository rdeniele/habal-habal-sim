class_name Sfx
extends RefCounted
## Placeholder sound effects generated in code (beeps), so we have audio feedback
## before we add real CC0 sounds in Milestone 7.

const RATE := 22050

static var _cache: Dictionary = {}


## A short sequence of sine "beeps", one per frequency (Hz).
static func tones(freqs: Array, note_len: float = 0.1, volume: float = 0.35) -> AudioStreamWAV:
	var key := "%s|%s|%s" % [str(freqs), note_len, volume]
	if _cache.has(key):
		return _cache[key]
	var per_note := int(RATE * note_len)
	var fade := RATE * 0.01   # 10 ms fade in/out so it doesn't click
	var data := PackedByteArray()
	data.resize(per_note * freqs.size() * 2)
	var idx := 0
	for f: float in freqs:
		for i in per_note:
			var env := minf(1.0, minf(float(i), float(per_note - i)) / fade)
			var s := sin(TAU * f * i / RATE) * volume * env
			data.encode_s16(idx * 2, int(s * 32767.0))
			idx += 1
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
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
