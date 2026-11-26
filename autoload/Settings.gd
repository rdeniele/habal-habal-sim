extends Node
## Player settings (display, graphics, audio, controls, language).
## Saved in user://settings.cfg (separate from save slots, shared by all slots).
## Read anywhere: Settings.mouse_sensitivity, Settings.graphics, ...
## After changing values call Settings.apply() and Settings.save().

signal changed

const PATH := "user://settings.cfg"
const RESOLUTIONS := ["1280x720", "1600x900", "1920x1080"]
const FPS_LIMITS := [0, 30, 60, 120]          # 0 = unlimited
const GRAPHICS := ["low", "medium", "high"]
const LANGUAGES := {"mixed": "Mixed", "hil": "Hiligaynon", "ceb": "Bisaya", "tl": "Tagalog", "en": "English"}
const DEFAULT_MOUSE := 0.0025
## Day length: in-game minutes per real second. Normal = 7 AM to 11 PM in about 16 minutes.
const DAY_LENGTHS := {"short": 2.0, "normal": 1.0, "long": 0.5}

# Display
var fullscreen := false
var resolution := "1280x720"
var vsync := true
var fps_limit := 60
# Graphics: shadows, anti-aliasing, draw distance (and traffic density in Milestone 5)
var graphics := "medium"
# Audio (0.0 - 1.0)
var master_volume := 0.8
var music_volume := 0.6
var sfx_volume := 0.8
# Controls
var mouse_sensitivity := DEFAULT_MOUSE
var invert_y := false
# Gameplay
var passenger_language := "mixed"
var day_length := "normal"


func game_minutes_per_second() -> float:
	return float(DAY_LENGTHS.get(day_length, Economy.GAME_MINUTES_PER_SECOND))


func _ready() -> void:
	_ensure_audio_buses()
	load_settings()
	apply()


# --- Graphics preset values (used by the camera / world) ---------------------

func shadows_enabled() -> bool:
	return graphics != "low"


func draw_distance() -> float:
	match graphics:
		"low":
			return 450.0
		"medium":
			return 1200.0
	return 2500.0


# --- Apply / load / save -----------------------------------------------------

func apply() -> void:
	# Window
	if not DisplayServer.get_name().contains("headless"):
		if fullscreen:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		else:
			if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			var parts := resolution.split("x")
			if parts.size() == 2:
				var size := Vector2i(int(parts[0]), int(parts[1]))
				if DisplayServer.window_get_size() != size:
					DisplayServer.window_set_size(size)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = fps_limit

	# Anti-aliasing per graphics preset
	var vp := get_viewport()
	match graphics:
		"low":
			vp.msaa_3d = Viewport.MSAA_DISABLED
		"medium":
			vp.msaa_3d = Viewport.MSAA_2X
		_:
			vp.msaa_3d = Viewport.MSAA_4X

	# Low: draw the 3D world at 77% resolution and sharpen it back up (FSR).
	# Much faster on weak laptops/integrated graphics; menus and text stay sharp.
	if graphics == "low":
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
		vp.scaling_3d_scale = 0.77
	else:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = 1.0

	# Audio
	_set_bus_volume("Master", master_volume)
	_set_bus_volume("Music", music_volume)
	_set_bus_volume("SFX", sfx_volume)
	changed.emit()


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("display", "resolution", resolution)
	cfg.set_value("display", "vsync", vsync)
	cfg.set_value("display", "fps_limit", fps_limit)
	cfg.set_value("graphics", "preset", graphics)
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("controls", "invert_y", invert_y)
	cfg.set_value("gameplay", "passenger_language", passenger_language)
	cfg.set_value("gameplay", "day_length", day_length)
	var err := cfg.save(PATH)
	if err != OK:
		push_warning("Could not save settings (error %d)" % err)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return   # first launch: keep defaults
	fullscreen = cfg.get_value("display", "fullscreen", fullscreen)
	resolution = cfg.get_value("display", "resolution", resolution)
	vsync = cfg.get_value("display", "vsync", vsync)
	fps_limit = cfg.get_value("display", "fps_limit", fps_limit)
	graphics = cfg.get_value("graphics", "preset", graphics)
	master_volume = cfg.get_value("audio", "master", master_volume)
	music_volume = cfg.get_value("audio", "music", music_volume)
	sfx_volume = cfg.get_value("audio", "sfx", sfx_volume)
	mouse_sensitivity = cfg.get_value("controls", "mouse_sensitivity", mouse_sensitivity)
	invert_y = cfg.get_value("controls", "invert_y", invert_y)
	passenger_language = cfg.get_value("gameplay", "passenger_language", passenger_language)
	day_length = cfg.get_value("gameplay", "day_length", day_length)
	if not DAY_LENGTHS.has(day_length):
		day_length = "normal"
	if not GRAPHICS.has(graphics):
		graphics = "medium"
	if not LANGUAGES.has(passenger_language):
		passenger_language = "mixed"


# --- Audio buses -------------------------------------------------------------

## Creates "Music" and "SFX" buses (children of Master) if the project has none.
func _ensure_audio_buses() -> void:
	for bus_name: String in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")


func _set_bus_volume(bus_name: String, value: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(value, 0.0001)))
	AudioServer.set_bus_mute(idx, value <= 0.001)
