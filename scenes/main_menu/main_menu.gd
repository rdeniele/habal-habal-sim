extends Node3D
## Main menu: Continue, New Game, Load Game, Settings, Credits, Quit.
## The test city is shown in the background with a slowly circling camera.

const GAME_SCENE := "res://scenes/main/game.tscn"
const TEAL := Color("#14a39a")

const CREDITS_TEXT := """HABAL-HABAL SIMULATOR
A motorcycle-taxi rider game set in Bacolod City, Negros Occidental.

Made with Godot Engine (MIT License) - godotengine.org

Map data (from Milestone 6): © OpenStreetMap contributors (ODbL)
openstreetmap.org/copyright

All 3D models and sounds are placeholders made in code.
"Sakay" is a fictional ride-hailing app made for this game.
Motorcycle names are used for realism; this game is not affiliated
with any motorcycle brand.

See CREDITS.md for the full list of assets and licenses."""

@onready var cam: Camera3D = $Camera

var _angle := 0.0
var _main: VBoxContainer
var _slots_panel: PanelContainer
var _slots_box: VBoxContainer
var _slots_title: Label
var _settings: SettingsPanel
var _credits: PanelContainer
var _message: Label
var _continue_btn: Button
var _load_btn: Button
var _slot_mode := ""     # "new" or "load"
var _confirm_slot := -1


func _ready() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	GameState.time_hours = 16.6   # warm late-afternoon light for the menu
	var cycle := DayCycle.new()
	add_child(cycle)
	cycle.setup($World, null, null)
	($World as TestCity).environment.fog_density = 0.0007   # less haze from up high
	_build_ui()


func _process(delta: float) -> void:
	_angle += delta * 0.05
	cam.position = Vector3(cos(_angle) * 170.0, 70.0, sin(_angle) * 170.0)
	cam.look_at(Vector3(0, 0, 0))


# --- UI ----------------------------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := MarginContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "top", "right", "bottom"]:
		root.add_theme_constant_override("margin_" + side, 60)
	layer.add_child(root)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 40)
	root.add_child(row)

	# Left: title + buttons
	_main = VBoxContainer.new()
	_main.add_theme_constant_override("separation", 12)
	_main.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_main)
	var title := _label(_main, "HABAL-HABAL\nSIMULATOR", 54, Color.WHITE)
	title.add_theme_constant_override("outline_size", 10)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
	var sub := _label(_main, "Bacolod City · Sakay rider life", 22, Color("#ffd166"))
	sub.add_theme_constant_override("outline_size", 8)
	sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	_main.add_child(_spacer(20))
	_continue_btn = _button(_main, "Continue", _on_continue)
	_button(_main, "New Game", func() -> void:
		_confirm_slot = -1
		_show_slots("new"))
	_load_btn = _button(_main, "Load Game", func() -> void: _show_slots("load"))
	_button(_main, "Settings", _show_settings)
	_button(_main, "Credits", _show_credits)
	_button(_main, "Quit", func() -> void: get_tree().quit())
	_message = _label(_main, "", 15, Color("#ffb4a2"))
	var latest := SaveManager.latest_slot()
	_continue_btn.disabled = latest == -1
	_load_btn.disabled = latest == -1
	if latest != -1:
		_continue_btn.text = "Continue  ·  %s" % SaveManager.describe_slot(latest)

	# Right side: slot picker / settings / credits (one at a time)
	var right := CenterContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)

	_slots_panel = _panel(right)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 10)
	_slots_panel.add_child(sv)
	_slots_title = _label(sv, "", 24, Color("#1d2733"))
	_slots_box = VBoxContainer.new()
	_slots_box.add_theme_constant_override("separation", 8)
	sv.add_child(_slots_box)
	_slots_panel.visible = false

	_settings = SettingsPanel.new()
	_settings.closed.connect(func() -> void: _settings.visible = false)
	_settings.visible = false
	right.add_child(_settings)

	_credits = _panel(right)
	var cv := VBoxContainer.new()
	_credits.add_child(cv)
	var ct := _label(cv, CREDITS_TEXT, 15, Color("#1d2733"))
	ct.custom_minimum_size.x = 560
	ct.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_button(cv, "Back", func() -> void: _credits.visible = false)
	_credits.visible = false


func _hide_right() -> void:
	_slots_panel.visible = false
	_settings.visible = false
	_credits.visible = false
	_confirm_slot = -1


func _show_settings() -> void:
	_hide_right()
	_settings.visible = true


func _show_credits() -> void:
	_hide_right()
	_credits.visible = true


## Slot picker for New Game ("new") or Load Game ("load").
func _show_slots(mode: String) -> void:
	var keep_confirm := _confirm_slot
	_hide_right()
	_confirm_slot = keep_confirm
	_slot_mode = mode
	_slots_title.text = "Choose a save slot for your new game" if mode == "new" else "Load which game?"
	for c in _slots_box.get_children():
		_slots_box.remove_child(c)
		c.queue_free()
	for slot in range(1, SaveManager.SLOT_COUNT + 1):
		var used := SaveManager.has_save(slot)
		var text := "Slot %d   ·   %s" % [slot, SaveManager.describe_slot(slot)]
		if mode == "new" and used and _confirm_slot == slot:
			text = "Slot %d   ·   Overwrite this save? Click again to confirm" % slot
		var b := _button(_slots_box, text, func() -> void: _on_slot_pressed(slot))
		b.custom_minimum_size.x = 520
		b.disabled = mode == "load" and not used
	_button(_slots_box, "Back", _hide_right)
	_slots_panel.visible = true


func _on_slot_pressed(slot: int) -> void:
	if _slot_mode == "load":
		_start_loaded(slot)
		return
	if SaveManager.has_save(slot) and _confirm_slot != slot:
		_confirm_slot = slot
		_show_slots("new")
		return
	SaveManager.delete_slot(slot)
	GameState.reset_new_game()
	GameState.save_slot = slot
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_continue() -> void:
	var slot := SaveManager.latest_slot()
	if slot != -1:
		_start_loaded(slot)


func _start_loaded(slot: int) -> void:
	if SaveManager.load_game(slot):
		get_tree().change_scene_to_file(GAME_SCENE)
	else:
		_message.text = "Could not load slot %d." % slot


# --- Builders ----------------------------------------------------------------

func _panel(parent: Control) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#f4f7f9")
	sb.set_corner_radius_all(18)
	sb.set_content_margin_all(22)
	p.add_theme_stylebox_override("panel", sb)
	parent.add_child(p)
	return p


func _button(parent: Control, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(320, 48)
	b.add_theme_font_size_override("font_size", 20)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.06, 0.08, 0.12, 0.78)
	normal.set_corner_radius_all(12)
	normal.set_content_margin_all(12)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = TEAL
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.06, 0.08, 0.12, 0.4)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.35))
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _label(parent: Control, text: String, size: int, c: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	parent.add_child(l)
	return l


func _spacer(h: float) -> Control:
	var s := Control.new()
	s.custom_minimum_size.y = h
	return s
