extends SceneTree
## Makes every code-generated sound, checks it isn't empty/broken, and saves a .wav copy to
## user://sounds/ so you can listen to them in any music player.
## Runs without a window:
##   godot --headless --path . -s res://tests/audio_test.gd

var _fails := 0


func _init() -> void:
	DirAccess.make_dir_recursive_absolute("user://sounds")
	var sounds := {
		"ping": func() -> AudioStreamWAV: return Sfx.ping(),
		"cash": func() -> AudioStreamWAV: return Sfx.cash(),
		"error": func() -> AudioStreamWAV: return Sfx.error(),
		"horn_car": func() -> AudioStreamWAV: return Sfx.horn("car"),
		"horn_jeepney": func() -> AudioStreamWAV: return Sfx.horn("jeepney"),
		"horn_tricycle": func() -> AudioStreamWAV: return Sfx.horn("tricycle"),
		"horn_motorbike": func() -> AudioStreamWAV: return Sfx.horn("motorbike"),
		"crash": func() -> AudioStreamWAV: return Sfx.crash(),
		"punch": func() -> AudioStreamWAV: return Sfx.punch(false),
		"punch_blocked": func() -> AudioStreamWAV: return Sfx.punch(true),
		"whistle": func() -> AudioStreamWAV: return Sfx.whistle(),
		"siren": func() -> AudioStreamWAV: return Sfx.siren(),
		"music_loop": func() -> AudioStreamWAV: return Sfx.music_loop(),
		"amb_city": func() -> AudioStreamWAV: return NatureSfx.loop("city"),
		"amb_wind": func() -> AudioStreamWAV: return NatureSfx.loop("wind"),
		"amb_leaves": func() -> AudioStreamWAV: return NatureSfx.loop("leaves"),
		"amb_sea": func() -> AudioStreamWAV: return NatureSfx.loop("sea"),
		"amb_night": func() -> AudioStreamWAV: return NatureSfx.loop("night"),
		"bird_sparrow": func() -> AudioStreamWAV: return NatureSfx.bird("sparrow", 0),
		"bird_dove": func() -> AudioStreamWAV: return NatureSfx.bird("dove", 0),
		"bird_myna": func() -> AudioStreamWAV: return NatureSfx.bird("myna", 0),
		"rooster": func() -> AudioStreamWAV: return NatureSfx.rooster(0),
		"dog": func() -> AudioStreamWAV: return NatureSfx.dog(0),
		"gecko": func() -> AudioStreamWAV: return NatureSfx.gecko(0),
	}
	for sound_name: String in sounds:
		var t0 := Time.get_ticks_msec()
		var wav: AudioStreamWAV = (sounds[sound_name] as Callable).call()
		var ms := Time.get_ticks_msec() - t0
		var secs := wav.data.size() / 2.0 / Sfx.RATE
		var peak := 0
		for i in range(0, wav.data.size(), 2):
			peak = maxi(peak, absi(wav.data.decode_s16(i)))
		var ok := secs > 0.05 and peak > 1000
		if not ok:
			_fails += 1
		print("  %s  %-15s %5.2f s  peak %3d%%  made in %d ms" % ["PASS" if ok else "FAIL", sound_name, secs, peak * 100 / 32767, ms])
		wav.save_to_wav("user://sounds/%s.wav" % sound_name)
	print("  saved to: ", ProjectSettings.globalize_path("user://sounds"))
	print("AUDIO TEST DONE: %s" % ("ALL PASSED" if _fails == 0 else "%d FAILED" % _fails))
	quit(1 if _fails > 0 else 0)
