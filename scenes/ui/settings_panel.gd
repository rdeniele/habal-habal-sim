class_name SettingsPanel
extends PanelContainer
## Settings screen (used by the main menu and the pause menu).
## Every change is applied and saved right away to user://settings.cfg.

signal closed

const INK := Color("#1d2733")
const MUTED := Color("#6b7785")

const CONTROLS_TEXT := """On foot: WASD walk · Shift run · Mouse look · F get on motor · E interact
On motor: W gas · S brake/reverse · A/D steer · Space handbrake · H horn · F get off
Sakay app: Tab phone · 1 accept · 2 decline
Camera: C change view   ·   Esc pause   ·   F1 controls help
Fighting (Milestone 5): J / left mouse punch · K / right mouse block · L dodge
Gamepad: LS move/steer · RT gas · LT brake · Y get on/off · A interact · RB handbrake · Back phone"""


func _ready() -> void:
	custom_minimum_size = Vector2(620, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#f4f7f9")
	sb.set_corner_radius_all(18)
	sb.set_content_margin_all(22)
	add_theme_stylebox_override("panel", sb)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	add_child(col)
	_label(col, "SETTINGS", 24, INK)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 470)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)

	_section(grid, "Display")
	_check(grid, "Fullscreen", Settings.fullscreen, func(v: bool) -> void: Settings.fullscreen = v)
	_option(grid, "Window size", Settings.RESOLUTIONS, Settings.RESOLUTIONS.find(Settings.resolution),
		func(i: int) -> void: Settings.resolution = Settings.RESOLUTIONS[i])
	_check(grid, "V-Sync", Settings.vsync, func(v: bool) -> void: Settings.vsync = v)
	var fps_names := ["Unlimited", "30", "60", "120"]
	_option(grid, "FPS limit", fps_names, Settings.FPS_LIMITS.find(Settings.fps_limit),
		func(i: int) -> void: Settings.fps_limit = Settings.FPS_LIMITS[i])

	_section(grid, "Graphics")
	_option(grid, "Quality (shadows, draw distance)", ["Low", "Medium", "High"], Settings.GRAPHICS.find(Settings.graphics),
		func(i: int) -> void: Settings.graphics = Settings.GRAPHICS[i])

	_section(grid, "Audio")
	_slider(grid, "Master volume", Settings.master_volume, 0.0, 1.0, func(v: float) -> void: Settings.master_volume = v)
	_slider(grid, "Music volume", Settings.music_volume, 0.0, 1.0, func(v: float) -> void: Settings.music_volume = v)
	_slider(grid, "Sound effects", Settings.sfx_volume, 0.0, 1.0, func(v: float) -> void: Settings.sfx_volume = v)

	_section(grid, "Controls")
	_slider(grid, "Mouse sensitivity", Settings.mouse_sensitivity / Settings.DEFAULT_MOUSE, 0.3, 2.5,
		func(v: float) -> void: Settings.mouse_sensitivity = v * Settings.DEFAULT_MOUSE)
	_check(grid, "Invert Y (look)", Settings.invert_y, func(v: bool) -> void: Settings.invert_y = v)

	_section(grid, "Gameplay")
	var lang_keys: Array = Settings.LANGUAGES.keys()
	var lang_names: Array = Settings.LANGUAGES.values()
	_option(grid, "Passenger language", lang_names, lang_keys.find(Settings.passenger_language),
		func(i: int) -> void: Settings.passenger_language = lang_keys[i])

	_section(grid, "Controls list")
	var controls := _label(grid, CONTROLS_TEXT, 13, MUTED)
	controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls.custom_minimum_size.x = 540
	grid.add_child(Control.new())

	var back := Button.new()
	back.text = "Back"
	back.focus_mode = Control.FOCUS_NONE
	back.custom_minimum_size.y = 40
	back.pressed.connect(func() -> void: closed.emit())
	col.add_child(back)


func _changed() -> void:
	Settings.apply()
	Settings.save()


func _section(grid: GridContainer, text: String) -> void:
	var l := _label(grid, text.to_upper(), 13, Color("#14a39a"))
	l.custom_minimum_size.y = 26
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	grid.add_child(Control.new())


func _check(grid: GridContainer, text: String, value: bool, setter: Callable) -> void:
	_label(grid, text, 15, INK)
	var c := CheckBox.new()
	c.button_pressed = value
	c.focus_mode = Control.FOCUS_NONE
	c.toggled.connect(func(v: bool) -> void:
		setter.call(v)
		_changed())
	grid.add_child(c)


func _option(grid: GridContainer, text: String, names: Array, selected: int, setter: Callable) -> void:
	_label(grid, text, 15, INK)
	var o := OptionButton.new()
	o.focus_mode = Control.FOCUS_NONE
	for n in names:
		o.add_item(str(n))
	o.selected = maxi(0, selected)
	o.item_selected.connect(func(i: int) -> void:
		setter.call(i)
		_changed())
	grid.add_child(o)


func _slider(grid: GridContainer, text: String, value: float, lo: float, hi: float, setter: Callable) -> void:
	_label(grid, text, 15, INK)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 0.01
	s.value = value
	s.custom_minimum_size = Vector2(220, 24)
	s.focus_mode = Control.FOCUS_NONE
	s.value_changed.connect(func(v: float) -> void:
		setter.call(v)
		_changed())
	grid.add_child(s)


func _label(parent: Control, text: String, size: int, c: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	parent.add_child(l)
	return l
